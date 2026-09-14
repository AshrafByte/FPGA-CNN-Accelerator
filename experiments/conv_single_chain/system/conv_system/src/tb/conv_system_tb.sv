//------------------------------------------------------------------------------
// Testbench: conv_system_tb
//
// Description:
//   Self-checking testbench for conv_system. Loads the kernels serially over the
//   shared data bus, streams one frame in raster order, and compares every
//   valid-gated feature of every lane against a reference model of the pipeline
//   (signed MAC -> round-to-nearest-even -> saturation -> ReLU).
//
// Two things the model has to get right, both non-obvious from the port list:
//
//   Tap ordering. window_generator shifts each new column in at index 0, and
//   o_window[kr*WINDOW_SIZE + kc] reads r_window[kr][kc], so tap kc selects the
//   column kc positions BEFORE the newest one:
//
//     window[kr*WINDOW_SIZE + kc] == image[orow + kr][ocol + (WINDOW_SIZE-1-kc)]
//
//   The flattened window is row-ascending but COLUMN-DESCENDING - a correlation
//   down the rows, a convolution across the columns. This is NOT the tap order
//   of tb_util_pkg::conv. The tap_order test uses all-distinct taps, rotated per
//   lane, so a deviation cannot be masked by a symmetric kernel.
//
//   Order and count, not latency. output_fifo re-times the stream behind a
//   prefill gate, so absolute latency is not a contract. One frame yields
//   exactly OUTPUT_SIZE**2 features per lane in raster order, and that is what
//   gets checked.
//
//   ReLU placement. relu_unit sits AFTER round_saturate, so it clamps the
//   narrowed feature rather than the raw accumulator. This is a COST choice,
//   not a numerical one: the two orders are provably equivalent, because
//   round_saturate is monotonic and maps 0 to 0, so relu(rs(x)) == rs(relu(x))
//   for every x (checked exhaustively over all 2**20 accumulator values).
//   Placing it second just makes the clamp FEATURE_WIDTH bits wide instead of
//   ACCUM_WIDTH. The model mirrors the RTL's order anyway - not because the
//   result would differ, but so the two stay comparable stage by stage if a
//   future parameterisation breaks the equivalence.
//
//   ReLU is a pipeline stage, not a mux, so ENABLE_RELU=1 makes every lane one
//   cycle deeper. Nothing here depends on that: the checks are on order and
//   count, and relu_unit reproduces its input valid pattern exactly.
//
//   Negative coverage. A ReLU that is wired up but never presented with a
//   negative feature passes every value check trivially, and so does a ReLU
//   that has been optimised away. tb_clamped counts how many features the
//   MODEL had to clamp, and relu_clamp fails if that count is zero - the
//   stimulus itself is checked, not just the response to it.
//
// Kernel count:
//   NUM_KERNELS is an overridable parameter - run the single-lane case with
//   `vsim -gNUM_KERNELS=1 work.conv_system_tb`. ENABLE_RELU is overridable the
//   same way (`-gENABLE_RELU=0`) and is forwarded to both the DUT and the
//   model, so the bypass build is checked by the same suite rather than by a
//   second, drifting copy of it. SEL_WIDTH mirrors conv_system's
//   sel_ker_t ($clog2(N)+1 bits) rather than computing its own minimum, so a
//   change to that encoding shows up as a width mismatch instead of silently
//   truncating.
//
// Per-test reset:
//   kernel_register's load counter and output_fifo's prefill latch are both
//   sticky, so every test starts from a fresh reset rather than a primed
//   pipeline. conv_system also gates the datapath behind &w_kernel_ready, so
//   every lane must be loaded before a frame can stream.
//------------------------------------------------------------------------------
module conv_system_tb;

   import tb_util_pkg::apply_reset;

   parameter int NUM_KERNELS = 2;      // override with vsim -gNUM_KERNELS=<n>
   parameter bit ENABLE_RELU = 1'b1;   // override with vsim -gENABLE_RELU=0
   parameter int WINDOW_SIZE = 3;      // override with vsim -gWINDOW_SIZE=<n>
   parameter int INPUT_SIZE  = 32;     // override with vsim -gINPUT_SIZE=<n>; spec minimum is 32
   // 0: round half to even (rtl_low_area and earlier builds)
   // 1: round half up, i.e. floor((x + 2^(DROP-1)) / 2^DROP) - conv_system in
   //    hw/ and every experiments build (default)
   parameter int ROUND_MODE  = 1;
   // 1: stall the input stream - i_pixel_valid drops for random 1..3-cycle gaps
   // (and an occasional 20-cycle gap) mid-row, mid-frame and at row
   // boundaries, with junk on i_data while it is low. The expected features
   // do not change: order and count must survive any stall pattern.
   parameter bit STALL       = 1'b0;

   localparam time CLK_PERIOD    = 10ns;
   localparam int  PIXEL_WIDTH   = 8;
   localparam int  FEATURE_WIDTH = 16;

   localparam int WINDOW_ELEMENTS = WINDOW_SIZE ** 2;
   localparam int OUTPUT_SIZE     = INPUT_SIZE - WINDOW_SIZE + 1;
   localparam int FRAME_FEATURES  = OUTPUT_SIZE ** 2;
   localparam int ACCUM_WIDTH     = 2*PIXEL_WIDTH + $clog2(WINDOW_ELEMENTS);
   localparam int DROP            = ACCUM_WIDTH - FEATURE_WIDTH;
   localparam int SEL_WIDTH       = $clog2(NUM_KERNELS) + 1;

   localparam int MAX_FEAT      = (1 << (FEATURE_WIDTH-1)) - 1;
   localparam int MIN_FEAT      = -(1 << (FEATURE_WIDTH-1));
   localparam int DRAIN_TIMEOUT = 4 * INPUT_SIZE * INPUT_SIZE;
   localparam int MAX_REPORTED  = 5;

   typedef logic        [PIXEL_WIDTH-1:0]   data_t;
   typedef logic signed [PIXEL_WIDTH-1:0]   weight_t;
   typedef logic signed [ACCUM_WIDTH-1:0]   accum_t;
   typedef logic signed [FEATURE_WIDTH-1:0] feature_t;

   typedef enum { IMAGE_RAMP, IMAGE_RANDOM, IMAGE_MAX } image_mode_e;

   //---------------------------------------------------------------------------
   // DUT
   //---------------------------------------------------------------------------
   logic                 clk;
   logic                 rst_n           = 1'b0;
   data_t                i_data          = '0;
   logic                 i_pixel_valid   = 1'b0;
   logic                 i_weight_valid  = 1'b0;
   logic [SEL_WIDTH-1:0] i_select_kernel = '0;
   feature_t             o_feature [NUM_KERNELS];
   logic                 o_valid;

   clk_gen #(.CLK_PERIOD(CLK_PERIOD)) u_clk_gen (.clk(clk));

   conv_system #(
      .PIXEL_WIDTH  (PIXEL_WIDTH),
      .WINDOW_SIZE  (WINDOW_SIZE),
      .INPUT_SIZE   (INPUT_SIZE),
      .FEATURE_WIDTH(FEATURE_WIDTH),
      .NUM_KERNELS  (NUM_KERNELS),
      .ENABLE_RELU  (ENABLE_RELU)
   ) u_dut (
      .clk(clk), .rst_n(rst_n),
      .i_data(i_data), .i_pixel_valid(i_pixel_valid),
      .i_weight_valid(i_weight_valid), .i_select_kernel(i_select_kernel),
      .o_feature(o_feature), .o_valid(o_valid)
   );

   //---------------------------------------------------------------------------
   // State
   //---------------------------------------------------------------------------
   data_t    tb_image    [INPUT_SIZE][INPUT_SIZE];
   weight_t  tb_kernel   [NUM_KERNELS][WINDOW_ELEMENTS];
   feature_t tb_expected [NUM_KERNELS][$];

   string tb_test;
   int    tb_checked;
   int    tb_clamped;        // features the model clamped this test (pre-ReLU < 0)
   int    tb_test_errors;
   int    tb_errors;
   int    tb_tests_failed;
   int    tb_tests_run;

   function automatic void fail(string msg);
      tb_test_errors++;
      tb_errors++;
      if (tb_test_errors <= MAX_REPORTED)
         $display("[FAIL] %s: %s", tb_test, msg);
      else if (tb_test_errors == MAX_REPORTED + 1)
         $display("[FAIL] %s: further errors suppressed", tb_test);
   endfunction

   //---------------------------------------------------------------------------
   // Monitor - samples in the Active region, so it sees what the DUT's
   // non-blocking outputs settled to during the preceding cycle. Runs always:
   // outside a frame the queues are empty, so a stray o_valid is reported.
   //---------------------------------------------------------------------------
   always @(posedge clk) begin
      feature_t expected;
      int       index;
      if (o_valid !== 1'b1) ;
      else if (tb_expected[0].size() == 0)
         fail($sformatf("o_valid after all %0d expected feature(s) consumed", tb_checked));
      else begin
         index = tb_checked++;
         for (int k = 0; k < NUM_KERNELS; k++) begin
            expected = tb_expected[k].pop_front();
            if (o_feature[k] !== expected)
               fail($sformatf("feature %0d (row %0d, col %0d) kernel %0d: got %0d, expected %0d",
                              index, index / OUTPUT_SIZE, index % OUTPUT_SIZE,
                              k, o_feature[k], expected));
         end
      end
   end

   //---------------------------------------------------------------------------
   // Reference model
   //---------------------------------------------------------------------------

   // signed MAC over one window, in the DUT's tap order (see header)
   function automatic accum_t model_mac(int kernel, int orow, int ocol);
      int sum = 0;
      for (int kr = 0; kr < WINDOW_SIZE; kr++)
         for (int kc = 0; kc < WINDOW_SIZE; kc++)
            sum += int'(tb_image[orow + kr][ocol + (WINDOW_SIZE-1-kc)]) *
                   int'(tb_kernel[kernel][kr*WINDOW_SIZE + kc]);
      return accum_t'(sum);
   endfunction

   // round_saturate, from the definition, on value/2^DROP: ROUND_MODE 1 (default)
   // rounds half up, floor((value + 2^(DROP-1)) / 2^DROP); ROUND_MODE 0 rounds
   // half to even (older builds). Then clamp. Verified exhaustively against the
   // RTL over all 2^20 inputs.
   function automatic feature_t model_round_saturate(accum_t value);
      int v = int'(value);
      int q, rem, half;

      if (DROP <= 0) return feature_t'(v);

      half = 1 << (DROP-1);
      q    = v >>> DROP;          // floor division toward -inf
      rem  = v - (q <<< DROP);    // exact remainder, always 0..2^DROP-1

      if (ROUND_MODE == 1) begin
         if (rem >= half) q++;                        // tie -> up
      end
      else if (rem > half || (rem == half && q[0])) q++;   // tie -> make even
      if (q > MAX_FEAT) q = MAX_FEAT;
      if (q < MIN_FEAT) q = MIN_FEAT;
      return feature_t'(q);
   endfunction

   // relu_unit: sign bit of the ALREADY-NARROWED feature selects zero.
   function automatic feature_t model_relu(feature_t value);
      if (!ENABLE_RELU)  return value;
      return value[FEATURE_WIDTH-1] ? '0 : value;
   endfunction

   task automatic expect_frame();
      feature_t narrowed;
      tb_clamped = 0;
      for (int k = 0; k < NUM_KERNELS; k++)
         for (int r = 0; r < OUTPUT_SIZE; r++)
            for (int c = 0; c < OUTPUT_SIZE; c++) begin
               narrowed = model_round_saturate(model_mac(k, r, c));
               if (narrowed[FEATURE_WIDTH-1]) tb_clamped++;
               tb_expected[k].push_back(model_relu(narrowed));
            end
   endtask

   //---------------------------------------------------------------------------
   // Stimulus
   //---------------------------------------------------------------------------
   task automatic fill_image(image_mode_e mode);
      for (int r = 0; r < INPUT_SIZE; r++)
         for (int c = 0; c < INPUT_SIZE; c++)
            case (mode)
               IMAGE_RAMP:   tb_image[r][c] = data_t'(r*INPUT_SIZE + c + 1);
               IMAGE_RANDOM: tb_image[r][c] = data_t'($urandom_range(0, 255));
               IMAGE_MAX:    tb_image[r][c] = '1;
            endcase
   endtask

   task automatic set_uniform(int kernel, weight_t value);
      for (int i = 0; i < WINDOW_ELEMENTS; i++)
         tb_kernel[kernel][i] = value;
   endtask

   // same taps in every lane, rotated by lane index, so no two lanes match
   task automatic set_rotated(int kernel, weight_t taps [WINDOW_ELEMENTS]);
      for (int i = 0; i < WINDOW_ELEMENTS; i++)
         tb_kernel[kernel][i] = taps[(i + kernel) % WINDOW_ELEMENTS];
   endtask

   //---------------------------------------------------------------------------
   // Drivers. Inputs are driven with non-blocking assignments issued right after
   // a clock edge, so the value lands in that edge's NBA region and is sampled
   // by the DUT on the FOLLOWING edge - race-free against its always_ff blocks.
   //---------------------------------------------------------------------------

   // conv_system gates each kernel_register with
   // r_weight_write_en && (i_select_kernel == k). r_weight_write_en is a
   // registered copy of i_weight_valid but i_select_kernel is used un-delayed,
   // so select must hold one extra cycle past the last beat.
   task automatic push_weights(logic [SEL_WIDTH-1:0] select, weight_t taps [WINDOW_ELEMENTS]);
      i_select_kernel <= select;
      for (int i = 0; i < WINDOW_ELEMENTS; i++) begin
         i_weight_valid <= 1'b1;
         i_data         <= data_t'(taps[i]);
         @(posedge clk);
      end
      i_weight_valid <= 1'b0;
      i_data         <= '0;
      @(posedge clk);   // covers the one-cycle r_weight_write_en tail
   endtask

   task automatic stream_frame();
      for (int r = 0; r < INPUT_SIZE; r++)
         for (int c = 0; c < INPUT_SIZE; c++) begin
            if (STALL) begin
               if ($urandom_range(0, 99) == 0)
                  repeat (20) begin
                     i_pixel_valid <= 1'b0;
                     i_data        <= data_t'($urandom);
                     @(posedge clk);
                  end
               while ($urandom_range(0, 3) == 0) begin
                  i_pixel_valid <= 1'b0;
                  i_data        <= data_t'($urandom);
                  @(posedge clk);
               end
            end
            i_pixel_valid <= 1'b1;
            i_data        <= tb_image[r][c];
            @(posedge clk);
         end
      i_pixel_valid <= 1'b0;
      i_data        <= '0;
      @(posedge clk);
   endtask

   task automatic drain_and_check();
      int idle = 0;
      while (tb_expected[0].size() != 0 && idle < DRAIN_TIMEOUT) begin
         @(posedge clk);
         idle = o_valid ? 0 : idle + 1;
      end
      if (tb_expected[0].size() != 0)
         fail($sformatf("timed out with %0d feature(s) undrained", tb_expected[0].size()));

      repeat (20) @(posedge clk);   // catch any trailing spurious valid

      if (tb_checked != FRAME_FEATURES)
         fail($sformatf("frame produced %0d feature(s), expected %0d", tb_checked, FRAME_FEATURES));
   endtask

   //---------------------------------------------------------------------------
   // Test body. poison_unused writes a full kernel at select == NUM_KERNELS,
   // which addresses no lane and must leave every lane untouched.
   //
   // min_clamped is a floor on the STIMULUS, not on the DUT: it asserts that
   // this test actually drove at least that many negative features into the
   // ReLU. Without it a test can pass for the wrong reason - every feature
   // non-negative, nothing for the clamp to do.
   //---------------------------------------------------------------------------
   task automatic run_frame_test(string name, bit poison_unused = 0, int min_clamped = 0);
      weight_t poison [WINDOW_ELEMENTS];

      tb_test        = name;
      tb_test_errors = 0;
      tb_checked     = 0;
      tb_clamped     = 0;
      tb_tests_run++;
      foreach (tb_expected[k]) tb_expected[k].delete();

      apply_reset(clk, 5, rst_n);
      i_data <= '0; i_pixel_valid <= 1'b0; i_weight_valid <= 1'b0; i_select_kernel <= '0;
      @(posedge clk);

      if (poison_unused) begin
         for (int i = 0; i < WINDOW_ELEMENTS; i++) poison[i] = -8'sd128;
         push_weights(SEL_WIDTH'(NUM_KERNELS), poison);
      end

      for (int k = 0; k < NUM_KERNELS; k++)
         push_weights(SEL_WIDTH'(k), tb_kernel[k]);
      repeat (2) @(posedge clk);

      if (o_valid === 1'b1) fail("o_valid asserted during kernel load");

      expect_frame();
      stream_frame();
      drain_and_check();

      if (tb_clamped < min_clamped)
         fail($sformatf("stimulus drove %0d negative feature(s) into ReLU, test needs >= %0d",
                        tb_clamped, min_clamped));

      if (tb_test_errors == 0)
         $display("[PASS] %s: %0d feature(s) x %0d kernel(s), %0d clamped",
                  name, tb_checked, NUM_KERNELS, ENABLE_RELU ? tb_clamped : 0);
      else begin
         tb_tests_failed++;
         $display("[FAIL] %s: %0d error(s)", name, tb_test_errors);
      end

      rst_n = 1'b0;
   endtask

   //---------------------------------------------------------------------------
   // Tests
   //---------------------------------------------------------------------------
   initial begin
      weight_t ascending [WINDOW_ELEMENTS];
      weight_t laplacian [WINDOW_ELEMENTS];

      for (int i = 0; i < WINDOW_ELEMENTS; i++) ascending[i] = weight_t'(i + 1);
      // Generalised laplacian: -1 everywhere, WINDOW_ELEMENTS-1 at the centre
      // tap, so the taps sum to zero. At WINDOW_SIZE=3 this is exactly the
      // classic {-1,-1,-1, -1,8,-1, -1,-1,-1}. The centre weight must fit int8:
      // exact up to WINDOW_SIZE=11, clamped to +127 above that (the kernel
      // then no longer sums to zero, which the test does not rely on).
      for (int i = 0; i < WINDOW_ELEMENTS; i++) laplacian[i] = -8'sd1;
      laplacian[WINDOW_ELEMENTS/2] = weight_t'((WINDOW_ELEMENTS - 1 > 127) ? 127 : WINDOW_ELEMENTS - 1);

      $display("============================================================");
      $display("[TEST] conv_system: %0dx%0d image, %0dx%0d window, NUM_KERNELS=%0d (SEL_WIDTH=%0d)",
               INPUT_SIZE, INPUT_SIZE, WINDOW_SIZE, WINDOW_SIZE, NUM_KERNELS, SEL_WIDTH);
      $display("[TEST] conv_system: %0d feature(s) per lane per frame, ACCUM=%0d DROP=%0d",
               FRAME_FEATURES, ACCUM_WIDTH, DROP);
      if (ENABLE_RELU) $display("[TEST] conv_system: ENABLE_RELU=1 (relu_unit per lane)");
      else             $display("[TEST] conv_system: ENABLE_RELU=0 (ReLU bypassed)");

      // uniform kernels over a ramp: plain streaming path, distinct gain per lane
      fill_image(IMAGE_RAMP);
      for (int k = 0; k < NUM_KERNELS; k++) set_uniform(k, weight_t'(k + 1));
      run_frame_test("box_filter");

      // all taps distinct and rotated per lane: catches tap order and lane crossing
      fill_image(IMAGE_RANDOM);
      for (int k = 0; k < NUM_KERNELS; k++) set_rotated(k, ascending);
      run_frame_test("tap_order");

      // negative weights: weights are typed signed, results must be too.
      // A laplacian over a random image straddles zero, so this is the mixed
      // case - some features pass through the ReLU, some are clamped, and a
      // clamp that leaked into the positive side would show up as a mismatch.
      fill_image(IMAGE_RANDOM);
      for (int k = 0; k < NUM_KERNELS; k++) set_rotated(k, laplacian);
      run_frame_test("signed_weights", 0, 1);

      // widest legal accumulation: 255 * 127 * 9 = 291465, inside 20-bit signed
      fill_image(IMAGE_MAX);
      for (int k = 0; k < NUM_KERNELS; k++) set_uniform(k, weight_t'(127 - k));
      run_frame_test("dynamic_range");

      // every window negative by construction: a uniformly negative kernel over
      // a saturated image. With ReLU on, the whole frame must read back zero on
      // every lane; with it off, the same frame must read back the untouched
      // negative values. Demanding that ALL of them were clamped keeps this
      // from passing on a ReLU that only handles some sign patterns.
      fill_image(IMAGE_MAX);
      for (int k = 0; k < NUM_KERNELS; k++) set_uniform(k, weight_t'(-(k + 1)));
      run_frame_test("relu_clamp", 0, FRAME_FEATURES * NUM_KERNELS);

      // largest-magnitude negative feature the design can produce: 255 * -128 * 9
      // = -293760, which is -18360 after the >>4. round_saturate does NOT saturate
      // here - at 8-bit pixels nothing can, since the post-shift magnitude is
      // bounded by 255*128 = 32640 < 32767 for every odd K - it only narrows.
      // The ReLU is what turns this into zero.
      fill_image(IMAGE_MAX);
      for (int k = 0; k < NUM_KERNELS; k++) set_uniform(k, weight_t'(-128 + k));
      run_frame_test("relu_negative_range", 0, FRAME_FEATURES * NUM_KERNELS);

      // a kernel written at an out-of-range select must land nowhere
      fill_image(IMAGE_RANDOM);
      for (int k = 0; k < NUM_KERNELS; k++) set_rotated(k, ascending);
      run_frame_test("unused_select", 1);

      $display("============================================================");
      if (tb_errors == 0)
         $display("[PASS] conv_system: all %0d test(s) passed", tb_tests_run);
      else
         $display("[FAIL] conv_system: %0d of %0d test(s) failed, %0d error(s)",
                  tb_tests_failed, tb_tests_run, tb_errors);
      $display("============================================================");

      $finish(tb_errors == 0 ? 0 : 1);
   end

   initial begin
      #(CLK_PERIOD * 500 * INPUT_SIZE * INPUT_SIZE);
      $display("[FAIL] conv_system: watchdog expired");
      $finish(1);
   end

endmodule

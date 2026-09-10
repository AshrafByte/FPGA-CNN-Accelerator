//------------------------------------------------------------------------------
// Testbench: conv_system_tb
//
// Description:
//   Self-checking testbench for conv_system. Loads the kernels serially over the
//   shared data bus, streams one frame in raster order, and compares every
//   valid-gated feature of every lane against a reference model of the pipeline
//   (signed MAC -> round-to-nearest-even -> saturation).
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
// Kernel count:
//   NUM_KERNELS is an overridable parameter - run the single-lane case with
//   `vsim -gNUM_KERNELS=1 work.conv_system_tb`. SEL_WIDTH mirrors conv_system's
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

   parameter int NUM_KERNELS = 2;   // override with vsim -gNUM_KERNELS=<n>

   localparam time CLK_PERIOD    = 10ns;
   localparam int  PIXEL_WIDTH   = 8;
   localparam int  WINDOW_SIZE   = 3;
   localparam int  INPUT_SIZE    = 8;
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
      .NUM_KERNELS  (NUM_KERNELS)
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

   // round_saturate, from the definition: round-half-to-even on value/2^DROP,
   // then clamp. Verified exhaustively against the RTL over all 2^20 inputs.
   function automatic feature_t model_round_saturate(accum_t value);
      int v = int'(value);
      int q, rem, half;

      if (DROP <= 0) return feature_t'(v);

      half = 1 << (DROP-1);
      q    = v >>> DROP;          // floor division toward -inf
      rem  = v - (q <<< DROP);    // exact remainder, always 0..2^DROP-1

      if (rem > half || (rem == half && q[0])) q++;   // tie -> make even
      if (q > MAX_FEAT) q = MAX_FEAT;
      if (q < MIN_FEAT) q = MIN_FEAT;
      return feature_t'(q);
   endfunction

   task automatic expect_frame();
      for (int k = 0; k < NUM_KERNELS; k++)
         for (int r = 0; r < OUTPUT_SIZE; r++)
            for (int c = 0; c < OUTPUT_SIZE; c++)
               tb_expected[k].push_back(model_round_saturate(model_mac(k, r, c)));
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
   //---------------------------------------------------------------------------
   task automatic run_frame_test(string name, bit poison_unused = 0);
      weight_t poison [WINDOW_ELEMENTS];

      tb_test        = name;
      tb_test_errors = 0;
      tb_checked     = 0;
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

      if (tb_test_errors == 0)
         $display("[PASS] %s: %0d feature(s) x %0d kernel(s)", name, tb_checked, NUM_KERNELS);
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
      laplacian = '{-8'sd1, -8'sd1, -8'sd1,
                    -8'sd1,  8'sd8, -8'sd1,
                    -8'sd1, -8'sd1, -8'sd1};

      $display("============================================================");
      $display("[TEST] conv_system: %0dx%0d image, %0dx%0d window, NUM_KERNELS=%0d (SEL_WIDTH=%0d)",
               INPUT_SIZE, INPUT_SIZE, WINDOW_SIZE, WINDOW_SIZE, NUM_KERNELS, SEL_WIDTH);
      $display("[TEST] conv_system: %0d feature(s) per lane per frame, ACCUM=%0d DROP=%0d",
               FRAME_FEATURES, ACCUM_WIDTH, DROP);

      // uniform kernels over a ramp: plain streaming path, distinct gain per lane
      fill_image(IMAGE_RAMP);
      for (int k = 0; k < NUM_KERNELS; k++) set_uniform(k, weight_t'(k + 1));
      run_frame_test("box_filter");

      // all taps distinct and rotated per lane: catches tap order and lane crossing
      fill_image(IMAGE_RANDOM);
      for (int k = 0; k < NUM_KERNELS; k++) set_rotated(k, ascending);
      run_frame_test("tap_order");

      // negative weights: weights are typed signed, results must be too
      fill_image(IMAGE_RANDOM);
      for (int k = 0; k < NUM_KERNELS; k++) set_rotated(k, laplacian);
      run_frame_test("signed_weights");

      // widest legal accumulation: 255 * 127 * 9 = 291465, inside 20-bit signed
      fill_image(IMAGE_MAX);
      for (int k = 0; k < NUM_KERNELS; k++) set_uniform(k, weight_t'(127 - k));
      run_frame_test("dynamic_range");

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

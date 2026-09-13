//------------------------------------------------------------------------------
// Testbench: conv_image_tb
//
// Description:
//   File-driven harness around conv_system. Unlike conv_system_tb (which is
//   self-checking against a built-in reference model), this one carries no
//   stimulus and no expectations of its own: it reads an image and a set of
//   kernels from a text file, streams exactly one frame, and writes every
//   feature it observes to a second text file. Checking is the caller's job.
//
//   This is the hardware half of the Python conv_lab application
//   (sw/conv_lab) - see sw/README.md for the full contract. It is equally
//   usable by hand:
//
//     vlog -sv -timescale 1ns/1ps -F hw/system/conv_system/sim/compile.f
//     vsim -c -gINPUT_SIZE=32 work.conv_image_tb \
//          +stim=stimulus.txt +result=features.txt -do "run -all; quit -f"
//
// Geometry is elaboration-time:
//   INPUT_SIZE / WINDOW_SIZE / NUM_KERNELS size the DUT, so they cannot come
//   from the file - they arrive as vsim -g overrides. The stimulus file
//   repeats them in its header and the header is checked against the
//   elaborated values, so a caller that forgets an override gets a clear
//   mismatch instead of a silently truncated image.
//
// Tap ordering (the one non-obvious thing about the interface):
//   window_generator shifts each new column in at index 0, so the flattened
//   window is row-ascending but COLUMN-DESCENDING:
//
//     window[kr*WINDOW_SIZE + kc] == image[orow + kr][ocol + (WINDOW_SIZE-1-kc)]
//
//   The weights are loaded in the file's order, verbatim. Whoever writes the
//   file therefore owns the flip: to get a textbook correlation the caller
//   must send each kernel row reversed. conv_lab.hardware.contract.pack_kernel
//   does exactly that; this module deliberately does not, so the file format
//   stays a literal picture of the kernel_register contents.
//
// Output scaling:
//   round_saturate drops ACCUM_WIDTH-FEATURE_WIDTH bits, so a recorded
//   feature is the MAC divided by 2^DROP with round-half-to-even, clamped to
//   FEATURE_WIDTH bits. DROP is echoed into the result header so the caller
//   never has to rederive it.
//
// One frame per run:
//   output_fifo's prefill latch and kernel_register's load counter are both
//   reset only by rst_n, so a second frame would need another reset. This
//   testbench runs exactly one frame and finishes.
//------------------------------------------------------------------------------
module conv_image_tb;

   import tb_util_pkg::apply_reset;

   // Overridden per run via vsim -g<NAME>=<value>.
   parameter int INPUT_SIZE    = 32;
   parameter int WINDOW_SIZE   = 3;
   parameter int NUM_KERNELS   = 1;
   parameter int PIXEL_WIDTH   = 8;
   parameter int FEATURE_WIDTH = 16;

   localparam time CLK_PERIOD = 10ns;

   localparam int WINDOW_ELEMENTS = WINDOW_SIZE ** 2;
   localparam int OUTPUT_SIZE     = INPUT_SIZE - WINDOW_SIZE + 1;
   localparam int FRAME_FEATURES  = OUTPUT_SIZE ** 2;
   localparam int ACCUM_WIDTH     = 2*PIXEL_WIDTH + $clog2(WINDOW_ELEMENTS);
   localparam int DROP            = ACCUM_WIDTH - FEATURE_WIDTH;
   localparam int SEL_WIDTH       = $clog2(NUM_KERNELS) + 1;

   // Generous: the pipeline drains in O(INPUT_SIZE) cycles after the last
   // pixel, so anything near this bound means the stream has stalled.
   localparam int DRAIN_TIMEOUT = 8 * INPUT_SIZE * INPUT_SIZE + 1000;

   typedef logic        [PIXEL_WIDTH-1:0]   data_t;
   typedef logic signed [PIXEL_WIDTH-1:0]   weight_t;
   typedef logic signed [FEATURE_WIDTH-1:0] feature_t;

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
   feature_t tb_captured [NUM_KERNELS][FRAME_FEATURES];

   string tb_stim_path;
   string tb_result_path;
   int    tb_captured_cnt;
   int    tb_overrun;

   function automatic void die(string msg);
      $display("[conv_image_tb] ERROR: %s", msg);
      $display("[conv_image_tb] STATUS: ERROR");
      $fatal(1);
   endfunction

   //---------------------------------------------------------------------------
   // Capture monitor. Sampled in the Active region, so it sees what the DUT's
   // non-blocking outputs settled to during the preceding cycle. Runs always:
   // any o_valid past FRAME_FEATURES is an overrun and is reported, not stored.
   //---------------------------------------------------------------------------
   always @(posedge clk) begin
      if (o_valid === 1'b1) begin
         if (tb_captured_cnt < FRAME_FEATURES) begin
            for (int k = 0; k < NUM_KERNELS; k++)
               tb_captured[k][tb_captured_cnt] = o_feature[k];
            tb_captured_cnt++;
         end else begin
            tb_overrun++;
         end
      end
   end

   //---------------------------------------------------------------------------
   // Stimulus file. Pure whitespace-separated decimals, in this order:
   //   INPUT_SIZE WINDOW_SIZE NUM_KERNELS
   //   NUM_KERNELS * WINDOW_ELEMENTS signed weights, kernel-major
   //   INPUT_SIZE**2 unsigned pixels, raster order
   //---------------------------------------------------------------------------
   task automatic read_stimulus();
      int    fd, code, value, expected;
      string name;

      fd = $fopen(tb_stim_path, "r");
      if (fd == 0) die($sformatf("cannot open stimulus file '%s'", tb_stim_path));

      // Header, checked against the elaborated geometry.
      for (int field = 0; field < 3; field++) begin
         expected = (field == 0) ? INPUT_SIZE  : (field == 1) ? WINDOW_SIZE   : NUM_KERNELS;
         name     = (field == 0) ? "INPUT_SIZE" : (field == 1) ? "WINDOW_SIZE" : "NUM_KERNELS";
         code = $fscanf(fd, "%d", value);
         if (code != 1) die($sformatf("stimulus header truncated at field '%s'", name));
         if (value != expected)
            die($sformatf("stimulus %s=%0d but elaborated with %0d - pass vsim -g%s=%0d",
                          name, value, expected, name, value));
      end

      for (int k = 0; k < NUM_KERNELS; k++)
         for (int i = 0; i < WINDOW_ELEMENTS; i++) begin
            code = $fscanf(fd, "%d", value);
            if (code != 1) die($sformatf("stimulus truncated at kernel %0d tap %0d", k, i));
            if (value < -128 || value > 127)
               die($sformatf("kernel %0d tap %0d = %0d is outside signed 8-bit range", k, i, value));
            tb_kernel[k][i] = weight_t'(value);
         end

      for (int r = 0; r < INPUT_SIZE; r++)
         for (int c = 0; c < INPUT_SIZE; c++) begin
            code = $fscanf(fd, "%d", value);
            if (code != 1) die($sformatf("stimulus truncated at pixel (%0d,%0d)", r, c));
            if (value < 0 || value > 255)
               die($sformatf("pixel (%0d,%0d) = %0d is outside unsigned 8-bit range", r, c, value));
            tb_image[r][c] = data_t'(value);
         end

      $fclose(fd);
   endtask

   //---------------------------------------------------------------------------
   // Result file:
   //   # generated by conv_image_tb
   //   OUTPUT_SIZE NUM_KERNELS DROP
   //   one line per output pixel in raster order, NUM_KERNELS signed values each
   //---------------------------------------------------------------------------
   task automatic write_results();
      int fd;

      fd = $fopen(tb_result_path, "w");
      if (fd == 0) die($sformatf("cannot open result file '%s' for writing", tb_result_path));

      $fdisplay(fd, "# conv_image_tb: OUTPUT_SIZE NUM_KERNELS DROP, then one raster line per output pixel");
      $fdisplay(fd, "%0d %0d %0d", OUTPUT_SIZE, NUM_KERNELS, DROP);
      for (int n = 0; n < FRAME_FEATURES; n++) begin
         for (int k = 0; k < NUM_KERNELS; k++)
            $fwrite(fd, "%0d%s", tb_captured[k][n], (k == NUM_KERNELS-1) ? "\n" : " ");
      end

      $fclose(fd);
   endtask

   //---------------------------------------------------------------------------
   // Drivers. Inputs are driven with non-blocking assignments issued right
   // after a clock edge, so the value lands in that edge's NBA region and is
   // sampled by the DUT on the FOLLOWING edge - race-free against its
   // always_ff blocks.
   //---------------------------------------------------------------------------

   // conv_system gates each kernel_register with
   // r_weight_write_en && (i_select_kernel == k). r_weight_write_en is a
   // registered copy of i_weight_valid but i_select_kernel is used un-delayed,
   // so select must hold one extra cycle past the last beat.
   task automatic push_weights(int select, weight_t taps [WINDOW_ELEMENTS]);
      i_select_kernel <= SEL_WIDTH'(select);
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

   task automatic drain();
      int idle = 0;
      while (tb_captured_cnt < FRAME_FEATURES && idle < DRAIN_TIMEOUT) begin
         @(posedge clk);
         idle = o_valid ? 0 : idle + 1;
      end
      repeat (20) @(posedge clk);   // catch any trailing spurious valid
   endtask

   //---------------------------------------------------------------------------
   // Run
   //---------------------------------------------------------------------------
   initial begin
      if (!$value$plusargs("stim=%s", tb_stim_path))
         die("missing +stim=<path> plusarg");
      if (!$value$plusargs("result=%s", tb_result_path))
         die("missing +result=<path> plusarg");
      if (OUTPUT_SIZE < 1)
         die($sformatf("INPUT_SIZE=%0d is not larger than WINDOW_SIZE=%0d", INPUT_SIZE, WINDOW_SIZE));

      $display("[conv_image_tb] %0dx%0d image, %0dx%0d window, %0d kernel(s), DROP=%0d",
               INPUT_SIZE, INPUT_SIZE, WINDOW_SIZE, WINDOW_SIZE, NUM_KERNELS, DROP);

      read_stimulus();

      apply_reset(clk, 5, rst_n);
      i_data <= '0; i_pixel_valid <= 1'b0; i_weight_valid <= 1'b0; i_select_kernel <= '0;
      @(posedge clk);

      for (int k = 0; k < NUM_KERNELS; k++)
         push_weights(k, tb_kernel[k]);
      repeat (2) @(posedge clk);

      stream_frame();
      drain();

      if (tb_captured_cnt != FRAME_FEATURES)
         die($sformatf("captured %0d feature(s), expected %0d - pipeline stalled",
                       tb_captured_cnt, FRAME_FEATURES));
      if (tb_overrun != 0)
         die($sformatf("%0d feature(s) arrived after the frame was complete", tb_overrun));

      write_results();

      $display("[conv_image_tb] wrote %0d feature(s) x %0d kernel(s) to %s",
               tb_captured_cnt, NUM_KERNELS, tb_result_path);
      $display("[conv_image_tb] STATUS: OK");
      $finish(0);
   end

   initial begin
      #(CLK_PERIOD * (50 * INPUT_SIZE * INPUT_SIZE + 100000));
      $display("[conv_image_tb] ERROR: watchdog expired");
      $display("[conv_image_tb] STATUS: ERROR");
      $fatal(1);
   end

endmodule

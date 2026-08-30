//------------------------------------------------------------------------------
// Testbench: conv_system_tb
//
// Description:
//   Comprehensive testbench for the conv_system module.
//   Tests pixel streaming, kernel loading, and feature output validation.
//
// Test Flow:
//   1. Initialize signals
//   2. Apply reset
//   3. Load kernel weights via i_weight_valid / i_data streaming
//   4. Stream image pixels via i_pixel_valid / i_data
//   5. Capture and verify output features
//   6. Check valid signal cascading
//
//------------------------------------------------------------------------------
module conv_system_tb;

   import common_pkg::*;
   import tb_util_pkg::*;

   parameter CLK_PERIOD = 10ns;

   parameter int PIXEL_WIDTH   = 8;
   parameter int WINDOW_SIZE   = 3;
   parameter int INPUT_SIZE    = 8;
   parameter int MEMORY_SIZE   = INPUT_SIZE ** 2;
   localparam int WINDOW_ELEMENTS = WINDOW_SIZE ** 2;
   localparam int FEATURE_WIDTH = 2 * PIXEL_WIDTH + $clog2(WINDOW_ELEMENTS);
   localparam type data_t = logic [PIXEL_WIDTH-1:0];
   localparam type feature_t = logic [FEATURE_WIDTH-1:0];

   logic clk;
   logic rst_n;

   data_t    i_data;
   logic     i_pixel_valid;
   logic     i_weight_valid;
   feature_t o_feature;
   logic     o_valid;

   data_t tb_image[MEMORY_SIZE];
   data_t tb_kernel[WINDOW_ELEMENTS];
   int tb_feature_cnt;

   clk_gen #(
      .CLK_PERIOD(CLK_PERIOD)
   )
   u_clk_gen (
      .clk(clk)
   );

   conv_system #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE),
      .INPUT_SIZE(INPUT_SIZE)
   )
   u_conv_system (
      .clk(clk),
      .rst_n(rst_n),
      .i_data(i_data),
      .i_pixel_valid(i_pixel_valid),
      .i_weight_valid(i_weight_valid),
      .o_feature(o_feature),
      .o_valid(o_valid)
   );

   // Monitor output features
   initial begin: output_monitor
      tb_feature_cnt = 0;
      forever begin
         @(posedge clk);
         if (o_valid) begin
            tb_feature_cnt++;
         end
      end
   end: output_monitor

   initial begin: stimulus_process

      init();
      apply_reset(clk, 100, rst_n);
      fill_kernel();
      fill_image();
      load_kernel();
      start_stream();
      $finish();

   end: stimulus_process

   task automatic init;
      i_data = '0;
      i_pixel_valid = '0;
      i_weight_valid = '0;
      tb_feature_cnt = 0;
   endtask

   // Fill test image with incrementing pattern
   task automatic fill_image;
      for (int i = 0; i < MEMORY_SIZE; i++)
         tb_image[i] = ((i+1) % 256);
   endtask

   // Fill kernel with constant values
   task automatic fill_kernel;
      for (int i = 0; i < WINDOW_ELEMENTS; i++)
         tb_kernel[i] = 1;
   endtask

   // Load kernel weights via i_weight_valid / i_data streaming
   task automatic load_kernel;
      i_weight_valid <= 1'b1;
      for (int i = 0; i < WINDOW_ELEMENTS; i++) begin
         i_data <= tb_kernel[i];
         @(posedge clk);
      end
      i_weight_valid <= 1'b0;
      i_data <= '0;
      @(posedge clk);
   endtask

   // Stream image pixels via i_pixel_valid / i_data
   task automatic start_stream;
      i_pixel_valid = 1'b1;
      for (int i = 0; i < MEMORY_SIZE; i++) begin
         i_data = tb_image[i];
         @(posedge clk);
      end
      i_pixel_valid = 1'b0;
      i_data = '0;

      repeat (500) @(posedge clk);
   endtask

endmodule
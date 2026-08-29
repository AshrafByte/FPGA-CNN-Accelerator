module conv_system_tb;

   import common_pkg::*;
   import tb_util_pkg::*;

   parameter CLK_PERIOD = 10ns;

   parameter  PIXEL_WIDTH   = 8;
   parameter  WINDOW_SIZE   = 3;
   parameter  INPUT_SIZE    = 8;
   parameter  MEMORY_SIZE   = INPUT_SIZE**2;
   localparam FEATURE_WIDTH = 2 * PIXEL_WIDTH + $clog2(WINDOW_SIZE**2);

   logic clk;
   logic rst_n;

   logic                     i_valid_in;
   logic [PIXEL_WIDTH-1:0]   i_pixel;
   logic                     i_load_en;
   logic [PIXEL_WIDTH-1:0]   i_weights   [WINDOW_SIZE**2];
   logic [FEATURE_WIDTH-1:0] o_feature;
   logic                     o_valid_out;

   
   logic [PIXEL_WIDTH-1:0] tb_image[MEMORY_SIZE];

   clk_gen #(
      .CLK_PERIOD(CLK_PERIOD)
   )
   u_clk_gen (
      // Outputs
      .clk(clk)
   );

   conv_system #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .WINDOW_SIZE(WINDOW_SIZE),
      .INPUT_SIZE (INPUT_SIZE)
   )
   u_conv_system (
      // Inputs
      .clk (clk),
      .rst_n (rst_n),
      .i_load_en (i_load_en),
      .i_pixel (i_pixel),
      .i_valid_in (i_valid_in),
      .i_weights (i_weights),
      // Outputs
      .o_feature (o_feature),
      .o_valid_out(o_valid_out)
   );

   initial begin: stimulus_process

      init();
      apply_reset(clk,100, rst_n);

      fill_image();
      load_kernal();
      start_stream();

      repeat (100) @(posedge clk);
      $finish();

   end: stimulus_process

   task automatic init;
      i_load_en  = '0;
      i_valid_in = '0;
      i_pixel    = '0;
   endtask

   
   task automatic fill_image;
      for (int i = 0; i < MEMORY_SIZE; i++)
         tb_image[i] = (i % 256);
   endtask

   task automatic load_kernal;
      i_load_en = '1;
      i_weights = '{default:'d1};
      @(posedge clk);
      i_load_en = '0;
   endtask

  
   task automatic start_stream;
      i_valid_in = 1'b1;
      for (int i = 0; i < MEMORY_SIZE; i++) begin
         i_pixel = tb_image[i];
         @(posedge clk);
      end
      i_valid_in = 1'b0;
   endtask
endmodule
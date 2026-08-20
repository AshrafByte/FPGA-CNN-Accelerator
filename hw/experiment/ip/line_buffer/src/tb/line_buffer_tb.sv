module line_buffer_tb;

   // Parameters
   parameter PIXEL_WIDTH = 8;
   parameter LINE_LENGTH = 8;
   parameter LINE_NUM    = 3;
   parameter CLK_PERIOD  = 10ns;

   // Signals
   logic clk;
   logic rst_n;

   logic i_write_en;
   logic[7:0] i_pixel;

   logic [7:0] o_rows [LINE_NUM];

   // Instance
   line_buffer #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .LINE_LENGTH(LINE_LENGTH),
      .LINE_NUM (LINE_NUM)
   ) u_line_buffer (
      .clk (clk),
      .rst_n (rst_n),

      .i_pixel (i_pixel),
      .i_write_en(i_write_en),

      .o_rows (o_rows)
   );

   // CLK
   clk_gen #(
      .CLK_PERIOD(CLK_PERIOD)
   ) u_clk_gen (
      .clk(clk)
   );

   // SIM
   initial begin: stimulus_process

      tb_util_pkg::apply_reset(
         .i_clk (clk),
         .i_cycles(5),
         .o_rst_n (rst_n)
      );

      i_write_en = '1;
      
      tb_util_pkg::drive_pixels(
          .i_clk  (clk),
          .i_count(LINE_LENGTH*10),
          .o_pixel(i_pixel)
      );

      $finish();

   end: stimulus_process

endmodule
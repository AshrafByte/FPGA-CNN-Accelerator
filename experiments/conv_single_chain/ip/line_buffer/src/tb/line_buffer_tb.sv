//------------------------------------------------------------------------------
// Testbench: line_buffer_tb
//
// Description:
//   Self-checking test of line_buffer over FRAMES consecutive frames with no
//   reset between them and random write stalls. On every accepted pixel it
//   checks:
//     - o_row_done on the last pixel of each row
//     - o_rows_ready from row LINE_NUM-1 of each frame on, low again for the
//       first rows of the next frame (the banks refill without a reset)
//     - o_frame_end one cycle after the frame's last pixel, and never elsewhere
//     - o_rows: the live pixel and the pixels one and two rows back
//------------------------------------------------------------------------------
module line_buffer_tb;

   import tb_util_pkg::apply_reset;

   parameter int PIXEL_WIDTH = 8;
   parameter int LINE_LENGTH = 8;
   parameter int LINE_NUM    = 3;
   parameter int FRAMES      = 3;
   parameter time CLK_PERIOD = 10ns;

   localparam int FRAME_ROWS   = LINE_LENGTH;
   localparam int FRAME_PIXELS = LINE_LENGTH * FRAME_ROWS;

   typedef logic [PIXEL_WIDTH-1:0] pixel_t;

   logic   clk;
   logic   rst_n      = 1'b0;
   logic   i_write_en = 1'b0;
   pixel_t i_pixel    = '0;

   pixel_t o_rows [LINE_NUM];
   logic   o_row_done;
   logic   o_rows_ready;
   logic   o_frame_end;

   int tb_written;       // pixels accepted so far
   bit tb_expect_end;    // the previous accepted pixel closed a frame
   int tb_frame_ends;
   int tb_errors;

   line_buffer #(
      .PIXEL_WIDTH(PIXEL_WIDTH),
      .LINE_LENGTH(LINE_LENGTH),
      .LINE_NUM   (LINE_NUM)
   ) u_line_buffer (
      .clk         (clk),
      .rst_n       (rst_n),
      .i_pixel     (i_pixel),
      .i_write_en  (i_write_en),
      .o_rows      (o_rows),
      .o_row_done  (o_row_done),
      .o_rows_ready(o_rows_ready),
      .o_frame_end (o_frame_end)
   );

   clk_gen #(.CLK_PERIOD(CLK_PERIOD)) u_clk_gen (.clk(clk));

   function automatic pixel_t value_of(int index);
      return pixel_t'(index * 7 + 3);
   endfunction

   function automatic void fail(string msg);
      if (tb_errors++ < 8) $display("[FAIL] pixel %0d: %s", tb_written, msg);
   endfunction

   // Sampled in the Active region: registered outputs still hold their value
   // from before this edge, combinational ones reflect the current write.
   always @(posedge clk) begin
      int row, col;
      if (rst_n) begin
         if (o_frame_end !== tb_expect_end)
            fail($sformatf("o_frame_end=%0b, expected %0b", o_frame_end, tb_expect_end));
         if (o_frame_end === 1'b1) tb_frame_ends++;
         tb_expect_end = 1'b0;

         if (i_write_en) begin
            row = (tb_written % FRAME_PIXELS) / LINE_LENGTH;
            col = tb_written % LINE_LENGTH;
            if (o_row_done !== (col == LINE_LENGTH - 1))
               fail($sformatf("o_row_done=%0b at column %0d", o_row_done, col));
            if (o_rows_ready !== (row >= LINE_NUM - 1))
               fail($sformatf("o_rows_ready=%0b at row %0d", o_rows_ready, row));
            if (o_rows[LINE_NUM-1] !== value_of(tb_written))
               fail("live row is not the current pixel");
            for (int b = 1; b < LINE_NUM; b++)
               if (tb_written >= b * LINE_LENGTH &&
                   o_rows[LINE_NUM-1-b] !== value_of(tb_written - b * LINE_LENGTH))
                  fail($sformatf("o_rows[%0d] is not the pixel %0d row(s) back", LINE_NUM-1-b, b));
            tb_expect_end = (tb_written % FRAME_PIXELS) == FRAME_PIXELS - 1;
            tb_written++;
         end
      end
   end

   initial begin
      $display("============================================================");
      $display("[TEST] line_buffer: %0d frames of %0dx%0d, LINE_NUM=%0d, random stalls, no reset between",
               FRAMES, LINE_LENGTH, FRAME_ROWS, LINE_NUM);

      apply_reset(clk, 5, rst_n);

      for (int p = 0; p < FRAMES * FRAME_PIXELS; p++) begin
         while ($urandom_range(0, 3) == 0) begin
            i_write_en <= 1'b0;
            i_pixel    <= pixel_t'($urandom);
            @(posedge clk);
         end
         i_write_en <= 1'b1;
         i_pixel    <= value_of(p);
         @(posedge clk);
      end
      i_write_en <= 1'b0;
      repeat (4) @(posedge clk);

      if (tb_frame_ends != FRAMES) begin
         $display("[FAIL] %0d o_frame_end pulse(s) for %0d frame(s)", tb_frame_ends, FRAMES);
         tb_errors++;
      end

      $display("============================================================");
      if (tb_errors == 0)
         $display("[PASS] line_buffer: %0d pixels over %0d frames checked", tb_written, FRAMES);
      else
         $display("[FAIL] line_buffer: %0d error(s)", tb_errors);
      $display("============================================================");
      $finish(tb_errors == 0 ? 0 : 1);
   end

endmodule

//------------------------------------------------------------------------------
// Module: window_generator
//
// Description:
//   Extracts a WINDOW_SIZE x WINDOW_SIZE sliding window by combining
//   WINDOW_SIZE-1 buffered previous rows from line_buffer with the live,
//   currently-streaming pixel as the newest (bottom) row, shifting
//   horizontally each cycle.
//
// Architecture:
//   - One shift register per row (WINDOW_SIZE total), WINDOW_SIZE columns
//     deep each. Rows 0..WINDOW_SIZE-2 are fed from i_rows (line_buffer);
//     row WINDOW_SIZE-1 is fed directly from the live i_pixel.
//   - Column-validity counter re-arms on every row boundary, not just once
//     at start-of-frame, so windows spanning two different row bands are
//     correctly marked invalid.
//
// Data Flow:
//   - i_rows (buffered previous rows) and i_pixel (live current row) shift
//     into the window registers each cycle i_write_en is asserted.
//   - o_window exposes the full flattened window every cycle.
//   - o_valid_out reflects whether the current window is fully formed from
//     a single, consistent row band and column range.
//
// Timing:
//   - Window contents, column counter, and o_valid_out are all registered,
//     updated on the rising clock edge while i_write_en is asserted.
//   - o_valid_out lags the shift by one cycle (registered).
//   - CRITICAL: o_valid_out is explicitly forced low on any cycle
//     i_write_en is NOT asserted. This is deliberate, not a reset-only
//     behavior — without it, o_valid_out would simply hold its last
//     registered value forever once streaming stops, and if that last
//     value happened to be 1, the stale valid (and the stale window data
//     behind it) would propagate indefinitely through every downstream
//     stage that registers unconditionally every cycle (multiplier_array,
//     adder_tree), permanently feeding output_fifo and preventing it from
//     ever draining to empty.
//
// Assumptions:
//   - i_row_done pulses for exactly one cycle at every row boundary.
//   - i_rows_ready is a sticky level from line_buffer, not a pulse.
//   - i_pixel is the SAME pixel, on the SAME cycle, being written into
//     line_buffer via i_write_en — i.e. i_write_en, i_pixel, i_rows, and
//     i_row_done all originate from the same upstream timebase.
//
// Parameters:
//   PIXEL_WIDTH : Width of each input/output pixel.
//   WINDOW_SIZE : Kernel dimension; window holds WINDOW_SIZE**2 pixels.
//------------------------------------------------------------------------------
module window_generator
   #(
      parameter int PIXEL_WIDTH = 8,
      parameter int WINDOW_SIZE = 3,

      localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
      localparam type col_cnt_t = logic [$clog2(WINDOW_SIZE + 1)-1:0]
   )(
      input logic clk,
      input logic rst_n,

      input logic   i_write_en,
      input logic   i_row_done,
      input logic   i_rows_ready,
      input pixel_t i_rows       [WINDOW_SIZE-1],
      input pixel_t i_pixel,

      output pixel_t o_window    [WINDOW_SIZE ** 2],
      output logic   o_valid_out
   );

   pixel_t   r_window  [WINDOW_SIZE][WINDOW_SIZE];
   col_cnt_t r_col_cnt;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         r_window    <= '{default: '0};
         r_col_cnt   <= '0;
         o_valid_out <= 1'b0;
      end else if (i_write_en) begin
         for (int i = 0; i < WINDOW_SIZE - 1; i++) begin
            for (int j = WINDOW_SIZE-1; j > 0; j--)
               r_window[i][j] <= r_window[i][j-1];
            r_window[i][0] <= i_rows[i];
         end

      
         for (int j = WINDOW_SIZE-1; j > 0; j--)
            r_window[WINDOW_SIZE-1][j] <= r_window[WINDOW_SIZE-1][j-1];
         r_window[WINDOW_SIZE-1][0] <= i_pixel;

         if (i_row_done)
            r_col_cnt <= '0;
         else if (r_col_cnt < col_cnt_t'(WINDOW_SIZE))
            r_col_cnt <= r_col_cnt + 1'b1;

         o_valid_out <= i_rows_ready && (r_col_cnt >= col_cnt_t'(WINDOW_SIZE-1));
      end else begin
         o_valid_out <= 1'b0;
      end
   end

   always_comb begin
      o_window = '{default: '0};
      for (int i = 0; i < WINDOW_SIZE ** 2; i++)
         o_window[i] = r_window[i / WINDOW_SIZE][i % WINDOW_SIZE];
   end

endmodule
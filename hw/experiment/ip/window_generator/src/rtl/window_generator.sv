//------------------------------------------------------------------------------
// Module: window_generator
//
// Description:
//   Extracts a WINDOW_SIZE x WINDOW_SIZE sliding window from LINE_NUM active
//   row streams provided by line_buffer, shifting horizontally each cycle.
//
// Architecture:
//   - One shift register per active row, WINDOW_SIZE columns deep.
//   - Column-validity counter re-arms on every row boundary, not just once
//     at start-of-frame, so windows spanning two different row bands are
//     correctly marked invalid.
//
// Data Flow:
//   - i_rows (current active rows from line_buffer) shift into the window
//     registers each cycle i_shift_en is asserted.
//   - o_window exposes the full flattened window every cycle.
//   - o_valid_out reflects whether the current window is fully formed from
//     a single, consistent row band and column range.
//
// Timing:
//   - Window contents, column counter, and o_valid_out are all registered,
//     updated on the rising clock edge while i_shift_en is asserted.
//   - o_valid_out lags the shift by one cycle (registered), consistent with
//     the rest of the pipeline's valid-signal convention.
//
// Assumptions:
//   - i_row_done pulses for exactly one cycle at every row boundary; used to
//     re-invalidate the window rather than relying on a one-time signal.
//   - i_rows_ready is a sticky level from line_buffer, not a pulse.
//   - i_shift_en and i_row_done are aligned to the same pixel stream that
//     drives i_rows (i.e., all three come from the same upstream timebase).
//
// Parameters:
//   PIXEL_WIDTH : Width of each input/output pixel.
//   WINDOW_SIZE : Kernel dimension; window holds WINDOW_SIZE**2 pixels.
//------------------------------------------------------------------------------
module window_generator #(
   parameter  int  PIXEL_WIDTH = 8,
   parameter  int  WINDOW_SIZE = 3,

   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type col_cnt_t = logic [$clog2(WINDOW_SIZE + 1)-1:0]
)(
   input  logic   clk,
   input  logic   rst_n,

   input  logic   i_shift_en,
   input  logic   i_row_done,     // pulses every row boundary from line_buffer
   input  logic   i_rows_ready,   // sticky: enough rows loaded upstream
   input  pixel_t i_rows[WINDOW_SIZE],

   output pixel_t o_window[WINDOW_SIZE ** 2],
   output logic   o_valid_out
);

   pixel_t   r_window[WINDOW_SIZE][WINDOW_SIZE];
   col_cnt_t r_col_cnt;   // columns shifted in since the last row boundary
   logic     r_valid_out;

   assign o_valid_out = r_valid_out;

   always_ff @(posedge clk or negedge rst_n) begin : window_registers
      if (!rst_n) begin : reset_window_registers
         r_window    <= '{default: '0};
         r_col_cnt   <= '0;
         r_valid_out <= 1'b0;
      end else if (i_shift_en) begin : shift_window_registers
         for (int i = 0; i < WINDOW_SIZE; i++) begin : shift_row
            for (int j = WINDOW_SIZE-1; j > 0; j--)
               r_window[i][j] <= r_window[i][j-1];
            r_window[i][0] <= i_rows[i];
         end

         // resets on EVERY row boundary, not just the first - this is the fix
         if (i_row_done)
            r_col_cnt <= '0;
         else if (r_col_cnt < col_cnt_t'(WINDOW_SIZE))
            r_col_cnt <= r_col_cnt + 1'b1;

         r_valid_out <= i_rows_ready && (r_col_cnt >= col_cnt_t'(WINDOW_SIZE-1));
      end
   end : window_registers

   always_comb begin : window_flattening
      o_window = '{default: '0};
      for (int i = 0; i < WINDOW_SIZE ** 2; i++)
         o_window[i] = r_window[i / WINDOW_SIZE][i % WINDOW_SIZE];
   end : window_flattening

endmodule
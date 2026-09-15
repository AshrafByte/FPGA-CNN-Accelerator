//------------------------------------------------------------------------------
// Module: window_generator
//
// Description:
//   N x N sliding window (N = WINDOW_SIZE) over the rows delivered by
//   line_buffer. Each window row is a WINDOW_SIZE-deep shift register of
//   PIXEL_WIDTH-bit registers fed by one line-buffer tap, so every accepted
//   pixel moves the window one column along the raster scan (stride 1).
//
// Tap order:
//   A new column enters at column index 0, so the flattened window is
//   row-ascending but column-descending:
//     o_window[r*N + c] == image[row + r][col + (N-1-c)]
//   The host writes each kernel row right to left to obtain a correlation.
//
// Valid:
//   A column counter, cleared by the line buffer's row-done pulse and advanced
//   on every write, counts the columns of the current row; o_valid is
//   registered and high when rows_ready is set and N-1 earlier columns of the
//   row are present, so the partial windows at the start of a row never appear.
//
// Timing:
//   - Latency 1: the window and o_valid are registered on the write edge.
//   - A stall (write enable low) holds every register.
//------------------------------------------------------------------------------
module window_generator #(
   parameter  int  PIXEL_WIDTH = 8,
   parameter  int  WINDOW_SIZE = 3,

   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type col_cnt_t = logic [$clog2(WINDOW_SIZE + 1)-1:0]
)(
   input  logic   clk,
   input  logic   rst_n,

   input  logic   i_write_en,
   input  logic   i_row_done,
   input  logic   i_rows_ready,
   input  pixel_t i_rows[WINDOW_SIZE],

   output pixel_t o_window[WINDOW_SIZE ** 2],
   output logic   o_valid
);

   pixel_t   r_window[WINDOW_SIZE][WINDOW_SIZE];
   col_cnt_t r_col_cnt;

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         r_window    <= '{default: '0};
         r_col_cnt   <= '0;
         o_valid <= 1'b0;
      end else if (i_write_en) begin
         for (int i = 0; i < WINDOW_SIZE; i++) begin
            for (int j = WINDOW_SIZE-1; j > 0; j--)
               r_window[i][j] <= r_window[i][j-1];
            r_window[i][0] <= i_rows[i];
         end

         if (i_row_done)
            r_col_cnt <= '0;
         else if (r_col_cnt < col_cnt_t'(WINDOW_SIZE))
            r_col_cnt <= r_col_cnt + 1'b1;

         o_valid <= i_rows_ready && (r_col_cnt >= col_cnt_t'(WINDOW_SIZE-1));
      end else begin
         o_valid <= 1'b0;
      end
   end

   always_comb begin
      o_window = '{default: '0};
      for (int i = 0; i < WINDOW_SIZE ** 2; i++)
         o_window[i] = r_window[i / WINDOW_SIZE][i % WINDOW_SIZE];
   end

endmodule

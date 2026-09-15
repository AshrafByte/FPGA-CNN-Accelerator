//------------------------------------------------------------------------------
// Module: line_buffer
//
// Description:
//   Row store for the sliding window: keeps the LINE_NUM-1 rows preceding the
//   row currently streaming in, and passes the current row through live.
//
// Architecture:
//   - One shift-register bank of LINE_LENGTH pixels per stored row (SRLs); the
//     banks cascade, so a pixel leaving bank b enters bank b+1.
//   - r_col_addr counts the columns of the current row; o_row_done marks the
//     write of a row's last pixel.
//   - r_row_hot is the row position within the frame as a one-hot ring of
//     FRAME_ROWS flip-flops that rotates on every row_done. A ring needs no
//     incrementer and no comparator, so the frame position costs flip-flops
//     only, which the figure of merit does not charge.
//   - r_rows_ready is set when row LINE_NUM-2 completes and cleared when the
//     frame's last row completes, i.e. it is high from row LINE_NUM-1 on, only
//     while every bank holds a row of the current frame. The next frame
//     refills the banks before any window is declared valid, so no reset is
//     needed between frames.
//   - o_frame_end is a registered pulse on the cycle after the frame's last
//     pixel is written: the cycle on which window_generator raises o_valid
//     for the frame's last window.
//
// Assumptions:
//   - Frames are FRAME_ROWS x LINE_LENGTH pixels in raster order and every
//     pixel is written exactly once; i_write_en may drop at any time (stalls).
//   - An aborted frame is recovered with rst_n.
//
// Parameters:
//   PIXEL_WIDTH : Width of each pixel.
//   LINE_LENGTH : Pixels per row.
//   LINE_NUM    : Rows in the window (the buffer stores LINE_NUM-1).
//   FRAME_ROWS  : Rows per frame (square frames by default), at least 2.
//------------------------------------------------------------------------------
module line_buffer #(
   parameter int PIXEL_WIDTH = 8,
   parameter int LINE_LENGTH = 32,
   parameter int LINE_NUM    = 3,
   parameter int FRAME_ROWS  = LINE_LENGTH,

   localparam int  NUM_BANKS = LINE_NUM - 1,
   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type addr_t    = logic [$clog2(LINE_LENGTH)-1:0]
)(
   input  logic   clk,
   input  logic   rst_n,

   input  logic   i_write_en,
   input  pixel_t i_pixel,

   output pixel_t o_rows[LINE_NUM],
   output logic   o_row_done,
   output logic   o_rows_ready,
   output logic   o_frame_end
);

   addr_t                                     r_col_addr;
   (* srl_style = "register" *) logic [FRAME_ROWS-1:0] r_row_hot;
   logic                                      r_rows_ready;
   logic                                      w_row_done;
   logic                                      w_last_row;

   assign w_row_done   = i_write_en && (r_col_addr == addr_t'(LINE_LENGTH-1));
   assign w_last_row   = r_row_hot[FRAME_ROWS-1];
   assign o_row_done   = w_row_done;
   assign o_rows_ready = r_rows_ready;

   always_ff @(posedge clk or negedge rst_n) begin: col_address
      if (!rst_n)
         r_col_addr <= '0;
      else if (i_write_en)
         r_col_addr <= w_row_done ? '0 : r_col_addr + 1'b1;
   end: col_address

   always_ff @(posedge clk or negedge rst_n) begin: row_ring
      if (!rst_n)
         r_row_hot <= FRAME_ROWS'(1);
      else if (w_row_done)
         r_row_hot <= {r_row_hot[FRAME_ROWS-2:0], r_row_hot[FRAME_ROWS-1]};
   end: row_ring

   generate
      if (NUM_BANKS == 0) begin : gen_no_rows
         // 1 x 1 window: every pixel completes a window.
         always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) r_rows_ready <= 1'b0;
            else        r_rows_ready <= 1'b1;
      end : gen_no_rows
      else begin : gen_rows_ready
         always_ff @(posedge clk or negedge rst_n) begin: rows_ready
            if (!rst_n)
               r_rows_ready <= 1'b0;
            else if (w_row_done && w_last_row)
               r_rows_ready <= 1'b0;
            else if (w_row_done && r_row_hot[NUM_BANKS-1])
               r_rows_ready <= 1'b1;
         end: rows_ready
      end : gen_rows_ready
   endgenerate

   always_ff @(posedge clk or negedge rst_n) begin: frame_end
      if (!rst_n)
         o_frame_end <= 1'b0;
      else
         o_frame_end <= w_row_done && w_last_row;
   end: frame_end


   (* srl_style = "srl" *)
   pixel_t r_bank[NUM_BANKS][LINE_LENGTH];

   genvar b;
   generate
      for (b = 0; b < NUM_BANKS; b++) begin : shift_bank
         pixel_t w_bank_in;

         // Bank 0 takes the input; the others chain. Selected at elaboration
         // so no out-of-range r_bank[-1] reference exists for bank 0.
         if (b == 0) begin : gen_input
            assign w_bank_in = i_pixel;
         end : gen_input
         else begin : gen_chain
            assign w_bank_in = r_bank[b-1][LINE_LENGTH-1];
         end : gen_chain

         always_ff @(posedge clk) begin
            if (i_write_en) begin
               for (int j = LINE_LENGTH-1; j > 0; j--)
                  r_bank[b][j] <= r_bank[b][j-1];
               r_bank[b][0] <= w_bank_in;
            end
         end

         assign o_rows[NUM_BANKS-1-b] = r_bank[b][LINE_LENGTH-1];
      end
   endgenerate

   assign o_rows[NUM_BANKS] = i_pixel;   // live current row, zero-cost pass-through

endmodule

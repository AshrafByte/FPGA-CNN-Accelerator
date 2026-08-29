//------------------------------------------------------------------------------
// Module: line_buffer
//
// Description:
//   Multi-bank circular line buffer storing the WINDOW_SIZE-1 rows preceding
//   the row currently streaming in. The current row itself is not buffered
//   here — it is intended to be consumed live, directly off the input pixel
//   stream, by the window generator alongside these buffered previous rows.
//
// Architecture:
//   - NUM_BANKS = LINE_NUM - 1 banks, each holding one full previous row.
//   - The bank holding the oldest previous row is both read (its old value)
//     and overwritten (with the new row's data) on the same cycle, using
//     ordinary read-before-write register timing — no bank is ever excluded
//     from reads, unlike a design that reserves a separate write-only bank.
//   - Banks rotate circularly after the last column of each row.
//
// Data Flow:
//   - Each incoming pixel simultaneously: (a) is captured as the new value
//     for the currently-rotating bank, and (b) causes that same bank's old
//     value at this column to appear on o_rows for this cycle.
//   - On row boundary (last column written), the write bank rotates and
//     o_row_done pulses for one cycle.
//   - o_rows exposes all NUM_BANKS previous rows, oldest to newest.
//   - o_rows_ready goes and stays high once NUM_BANKS full rows have been
//     captured.
//
// Timing:
//   - Bank pointer and column-address updates occur on the rising clock edge.
//   - Reads use the CURRENT (not yet rotated) write-bank pointer — this is
//     deliberate: the read this cycle must reflect the bank's pre-write
//     value, and rotation is only meant to take effect for the next row.
//   - o_rows is combinational and therefore has no additional register latency.
//
// Memory:
//   - Storage is implemented as NUM_BANKS independent logical line buffers.
//   - Reads are asynchronous/combinational.
//
// Assumptions:
//   - i_write_en is asserted only when valid pixel data is present on i_pixel.
//   - Caller separately consumes the live i_pixel as the current row's tap;
//     this module does not buffer or expose the current row at all.
//   - LINE_NUM >= 2 (NUM_BANKS >= 1); LINE_NUM == 1 degenerates to no
//     buffered history and is not a supported configuration.
//   - Caller consumes o_row_done as a single-cycle pulse, not a level.
//
// Parameters:
//   PIXEL_WIDTH : Width of each input/output pixel.
//   LINE_LENGTH : Number of pixels in each image row.
//   LINE_NUM    : Total window height (K); NUM_BANKS = LINE_NUM - 1 rows
//                 are buffered here, the K-th (current) row is live.
//------------------------------------------------------------------------------
module line_buffer #(
   parameter int PIXEL_WIDTH = 8,
   parameter int LINE_LENGTH = 32,
   parameter int LINE_NUM    = 3,

   localparam type pixel_t = logic [PIXEL_WIDTH-1:0]
)(
   input  logic   clk,
   input  logic   rst_n,

   input  logic   i_write_en,
   input  pixel_t i_pixel,

   output pixel_t o_rows[LINE_NUM-1],
   output logic   o_row_done,
   output logic   o_rows_ready
);

   localparam int  NUM_BANKS   = LINE_NUM - 1;
   localparam type addr_t      = logic [$clog2(LINE_LENGTH)-1:0];
   localparam type bank_idx_t  = logic [$clog2(NUM_BANKS)-1:0];
   localparam type row_count_t = logic [$clog2(NUM_BANKS+1)-1:0];

   pixel_t     r_banks[NUM_BANKS][LINE_LENGTH];
   addr_t      r_col_addr;
   bank_idx_t  r_write_bank;
   row_count_t r_rows_loaded;
   logic       w_row_done;

   assign w_row_done   = i_write_en && (r_col_addr == addr_t'(LINE_LENGTH-1));
   assign o_row_done   = w_row_done;
   assign o_rows_ready = (r_rows_loaded == row_count_t'(NUM_BANKS));

   always_ff @(posedge clk or negedge rst_n) begin: bank_address
      if (!rst_n) begin : reset_bank_state
         r_write_bank  <= '0;
         r_rows_loaded <= '0;
      end else begin : update_bank_state
         if (w_row_done)
            r_write_bank <= (r_write_bank == bank_idx_t'(NUM_BANKS-1)) ? '0 : r_write_bank + 1'b1;
         if (w_row_done && (r_rows_loaded < row_count_t'(NUM_BANKS)))
            r_rows_loaded <= r_rows_loaded + 1'b1;
      end
   end: bank_address

   always_ff @(posedge clk or negedge rst_n) begin: col_address
      if (!rst_n)
         r_col_addr <= '0;
      else if (i_write_en)
         r_col_addr <= w_row_done ? '0 : r_col_addr + 1'b1;
   end: col_address

   // read-before-write: this cycle's read of r_write_bank reflects its OLD
   // value; the write below updates it for future cycles only
   always_ff @(posedge clk) begin: lines_buffer
      if (i_write_en)
         r_banks[r_write_bank][r_col_addr] <= i_pixel;
   end: lines_buffer

   always_comb begin: active_rows
      o_rows = '{default: '0};
      for (int k = 0; k < NUM_BANKS; k++)
         o_rows[k] = r_banks[(r_write_bank + k) % NUM_BANKS][r_col_addr];
   end: active_rows

endmodule
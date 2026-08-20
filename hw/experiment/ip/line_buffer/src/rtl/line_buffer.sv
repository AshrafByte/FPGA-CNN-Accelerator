//------------------------------------------------------------------------------
// Module: line_buffer
//
// Description:
//   Multi-bank circular line buffer for streaming image processing.
//   Stores LINE_NUM + 1 image rows and continuously provides the
//   LINE_NUM active rows at the current column.
//
// Architecture:
//   - LINE_NUM active banks are exposed through o_rows.
//   - One additional bank is used as the current write bank.
//   - Banks rotate circularly after the last column of each row.
//   - A new pixel can be written every cycle while i_write_en is asserted.
//
// Data Flow:
//   - Input pixel is written into the current write bank at the current column.
//   - On row boundary (last column written), the write bank rotates circularly
//     and o_row_done pulses for one cycle.
//   - Active rows are read out combinationally as o_rows[], oldest to newest.
//   - o_rows_ready goes and stays high once LINE_NUM full rows have been loaded.
//
// Timing:
//   - Write bank and column-address updates occur on the rising clock edge.
//   - The row boundary is detected from the current column address.
//   - The write bank is rotated on the same cycle as the last pixel of a row,
//     allowing the final pixel to be written to the new bank without an
//     additional bubble cycle.
//   - o_rows is combinational and therefore has no additional register latency.
//
// Memory:
//   - Storage is implemented as NUM_BANKS independent logical line buffers.
//   - Reads are asynchronous/combinational.
//   - The implementation is intended to support one pixel write per cycle
//     and simultaneous access to all active rows.
//
// Assumptions:
//   - i_write_en is asserted only when valid pixel data is present on i_pixel.
//   - Caller consumes o_row_done as a single-cycle pulse, not a level.
//   - Reset is held long enough to fully clear internal pointers before
//     i_write_en is first asserted.
//
// Parameters:
//   PIXEL_WIDTH : Width of each input/output pixel.
//   LINE_LENGTH : Number of pixels in each image row.
//   LINE_NUM    : Number of active rows required by the processing window.
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

   output pixel_t o_rows[LINE_NUM],
   output logic   o_row_done,    
   output logic   o_rows_ready   
);

   localparam int  NUM_BANKS   = LINE_NUM + 1;
   localparam type addr_t      = logic [$clog2(LINE_LENGTH)-1:0];
   localparam type bank_idx_t  = logic [$clog2(NUM_BANKS)-1:0];
   localparam type row_count_t = logic [$clog2(LINE_NUM + 1)-1:0];

   pixel_t     r_banks[NUM_BANKS][LINE_LENGTH];
   addr_t      r_col_addr;
   bank_idx_t  r_write_bank;
   row_count_t r_rows_loaded;
   logic       w_row_done;

   assign w_row_done   = i_write_en && (r_col_addr == addr_t'(LINE_LENGTH-1));
   assign o_row_done   = w_row_done;
   assign o_rows_ready = (r_rows_loaded == row_count_t'(LINE_NUM));   

   always_ff @(posedge clk or negedge rst_n) begin: bank_address
      if (!rst_n) begin : reset_bank_state
         r_write_bank  <= '0;
         r_rows_loaded <= '0;
      end else begin : update_bank_state
         if (w_row_done)
            r_write_bank <= r_write_bank + 1'b1;
         if (w_row_done && (r_rows_loaded < row_count_t'(LINE_NUM)))
            r_rows_loaded <= r_rows_loaded + 1'b1;
      end
   end: bank_address

   always_ff @(posedge clk or negedge rst_n) begin: col_address
      if (!rst_n)
         r_col_addr <= '0;
      else if (i_write_en)
         r_col_addr <= w_row_done ? '0 : r_col_addr + 1'b1;
   end: col_address

   always_ff @(posedge clk) begin: lines_buffer
      if (i_write_en)
         r_banks[r_write_bank][r_col_addr] <= i_pixel;
   end: lines_buffer

   always_comb begin: active_rows
      o_rows = '{default: '0};
      for (int k = 0; k < LINE_NUM; k++)
         o_rows[k] = r_banks[(r_write_bank + k + 1) % NUM_BANKS][r_col_addr];
   end: active_rows

endmodule
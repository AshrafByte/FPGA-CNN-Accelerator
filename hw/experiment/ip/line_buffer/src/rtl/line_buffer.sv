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

   output pixel_t o_rows[LINE_NUM],   // now WINDOW_SIZE wide, not LINE_NUM-1
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
      if (!rst_n) begin
         r_write_bank  <= '0;
         r_rows_loaded <= '0;
      end else begin
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

   always_ff @(posedge clk) begin: lines_buffer
      if (i_write_en)
         r_banks[r_write_bank][r_col_addr] <= i_pixel;
   end: lines_buffer

   always_comb begin: active_rows
      o_rows = '{default: '0};
      for (int k = 0; k < NUM_BANKS; k++)
         o_rows[k] = r_banks[(r_write_bank + k) % NUM_BANKS][r_col_addr];
      o_rows[NUM_BANKS] = i_pixel;   // pass-through: current row, live, no storage
   end: active_rows

endmodule
module line_buffer #(
   parameter int PIXEL_WIDTH = 8,
   parameter int LINE_LENGTH = 32,
   parameter int LINE_NUM    = 3,

   localparam int  NUM_BANKS = LINE_NUM - 1,
   localparam type pixel_t   = logic [PIXEL_WIDTH-1:0],
   localparam type addr_t      = logic [$clog2(LINE_LENGTH)-1:0],
   localparam type row_count_t = logic [$clog2(NUM_BANKS+1)-1:0]
)(
   input  logic   clk,
   input  logic   rst_n,

   input  logic   i_write_en,
   input  pixel_t i_pixel,

   output pixel_t o_rows[LINE_NUM],
   output logic   o_row_done,
   output logic   o_rows_ready
);

   addr_t      r_col_addr;
   row_count_t r_rows_loaded;
   logic       w_row_done;

   assign w_row_done   = i_write_en && (r_col_addr == addr_t'(LINE_LENGTH-1));
   assign o_row_done   = w_row_done;
   assign o_rows_ready = (r_rows_loaded == row_count_t'(NUM_BANKS));

   always_ff @(posedge clk or negedge rst_n) begin: col_address
      if (!rst_n)
         r_col_addr <= '0;
      else if (i_write_en)
         r_col_addr <= w_row_done ? '0 : r_col_addr + 1'b1;
   end: col_address

   always_ff @(posedge clk or negedge rst_n) begin: row_load_count
      if (!rst_n)
         r_rows_loaded <= '0;
      else if (w_row_done && (r_rows_loaded < row_count_t'(NUM_BANKS)))
         r_rows_loaded <= r_rows_loaded + 1'b1;
   end: row_load_count


   pixel_t r_bank[NUM_BANKS][LINE_LENGTH];

   genvar b;
   generate
      for (b = 0; b < NUM_BANKS; b++) begin : shift_bank
         pixel_t w_bank_in;
         assign w_bank_in = (b == 0) ? i_pixel : r_bank[b-1][LINE_LENGTH-1];

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
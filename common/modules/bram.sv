module bram #(
   parameter  int  DEPTH      = 1024,
   parameter  int  DATA_WIDTH = 8,

   localparam type data_t = logic [DATA_WIDTH-1:0],
   localparam type addr_t = logic [$clog2(DEPTH)-1:0]
)(
   input  logic  clk,

   // Write port
   input  logic  i_we,
   input  addr_t i_waddr,
   input  data_t i_din,

   // Read port
   input  addr_t i_raddr,
   output data_t o_dout
);

   data_t r_mem [0:DEPTH-1];

   always_ff @(posedge clk) begin
      if (i_we)
         r_mem[i_waddr] <= i_din;
      o_dout <= r_mem[i_raddr];
   end

endmodule : bram
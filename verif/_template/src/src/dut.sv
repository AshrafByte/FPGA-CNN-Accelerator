// TODO delete this
module dut (
   input  logic [15:0] i_din,
   input  logic        clk,
   input  logic        rst_n,
   output logic [15:0] o_dout

);
   logic [15:0] accum;
   always_ff @(posedge clk, negedge rst_n)
      if (!rst_n) accum <= 0;
      else accum <= accum + i_din;

   assign o_dout = accum;
endmodule

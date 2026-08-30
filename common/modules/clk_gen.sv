module clk_gen 
#(
   parameter time CLK_PERIOD = 10ns
)(
   output logic clk
);

   initial begin
      clk = 1'b0;
      forever #(CLK_PERIOD/2) clk = ~clk;
   end

endmodule
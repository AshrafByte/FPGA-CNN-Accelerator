module dut_probe
   import serdes_common_pkg::*;
(
   dut_if vif,

   // GEN:BEGIN INPUT LIST
   input logic [15:0] i_din,
   // GEN:END

   // GEN:BEGIN OUTPUT LIST
   input [15:0] o_dout
   // GEN:END
);
   // GEN:BEGIN INPUT
   assign vif.i_din = i_din;
   // GEN:END

   // GEN:BEGIN OUTPUT
   assign vif.o_dout = o_dout;
   // GEN:END
endmodule

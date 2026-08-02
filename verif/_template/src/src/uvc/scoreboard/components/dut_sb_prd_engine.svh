//----------------------------------------------------------------------
// DUT scoreboard engine — no UVM registration needed.
// Provides low-level logic used by the scoreboard predictor.
//----------------------------------------------------------------------
class dut_sb_prd_engine;

   // GEN:REMOVE:BEGIN
   local int accum;
   // GEN:REMOVE:END

   extern function new();
   extern function void predict(input dut_uvc_item exp_h);

endclass


function dut_sb_prd_engine::new();
   // GEN:REMOVE:BEGIN
   accum = 0;
   // GEN:REMOVE:END
endfunction

// TODO Add expected calculation logic here.
// Available signals on exp_h:
// GEN:BEGIN INPUT
//   input : i_din
// GEN:END
// GEN:BEGIN OUTPUT
//   output: o_dout
// GEN:END
function void dut_sb_prd_engine::predict(input dut_uvc_item exp_h);
   // GEN:REMOVE:BEGIN
   accum += exp_h.i_din;
   exp_h.o_dout = accum;
   // GEN:REMOVE:END
endfunction

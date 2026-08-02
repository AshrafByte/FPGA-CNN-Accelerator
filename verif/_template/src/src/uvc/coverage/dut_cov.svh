class dut_cov extends uvm_subscriber #(dut_uvc_item);

   `uvm_component_utils(dut_cov)

   // TRANSACTION HANDLE ────────────────────────────────────────────────────────

   local dut_uvc_item tr;

   // TODO COVERGROUP ───────────────────────────────────────────────────────────────

   covergroup cg;

      option.per_instance = 1;
      option.at_least = 10;
      option.auto_bin_max = 16;
      
      // GEN:BEGIN INPUT
      cp_i_din: coverpoint tr.i_din {
         bins i_din[16] = {[0 : $]};
      }
      // GEN:END

      // GEN:BEGIN OUTPUT
      cp_o_dout: coverpoint tr.o_dout {
         bins o_dout[16] = {[0 : $]};
      }
      // GEN:END


   // TODO: add cross(es) manually

   endgroup


   // PUBLIC API ────────────────────────────────────────────────────────────────

   extern function new(input string name, uvm_component parent);

   extern function void write(input dut_uvc_item t);

endclass


// METHOD DEFINITIONS ───────────────────────────────────────────────────────────


// ─── CONSTRUCTOR ──────────────────────────────────────────────────────────────

function dut_cov::new(input string name, uvm_component parent);

   super.new(name, parent);

   cg = new();

endfunction


// ─── WRITE CALLBACK ───────────────────────────────────────────────────────────

function void dut_cov::write(input dut_uvc_item t);

   tr = t;
   if (tr == null) begin
      `log_low(("NULL Tr at Coverage Write"))
   end
   // COVERAGE SAMPLING LOG ────────────────────────────────────────────────────

   `log_high(("Sampling coverage for dut_uvc_item"))

   // SAMPLE COVERGROUP ────────────────────────────────────────────────────────

   cg.sample();

endfunction

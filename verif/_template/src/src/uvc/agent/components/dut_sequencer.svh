class dut_sequencer extends uvm_sequencer #(dut_uvc_item);
   `uvm_component_utils(dut_sequencer)

   extern function new(input string name, uvm_component parent);

endclass

function dut_sequencer::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction

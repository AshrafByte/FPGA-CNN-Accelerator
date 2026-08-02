`ifndef RAND_MACROS_SVH
`define RAND_MACROS_SVH

`define rand_with(tr, statements) \
   if (!(tr.randomize() with statements)) begin \
      `uvm_error("RAND_MACRO", "Randomization failed in base_seq") \
   end 

`define send_rand_with(tr, statements) \
   begin \
      start_item(tr); \
      `rand_with(tr,statements); \
      finish_item(tr); \
   end
`endif
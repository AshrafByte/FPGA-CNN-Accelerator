package uvm_common_pkg;

   import uvm_pkg::*;
   `include "uvm_macros.svh"

   `include "logger.svh"
   `include "custom_report_server.svh"
   `include "base_seq.svh"

   typedef bit bool;

   localparam real TDRIVE_PLACE_HOLDER = 0;
   localparam real TDRIVE_HS = 0.01;
   localparam real TDRIVE_LS = 0.1;
   const bit true = 1'b1;
   const bit false = 1'b0;

   // VERBOSITY PARSER ────────────────────────────────────────────────────────────


   function automatic uvm_verbosity parse_verbosity(input string arg_val);
      case (arg_val.toupper())
         "UVM_NONE", "NONE": return UVM_NONE;
         "UVM_LOW", "LOW": return UVM_LOW;
         "UVM_MEDIUM", "MEDIUM": return UVM_MEDIUM;
         "UVM_HIGH", "HIGH": return UVM_HIGH;
         "UVM_FULL", "FULL": return UVM_FULL;
         "UVM_DEBUG", "DEBUG": return UVM_DEBUG;
         default: `uvm_error("VERBOSITY_CFG", $sformatf("Invalid verbosity value '%s'", arg_val))
      endcase
      return UVM_MEDIUM;
   endfunction

endpackage

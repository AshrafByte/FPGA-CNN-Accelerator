package clk_uvc_pkg;
   timeunit 1ps / 1fs;
   import uvm_pkg::*;
   import uvm_common_pkg::*;
   import clk_logger_pkg::*;

   typedef enum {
      CLK_CMD_CONFIGURE,  // unified config command: base / drift / ssc / combination
      CLK_CMD_STOP        // explicit stop
   } clk_cmd_e;

   `include "uvm_macros.svh"
   `include "log_macros.svh"

   `include "clk_uvc_cfg.svh"
   `include "clk_item.svh"

   typedef uvm_sequencer#(clk_item) clk_sequencer;
   `include "clk_driver.svh"
   `include "clk_monitor.svh"

   `include "clk_uvc.svh"

   `include "seq_lib/clk_normal_seq.svh"
   `include "seq_lib/clk_drift_seq.svh"
   `include "seq_lib/clk_ssc_seq.svh"

endpackage

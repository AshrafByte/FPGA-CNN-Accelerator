package dut_uvc_pkg;

   // BASE UVM INFRASTRUCTURE ───────────────────────────────────────────────
   import uvm_pkg::*;
   import uvm_common_pkg::*;

   // DUT CORE FRAMEWORK DEPENDENCIES ────────────────────────────────────────
   import dut_logger_pkg::*;
   import rst_uvc_pkg::*;
   import serdes_common_pkg::*;

   // UVM / LOGGING INFRASTRUCTURE ───────────────────────────────────────────
   `include "uvm_macros.svh"
   `include "log_macros.svh"

   `include "dut_uvc_item.svh"

   // AGENT COMPONENTS ──────────────────────────────────────────────────
   `include "dut_sequencer.svh"
   `include "dut_driver.svh"
   `include "dut_monitor.svh"
   `include "dut_agent.svh"

   // SCOREBOARD COMPONENTS ──────────────────────────────────────────────────
   `include "dut_sb_prd_engine.svh"
   `include "dut_sb_comparator.svh"
   `include "dut_sb_predictor.svh"
   `include "dut_sb.svh"

   // COVERAGE COMPONENTS ────────────────────────────────────────────────────
   `include "dut_cov.svh"

   // UVC CORE LIBRARY ───────────────────────────────────────────────────────
   `include "dut_uvc_cfg.svh"
   `include "dut_uvc.svh"

endpackage

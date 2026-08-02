package rst_uvc_pkg;

   timeunit 1ps / 1fs;

   // IMPORTS ────────────────────────────────────────────────────────────────
   import uvm_pkg::*;
   import uvm_common_pkg::*;
   import rst_logger_pkg::*;
   `include "uvm_macros.svh"
   `include "log_macros.svh"
   // TYPE DECLARATION ────────────────────────────────────────────────────────
   // REPLACES rst_event_kind_e + rst_kind_e
   typedef enum {
      RST_ASSERT,
      RST_RELEASE,
      RST_SYNC_ASSERT,
      RST_SYNC_RELEASE
   } rst_event_kind_e;

   typedef enum int unsigned {
      RESET_PRI_SEQUENCER  = 10,  // Always first — clears item queue
      RESET_PRI_DRIVER     = 20,  // Second — restarts against clean sequencer
      RESET_PRI_MONITOR    = 30,  // Third — restarts collection
      RESET_PRI_SCOREBOARD = 40,  // Fourth — flushes reference model
      RESET_PRI_COVERAGE   = 50,  // Last — samples reset coverage
      RESET_PRI_DEFAULT    = 60   // Fallback if component does not specify
   } reset_priority_e;

   // CORE UVC COMPONENTS ─────────────────────────────────────────────────────
   `include "rst_item.svh"
   `include "rst_uvc_cfg.svh"

   typedef uvm_sequencer#(rst_item) rst_sequencer;

   `include "rst_driver.svh"
   `include "rst_monitor.svh"
   `include "rst_uvc.svh"

   // RESET MANAGEMENT LAYER ────────────────────────────────────────────────
   `include "reset_event.svh"
   `include "reset_listener.svh"
   `include "reset_manager.svh"

   `include "seq_lib/rst_normal_seq.svh"

endpackage

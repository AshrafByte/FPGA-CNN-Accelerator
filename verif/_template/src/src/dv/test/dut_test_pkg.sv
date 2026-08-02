package dut_test_pkg;

   // BASE UVM INFRASTRUCTURE ───────────────────────────────────────────────
   import uvm_pkg::*;
   import uvm_common_pkg::*;

   // DUT FRAMEWORK DEPENDENCIES ────────────────────────────────────────────
   import dut_logger_pkg::*;

   import dut_uvc_pkg::*;
   import clk_uvc_pkg::*;
   import rst_uvc_pkg::*;

   // SEQUENCE LAYER DEPENDENCY ─────────────────────────────────────────────
   import dut_sequence_pkg::*;

   // UVM / MACROS INFRASTRUCTURE ───────────────────────────────────────────
   `include "uvm_macros.svh"
   `include "log_macros.svh"

   // TEST LIBRARY ───────────────────────────────────────────────────────────
   `include "dut_base_test.svh"
   `include "dut_test.svh"

endpackage

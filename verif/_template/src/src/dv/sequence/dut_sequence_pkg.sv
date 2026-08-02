package dut_sequence_pkg;
   timeunit 1ps / 1fs;
   // BASE UVM INFRASTRUCTURE ───────────────────────────────────────────────
   import uvm_pkg::*;
   import uvm_common_pkg::*;

   // DUT FRAMEWORK DEPENDENCIES ────────────────────────────────────────────
   import dut_logger_pkg::*;

   // DUT USED UVCS
   import dut_uvc_pkg::*;
   import rst_uvc_pkg::*;
   import clk_uvc_pkg::*;

   // UVM / LOGGING INFRASTRUCTURE ───────────────────────────────────────────
   `include "uvm_macros.svh"
   `include "log_macros.svh"
   `include "rand_macros.svh"
   // SEQUENCE LIBRARY ───────────────────────────────────────────────────────
   `include "seq/dut_seq.svh"


   // VIRTUAL SEQUENCE LIBRARY ───────────────────────────────────────────────
   `include "vseq/dut_base_vseq.svh"
   `include "vseq/dut_vseq.svh"

endpackage

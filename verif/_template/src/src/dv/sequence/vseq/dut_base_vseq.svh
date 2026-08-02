class dut_base_vseq extends uvm_sequence #(uvm_sequence_item);

   `uvm_object_utils(dut_base_vseq)

   // SEQUENCER HANDLES ────────────────────────────────────────────────────────

   dut_sequencer dut_sqr_h;
   rst_sequencer rst_sqr_h;
   clk_sequencer clk_sqr_h;

   int m_total_seq_items = 0;
   // CONSTRUCTOR ───────────────────────────────────────────────────────────────

   extern function new(input string name = "dut_base_vseq");
   extern function int get_total_seq_items();

endclass


// METHOD DEFINITIONS ───────────────────────────────────────────────────────────


// ─── CONSTRUCTOR ──────────────────────────────────────────────────────────────

function dut_base_vseq::new(input string name = "dut_base_vseq");
   super.new(name);
endfunction

function int dut_base_vseq::get_total_seq_items();
   return m_total_seq_items;
endfunction

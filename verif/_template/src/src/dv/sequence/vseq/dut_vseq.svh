class dut_vseq extends dut_base_vseq;
   `uvm_object_utils(dut_vseq)

   dut_seq        dut_seq_h;
   clk_normal_seq clk_seq_h;
   rst_normal_seq rst_seq_h;

   extern function new(input string name = "dut_vseq");
   extern virtual task body();
   extern virtual task post_body();

endclass

function dut_vseq::new(input string name = "dut_vseq");
   super.new(name);
   `log_create(("dut_vseq created"))
endfunction

task dut_vseq::body();
   // CREATE ─────────────────────────────────────────────
   dut_seq_h = dut_seq::type_id::create("dut_seq_h");
   clk_seq_h = clk_normal_seq::type_id::create("clk_seq_h");
   rst_seq_h = rst_normal_seq::type_id::create("rst_seq_h");

   // CONFIGURE ──────────────────────────────────────────
   clk_seq_h.set_freq_mhz(100);
   rst_seq_h.set_pulse(10ns);

   // START ──────────────────────────────────────────────
   `log_medium(("Starting DUT, clock, and reset sequences in parallel"))
   fork
      rst_seq_h.start(rst_sqr_h);
      clk_seq_h.start(clk_sqr_h);
      dut_seq_h.start(dut_sqr_h);
   join

   `log_low(("Virtual sequence completed"))
endtask

task dut_vseq::post_body();
   m_total_seq_items = dut_seq_h.get_total_seq_items();
endtask

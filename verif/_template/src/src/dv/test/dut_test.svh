class dut_test extends dut_base_test;

   `uvm_component_utils(dut_test)

   // CONSTRUCTOR ───────────────────────────────────────────────────────────────

   extern function new(input string name, input uvm_component parent);

   // CONFIGURATION HOOKS ───────────────────────────────────────────────────────

   // extern virtual function void configure_dut_uvc(input dut_uvc_cfg cfg);

   // extern virtual function void configure_clk_uvc(input clk_uvc_cfg cfg);

   // extern virtual function void configure_rst_uvc(input rst_uvc_cfg cfg);

   // PHASES ────────────────────────────────────────────────────────────────────

   extern task run_phase(input uvm_phase phase);

endclass


// METHOD DEFINITIONS ───────────────────────────────────────────────────────────


// CONSTRUCTOR ──────────────────────────────────────────────────────────────

function dut_test::new(input string name, input uvm_component parent);
   super.new(name, parent);
endfunction


// TODO RUN PHASE ────────────────────────────────────────────────────────────────

task dut_test::run_phase(input uvm_phase phase);

   dut_vseq vseq;

   // TEST START ────────────────────────────────────────────────────────────────

   phase.raise_objection(this, $sformatf("'%s' run_phase started", get_type_name()));

   `log_low(("Starting DUT test"))

   // CREATE VIRTUAL SEQUENCE ──────────────────────────────────────────────────

   `log_create(("Creating virtual sequence"))

   vseq = dut_vseq::type_id::create("vseq");

   // INITIALIZE VIRTUAL SEQUENCE ──────────────────────────────────────────────

   init_vseq(vseq);

   // EXECUTE VIRTUAL SEQUENCE ─────────────────────────────────────────────────

   `log_medium(("Starting virtual sequence"))

   vseq.start(null);

   `log_low(("Virtual sequence completed"))

   // TEST COMPLETE ────────────────────────────────────────────────────────────

   uvm_config_db#(int)::set(null, "*", "total_seq_items", (vseq.get_total_seq_items() + 1));

   phase.drop_objection(this, $sformatf("'%s' run_phase completed", get_type_name()));

   `log_low(("DUT test completed"))

endtask

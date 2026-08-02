class dut_base_test extends uvm_test;

   `uvm_component_utils(dut_base_test)

   // UVCS ──────────────────────────────────────────────────────────────────────
   dut_uvc m_dut_uvc;
   clk_uvc m_clk_uvc;
   rst_uvc m_rst_uvc;

   // MANAGERS ──────────────────────────────────────────────────────────────────
   reset_manager m_rst_mgr;

   // CONSTRUCTOR ───────────────────────────────────────────────────────────────
   extern function new(input string name, input uvm_component parent);

   // CONFIGURATION HOOKS ───────────────────────────────────────────────────────
   extern virtual function void configure_dut_uvc(input dut_uvc_cfg cfg);
   extern virtual function void configure_clk_uvc(input clk_uvc_cfg cfg);
   extern virtual function void configure_rst_uvc(input rst_uvc_cfg cfg);
   extern virtual function void init_vseq(input dut_vseq vseq);

   // PHASES ────────────────────────────────────────────────────────────────────
   extern function void build_phase(input uvm_phase phase);
   extern function void connect_phase(input uvm_phase phase);
   extern function void end_of_elaboration_phase(input uvm_phase phase);
   extern function void start_of_simulation_phase(input uvm_phase phase);

endclass


// ─────────────────────────────────────────────────────────────────────────────
// CONSTRUCTOR
// ─────────────────────────────────────────────────────────────────────────────
function dut_base_test::new(input string name, input uvm_component parent);
   super.new(name, parent);
   `log_build(("dut_base_test constructed"))
endfunction


// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION HOOKS
// ─────────────────────────────────────────────────────────────────────────────
function void dut_base_test::configure_dut_uvc(input dut_uvc_cfg cfg);

   virtual dut_if vif;

   `log_cfg(("Configuring DUT UVC configuration object"))

   if (!uvm_config_db#(virtual dut_if)::get(this, "", "dut_vif", vif)) begin
      `log_cfg_err(("DUT virtual interface not found in uvm_config_db"))
   end

   cfg.set_vif(vif);
   cfg.set_activity(UVM_ACTIVE);

   cfg.enable_scoreboard(true);
   cfg.enable_coverage(false);

endfunction


function void dut_base_test::configure_clk_uvc(input clk_uvc_cfg cfg);

   `log_cfg(("Configuring clock UVC configuration object"))

   if (!uvm_config_db#(virtual clk_if)::get(this, "", "clk_vif", cfg.m_vif)) begin
      `log_cfg_err(("Clock virtual interface not found in uvm_config_db"))
   end

   cfg.active = UVM_ACTIVE;

endfunction


function void dut_base_test::configure_rst_uvc(input rst_uvc_cfg cfg);

   `log_cfg(("Configuring reset UVC configuration object"))

   if (!uvm_config_db#(virtual rst_if)::get(this, "", "rst_vif", cfg.m_vif)) begin
      `log_cfg_err(("Reset virtual interface not found in uvm_config_db"))
   end

   cfg.active     = UVM_ACTIVE;
   cfg.active_low = true;

endfunction


function void dut_base_test::init_vseq(input dut_vseq vseq);

   `log_medium(("Initializing virtual sequence handles"))

   vseq.dut_sqr_h = m_dut_uvc.get_sqr();
   vseq.clk_sqr_h = m_clk_uvc.get_sqr();
   vseq.rst_sqr_h = m_rst_uvc.get_sqr();

endfunction


// ─────────────────────────────────────────────────────────────────────────────
// BUILD PHASE
// ─────────────────────────────────────────────────────────────────────────────
function void dut_base_test::build_phase(input uvm_phase phase);

   dut_uvc_cfg          dut_cfg;
   clk_uvc_cfg          clk_cfg;
   rst_uvc_cfg          rst_cfg;
   custom_report_server custom_server;

   super.build_phase(phase);

   // CREATE CONFIG OBJECTS
   dut_cfg = dut_uvc_cfg::type_id::create("dut_uvc_cfg");
   clk_cfg = clk_uvc_cfg::type_id::create("clk_uvc_cfg");
   rst_cfg = rst_uvc_cfg::type_id::create("rst_uvc_cfg");

   // REPORT SERVER
   `log_build(("Applying custom report server"))

   custom_server = custom_report_server::type_id::create("custom_report_server");
   uvm_report_server::set_server(custom_server);
   custom_server.set_timeformat();

   // CONFIGURE UVCS
   configure_dut_uvc(dut_cfg);
   configure_clk_uvc(clk_cfg);
   configure_rst_uvc(rst_cfg);

   // CREATE UVCS
   m_dut_uvc = dut_uvc::type_id::create("dut_uvc", this);
   m_clk_uvc = clk_uvc::type_id::create("clk_uvc", this);
   m_rst_uvc = rst_uvc::type_id::create("rst_uvc", this);

   // APPLY CONFIGURATION
   `log_build(("Configuring DUT UVC"))
   m_dut_uvc.set_cfg(dut_cfg);

   `log_build(("Configuring clock UVC"))
   m_clk_uvc.set_cfg(clk_cfg);

   `log_build(("Configuring reset UVC"))
   m_rst_uvc.set_cfg(rst_cfg);

   // MANAGER
   `log_build(("Creating reset manager"))
   m_rst_mgr = reset_manager::type_id::create("rst_mgr", this);

   // TODO: Add reset manager configuration hooks if needed
   // m_rst_mgr.enable_sync_rst();
endfunction


// ─────────────────────────────────────────────────────────────────────────────
// CONNECT PHASE
// ─────────────────────────────────────────────────────────────────────────────
function void dut_base_test::connect_phase(input uvm_phase phase);
   m_rst_uvc.m_ap.connect(m_rst_mgr.m_ap_imp);
endfunction


// ─────────────────────────────────────────────────────────────────────────────
// END OF ELABORATION
// ─────────────────────────────────────────────────────────────────────────────
function void dut_base_test::end_of_elaboration_phase(input uvm_phase phase);

   super.end_of_elaboration_phase(phase);

   `log_low(("End of elaboration phase completed"))

endfunction


// ─────────────────────────────────────────────────────────────────────────────
// START OF SIMULATION
// ─────────────────────────────────────────────────────────────────────────────
function void dut_base_test::start_of_simulation_phase(input uvm_phase phase);

   super.start_of_simulation_phase(phase);

   if (bit'(uvm_report_enabled(UVM_HIGH))) begin
      print();
      uvm_factory::get().print();
   end

   `log_low(("Start of simulation phase completed"))

endfunction

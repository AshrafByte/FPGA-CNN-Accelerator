class dut_uvc extends uvm_env;

   `uvm_component_utils(dut_uvc)

   // OWNED COMPONENTS ─────────────────────────────────────────────────────────

   local dut_agent m_dut_agent;
   local dut_sb    m_dut_sb;
   local dut_cov   m_dut_cov;

   // CONFIG ───────────────────────────────────────────────────────────────────

   local dut_uvc_cfg m_uvc_cfg;

   // PUBLIC API ───────────────────────────────────────────────────────────────

   extern function new(input string name, uvm_component parent);

   extern function void set_cfg(input dut_uvc_cfg cfg);
   extern function dut_uvc_cfg get_cfg();
   extern function dut_sequencer get_sqr();

   extern function void build_phase(input uvm_phase phase);
   extern function void connect_phase(input uvm_phase phase);
   extern function void end_of_elaboration_phase(input uvm_phase phase);

endclass


// ─── CONSTRUCTOR ─────────────────────────────────────────────────────────────

function dut_uvc::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


// ─── CONFIG ACCESS ────────────────────────────────────────────────────────────

function dut_uvc_cfg dut_uvc::get_cfg();

   if (m_uvc_cfg == null) begin
      m_uvc_cfg = dut_uvc_cfg::get_cfg(this);
      `log_build(("Environment configuration acquired"))
   end

   return m_uvc_cfg;

endfunction


function void dut_uvc::set_cfg(input dut_uvc_cfg cfg);
   m_uvc_cfg = cfg;
endfunction


// ─── SEQUENCER ACCESS ────────────────────────────────────────────────────────

function dut_sequencer dut_uvc::get_sqr();

   `log_full(("Entering dut_uvc::get_sqr()"))

   if (m_dut_agent == null) begin
      `log_cfg_err(("m_dut_agent is NULL in dut_uvc::get_sqr()"))
      return null;
   end

   `log_high(("Returning sequencer handle from dut_agent"))
   return m_dut_agent.get_sqr();

endfunction


// ─── BUILD PHASE ──────────────────────────────────────────────────────────────

function void dut_uvc::build_phase(input uvm_phase phase);

   super.build_phase(phase);
   m_uvc_cfg = this.get_cfg();

   if (m_uvc_cfg.get_vif() == null) begin
      `log_cfg_err("DUT virtual interface is null. Configure it before build.")
   end

   m_dut_agent = dut_agent::type_id::create("m_dut_agent", this);
   m_dut_agent.set_vif(m_uvc_cfg.get_vif());
   m_dut_agent.set_activity(m_uvc_cfg.get_activity());

   `log_build(("DUT agent created"))

   if (m_uvc_cfg.has_scoreboard()) begin
      m_dut_sb = dut_sb::type_id::create("m_dut_sb", this);
      `log_build(("Scoreboard created"))
   end

   if (m_uvc_cfg.has_coverage()) begin
      m_dut_cov = dut_cov::type_id::create("m_dut_cov", this);
      `log_build(("Coverage component created"))
   end

endfunction


// ─── CONNECT PHASE ────────────────────────────────────────────────────────────

function void dut_uvc::connect_phase(input uvm_phase phase);

   super.connect_phase(phase);

   if (m_uvc_cfg.has_scoreboard()) begin
      `log_connect(("Connecting agent streams to scoreboard"))
      m_dut_agent.ap_input.connect(m_dut_sb.ap_input);
      m_dut_agent.ap_output.connect(m_dut_sb.ap_output);
   end

   if (m_uvc_cfg.has_coverage()) begin
      `log_connect(("Connecting agent stream to coverage"))
      m_dut_agent.ap_input.connect(m_dut_cov.analysis_export);
   end

   `log_connect(("Environment connections complete"))

endfunction


// ─── END OF ELABORATION PHASE ────────────────────────────────────────────────

function void dut_uvc::end_of_elaboration_phase(input uvm_phase phase);

   uvm_verbosity v;
   string        arg_val;

   super.end_of_elaboration_phase(phase);

   v = m_uvc_cfg.get_log_verbosity();

   if ($value$plusargs("DUT_VERBOSITY=%s", arg_val)) begin
      v = parse_verbosity(arg_val);
      `log_end_of_elaboration(("Verbosity overridden via plusarg: %s", arg_val))
   end

   set_report_verbosity_level(v);

   m_dut_agent.set_report_verbosity_level_hier(v);
   if (m_uvc_cfg.has_scoreboard()) m_dut_sb.set_report_verbosity_level_hier(v);
   if (m_uvc_cfg.has_coverage()) m_dut_cov.set_report_verbosity_level_hier(v);

   `log_end_of_elaboration(("Final DUT Environment verbosity set to: %s", v))

endfunction

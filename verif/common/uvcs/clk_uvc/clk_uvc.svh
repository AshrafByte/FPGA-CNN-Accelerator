class clk_uvc extends uvm_agent;

   `uvm_component_utils(clk_uvc)

   // CONFIGURATION HANDLE ───────────────────────────────────────────────────────
   clk_uvc_cfg                   m_cfg;

   // INTERNAL COMPONENT HANDLES ────────────────────────────────────────────────
   clk_driver                    m_driver;
   clk_sequencer                 m_sqr;
   clk_monitor                   m_monitor;

   // EXTERNAL BROADCAST PORT ───────────────────────────────────────────────────
   uvm_analysis_port #(clk_item) m_ap;

   // PUBLIC API ─────────────────────────────────────────────────────────────────
   extern function new(input string name, uvm_component parent);
   extern function clk_sequencer get_sqr();
   extern function void set_cfg(input clk_uvc_cfg cfg);
   extern virtual function void build_phase(input uvm_phase phase);
   extern virtual function void connect_phase(input uvm_phase phase);

endclass


// ─────────────────────────────────────────────────────────────────────────────
// CONSTRUCTOR
// ─────────────────────────────────────────────────────────────────────────────
function clk_uvc::new(input string name, uvm_component parent);
   super.new(name, parent);
   `log_build(("clk_uvc constructed: %s", name))
endfunction


// ─────────────────────────────────────────────────────────────────────────────
// GET SEQUENCER
// ─────────────────────────────────────────────────────────────────────────────
function clk_sequencer clk_uvc::get_sqr();

   `log_full(("Entering clk_uvc::get_sqr()"))

   if (this.m_sqr != null) begin

      `log_high(("Returning clk_sequencer handle from clk_uvc"))
      return m_sqr;

   end

   `log_cfg_err("clk_sequencer is NULL in clk_uvc (agent not configured or inactive)")

   return null;

endfunction

function void clk_uvc::set_cfg(input clk_uvc_cfg cfg);
   this.m_cfg = cfg;
endfunction

// ─────────────────────────────────────────────────────────────────────────────
// BUILD PHASE
// ─────────────────────────────────────────────────────────────────────────────
function void clk_uvc::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   `log_build(("Building clk_uvc"))

   // CONFIG ───────────────────────────────────────────────────────────────
   if (m_cfg == null) m_cfg = clk_uvc_cfg::get_cfg(this);

   // ANALYSIS PORT ────────────────────────────────────────────────────────
   m_ap            = new("m_ap", this);

   // MONITOR (always active) ──────────────────────────────────────────────
   m_monitor       = clk_monitor::type_id::create("m_monitor", this);
   m_monitor.vif   = m_cfg.m_vif;
   m_monitor.m_cfg = m_cfg;

   `log_build(("clk_monitor created and configured"))

   // ACTIVE MODE COMPONENTS ───────────────────────────────────────────────
   if (m_cfg.active == UVM_ACTIVE) begin

      `log_connect(("clk_uvc configured in ACTIVE mode"))

      m_driver       = clk_driver::type_id::create("m_driver", this);
      m_sqr          = clk_sequencer::type_id::create("m_sqr", this);

      m_driver.vif   = m_cfg.m_vif;
      m_driver.m_cfg = m_cfg;

      `log_build(("clk_driver and clk_sequencer created"))

   end
   else begin
      `log_low(("clk_uvc configured in PASSIVE mode"))
   end

endfunction


// ─────────────────────────────────────────────────────────────────────────────
// CONNECT PHASE
// ─────────────────────────────────────────────────────────────────────────────
function void clk_uvc::connect_phase(input uvm_phase phase);

   super.connect_phase(phase);

   `log_connect(("Connecting clk_uvc components"))

   // MONITOR → AGENT ANALYSIS PORT ───────────────────────────────────────
   if (m_monitor != null) begin
      m_monitor.m_ap.connect(this.m_ap);
      `log_connect(("clk_monitor connected to clk_uvc analysis port"))
   end

   // DRIVER + SEQUENCER ───────────────────────────────────────────────────
   if (m_cfg.active == UVM_ACTIVE) begin

      if (m_driver == null || m_sqr == null) begin
         `log_cfg_err("clk_uvc missing driver or sequencer in ACTIVE mode")
      end

      m_driver.seq_item_port.connect(m_sqr.seq_item_export);

      `log_connect(("clk_driver connected to clk_sequencer"))

   end

   `log_connect(("clk_uvc connect_phase completed"))

endfunction

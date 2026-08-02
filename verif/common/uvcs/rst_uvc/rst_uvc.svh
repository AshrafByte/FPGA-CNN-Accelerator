class rst_uvc extends uvm_agent;

   `uvm_component_utils(rst_uvc)

   // CONFIGURATION ──────────────────────────────────────────────────────────────

   rst_uvc_cfg                   m_cfg;

   // INTERNAL COMPONENTS ────────────────────────────────────────────────────────

   rst_driver                    m_drv;
   rst_monitor                   m_mon;
   uvm_sequencer #(rst_item)     m_sqr;

   // EXTERNAL ANALYSIS PORT ─────────────────────────────────────────────────────

   uvm_analysis_port #(rst_item) m_ap;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name, uvm_component parent);
   extern function rst_sequencer get_sqr();
   extern function void set_cfg(input rst_uvc_cfg cfg);
   extern virtual function void build_phase(input uvm_phase phase);
   extern virtual function void connect_phase(input uvm_phase phase);

endclass


// ──────────────────────────────────────────────────────────────────────────────
// ----------------------------- METHOD DEFINITIONS ----------------------------- 
// ──────────────────────────────────────────────────────────────────────────────

// ──────────────────────────────────────────────────────────────────────────────
// CONSTRUCTOR 
// ──────────────────────────────────────────────────────────────────────────────

function rst_uvc::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction

// ──────────────────────────────────────────────────────────────────────────────
// GET SQR
// ──────────────────────────────────────────────────────────────────────────────
function rst_sequencer rst_uvc::get_sqr();

   // FULL ────────────────────────────────────────────────────────────────
   `log_full(("Entering rst_uvc::get_sqr()"))

   if (m_sqr != null) begin

      // HIGH ─────────────────────────────────────────────────────────────
      `log_high(("Returning rst_sequencer handle from rst_uvc"))
      return m_sqr;

   end

   // CFG ERROR ───────────────────────────────────────────────────────────
   `log_cfg_err(
      "rst_sequencer is NULL inside rst_uvc::get_sqr() (agent not properly built or configured)")

   return null;

endfunction

function void rst_uvc::set_cfg(input rst_uvc_cfg cfg);
   this.m_cfg = cfg;
endfunction

// ──────────────────────────────────────────────────────────────────────────────
// BUILD PHASE
// ──────────────────────────────────────────────────────────────────────────────
function void rst_uvc::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   if (m_cfg == null) m_cfg = rst_uvc_cfg::get_cfg(this);

   // MONITOR (always active) ───────────────────────────────────────────────────

   m_mon = rst_monitor::type_id::create("m_mon", this);

   // ANALYSIS PORT ─────────────────────────────────────────────────────────────

   m_ap  = new("m_ap", this);

   // ACTIVE COMPONENTS ─────────────────────────────────────────────────────────

   if (m_cfg.active == UVM_ACTIVE) begin

      m_drv = rst_driver::type_id::create("m_drv", this);
      m_sqr = uvm_sequencer#(rst_item)::type_id::create("m_sqr", this);

   end

endfunction

// ──────────────────────────────────────────────────────────────────────────────
// CONNECT PHASE
// ──────────────────────────────────────────────────────────────────────────────
function void rst_uvc::connect_phase(input uvm_phase phase);

   super.connect_phase(phase);

   // CONFIG WIRING ────────────────────────────────────────────────────────────
   m_mon.m_vif = m_cfg.m_vif;

   if (m_cfg.active == UVM_ACTIVE) begin
      m_drv.m_vif = m_cfg.m_vif;
      m_drv.seq_item_port.connect(m_sqr.seq_item_export);
   end

   // MONITOR → RESET MANAGER ──────────────────────────────────────────────────
   m_mon.m_ap.connect(m_ap);

endfunction

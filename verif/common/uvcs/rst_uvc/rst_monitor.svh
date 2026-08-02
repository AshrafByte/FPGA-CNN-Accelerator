class rst_monitor extends uvm_monitor;

   `uvm_component_utils(rst_monitor)

   // STRUCTURAL LINKS ───────────────────────────────────────────────────────────

   virtual rst_if                m_vif;

   // ANALYSIS PORT ─────────────────────────────────────────────────────────────

   uvm_analysis_port #(rst_item) m_ap;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name, uvm_component parent);
   extern virtual function void build_phase(input uvm_phase phase);
   extern virtual task run_phase(input uvm_phase phase);

   // INTERNAL TASKS ─────────────────────────────────────────────────────────────

   extern protected task monitor_normal_reset();
   extern protected task monitor_sync_reset();
   extern protected function void publish(input rst_event_kind_e evt, input realtime ts);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

// CONSTRUCTOR ──────────────────────────────────────────────────────────────────

function rst_monitor::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


// BUILD PHASE ──────────────────────────────────────────────────────────────────

function void rst_monitor::build_phase(input uvm_phase phase);
   super.build_phase(phase);
   m_ap = new("m_ap", this);
endfunction


// RUN PHASE ────────────────────────────────────────────────────────────────────

task rst_monitor::run_phase(input uvm_phase phase);

   if (m_vif == null) `uvm_fatal("RST_MON", "No rst_if provided")

   fork
      monitor_normal_reset();
      monitor_sync_reset();
   join

endtask


// NORMAL RESET (rst_n) ────────────────────────────────────────────────────────

task rst_monitor::monitor_normal_reset();

   logic last_state;

   last_state = m_vif.rst_n;

   forever begin
      @(m_vif.rst_n);

      if (m_vif.rst_n !== last_state && (m_vif.rst_n === 1'b0 || m_vif.rst_n === 1'b1)) begin
         publish((m_vif.rst_n) ? RST_RELEASE : RST_ASSERT, $realtime);
         last_state = m_vif.rst_n;
      end
   end

endtask


// SYNC RESET (rst_n_sync) ──────────────────────────────────────────────────────

task rst_monitor::monitor_sync_reset();

   logic last_state;

   last_state = m_vif.rst_n_sync;

   forever begin
      @(m_vif.rst_n_sync);

      if (m_vif.rst_n_sync !== last_state &&
          (m_vif.rst_n_sync === 1'b0 || m_vif.rst_n_sync === 1'b1)) begin
         publish((m_vif.rst_n_sync) ? RST_SYNC_RELEASE : RST_SYNC_ASSERT, $realtime);
         last_state = m_vif.rst_n_sync;
      end
   end

endtask


// PUBLISH HELPER ─────────────────────────────────────────────────────────────

function void rst_monitor::publish(input rst_event_kind_e evt, input realtime ts);

   rst_item tr;

   tr           = rst_item::type_id::create("tr");
   tr.rst_event = evt;
   tr.timestamp = ts;

   m_ap.write(tr);

endfunction

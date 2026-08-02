class dut_agent extends uvm_agent;

   `uvm_component_utils(dut_agent)

   // Configuration
   local virtual dut_if          m_vif;
   local uvm_active_passive_enum m_activity = UVM_PASSIVE;

   // Analysis streams
   uvm_analysis_port #(dut_uvc_item) ap_input;
   uvm_analysis_port #(dut_uvc_item) ap_output;

   // Active/passive components
   local dut_driver    m_drv;
   local dut_monitor   m_mon;
   local dut_sequencer m_sqr;

   // Public API
   extern function new(input string name, uvm_component parent);

   extern function void set_vif(input virtual dut_if vif);
   extern function void set_activity(input uvm_active_passive_enum activity);
   extern function dut_sequencer get_sqr();

   extern virtual function void build_phase(input uvm_phase phase);
   extern virtual function void connect_phase(input uvm_phase phase);

endclass


// Constructor
function dut_agent::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


// Configuration
function void dut_agent::set_vif(input virtual dut_if vif);
   m_vif = vif;
endfunction

function void dut_agent::set_activity(input uvm_active_passive_enum activity);
   m_activity = activity;
endfunction


// Component access
function dut_sequencer dut_agent::get_sqr();
   return m_sqr;
endfunction


// Build and connect
function void dut_agent::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   `log_agent_mode(m_activity.name())

   if (m_activity == UVM_ACTIVE) begin
      `log_build(("Creating driver and sequencer"))
      m_drv = dut_driver::type_id::create("m_drv", this);
      m_sqr = dut_sequencer::type_id::create("m_sqr", this);
   end

   m_mon     = dut_monitor::type_id::create("m_mon", this);
   ap_input  = new("ap_input", this);
   ap_output = new("ap_output", this);

   `log_build(("Agent build phase completed"))

endfunction


function void dut_agent::connect_phase(input uvm_phase phase);

   super.connect_phase(phase);

   if (m_activity == UVM_ACTIVE) begin
      `log_connect(("Connecting driver to sequencer"))
      m_drv.seq_item_port.connect(m_sqr.seq_item_export);
      m_drv.set_vif(m_vif);
   end

   `log_connect(("Connecting monitor analysis streams"))
   m_mon.ap_input.connect(ap_input);
   m_mon.ap_output.connect(ap_output);
   m_mon.set_vif(m_vif);

   `log_connect(("Agent connect phase complete"))

endfunction

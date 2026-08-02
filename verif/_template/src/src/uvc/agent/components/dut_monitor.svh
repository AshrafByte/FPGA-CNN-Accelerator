class dut_monitor extends uvm_monitor implements IResetListener;

   `uvm_component_utils(dut_monitor)

   // STRUCTURAL LINKS ────────────────────────────────────────────────────────
   local virtual dut_if.mon_mp m_vif;

   // ANALYSIS PORT ───────────────────────────────────────────────────────────
   uvm_analysis_port #(dut_uvc_item) ap_input;
   uvm_analysis_port #(dut_uvc_item) ap_output;

   // RESET CONTROL ───────────────────────────────────────────────────────────
   bool is_reset_active;

   // PUBLIC API ──────────────────────────────────────────────────────────────
   extern function new(input string name, uvm_component parent);

   extern function void set_vif(input virtual dut_if.mon_mp vif);

   extern virtual function void build_phase(input uvm_phase phase);
   extern virtual function void connect_phase(input uvm_phase phase);
   extern virtual task run_phase(input uvm_phase phase);

   extern virtual task monitor_in();
   extern virtual task monitor_out();

   // RESET LISTENER API ──────────────────────────────────────────────────────
   extern virtual function void handle_reset(input rst_event evt);
   extern virtual function reset_priority_e get_reset_priority();

endclass


// RUN PHASE ───────────────────────────────────────────────────────────────────
task dut_monitor::run_phase(input uvm_phase phase);

   `log_reset(("waiting for reset to resolve..."))
   m_vif.wait_reset_resolve();
   is_reset_active = (m_vif.rst_n == 1'd0);
   `log_reset(("reset resolved, entering monitor loop"))

   `log_medium(("current reset state: %0s", is_reset_active ? "ASSERTED" : "RELEASED"))

   forever begin

      // Wait until reset is de-asserted before spawning threads
      wait (!is_reset_active);

      fork

         // Thread 1: Continuous Input Sampling
         forever monitor_in();

         // Thread 2: Continuous Output Sampling
         forever monitor_out();

         // Thread 3: Reset Watcher
         wait (is_reset_active == true);

      join_any

      // When reset asserts, kill sampling threads immediately
      disable fork;

      `log_medium(("Monitor threads killed due to reset assertion"))

   end

endtask


// SAMPLE INPUT ────────────────────────────────────────────────────────────────
task dut_monitor::monitor_in();

   dut_uvc_item tr_in;

   tr_in = dut_uvc_item::type_id::create("tr_in");

   @(m_vif.mon_cb);

   // GEN:BEGIN INPUT
   tr_in.i_din = m_vif.mon_cb.i_din;
   // GEN:END

   `log_tr_in(tr_in, "publishing input transaction")
   tr_in.d_monitor_time = $realtime;
   ap_input.write(tr_in);

endtask


// SAMPLE OUTPUT ───────────────────────────────────────────────────────────────
task dut_monitor::monitor_out();

   dut_uvc_item tr_out;

   tr_out = dut_uvc_item::type_id::create("tr_out");

   @(m_vif.mon_cb);

   // GEN:BEGIN OUTPUT
   tr_out.o_dout = m_vif.mon_cb.o_dout;
   // GEN:END

   `log_tr_out(tr_out, "publishing output transaction")
   tr_out.d_monitor_time = $realtime;
   ap_output.write(tr_out);

endtask


// HANDLE RESET ────────────────────────────────────────────────────────────────
function void dut_monitor::handle_reset(input rst_event evt);

   case (evt.kind)

      RST_ASSERT: begin
         `log_reset(("reset asserted — will discard current sample"))
         is_reset_active = true;
      end

      RST_RELEASE: begin
         `log_reset(("reset released — monitor resuming"))
         is_reset_active = false;
      end

      default:  /* */;

   endcase

endfunction


// CONSTRUCTOR ─────────────────────────────────────────────────────────────────
function dut_monitor::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


// BUILD PHASE ─────────────────────────────────────────────────────────────────
function void dut_monitor::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   ap_input  = new("ap_input", this);
   ap_output = new("ap_output", this);

   `log_build(("monitor analysis ports created"))

endfunction


// CONNECT PHASE ───────────────────────────────────────────────────────────────
function void dut_monitor::connect_phase(input uvm_phase phase);
   reset_manager::get().register(this);
endfunction


// GET RESET PRIORITY ──────────────────────────────────────────────────────────
function reset_priority_e dut_monitor::get_reset_priority();
   return RESET_PRI_MONITOR;
endfunction

function void dut_monitor::set_vif(input virtual dut_if.mon_mp vif);
   this.m_vif = vif;
endfunction

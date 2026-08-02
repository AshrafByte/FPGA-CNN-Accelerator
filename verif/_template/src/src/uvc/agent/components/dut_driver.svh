class dut_driver extends uvm_driver #(dut_uvc_item) implements IResetListener;

   `uvm_component_utils(dut_driver)

   // STRUCTURAL LINKS ────────────────────────────────────────────────────────
   virtual dut_if.drv_mp m_vif;

   // RESET CONTROL ───────────────────────────────────────────────────────────
   local bool is_reset_active;
   local bool item_in_flight;

   // PUBLIC API ──────────────────────────────────────────────────────────────
   extern function new(input string name, input uvm_component parent);
   extern function void set_vif(input virtual dut_if.drv_mp vif);

   extern function void connect_phase(input uvm_phase phase);
   extern virtual task run_phase(input uvm_phase phase);

   extern virtual task drive_item(input dut_uvc_item tr);

   // RESET LISTENER API ──────────────────────────────────────────────────────
   extern virtual function void handle_reset(input rst_event evt);
   extern virtual function reset_priority_e get_reset_priority();

endclass


// TODO DRIVE ITEM ──────────────────────────────────────────────────────────────────
task dut_driver::drive_item(input dut_uvc_item tr);

   `log_tr_in(tr, "Driving input transaction")

   @(m_vif.drv_cb);

   // GEN:BEGIN INPUT
   m_vif.drv_cb.i_din <= tr.i_din;
   // GEN:END


endtask


// HANDLE RESET ────────────────────────────────────────────────────────────────
function void dut_driver::handle_reset(input rst_event evt);
   case (evt.kind)

      RST_ASSERT: begin
         `log_reset(("reset asserted — will stop after current cycle"))
         is_reset_active = true;
      end

      RST_RELEASE: begin
         `log_reset(("reset released — driver loop resuming"))
         is_reset_active = false;
      end

      default:  /* */;
   endcase
endfunction

// CONSTRUCTOR ─────────────────────────────────────────────────────────────────
function dut_driver::new(input string name, input uvm_component parent);
   super.new(name, parent);
endfunction


// CONNECT PHASE ───────────────────────────────────────────────────────────────
function void dut_driver::connect_phase(input uvm_phase phase);
   reset_manager::get().register(this);
endfunction


// RUN PHASE ───────────────────────────────────────────────────────────────────
task dut_driver::run_phase(input uvm_phase phase);

   `log_reset(("initialising interface and waiting for reset to resolve..."))
   m_vif.drive_idle();
   m_vif.wait_reset_resolve();
   is_reset_active = (m_vif.rst_n == 1'd0);
   `log_reset(("reset resolved, entering driver loop"))

   forever begin

      // gate here — never fetch a new item while reset is active
      wait (!is_reset_active);

      seq_item_port.get_next_item(req);
      item_in_flight = true;
      `log_high(("got item from sequencer"))

      fork
         drive_item(req);
         wait (is_reset_active);
      join_any
      disable fork;

      // we know item is in flight because of the flag
      if (item_in_flight) begin
         seq_item_port.item_done();
         item_in_flight = false;
      end

      if (is_reset_active) `log_reset(("item dropped — reset fired mid-transaction"))

   end

endtask



// GET RESET PRIORITY ──────────────────────────────────────────────────────────
function reset_priority_e dut_driver::get_reset_priority();
   return RESET_PRI_DRIVER;
endfunction


function void dut_driver::set_vif(input virtual dut_if.drv_mp vif);
   this.m_vif = vif;
endfunction

class rst_driver extends uvm_driver #(rst_item);
   
   
   `uvm_component_utils(rst_driver)
   // STRUCTURAL LINKS ───────────────────────────────────────────────────────────

   virtual rst_if m_vif;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name, uvm_component parent);
   extern virtual task run_phase(input uvm_phase phase);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

// CONSTRUCTOR ──────────────────────────────────────────────────────────────────

function rst_driver::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


// RUN PHASE ────────────────────────────────────────────────────────────────────

task rst_driver::run_phase(input uvm_phase phase);
   rst_item req;

   m_vif.drive_idle();
   forever begin

      seq_item_port.get_next_item(req);

      case (req.rst_event)

         RST_ASSERT: begin
            `uvm_info("RST_DRV", $sformatf("Applying reset pulse(s): %0d", req.pulse_count), UVM_HIGH)

            `uvm_info("RST_DRV/ITEM", $sformatf(
                      "start=%0t assert=%0t gap=%0t count=%0d",
                      req.start_delay,
                      req.assert_time,
                      req.gap_time,
                      req.pulse_count
                      ), UVM_HIGH)

            m_vif.apply_reset_pulse(req.start_delay, req.assert_time, req.gap_time, req.pulse_count);
         end

         RST_SYNC_ASSERT, RST_SYNC_RELEASE: begin
            `uvm_error("RST_DRV", $sformatf(
                       "Sync reset (%s) is driven externally and cannot be issued via sequence items",
                       req.rst_event.name()))
         end

         default: begin
            `uvm_error("RST_DRV", $sformatf("Unhandled rst_event: %s", req.rst_event.name()))
         end

      endcase

      seq_item_port.item_done();

   end

endtask
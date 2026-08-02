class clk_driver extends uvm_driver #(clk_item);
   `uvm_component_utils(clk_driver)

   // STRUCTURAL LINKS ───────────────────────────────────────────────────────────

   virtual clk_if vif;  // Physical pin interface access
   clk_uvc_cfg    m_cfg;  // Configuration handle

   // PUBLIC API ─────────────────────────────────────────────────────────────────
   extern function new(input string name, uvm_component parent);
   extern virtual task run_phase(input uvm_phase phase);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

function clk_driver::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


task clk_driver::run_phase(input uvm_phase phase);

   if (m_cfg == null) begin
      `uvm_fatal("CLK_DRV_CFG", "m_cfg configuration handle is null inside the driver!")
   end

   if (vif == null) begin
      `uvm_fatal("CLK_DRV_VIF", "vif  handle is null inside the driver!")
   end

   // BOOTSTRAP INITIALIZATION ───────────────────────────────────────────────────

   // Prime the interface in stopped state until a CLK_CMD_CONFIGURE arrives
   vif.stop_clk();

   // REQUEST PROCESSING LOOP ────────────────────────────────────────────────────
   forever begin

      // Retrieve next command transaction
      seq_item_port.get_next_item(req);

      // Route command directly to the clock interface API
      `log_tr(req)
      case (req.cmd)

         CLK_CMD_CONFIGURE:
            vif.apply_config(
               .freq_mhz      (req.freq_mhz),
               .drift_enable  (req.drift_enable),  .drift_ppm  (req.drift_ppm),
               .jitter_enable (req.jitter_enable), .jitter_ppm (req.jitter_ppm),
               .ssc_enable    (req.ssc_enable),    .ssc_ppm    (req.ssc_ppm),
               .ssc_mod_hz    (req.ssc_mod_hz));

         CLK_CMD_STOP:
            vif.stop_clk();

         default:
            `uvm_error("CLK_DRV", $sformatf("Unhandled command type received: %s", req.cmd.name()))
      endcase

      // Notify the sequencer that processing is complete
      seq_item_port.item_done();

   end

endtask
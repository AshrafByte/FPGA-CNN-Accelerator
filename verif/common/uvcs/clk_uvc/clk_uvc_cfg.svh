class clk_uvc_cfg extends uvm_object;

   `uvm_object_utils(clk_uvc_cfg)

   // CONFIGURATION INTERFACE ────────────────────────────────────────────────────

   virtual clk_if          m_vif;
   uvm_active_passive_enum active        = UVM_ACTIVE;

   // BASE STIMULUS PARAMETERS ───────────────────────────────────────────────────

   real                    freq_mhz      = 100.0;

   // HIGH-LEVEL MODULATION PARAMETERS ──────────────────────────────────────────

   bit                     jitter_enable = 1'b0;
   real                    jitter_ppm    = 600.0;

   bit                     ssc_enable    = 1'b0;
   real                    ssc_ppm       = 5000.0;
   real                    ssc_mod_hz    = 33000.0;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name = "clk_uvc_cfg");
   extern function real get_nominal_period_ps();
   extern static function clk_uvc_cfg get_cfg(input uvm_component c);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

function clk_uvc_cfg::new(input string name = "clk_uvc_cfg");
   super.new(name);
endfunction


function real clk_uvc_cfg::get_nominal_period_ps();
   return 1.0e6 / freq_mhz;
endfunction


function clk_uvc_cfg clk_uvc_cfg::get_cfg(input uvm_component c);

   clk_uvc_cfg cfg;

   if (!uvm_config_db#(clk_uvc_cfg)::get(c, "", "clk_uvc_cfg", cfg)) begin
      c.uvm_report_fatal("CLK_CFG_MISSING", "Could not find clk_uvc_cfg in uvm_config_db");
   end

   return cfg;

endfunction

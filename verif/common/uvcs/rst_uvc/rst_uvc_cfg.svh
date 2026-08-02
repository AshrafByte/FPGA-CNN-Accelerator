class rst_uvc_cfg extends uvm_object;
   `uvm_object_utils(rst_uvc_cfg)

   // CONFIGURATION INTERFACE ────────────────────────────────────────────────────

   virtual rst_if          m_vif;
   uvm_active_passive_enum active     = UVM_ACTIVE;
   bit                     active_low = 1;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name = "rst_uvc_cfg");
   extern static function rst_uvc_cfg get_cfg(input uvm_component c);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

function rst_uvc_cfg::new(input string name = "rst_uvc_cfg");
   super.new(name);
endfunction


function rst_uvc_cfg rst_uvc_cfg::get_cfg(input uvm_component c);

   rst_uvc_cfg cfg;

   if (!uvm_config_db#(rst_uvc_cfg)::get(c, "", "rst_uvc_cfg", cfg)) begin
      c.uvm_report_fatal("RST_CFG", $sformatf("'rst_uvc_cfg' not found for %s", c.get_full_name()));
   end

   return cfg;

endfunction

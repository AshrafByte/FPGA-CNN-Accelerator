class dut_uvc_cfg extends uvm_object;

   `uvm_object_utils(dut_uvc_cfg)

   // AGENT-FACING CONFIGURATION ───────────────────────────────────────────────

   virtual dut_if          m_vif;
   uvm_active_passive_enum m_activity = UVM_ACTIVE;

   // OPTIONAL ENVIRONMENT FEATURES ────────────────────────────────────────────

   bool scoreboard_enable = true;
   bool coverage_enable   = true;

   uvm_verbosity log_verbosity;

   // PUBLIC API ───────────────────────────────────────────────────────────────

   extern function new(input string name = "dut_uvc_cfg");

   extern static function dut_uvc_cfg get_cfg(input uvm_component comp, string cfg_name = "dut_uvc_cfg");

   extern function void set_vif(input virtual dut_if vif);
   extern function void set_activity(input uvm_active_passive_enum activity);
   extern function void set_log_verbosity(input uvm_verbosity v);
   extern function void enable_scoreboard(input bit enable = true);
   extern function void enable_coverage(input bit enable = true);

   extern function virtual dut_if get_vif();
   extern function uvm_active_passive_enum get_activity();
   extern function uvm_verbosity get_log_verbosity();



   extern function bit has_scoreboard();
   extern function bit has_coverage();

endclass


// ─── CONSTRUCTOR ─────────────────────────────────────────────────────────────

function dut_uvc_cfg::new(input string name = "dut_uvc_cfg");

   super.new(name);

   log_verbosity = uvm_verbosity'(uvm_root::get().get_report_verbosity_level());

endfunction


// ─── CONFIG DB HELPER ────────────────────────────────────────────────────────

function dut_uvc_cfg dut_uvc_cfg::get_cfg(input uvm_component comp, string cfg_name = "dut_uvc_cfg");

   dut_uvc_cfg cfg;

   if (!uvm_config_db#(dut_uvc_cfg)::get(comp, "", cfg_name, cfg)) begin

      `log_cfg_fallback(
          ("Config '%s' not found in uvm_config_db for %s. Creating default instance.", cfg_name, comp.get_full_name()))

      cfg = dut_uvc_cfg::type_id::create(cfg_name);

   end

   return cfg;

endfunction


// ─── SETTERS ────────────────────────────────────────────────────────────────

function void dut_uvc_cfg::set_vif(input virtual dut_if vif);

   if (vif == null) begin
      `log_cfg_err("Cannot configure DUT UVC with a null virtual interface")
      return;
   end

   m_vif = vif;

endfunction


function void dut_uvc_cfg::set_activity(input uvm_active_passive_enum activity);

   m_activity = activity;

endfunction


function void dut_uvc_cfg::set_log_verbosity(input uvm_verbosity v);
   log_verbosity = v;
endfunction


// ─── GETTERS ────────────────────────────────────────────────────────────────

function virtual dut_if dut_uvc_cfg::get_vif();
   return m_vif;
endfunction


function uvm_active_passive_enum dut_uvc_cfg::get_activity();
   return m_activity;
endfunction


function uvm_verbosity dut_uvc_cfg::get_log_verbosity();
   return log_verbosity;
endfunction


// ─── FEATURE CONTROL ─────────────────────────────────────────────────────────

function void dut_uvc_cfg::enable_scoreboard(input bit enable = true);
   scoreboard_enable = enable;
endfunction


function void dut_uvc_cfg::enable_coverage(input bit enable = true);
   coverage_enable = enable;
endfunction


// ─── STATUS QUERIES ──────────────────────────────────────────────────────────

function bit dut_uvc_cfg::has_scoreboard();
   return scoreboard_enable;
endfunction


function bit dut_uvc_cfg::has_coverage();
   return coverage_enable;
endfunction

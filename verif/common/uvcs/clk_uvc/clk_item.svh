class clk_item extends uvm_sequence_item;

   `uvm_object_utils(clk_item)

   // ── COMMAND ──────────────────────────────────────────────────────────────────

   clk_cmd_e cmd = CLK_CMD_CONFIGURE;

   // ── STIMULUS FIELDS ──────────────────────────────────────────────────────────

   real freq_mhz;          // Nominal (un-modified) frequency. 0 = stop.

   // Fixed drift: clock runs at a constant PPM offset from freq_mhz.
   // Positive drift_ppm = clock runs SLOWER (longer period).
   // Monitor will report approximately +drift_ppm.
   bit  drift_enable;
   real drift_ppm;

   // Random cycle-to-cycle jitter: uniform ±jitter_ppm per cycle.
   // Does NOT produce a net DC offset -- use drift for that.
   bit  jitter_enable;
   real jitter_ppm;

   // Spread Spectrum Clocking: triangle-wave down-spread.
   bit  ssc_enable;
   real ssc_ppm;           // Max spread, e.g. 5000.0 = -0.5%
   real ssc_mod_hz;        // Modulation rate, e.g. 33000.0 = 33 kHz

   // ── MONITOR / TELEMETRY (populated by monitor, broadcast via analysis port) ─

   realtime measured_period;
   real     measured_clk_offset_ppm;

   // ── API DECLARATIONS ─────────────────────────────────────────────────────────

   extern function new(input string name = "clk_item");
   extern virtual function string convert2string();
   extern virtual function void   do_copy(input uvm_object rhs);

   // Base helpers -- chain freely on one freshly-created item
   extern virtual function void set_base   (input real freq_mhz);
   extern virtual function void set_drift  (input bit en, input real ppm);
   extern virtual function void set_jitter (input bit en, input real ppm);
   extern virtual function void set_ssc    (input bit en, input real ppm, input real mod_hz);
   extern virtual function void set_stop   ();

   // Protocol presets
   extern virtual function void set_usb3_ssc(input real freq_mhz,
                                             input real ssc_ppm    = 5000.0,
                                             input real ssc_mod_hz = 33000.0);

endclass


// ── CONSTRUCTOR ──────────────────────────────────────────────────────────────

function clk_item::new(input string name = "clk_item");
   super.new(name);
endfunction


// ── CONVERT2STRING ───────────────────────────────────────────────────────────

function string clk_item::convert2string();
   string msg;
   msg = $sformatf("cmd=%s", cmd.name());

   case (cmd)
      CLK_CMD_CONFIGURE: begin
         msg = {msg, $sformatf(" freq_mhz=%0.3f", freq_mhz)};

         if (drift_enable)
            msg = {msg, $sformatf(" drift_enable=1 drift_ppm=%0.3f", drift_ppm)};

         if (jitter_enable)
            msg = {msg, $sformatf(" jitter_enable=1 jitter_ppm=%0.3f", jitter_ppm)};

         if (ssc_enable)
            msg = {msg, $sformatf(" ssc_enable=1 ssc_ppm=%0.3f ssc_mod_hz=%0.3f",
                                   ssc_ppm, ssc_mod_hz)};
      end

      CLK_CMD_STOP: ; // command name is sufficient

      default: msg = {msg, " <unknown command>"};
   endcase

   if (measured_period != 0.0)
      msg = {msg, $sformatf(" measured_period=%0.3t", measured_period)};

   if (measured_clk_offset_ppm != 0.0)
      msg = {msg, $sformatf(" measured_clk_offset_ppm=%0.3f", measured_clk_offset_ppm)};

   return msg;
endfunction


// ── DO_COPY ──────────────────────────────────────────────────────────────────

function void clk_item::do_copy(input uvm_object rhs);
   clk_item rhs_;
   if (!$cast(rhs_, rhs))
      `uvm_fatal("DO_COPY", "Type mismatch in clk_item::do_copy")

   super.do_copy(rhs);

   cmd                      = rhs_.cmd;
   freq_mhz                 = rhs_.freq_mhz;

   drift_enable             = rhs_.drift_enable;
   drift_ppm                = rhs_.drift_ppm;

   jitter_enable            = rhs_.jitter_enable;
   jitter_ppm               = rhs_.jitter_ppm;

   ssc_enable               = rhs_.ssc_enable;
   ssc_ppm                  = rhs_.ssc_ppm;
   ssc_mod_hz               = rhs_.ssc_mod_hz;

   measured_period          = rhs_.measured_period;
   measured_clk_offset_ppm  = rhs_.measured_clk_offset_ppm;
endfunction


// ── BASE HELPERS ─────────────────────────────────────────────────────────────

function void clk_item::set_base(input real freq_mhz);
   this.cmd      = CLK_CMD_CONFIGURE;
   this.freq_mhz = freq_mhz;
endfunction

// Constant PPM offset applied every cycle.
// Positive ppm = longer period = monitor reads approximately +ppm.
function void clk_item::set_drift(input bit en, input real ppm);
   this.cmd          = CLK_CMD_CONFIGURE;
   this.drift_enable = en;
   this.drift_ppm    = ppm;
endfunction

// Random cycle-to-cycle jitter.  Does NOT create a net DC offset.
function void clk_item::set_jitter(input bit en, input real ppm);
   this.cmd           = CLK_CMD_CONFIGURE;
   this.jitter_enable = en;
   this.jitter_ppm    = ppm;
endfunction

function void clk_item::set_ssc(input bit en, input real ppm, input real mod_hz);
   this.cmd        = CLK_CMD_CONFIGURE;
   this.ssc_enable = en;
   this.ssc_ppm    = ppm;
   this.ssc_mod_hz = mod_hz;
endfunction

function void clk_item::set_stop();
   this.cmd      = CLK_CMD_STOP;
   this.freq_mhz = 0.0;
endfunction


// ── PROTOCOL PRESETS ─────────────────────────────────────────────────────────

// USB 3.x SuperSpeed: down-spread only, max -5000 ppm, 30-33 kHz modulation.
function void clk_item::set_usb3_ssc(input real freq_mhz,
                                     input real ssc_ppm    = 5000.0,
                                     input real ssc_mod_hz = 33000.0);
   set_base(freq_mhz);
   set_ssc(1'b1, ssc_ppm, ssc_mod_hz);
endfunction
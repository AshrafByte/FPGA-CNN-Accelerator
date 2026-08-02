interface clk_if;

   timeunit 1ps / 1fs;

   import uvm_pkg::*;
   import clk_model_pkg::*;

   // ── STATE ───────────────────────────────────────────────────────────────────

   clk_util_ctrl_t ctrl;
   event           clk_start_evt;
   logic           clk = 1'b0;

   // ── PUBLIC API ───────────────────────────────────────────────────────────────


   task apply_config(input real freq_mhz, input bit drift_enable, input real drift_ppm, input bit jitter_enable,
                     input real jitter_ppm, input bit ssc_enable, input real ssc_ppm, input real ssc_mod_hz);

      ctrl.drift_enable = drift_enable;
      ctrl.drift_ppm    = drift_ppm;

      ctrl.jitter_enable = jitter_enable;
      ctrl.jitter_ppm    = jitter_ppm;

      ctrl.ssc_enable = ssc_enable;
      ctrl.ssc_ppm    = ssc_ppm;
      if (ssc_mod_hz > 0.0) ctrl.ssc_period = (1.0 / ssc_mod_hz) * 1s;

      if (freq_mhz > 0.0) begin
         ctrl.freq_hz = freq_mhz * 1.0e6;
         ctrl.period  = (1.0e6 / freq_mhz) * 1ps;

         if (!ctrl.active) begin
            ctrl.active = 1'b1;
            ->clk_start_evt;
         end
      end else begin
         ctrl.active = 1'b0;
      end

   endtask

   task stop_clk();
      ctrl.active = 1'b0;
   endtask

   function bit is_idle();
      return !ctrl.active;
   endfunction

   // ── CLOCK ENGINE ────────────────────────────────────────────────────────────

   initial begin
      static realtime              half_period;
      static realtime              last_half_period = 0ns;
      static clk_util_phys_state_t phys_state;

      phys_state.tri_phase = 0.0;
      phys_state.direction = 1.0;
      phys_state.seed      = $urandom;

      forever begin

         uvm_report_info("CLK_IF/START", "Waiting for start event", UVM_FULL);
         @(clk_start_evt);
         uvm_report_info("CLK_IF/START", "Start event triggered", UVM_FULL);

         while (ctrl.active) begin

            if (ctrl.freq_hz <= 0.0) begin
               uvm_report_error("CLK_IF/ERR", "Invalid freq_hz -- stopping clock");
               ctrl.active = 0;
               break;
            end

            half_period = calculate_emulated_half_period(.freq_hz(ctrl.freq_hz), .ctrl(ctrl), .state(
                                                         phys_state), .last_half_period(last_half_period));

            #(half_period);
            clk              = ~clk;
            last_half_period = half_period;

            uvm_report_info("CLK_IF/PERIOD", $sformatf("half=%0t full=%0t", half_period, half_period * 2), UVM_FULL);
         end

      end
   end

endinterface

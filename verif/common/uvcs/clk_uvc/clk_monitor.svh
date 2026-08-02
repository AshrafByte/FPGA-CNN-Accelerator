class clk_monitor extends uvm_monitor;

   `uvm_component_utils(clk_monitor)

   // STRUCTURAL LINKS ───────────────────────────────────────────────────────────

   virtual clk_if                vif;  // Physical pin access
   clk_uvc_cfg                   m_cfg;  // Configuration handle
   uvm_analysis_port #(clk_item) m_ap;  // Telemetry broadcast port

   // LOCAL TRACKING STATE ───────────────────────────────────────────────────────

   clk_model_pkg::clk_mon_state_t m_mon_state;

   // PUBLIC API ─────────────────────────────────────────────────────────────────

   extern function new(input string name, uvm_component parent);
   extern virtual function void build_phase(input uvm_phase phase);
   extern virtual task run_phase(input uvm_phase phase);

endclass


// METHOD DEFINITIONS ────────────────────────────────────────────────────────────

function clk_monitor::new(input string name, uvm_component parent);
   super.new(name, parent);
endfunction


function void clk_monitor::build_phase(input uvm_phase phase);
   super.build_phase(phase);
   m_ap                    = new("m_ap", this);
   // Initialize moving-average history depth
   m_mon_state.window_size = 8;
endfunction


task clk_monitor::run_phase(input uvm_phase phase);
   clk_item tr;

   realtime current_edge_time = 0;
   realtime last_edge_time = 0;
   realtime raw_calculated_period_ps = 0;

   realtime filtered_avg_period = 0;
   real     calculated_ppm_offset = 0;

   // Ensure the clock line has reached a known state before tracing

   wait (vif.clk === 1'b0 || vif.clk === 1'b1);

   forever begin
      @(posedge vif.clk);

      current_edge_time = $realtime;

      // Only process once a valid reference edge exists
      if (last_edge_time > 0) begin

         raw_calculated_period_ps = current_edge_time - last_edge_time;

         // Calculate running averages and clean PPM offsets
         clk_model_pkg::calculate_ppm_metrics(.raw_measured_period(real'(raw_calculated_period_ps)),
                                              .nominal_baseline_period(m_cfg.get_nominal_period_ps()),
                                              .mon_state(m_mon_state), .output_avg_period(filtered_avg_period),
                                              .output_ppm_offset(calculated_ppm_offset));

         // Populate and broadcast telemetry transaction
         tr = clk_item::type_id::create("tr");

         tr.measured_period         = filtered_avg_period;
         tr.measured_clk_offset_ppm = calculated_ppm_offset;

         `log_full(("Ref Clk Offset= %0.1f ppm", calculated_ppm_offset))
         m_ap.write(tr);

      end
      // Save edge timestamp for the next cycle comparison
      last_edge_time = current_edge_time;
   end

endtask

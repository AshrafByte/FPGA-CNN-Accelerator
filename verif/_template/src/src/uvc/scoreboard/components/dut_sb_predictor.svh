class dut_sb_predictor extends uvm_subscriber #(dut_uvc_item);

   `uvm_component_utils(dut_sb_predictor)

   // ─── CONFIGURATION ───────────────────────────────────────────────────────
   protected int m_ratio;
   protected bit m_fanout;

   // ─── STRUCTURAL LINKS ────────────────────────────────────────────────────

   uvm_analysis_port #(dut_uvc_item) ap_results;

   local dut_sb_prd_engine m_engine;

   // ─── INTERNAL STATE ──────────────────────────────────────────────────────

   local int collect_cnt = 0;

   // ─── PUBLIC API ──────────────────────────────────────────────────────────

   extern function new(input string name, input uvm_component parent);

   extern function void build_phase(input uvm_phase phase);

   extern function void configure(input int in_count, input int out_count);

   extern function void write(input dut_uvc_item t);

   extern function dut_uvc_item sb_calc_exp(input dut_uvc_item tr);

   extern function void reset();

endclass


// ────────────────────────────────────────────────────────────────────────────
// METHOD DEFINITIONS
// ────────────────────────────────────────────────────────────────────────────


// ─── CONSTRUCTOR ────────────────────────────────────────────────────────────

function dut_sb_predictor::new(input string name, input uvm_component parent);

   super.new(name, parent);

endfunction


// ─── BUILD PHASE ────────────────────────────────────────────────────────────

function void dut_sb_predictor::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   ap_results = new("ap_results", this);
   m_engine   = new();

   `log_build(("Predictor built"))

endfunction


// ─── CONFIGURATION ──────────────────────────────────────────────────────────

function void dut_sb_predictor::configure(input int in_count, input int out_count);

   m_ratio  = (out_count > in_count) ? out_count : in_count;
   m_fanout = (out_count > in_count);

   `log_cfg(
       ("Predictor configured: IN=%0d OUT=%0d MODE=%s RATIO=%0d", in_count, out_count, m_fanout ? "fanout" : "collect",
        m_ratio))

endfunction


// ─── WRITE ──────────────────────────────────────────────────────────────────

function void dut_sb_predictor::write(input dut_uvc_item t);

   dut_uvc_item exp_tr;
   int          loop_count;
   bit          should_publish;

   loop_count = m_fanout ? m_ratio : 1;

   if (!m_fanout) collect_cnt++;

   `log_high((m_fanout ? $sformatf("Fanout — calling engine %0d time(s)", m_ratio) : $sformatf(
             "Collect — received %0d/%0d", collect_cnt, m_ratio)))

   for (int i = 1; i <= loop_count; i++) begin

      exp_tr = sb_calc_exp(t);

      should_publish = m_fanout || (collect_cnt == m_ratio);

      if (should_publish) begin

         `log_high(("Publishing result [%0d/%0d]", i, loop_count))

         exp_tr.d_predictor_id = i;
         exp_tr.d_monitor_time = t.d_monitor_time;
         ap_results.write(exp_tr);

         `log_tr_out(exp_tr);

      end else begin

         `log_high(("Waiting for %0d more input(s)", m_ratio - collect_cnt))

      end

   end

   if (!m_fanout && (collect_cnt == m_ratio)) collect_cnt = 0;

endfunction


// ─── PREDICTION CORE ────────────────────────────────────────────────────────

function dut_uvc_item dut_sb_predictor::sb_calc_exp(input dut_uvc_item tr);

   dut_uvc_item exp_tr;

   exp_tr = dut_uvc_item::type_id::create("exp_tr");

   `log_full(("Predictor input:\n%s", tr.convert2string()))

   exp_tr.copy(tr);

   m_engine.predict(exp_tr);

   `log_full(("Predictor output:\n%s", exp_tr.convert2string()))

   return exp_tr;

endfunction


// ─── RESET ──────────────────────────────────────────────────────────────────

function void dut_sb_predictor::reset();

   m_engine = new();

   collect_cnt = 0;

   `log_medium(("Predictor reset — engine reinitialized"))

endfunction

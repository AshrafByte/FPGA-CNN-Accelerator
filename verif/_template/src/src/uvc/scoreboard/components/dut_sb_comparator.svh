class dut_sb_comparator extends uvm_component;

   `uvm_component_utils(dut_sb_comparator)

   // ─── CONFIGURATION ───────────────────────────────────────────────────────

   protected int  m_target_vectors;
   protected int  m_max_retries;
   protected int  m_sync_confirm_cnt;
   protected real m_ratio;

   // ─── TRANSACTIONS ────────────────────────────────────────────────────────

   dut_uvc_item exp_tr;
   dut_uvc_item act_tr;

   // ─── COUNTERS ────────────────────────────────────────────────────────────

   int vector_cnt;
   int pass_cnt;
   int error_cnt;

   // ─── INTERNAL STATE ──────────────────────────────────────────────────────

   int retries;
   int confirm_matches;

   bool in_reset  = false;
   bool is_synced = false;

   // ─── ANALYSIS PORTS / FIFOS ──────────────────────────────────────────────

   uvm_analysis_export #(dut_uvc_item) ap_expected;
   uvm_analysis_export #(dut_uvc_item) ap_actual;

   uvm_tlm_analysis_fifo #(dut_uvc_item) exp_fifo;
   uvm_tlm_analysis_fifo #(dut_uvc_item) act_fifo;

   // ─── PUBLIC API ──────────────────────────────────────────────────────────

   extern function new(input string name, input uvm_component parent);

   extern function void build_phase(input uvm_phase phase);
   extern function void connect_phase(input uvm_phase phase);
   extern function void report_phase(input uvm_phase phase);
   extern function void phase_ready_to_end(input uvm_phase phase);

   extern task run_phase(input uvm_phase phase);

   extern function void configure(input int max_retries, input int sync_confirm_cnt, input real ratio);

   extern function void reset();

   // ─── INTERNAL METHODS ────────────────────────────────────────────────────

   extern task comparison();
   extern task detect_latency();

   extern function void handle_pass();
   extern function void handle_error();

   extern function string get_vector_str();

endclass


// ────────────────────────────────────────────────────────────────────────────
// METHOD DEFINITIONS
// ────────────────────────────────────────────────────────────────────────────


// ─── CONSTRUCTOR ────────────────────────────────────────────────────────────

function dut_sb_comparator::new(input string name, input uvm_component parent);
   super.new(name, parent);
endfunction


// ─── CONFIGURATION ──────────────────────────────────────────────────────────

function void dut_sb_comparator::configure(input int max_retries, input int sync_confirm_cnt, input real ratio);

   m_max_retries      = max_retries;
   m_sync_confirm_cnt = sync_confirm_cnt;
   m_ratio            = ratio;

   retries         = m_max_retries;
   confirm_matches = m_sync_confirm_cnt;

   `log_cfg(("Comparator configured: retries=%0d confirm=%0d ratio=%0d", m_max_retries, m_sync_confirm_cnt, m_ratio))

endfunction


// ─── BUILD PHASE ────────────────────────────────────────────────────────────

function void dut_sb_comparator::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   ap_expected = new("ap_expected", this);
   ap_actual   = new("ap_actual", this);

   exp_fifo = new("exp_fifo", this);
   act_fifo = new("act_fifo", this);

   `log_build(("Comparator built"))

endfunction


// ─── CONNECT PHASE ──────────────────────────────────────────────────────────

function void dut_sb_comparator::connect_phase(input uvm_phase phase);

   super.connect_phase(phase);

   ap_expected.connect(exp_fifo.analysis_export);
   ap_actual.connect(act_fifo.analysis_export);

   `log_connect(("Connected exp/act FIFOs"))

endfunction

// ─── READY TO END ───────────────────────────────────────────────────────────

function void dut_sb_comparator::phase_ready_to_end(input uvm_phase phase);

   if (!uvm_config_db#(int)::get(this, "", "total_seq_items", m_target_vectors)) begin
      return;
   end


   if (vector_cnt >= int'(m_target_vectors * m_ratio)) return;

   `log_low(("Waiting for scoreboard completion (%0d/%0d vectors)", vector_cnt, m_target_vectors))

   phase.raise_objection(this, "Waiting for scoreboard");

   fork
      begin
         wait (vector_cnt >= int'(m_target_vectors * m_ratio));
         `log_low(("Scoreboard completed (%0d/%0d vectors)", vector_cnt, m_target_vectors))
         phase.drop_objection(this, "Scoreboard complete");
      end
   join_none

endfunction
// ─── RUN PHASE ──────────────────────────────────────────────────────────────

task dut_sb_comparator::run_phase(input uvm_phase phase);

   forever begin

      fork
         forever comparison();
         wait (in_reset);
      join_any

      disable fork;

      exp_fifo.flush();
      act_fifo.flush();

      retries         = m_max_retries;
      confirm_matches = m_sync_confirm_cnt;

      is_synced = false;
      in_reset  = false;

      `log_medium(("Comparator reset — restarting comparison loop"))

   end

endtask


// ─── COMPARISON ─────────────────────────────────────────────────────────────

task dut_sb_comparator::comparison();

   `log_high(("COMPARISON #%0d", vector_cnt + 1))

   if (!is_synced) begin
      detect_latency();
      return;
   end

   exp_fifo.get(exp_tr);
   act_fifo.get(act_tr);

   if (exp_tr.compare(act_tr)) handle_pass();
   else handle_error();

endtask


// ─── DETECT LATENCY ─────────────────────────────────────────────────────────

task dut_sb_comparator::detect_latency();

   dut_uvc_item peek_act;

   exp_fifo.peek(exp_tr);
   act_fifo.peek(peek_act);

   while (!exp_tr.compare(
       peek_act
   )) begin

      if (retries == 0) begin
         `uvm_fatal("SB_CMP/RETRIES_FAILED", "Failed to synchronize expected and actual streams.")
      end

      `log_medium(
          ("[LATENCY PROBE MISMATCH] EXP : predictor_id=%0d, input_time=%0t | ACT : output_time=%0t",
           exp_tr.d_predictor_id, exp_tr.d_monitor_time, peek_act.d_monitor_time))

      retries--;

      `log_high(("Latency probe: retries remaining = %0d", retries))

      act_fifo.get(act_tr);
      act_fifo.peek(peek_act);

   end

   exp_fifo.get(exp_tr);
   act_fifo.get(act_tr);

   if (confirm_matches == 0) begin

      is_synced = true;

      `log_low(("Detected pipeline latency = %0d cycle(s)", m_max_retries - retries))

   end else begin

      `log_high(("Sync confirmation: %0d consecutive matches remaining", confirm_matches))

      confirm_matches--;

   end

   handle_pass();

endtask


// ─── RESET ──────────────────────────────────────────────────────────────────

function void dut_sb_comparator::reset();

   in_reset = true;

endfunction


// ─── HANDLE PASS ────────────────────────────────────────────────────────────

function void dut_sb_comparator::handle_pass();

   vector_cnt++;
   pass_cnt++;

   `log_high(("EXP : %s", exp_tr.compare2string(act_tr, 1)))

endfunction


// ─── HANDLE ERROR ───────────────────────────────────────────────────────────

function void dut_sb_comparator::handle_error();

   vector_cnt++;
   error_cnt++;

   `uvm_error("TX_SERIALIZER_SB", exp_tr.compare2string(act_tr, 0))

endfunction


// ─── VECTOR STRING ──────────────────────────────────────────────────────────

function string dut_sb_comparator::get_vector_str();

   return $sformatf("EXP:\n%s\nACT:\n%s", exp_tr.convert2string(), act_tr.convert2string());

endfunction


// ─── REPORT PHASE ───────────────────────────────────────────────────────────

function void dut_sb_comparator::report_phase(input uvm_phase phase);

   real   pass_pct;
   real   fail_pct;
   string report;

   super.report_phase(phase);

   pass_pct = (vector_cnt != 0) ? (real'(pass_cnt) * 100.0) / vector_cnt : 0.0;

   fail_pct = (vector_cnt != 0) ? (real'(error_cnt) * 100.0) / vector_cnt : 0.0;

   report = {
      "\n",
      "┌──────────────────────────────────────────────┐\n"
          ,
      "│        TX_SERIALIZER SCOREBOARD REPORT       │\n",
      "├──────────────────────────┬───────────────────┤\n"
          ,
      "│ Metric                   │ Value             │\n",
      "├──────────────────────────┼───────────────────┤\n"
          ,
      $sformatf("│ %-24s │ %17d │\n", "Total Input Items", int'(vector_cnt / m_ratio)),
      $sformatf("│ %-24s │ %17d │\n", "Total Comparisons", vector_cnt),
      $sformatf("│ %-24s │ %17d │\n", "Passed", pass_cnt),
      $sformatf("│ %-24s │ %17d │\n", "Failed", error_cnt),
      $sformatf("│ %-24s │ %16.2f%% │\n", "Fail %", fail_pct),
      "└──────────────────────────┴───────────────────┘\n"
   };

   if (error_cnt == 0 && vector_cnt != 0) `log_sb_report_pass(report)
   else `log_sb_report_fail(report);

endfunction

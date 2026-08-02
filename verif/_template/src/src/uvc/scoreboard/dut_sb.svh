class dut_sb extends uvm_scoreboard implements IResetListener;

   `uvm_component_utils(dut_sb)

   // ─── SCOREBOARD CONFIGURATION ─────────────────────────────────────────────

   localparam real IN_COUNT = 1.0;
   localparam real OUT_COUNT = 1.0;

   localparam int MAX_RETRIES = 10;
   localparam int SYNC_CONFIRM_CNT = 20;

   // ─── STRUCTURAL LINKS ─────────────────────────────────────────────────────

   uvm_analysis_port #(dut_uvc_item) ap_input;
   uvm_analysis_port #(dut_uvc_item) ap_output;

   local dut_sb_predictor  m_predictor;
   local dut_sb_comparator m_comparator;

   // ─── PUBLIC API ───────────────────────────────────────────────────────────

   extern function new(input string name, input uvm_component parent);

   extern function void build_phase(input uvm_phase phase);

   extern function void connect_phase(input uvm_phase phase);

   extern virtual function void handle_reset(input rst_event evt);

   extern virtual function reset_priority_e get_reset_priority();

   // ─── INTERNAL METHODS ─────────────────────────────────────────────────────

   extern function void configure();

endclass


// ─────────────────────────────────────────────────────────────────────────────
// METHOD DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────────


// ─── CONSTRUCTOR ─────────────────────────────────────────────────────────────

function dut_sb::new(input string name, input uvm_component parent);

   super.new(name, parent);

endfunction


// ─── BUILD PHASE ─────────────────────────────────────────────────────────────

function void dut_sb::build_phase(input uvm_phase phase);

   super.build_phase(phase);

   `log_build(("Creating scoreboard infrastructure (predictor + comparator)"))

   ap_input  = new("ap_input", this);
   ap_output = new("ap_output", this);

   m_predictor  = dut_sb_predictor::type_id::create("m_predictor", this);
   m_comparator = dut_sb_comparator::type_id::create("m_comparator", this);

   configure();

endfunction


// ─── CONFIGURATION ───────────────────────────────────────────────────────────

function void dut_sb::configure();

   real ratio = OUT_COUNT / IN_COUNT;
   `log_cfg(("Configuring scoreboard components"))

   m_predictor.configure(IN_COUNT, OUT_COUNT);

   m_comparator.configure(MAX_RETRIES, SYNC_CONFIRM_CNT, ratio);

endfunction


// ─── CONNECT PHASE ───────────────────────────────────────────────────────────

function void dut_sb::connect_phase(input uvm_phase phase);

   super.connect_phase(phase);

   `log_connect(("Connecting scoreboard input -> predictor"))
   ap_input.connect(m_predictor.analysis_export);

   `log_connect(("Connecting scoreboard output -> comparator"))
   ap_output.connect(m_comparator.ap_actual);

   `log_connect(("Connecting predictor -> comparator"))
   m_predictor.ap_results.connect(m_comparator.ap_expected);
   reset_manager::get().register(this);

   `log_low(("Scoreboard connectivity completed"))

endfunction


// ─── RESET HANDLING ──────────────────────────────────────────────────────────

function void dut_sb::handle_reset(input rst_event evt);

   `log_medium(("Resetting scoreboard"))

   if (evt.kind == RST_ASSERT) begin
      m_predictor.reset();
      m_comparator.reset();
   end

endfunction


// ─── RESET PRIORITY ──────────────────────────────────────────────────────────

function reset_priority_e dut_sb::get_reset_priority();
   return RESET_PRI_SCOREBOARD;
endfunction

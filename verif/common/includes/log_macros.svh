`ifndef LOG_MACROS_SVH
`define LOG_MACROS_SVH

// =============================================================================
// VERBOSITY SEMANTICS
// =============================================================================
// LOW    — messages that happen once per run or reset
// MEDIUM — single-line summary of each transaction
// HIGH   — print each transaction or sequence once
// FULL   — method parameters, signal sampling, debug traces, implementation details
// DEBUG  — internal framework diagnostics
//

// =============================================================================
// INTERNAL WORKER MACROS (Do not call directly)
// =============================================================================

// Base standard verbosity worker
`define __base_log(VERBOSITY, args) \
    begin \
        if (uvm_report_enabled(VERBOSITY, UVM_INFO, m_log.get_id(`__FILE__))) begin \
            `uvm_info(m_log.get_id(`__FILE__), $sformatf args, VERBOSITY) \
        end \
    end

// Base conditional event worker (Lifecycle, Config, Checkers)
`define __base_log_cond(VERBOSITY, ENUM, args) \
    begin \
        if (uvm_report_enabled(VERBOSITY, UVM_INFO, m_log.get_id_cond(`__FILE__, ENUM))) begin \
            `uvm_info(m_log.get_id_cond(`__FILE__, ENUM), $sformatf args, VERBOSITY) \
        end \
    end

// Base transaction worker (Guarantees lazy evaluation of string methods)
`define __base_log_tr(STR_EXPR) \
    begin \
        automatic string _log_id = m_log.get_id_cond(`__FILE__, logger::TR); \
        if (uvm_report_enabled(UVM_HIGH, UVM_INFO, _log_id)) begin \
            `uvm_info(_log_id, STR_EXPR, UVM_HIGH) \
        end \
    end

// Base fatal redirection worker
`define __base_fatal(ENUM, msg) \
    `uvm_fatal(m_log.get_id_cond(`__FILE__, ENUM), msg)

// Base non-fatal error redirection worker
`define __base_error(ENUM, msg) \
    `uvm_error(m_log.get_id_cond(`__FILE__, ENUM), msg)


// =============================================================================
// PUBLIC API
// =============================================================================

// CORE VERBOSITY INTERFACES ───────────────────────────────────────────────────
`define log_low(args) `__base_log(UVM_LOW, args)
`define log_medium(args) `__base_log(UVM_MEDIUM, args)
`define log_high(args) `__base_log(UVM_HIGH, args)
`define log_full(args) `__base_log(UVM_FULL, args)
`define log_debug(args) `__base_log(UVM_DEBUG, args)

// LIFECYCLE EVENTS ────────────────────────────────────────────────────────────
// Upgraded to accept (args) for inline $sformatf capability if needed
`define log_build(args) `__base_log_cond(UVM_LOW, logger::BUILD, args)
`define log_connect(args) `__base_log_cond(UVM_LOW, logger::CONNECT, args)
`define log_reset(args) `__base_log_cond(UVM_LOW, logger::RESET, args)
`define log_end_of_elaboration(args) `__base_log_cond(UVM_LOW, logger::EOE, args)

// RESOURCE / CONFIGURATION EVENTS ─────────────────────────────────────────────
`define log_create(args) `__base_log_cond(UVM_LOW, logger::CREATE, args)
`define log_cfg(args) `__base_log_cond(UVM_LOW, logger::CFG, args)
`define log_cfg_fallback(args) `__base_log_cond(UVM_LOW, logger::CFG_FALLBACK, args)

// TRANSACTION EVENTS ──────────────────────────────────────────────────────────
`define log_tr_msg(msg) `__base_log_tr(msg)
`define log_tr(tr, msg = "") `__base_log_tr({msg, tr.convert2string()})
`define log_tr_in(tr, msg = "") `__base_log_tr({msg, tr.input2string()})
`define log_tr_out(tr, msg = "") `__base_log_tr({msg, tr.output2string()})
`define log_tr_full(msg, tr) `__base_log_tr($sformatf("%s\n%s", msg, tr.convert2string()))

// AGENT MODE LOGGING ──────────────────────────────────────────────────────────
`define log_agent_mode(mode) `__base_log_cond(UVM_LOW, logger::AGENT_MODE, ("Agent mode: %s", mode))

// FATAL ERRORS ────────────────────────────────────────────────────────────────
`define log_cfg_err(msg) `__base_fatal(logger::CFG_NOT_FOUND, msg)
`define log_vif_err(msg) `__base_fatal(logger::VIF_NOT_FOUND, msg)
`define log_rand_err(msg) `__base_fatal(logger::RAND_FAIL, msg)
`define log_cast_err(msg) `__base_fatal(logger::CAST_FAIL, msg)
`define log_sqr_err(msg) `__base_fatal(logger::SQR_NULL, msg)

// NON-FATAL ERRORS ────────────────────────────────────────────────────────────
`define log_type_err(msg) `__base_error(logger::CFG_TYPE_ERR, msg)
`define log_null_err(msg) `__base_error(logger::CFG_VIF_NULL, msg)
`define log_mismatch(msg) `__base_error(logger::PKT_MISMATCH, msg)
`define log_timeout(msg) `__base_error(logger::TIMEOUT, msg)
`define log_test_err(msg) `__base_error(logger::TEST_FAIL, msg)

`define log_err(id, arg) `uvm_error(id, $sformatf arg)

// SUCCESS / CHECKER EVENTS ────────────────────────────────────────────────────
`define log_match(args) `__base_log_cond(UVM_HIGH, logger::PKT_MATCH, args)

// SCOREBOARD REPORTS ──────────────────────────────────────────────────────────
`define log_sb_report_pass(report) \
    `__base_log_cond(UVM_LOW, logger::TEST_PASS, ("✔ DUT SCOREBOARD STATUS : PASS \n%s", report))

`define log_sb_report_fail(msg) \
    `__base_error(logger::TEST_FAIL, $sformatf("✖ DUT SCOREBOARD STATUS : FAIL \n%s", msg))

// ESCAPE HATCH (CUSTOM CONDITIONS) ────────────────────────────────────────────
`define log_info(cond, msg, verb) \
    `uvm_info(m_log.get_id_str(`__FILE__, cond), msg, verb)

`endif  // LOG_MACROS_SVH

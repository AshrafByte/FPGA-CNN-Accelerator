# ==============================================================================
# Questa Simulation Script (run.do)
#
# Executes simulation assuming the design is pre-compiled into the 'work' library.
# Default parameters below can be overridden via Tcl injection by the CLI runner.
# ==============================================================================

# --- Environment Configuration ---
# Assumption: TOP expects a bare module name (the 'work.' prefix is appended later)

if {![info exists TOP]}            { set TOP dut_uvm_tb }
if {![info exists TEST]}           { set TEST "" }
if {![info exists SEED]}           { set SEED random }
if {![info exists VERBOSITY]}      { set VERBOSITY UVM_HIGH }
if {![info exists VSIM_ARGS]}      { set VSIM_ARGS "-voptargs=+acc -cover -suppress 3070" }
if {![info exists EXTRA_PLUSARGS]} { set EXTRA_PLUSARGS "" }
if {![info exists RECORD]}         { set RECORD 1 }

# --- Logging Setup ---
# Force fresh transcript log for each run

transcript off
catch {transcript file ""}
catch {file delete -force run.log}
transcript file run.log
transcript on

# --- Standalone Compile Fallback ---
# When vrun.py drives this (the normal path), its own compile() already
# ran in Python beforehand - vmap/vdir/vlib/vlog, with dynamic UVM-path
# resolution and optional coverage flags - and it explicitly sets
# SELF_COMPILE 0 below (a fact it knows for certain, not inferred from
# filesystem state), so this whole block is skipped in that path.
#
# This exists so `vsim -c -do run.do` also works completely standalone,
# e.g. for quick manual debugging with no Python involved at all - this
# mirrors what used to be a separate, always-runs, hardcoded-path script.
# SELF_COMPILE defaults to 1 (always recompile fresh) rather than checking
# whether work/ exists, to match the old script's actual behavior exactly -
# it always ran vdel+vlib+vlog unconditionally, so a stale compile was
# never possible there either.

if {![info exists SELF_COMPILE]} { set SELF_COMPILE 1 }
if {![info exists UVM_VER]}      { set UVM_VER 1.2 }
if {![info exists COVERAGE]}     { set COVERAGE 0 }

if {$SELF_COMPILE} {
    puts "INFO: SELF_COMPILE (standalone run) - compiling before elaboration."

    # Same resolution vrun.py's _get_uvm_path() uses: sibling "uvm-$UVM_VER"
    # of the running vsim's own install root, not a hardcoded machine-
    # specific path - override via QUESTA_UVM_HOME if your layout differs.
    if {[info exists env(QUESTA_UVM_HOME)]} {
        set uvm_dir $env(QUESTA_UVM_HOME)
    } else {
        set install_root [file dirname [file dirname [info nameofexecutable]]]
        set uvm_dir $install_root/uvm-$UVM_VER
    }

    vlib work
    vmap uvm12 $uvm_dir
    vdir -lib uvm12
    vmap mtiUvm $uvm_dir
    set cover_flags [expr {$COVERAGE ? "+cover -covercells " : ""}]
    eval vlog -work work $cover_flags-f compile.f
}

# --- Simulation Execution ---

set UVM_TEST_ARG ""
if {$TEST != ""} {
    set UVM_TEST_ARG "+UVM_TESTNAME=$TEST"
}

eval vsim \
    $VSIM_ARGS \
    work.$TOP \
    $UVM_TEST_ARG \
    +UVM_VERBOSITY=$VERBOSITY \
    -sv_seed $SEED \
    $EXTRA_PLUSARGS

# --- Waveform Setup ---
# `make wave` is the single canonical way to view waveforms afterward
# (batch or GUI run alike) - so recording is unconditional here, but this
# no longer auto-populates a live Wave pane during a GUI=1 run. Add signals
# manually via Structure/Objects if you want to watch live, or just use
# `make wave` once the run finishes.

if {$RECORD} {
    if {[file exists "wave.do"]} {
        puts "INFO: Loading waveform configuration from wave.do"
        do wave.do
    } else {
        puts "INFO: wave.do not found. Recording all DUT signals for later viewing via 'make wave'."
        log -r /$TOP/*
    }
}

# --- Run Simulation ---

run -all

# --- Exit ---

if {[batch_mode]} {
    quit -f
}

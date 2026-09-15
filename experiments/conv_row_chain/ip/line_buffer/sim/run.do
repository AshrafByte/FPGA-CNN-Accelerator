# ==============================================================================
# Questa simulation script for line_buffer (self-checking line_buffer_tb)
#
#   python common/script/vrun.py sim line_buffer       (compiles, then runs this)
#   vsim -c -do run.do                                  (standalone, from this folder)
#
# vrun.py may set TOP, SEED, VSIM_ARGS and RECORD before sourcing this file;
# the defaults below apply otherwise. Geometry overrides go in VSIM_ARGS,
# e.g. set VSIM_ARGS "-voptargs=+acc -gLINE_LENGTH=13 -gLINE_NUM=5".
# The run fails (exit code 1 in batch mode) on any [FAIL], error or fatal,
# or when the testbench never reports [PASS].
# ==============================================================================

if {![info exists TOP]}          { set TOP line_buffer_tb }
if {![info exists SEED]}         { set SEED random }
if {![info exists VSIM_ARGS]}    { set VSIM_ARGS "-voptargs=+acc" }
if {![info exists RECORD]}       { set RECORD 1 }
# vrun.py has already compiled into work/; compile here only when run standalone.
if {![info exists SELF_COMPILE]} { set SELF_COMPILE [expr {![file isdirectory work]}] }

transcript off
catch {transcript file ""}
catch {file delete -force run.log}
transcript file run.log
transcript on

if {$SELF_COMPILE} {
    puts "INFO: no work library - compiling compile.f"
    vlib work
    vlog -sv -work work -f compile.f
}

eval vsim $VSIM_ARGS -t 1ps work.$TOP -sv_seed $SEED

if {$RECORD} {
    if {[file exists "wave.do"]} {
        do wave.do
    } else {
        log -r /$TOP/*
    }
}

onfinish stop
run -all

# ---- verdict from the transcript ------------------------------------------------
transcript file ""
set status 1
if {![catch {set fh [open run.log r]}]} {
    set log [read $fh]
    close $fh
    if {[regexp {\[PASS\]} $log] && ![regexp {\[FAIL\]|STATUS: ERROR|\*\* (Error|Fatal)} $log]} {
        set status 0
    }
}
puts [expr {$status == 0 ? "RESULT: PASS ($TOP)" : "RESULT: FAIL ($TOP) - see run.log"}]

if {[batch_mode]} {
    quit -f -code $status
}

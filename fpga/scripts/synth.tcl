#------------------------------------------------------------------------------
# synth.tcl - synthesize conv_system (non-project mode)
#
#   vivado -mode batch -source fpga/scripts/synth.tcl [-tclargs N 3 W 32 ...]
#
# Output: fpga/synth/<tag>/
#   post_synth.dcp        checkpoint for impl.tcl
#   utilization.txt       utilization_hier.txt   timing_summary.txt
#   clock.xdc             the constraint actually used
#   metrics.txt           LUT / FF / DSP / BRAM / WNS in key=value form
#------------------------------------------------------------------------------
source [file join [file dirname [info script]] config.tcl]

file mkdir $SYNTH_DIR
catch {close_design}

set clock_xdc [make_clock_xdc $SYNTH_DIR]
read_verilog -sv $RTL_FILES
read_xdc [list $clock_xdc]

synth_design -top $TOP -part $PART {*}$GENERICS
write_checkpoint -force [file join $SYNTH_DIR post_synth.dcp]

report_utilization -file [file join $SYNTH_DIR utilization.txt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $SYNTH_DIR utilization_hier.txt]
report_timing_summary -max_paths 10 -file [file join $SYNTH_DIR timing_summary.txt]

set m [design_metrics]
write_metrics [file join $SYNTH_DIR metrics.txt] $m
puts "### SYNTH tag=$CFG(TAG) lut=[dict get $m lut] ff=[dict get $m ff] dsp=[dict get $m dsp] bram=[dict get $m bram] wns=[dict get $m wns]"

#------------------------------------------------------------------------------
# impl.tcl - place and route the synthesized conv_system
#
#   vivado -mode batch -source fpga/scripts/impl.tcl [-tclargs N 3 W 32 ...]
#
# Input:  fpga/synth/<tag>/post_synth.dcp
# Output: fpga/impl/<tag>/
#   post_route.dcp        checkpoint for power.tcl
#   utilization.txt       utilization_hier.txt   timing_summary.txt
#   route_status.txt      drc.txt                power_vectorless.txt
#   metrics.txt           LUT / FF / DSP / BRAM / WNS / Fmax / vectorless power
#------------------------------------------------------------------------------
source [file join [file dirname [info script]] config.tcl]

set dcp [file join $SYNTH_DIR post_synth.dcp]
if {![file exists $dcp]} { error "no synthesis checkpoint $dcp - run synth.tcl first" }

catch {close_design}
open_checkpoint $dcp

opt_design
place_design
phys_opt_design
route_design

file mkdir $IMPL_DIR
write_checkpoint -force [file join $IMPL_DIR post_route.dcp]

report_utilization -file [file join $IMPL_DIR utilization.txt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $IMPL_DIR utilization_hier.txt]
report_timing_summary -max_paths 10 -file [file join $IMPL_DIR timing_summary.txt]
report_route_status -file [file join $IMPL_DIR route_status.txt]
report_drc -file [file join $IMPL_DIR drc.txt]

set_units -power uW
report_power -file [file join $IMPL_DIR power_vectorless.txt]
set p [power_values [read_text [file join $IMPL_DIR power_vectorless.txt]]]

set m [design_metrics]
dict set m power_vectorless_mw [format %.3f [expr {[dict get $p total] / 1000.0}]]
write_metrics [file join $IMPL_DIR metrics.txt] $m

puts "### IMPL tag=$CFG(TAG) lut=[dict get $m lut] ff=[dict get $m ff] dsp=[dict get $m dsp] bram=[dict get $m bram] wns=[dict get $m wns] fmax=[dict get $m fmax_mhz] MHz p_vectorless=[dict get $m power_vectorless_mw] mW"
if {[dict get $m wns] < 0} { puts "### WARNING timing not met at $CFG(PERIOD) ns (WNS [dict get $m wns] ns)" }

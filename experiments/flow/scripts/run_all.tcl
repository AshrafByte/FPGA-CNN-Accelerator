#------------------------------------------------------------------------------
# run_all.tcl - the experiments flow (synth, impl, power) in one Vivado session
#
#   vivado -mode batch -source experiments/flow/scripts/run_all.tcl [-tclargs N 3 W 32 ...]
#
# STEPS selects the steps, joined with '+' (default synth+impl+power):
#   -tclargs STEPS synth+impl+power
#------------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir config.tcl]

set steps [split $CFG(STEPS) +]
foreach step $steps {
   if {$step ni {synth impl power}} { error "unknown step '$step'" }
}
foreach step {synth impl power} {
   if {$step in $steps} {
      set t0 [clock seconds]
      puts "### STEP $step started"
      source [file join $script_dir $step.tcl]
      puts "### STEP $step finished in [expr {[clock seconds] - $t0}] s"
   }
}

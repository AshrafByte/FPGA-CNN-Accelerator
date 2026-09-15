#------------------------------------------------------------------------------
# power.tcl - benchmark power and figure of merit of the routed conv_system
#
#   vivado -mode batch -source experiments/flow/scripts/power.tcl [-tclargs N 3 W 32 ...]
#
# 1. Simulates every benchmark with xsim (fpga/sim/conv_system_power_tb.sv) and
#    records conv.saif under experiments/flow/build/sim/<tag>/<benchmark>/. A SAIF newer
#    than every RTL source is reused.
# 2. Opens experiments/flow/build/impl/<tag>/post_route.dcp, annotates each SAIF and reports power.
# 3. FoM = Throughput / (Power[W] x (LUT + 50 DSP + 100 BRAM)),
#    Throughput = 1 output pixel per clock cycle (sustained rate of conv_system).
#
# Benchmarks: 3x3 kernels -> bars + Sobel-X and checker + Sobel-Y (competition);
#             other sizes -> random image + random kernel.
#
# Output: experiments/flow/build/reports/<tag>/
#   power_<benchmark>.txt   power_default.txt (vectorless)
#   summary.md              results.csv
#------------------------------------------------------------------------------
source [file join [file dirname [info script]] config.tcl]

set dcp [file join $IMPL_DIR post_route.dcp]
if {![file exists $dcp]} { error "no routed checkpoint $dcp - run impl.tcl first" }

# name  IMAGE_MODE  KERNEL_MODE  description
if {$CFG(N) == 3 && $CFG(BENCH) eq "auto"} {
   set BENCHMARKS {
      {bars_sobel_x    5 0 "Bars + Sobel-X"}
      {checker_sobel_y 2 3 "Checker + Sobel-Y"}
   }
} else {
   set BENCHMARKS {
      {random 1 1 "Random image + random kernel"}
   }
}

set TB_FILE  [file join $FPGA_DIR sim conv_system_power_tb.sv]
set SAIF_TCL [file join $FPGA_DIR sim saif.tcl]

proc newest_mtime {files} {
   set t 0
   foreach f $files { if {[file mtime $f] > $t} { set t [file mtime $f] } }
   return $t
}

proc run_saif_sim {dir image_mode kernel_mode} {
   global CFG RTL_FILES TB_FILE SAIF_TCL
   file mkdir $dir
   set fh [open [file join $dir power_cfg.vh] w]
   puts $fh "`define CLK_PS_VAL [expr {round($CFG(PERIOD) * 1000)}]"
   puts $fh "`define IMAGE_MODE_VAL $image_mode"
   puts $fh "`define KERNEL_MODE_VAL $kernel_mode"
   puts $fh "`define WINDOW_SIZE_VAL $CFG(N)"
   puts $fh "`define INPUT_SIZE_VAL $CFG(W)"
   puts $fh "`define NUM_KERNELS_VAL $CFG(K)"
   puts $fh "`define ENABLE_RELU_VAL $CFG(RELU)"
   close $fh
   write_prj [file join $dir files.prj] [concat $RTL_FILES [list $TB_FILE]]
   file copy -force $SAIF_TCL $dir

   set here [pwd]
   cd $dir
   file delete -force conv.saif
   if {[catch {
      run_tool xvlog.txt [xilinx_tool xvlog] -prj files.prj -i .
      run_tool xelab.txt [xilinx_tool xelab] -debug typical -timescale 1ps/1ps -s power_snap xil_defaultlib.conv_system_power_tb
      set log [run_tool xsim.txt [xilinx_tool xsim] power_snap -tclbatch saif.tcl]
   } err]} {
      cd $here
      error $err
   }
   cd $here

   set expected [expr {($CFG(W) - $CFG(N) + 1) ** 2}]
   if {![regexp {frame done: (\d+) features} $log -> seen] || $seen != $expected} {
      error "benchmark simulation in $dir emitted [expr {[info exists seen] ? $seen : 0}] features, expected $expected"
   }
   if {![file exists [file join $dir conv.saif]]} { error "xsim wrote no SAIF in $dir" }
}

# ---- 1. switching activity ---------------------------------------------------
set sources [concat $RTL_FILES [list $TB_FILE $SAIF_TCL]]
foreach b $BENCHMARKS {
   lassign $b name image_mode kernel_mode desc
   set dir  [file join $SIM_DIR $name]
   set saif [file join $dir conv.saif]
   if {[file exists $saif] && [file mtime $saif] > [newest_mtime $sources]} {
      puts "### SAIF $name reused ($saif)"
   } else {
      puts "### SAIF $name: simulating $desc"
      run_saif_sim $dir $image_mode $kernel_mode
   }
}

# ---- 2. power on the routed design --------------------------------------------
catch {close_design}
open_checkpoint $dcp
file mkdir $REPORT_DIR

set m   [design_metrics]
set res [expr {[dict get $m lut] + 50 * [dict get $m dsp] + 100 * [dict get $m bram]}]
set_units -power uW

reset_switching_activity -all
set f [file join $REPORT_DIR power_default.txt]
report_power -file $f
set results [list [list default "Vectorless (Vivado default activity)" [power_values [read_text $f]]]]

foreach b $BENCHMARKS {
   lassign $b name image_mode kernel_mode desc
   reset_switching_activity -all
   read_saif -strip_path conv_system_power_tb/u_dut [file join $SIM_DIR $name conv.saif]
   set f [file join $REPORT_DIR power_$name.txt]
   report_power -file $f
   lappend results [list $name $desc [power_values [read_text $f]]]
}

# ---- 3. figure of merit and summary ---------------------------------------------
set csv [open [file join $REPORT_DIR results.csv] w]
puts $csv "tag,benchmark,lut,lutram,ff,dsp,bram,resource_points,wns_ns,fmax_mhz,power_mw,dynamic_mw,static_mw,nets_matched,throughput_px_per_cycle,fom"

set rows ""
foreach r $results {
   lassign $r name desc p
   set p_mw  [expr {[dict get $p total] / 1000.0}]
   set fom   [expr {1.0 / (($p_mw / 1000.0) * $res)}]
   append rows [format "| %s | %.3f | %.3f | %.3f | %s | **%.5f** |\n" $desc $p_mw \
                   [expr {[dict get $p dynamic] / 1000.0}] [expr {[dict get $p static] / 1000.0}] \
                   [dict get $p matched] $fom]
   puts $csv [join [list $CFG(TAG) $name [dict get $m lut] [dict get $m lutram] [dict get $m ff] [dict get $m dsp] \
                        [dict get $m bram] $res [dict get $m wns] [dict get $m fmax_mhz] [format %.3f $p_mw] \
                        [format %.3f [expr {[dict get $p dynamic] / 1000.0}]] [format %.3f [expr {[dict get $p static] / 1000.0}]] \
                        "\"[dict get $p matched]\"" 1 [format %.6f $fom]] ,]
   puts [format "### FOM tag=%s bench=%s lut=%s ff=%s dsp=%s bram=%s res=%s wns=%s p_mw=%.3f fom=%.6f" \
            $CFG(TAG) $name [dict get $m lut] [dict get $m ff] [dict get $m dsp] [dict get $m bram] $res [dict get $m wns] $p_mw $fom]
}
close $csv

set mhz [format %.0f [expr {1000.0 / $CFG(PERIOD)}]]
set md [open [file join $REPORT_DIR summary.md] w]
puts $md "# FPGA results - `$CFG(TAG)`

Generated by `experiments/flow/scripts/power.tcl` on [clock format [clock seconds] -format {%Y-%m-%d %H:%M}] ([version -short]).

## Configuration

| Parameter | Value |
|---|---|
| Device | $PART (PYNQ-Z2) |
| Kernel size N | $CFG(N) x $CFG(N) |
| Image | $CFG(W) x $CFG(W), 8-bit unsigned pixels |
| Kernels K | $CFG(K) |
| ReLU | [expr {$CFG(RELU) ? "on" : "off"}] |
| Clock constraint | $CFG(PERIOD) ns ($mhz MHz) |

## Implementation (routed)

| LUT | LUT as memory | FF | DSP | BRAM tiles | LUT + 50 DSP + 100 BRAM |
|---|---|---|---|---|---|
| [dict get $m lut] | [dict get $m lutram] | [dict get $m ff] | [dict get $m dsp] | [dict get $m bram] | $res |

| WNS | TNS | WHS | Fmax |
|---|---|---|---|
| [dict get $m wns] ns | [dict get $m tns] ns | [dict get $m whs] ns | [dict get $m fmax_mhz] MHz |

## Power and figure of merit

FoM = Throughput / (Power \[W\] x (LUT + 50 DSP + 100 BRAM)), with Throughput = 1 output
pixel per clock cycle (conv_system's sustained output rate; $mhz Mpx/s at the constraint).
Benchmark power uses the SAIF of one full frame recorded by xsim and annotated on the
routed checkpoint.

| Workload | Total power (mW) | Dynamic (mW) | Device static (mW) | Nets matched | FoM |
|---|---|---|---|---|---|
$rows
## Reports

- Synthesis: `experiments/flow/build/synth/$CFG(TAG)/` (utilization, timing)
- Implementation: `experiments/flow/build/impl/$CFG(TAG)/` (utilization, hierarchy, timing, route status, DRC, vectorless power)
- Power: `experiments/flow/build/reports/$CFG(TAG)/power_*.txt`"
close $md

puts "### POWER tag=$CFG(TAG) summary [file join $REPORT_DIR summary.md]"

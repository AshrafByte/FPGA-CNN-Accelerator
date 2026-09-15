#------------------------------------------------------------------------------
# config.tcl - settings and helpers shared by every step of the experiments flow
#
# A copy of fpga/scripts/config.tcl for the architecture study: it adds the RTL, BENCH
# and MAX_DSP arguments and writes every output under experiments/flow/build/, so the
# competition flow and its results in fpga/ stay untouched. The power testbench and the
# clock constraint are read from fpga/.
#
# Every step script sources this file first. Arguments (vivado -tclargs) are
# key/value pairs without '=' (vivado.bat strips '=' and ',' on Windows):
#
#   N <kernel size>     W <image width>    K <kernels>     RELU <0|1>
#   PERIOD <ns>         TAG <folder name>  JOBS <threads>  STEPS <a+b+c>
#
# With no arguments the competition build is used - N 3, W 32, K 1, no ReLU,
# 4.000 ns (250 MHz) - and every output lands in a folder named "default".
#------------------------------------------------------------------------------
set FLOW_DIR [file normalize [file join [file dirname [info script]] ..]]
set REPO_DIR [file normalize [file join $FLOW_DIR .. ..]]
set FPGA_DIR [file join $REPO_DIR fpga]
set BUILD_ROOT [file join $FLOW_DIR build]

set PART xc7z020clg400-1
set TOP  conv_system

array unset CFG
array set CFG {N 3 W 32 K 1 RELU 0 PERIOD 4.000 TAG "" JOBS 4 STEPS synth+impl+power BUILD ""
               RTL hw BENCH auto MAX_DSP -1}
if {[llength $argv] % 2} { error "arguments must be key/value pairs, got: $argv" }
foreach {key value} $argv {
   set key [string toupper $key]
   if {![info exists CFG($key)]} { error "unknown argument '$key' (known: [lsort [array names CFG]])" }
   set CFG($key) $value
}
# RTL   hw (default) or the name of a build under experiments/ (conv_tree, conv_row_chain,
#       conv_single_chain, round_half_even, round_always_clamp)
# BENCH auto (3x3: bars + Sobel-X and checker + Sobel-Y, else random) or random (every size)
# MAX_DSP  synth_design -max_dsp limit; -1 = none. Multipliers beyond it go into LUTs.
if {$CFG(BENCH) ni {auto random}} { error "BENCH must be auto or random, got '$CFG(BENCH)'" }
if {$CFG(TAG) eq ""} {
   if {$CFG(N) == 3 && $CFG(W) == 32 && $CFG(K) == 1 && $CFG(RELU) == 0 && $CFG(PERIOD) == 4.0
       && $CFG(RTL) eq "hw" && $CFG(BENCH) eq "auto" && $CFG(MAX_DSP) < 0} {
      set CFG(TAG) default
   } else {
      set CFG(TAG) "n$CFG(N)_w$CFG(W)_k$CFG(K)_r$CFG(RELU)_p$CFG(PERIOD)"
      if {$CFG(RTL) ne "hw"}      { set CFG(TAG) "$CFG(RTL)_$CFG(TAG)" }
      if {$CFG(BENCH) ne "auto"}  { append CFG(TAG) "_$CFG(BENCH)" }
      if {$CFG(MAX_DSP) >= 0}     { append CFG(TAG) "_dsp$CFG(MAX_DSP)" }
   }
}

set SYNTH_DIR  [file join $BUILD_ROOT synth   $CFG(TAG)]
set IMPL_DIR   [file join $BUILD_ROOT impl    $CFG(TAG)]
set REPORT_DIR [file join $BUILD_ROOT reports $CFG(TAG)]
set SIM_DIR    [file join $BUILD_ROOT sim     $CFG(TAG)]
set BIT_DIR    [file join $FPGA_DIR bitstream]
set BOARD_DIR  [file join $FPGA_DIR board]
if {$CFG(RTL) eq "hw"} {
   set RTL_F   [file join $REPO_DIR hw system conv_system sim rtl.f]
} else {
   set RTL_F   [file join $REPO_DIR experiments $CFG(RTL) system conv_system sim rtl.f]
}
if {![file exists $RTL_F]} { error "RTL '$CFG(RTL)': no file list $RTL_F" }

set GENERICS [list -generic WINDOW_SIZE=$CFG(N) -generic INPUT_SIZE=$CFG(W) \
                   -generic NUM_KERNELS=$CFG(K) -generic ENABLE_RELU=$CFG(RELU)]

# ---- RTL file list: the same rtl.f the simulators use ------------------------
proc read_filelist {f} {
   set dir   [file dirname [file normalize $f]]
   set files {}
   set fh    [open $f r]
   foreach line [split [read $fh] "\n"] {
      set line [string trim $line]
      if {$line eq "" || [string match "//*" $line] || [string match "#*" $line]} { continue }
      if {[regexp {^-[fF]\s+(.+)$} $line -> sub]} {
         lappend files {*}[read_filelist [file join $dir [string trim $sub]]]
      } elseif {[string index $line 0] ne "-" && [string index $line 0] ne "+"} {
         lappend files [file normalize [file join $dir $line]]
      }
   }
   close $fh
   return $files
}
set RTL_FILES [read_filelist $RTL_F]

# ---- clock constraint with the requested period -------------------------------
proc make_clock_xdc {dir} {
   global FPGA_DIR CFG
   set fh  [open [file join $FPGA_DIR constraints conv_system.xdc] r]
   set xdc [read $fh]
   close $fh
   regsub -- {-period\s+[0-9.]+} $xdc "-period $CFG(PERIOD)" xdc
   file mkdir $dir
   set out [file join $dir clock.xdc]
   set fh  [open $out w]
   puts -nonewline $fh $xdc
   close $fh
   return $out
}

# ---- metrics of the open design ------------------------------------------------
proc util_value {report key} {
   # Synthesis reports mark estimated rows with '*' ("Slice LUTs*").
   if {[regexp "\\|\\s*$key\\*?\\s*\\|\\s*(\[0-9.\]+)" $report -> v]} { return $v }
   return 0
}

proc design_metrics {} {
   global CFG
   set u [report_utilization -return_string]
   dict set m lut    [util_value $u "Slice LUTs"]
   dict set m lutram [util_value $u "LUT as Memory"]
   dict set m ff     [util_value $u "Slice Registers"]
   dict set m dsp    [util_value $u "DSPs"]
   dict set m bram   [util_value $u "Block RAM Tile"]

   set t [report_timing_summary -no_header -no_detailed_paths -return_string]
   if {[regexp {WNS\(ns\)\s+TNS\(ns\)[^\n]*\n[^\n]*\n\s*([-0-9.]+)\s+([-0-9.]+)\s+\d+\s+\d+\s+([-0-9.]+)\s+([-0-9.]+)} \
           $t -> wns tns whs ths]} {
      dict set m wns $wns
      dict set m tns $tns
      dict set m whs $whs
   } else {
      dict set m wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
      dict set m tns 0
      dict set m whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
   }
   dict set m fmax_mhz [format %.1f [expr {1000.0 / ($CFG(PERIOD) - [dict get $m wns])}]]
   return $m
}

proc write_metrics {file metrics} {
   set fh [open $file w]
   dict for {k v} $metrics { puts $fh "$k=$v" }
   close $fh
}

proc read_metrics {file} {
   set m {}
   set fh [open $file r]
   foreach line [split [read $fh] "\n"] {
      if {[regexp {^([^=]+)=(.*)$} $line -> k v]} { dict set m $k $v }
   }
   close $fh
   return $m
}

proc read_text {file} {
   set fh [open $file r]
   set s  [read $fh]
   close $fh
   return $s
}

# report_power text (units uW) -> dict total dynamic static matched confidence
proc power_values {report} {
   set p {total 0 dynamic 0 static 0 matched - confidence -}
   if {[regexp {Total On-Chip Power \(uW\)\s*\|\s*([0-9.]+)} $report -> v]} { dict set p total   $v }
   if {[regexp {Dynamic \(uW\)\s*\|\s*([0-9.]+)}             $report -> v]} { dict set p dynamic $v }
   if {[regexp {Device Static \(uW\)\s*\|\s*([0-9.]+)}       $report -> v]} { dict set p static  $v }
   if {[regexp {Design Nets Matched\s*\|\s*([^|]+)\|}         $report -> v]} { dict set p matched [string trim $v] }
   if {[regexp {Confidence Level\s*\|\s*([A-Za-z]+)}          $report -> v]} { dict set p confidence $v }
   return $p
}

# ---- Vivado simulator (xvlog / xelab / xsim) -----------------------------------
proc xilinx_tool {name} {
   set bin [file join $::env(XILINX_VIVADO) bin $name]
   if {$::tcl_platform(platform) eq "windows"} { append bin .bat }
   return $bin
}

# Runs a tool in the current directory, keeps its output in <log>, fails on errors.
proc run_tool {log args} {
   set rc [catch {exec -ignorestderr {*}$args 2>@1} out]
   set fh [open $log w]
   puts $fh $out
   close $fh
   if {$rc || [regexp -line {^(ERROR|FATAL_ERROR|Fatal)} $out]} {
      error "[file tail [lindex $args 0]] failed - see [file normalize $log]"
   }
   return $out
}

# xvlog project file: one quoted path per line (the paths contain spaces).
proc write_prj {file sources} {
   set fh [open $file w]
   foreach f $sources { puts $fh "sv xil_defaultlib \"$f\"" }
   close $fh
}

puts "### config tag=$CFG(TAG) rtl=$CFG(RTL) N=$CFG(N) W=$CFG(W) K=$CFG(K) RELU=$CFG(RELU) period=$CFG(PERIOD) ns bench=$CFG(BENCH) max_dsp=$CFG(MAX_DSP) part=$PART"

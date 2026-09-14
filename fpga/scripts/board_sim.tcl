#------------------------------------------------------------------------------
# board_sim.tcl - self-checking xsim test of the board-demo AXI4-Lite wrapper
#
#   vivado -mode batch -source fpga/scripts/board_sim.tcl
#
# Runs fpga/board/tb/conv_axi_lite_tb.sv on three builds - the demo build
# (3x3, 32x32, one kernel), two kernel lanes, and a 5x5 row-chain build with
# ReLU - and fails if any feature read back through AXI differs from the model.
# Logs: fpga/sim/build/board/<build>/xsim.txt
#------------------------------------------------------------------------------
source [file join [file dirname [info script]] config.tcl]

set tb      [file join $BOARD_DIR tb conv_axi_lite_tb.sv]
set sources [concat $RTL_FILES [list [file join $BOARD_DIR rtl conv_axi_lite.sv] $tb]]

# N W K RELU
set builds {
   {3 32 1 0}
   {3 32 2 0}
   {5 16 1 1}
}

set failed {}
foreach b $builds {
   lassign $b n w k r
   set name "n${n}_w${w}_k${k}_r${r}"
   set dir  [file join $FPGA_DIR sim build board $name]
   file mkdir $dir

   set fh [open [file join $dir board_tb_cfg.vh] w]
   puts $fh "`define TB_WINDOW_SIZE $n"
   puts $fh "`define TB_INPUT_SIZE $w"
   puts $fh "`define TB_NUM_KERNELS $k"
   puts $fh "`define TB_ENABLE_RELU $r"
   close $fh
   write_prj [file join $dir files.prj] $sources

   set here [pwd]
   cd $dir
   set rc [catch {
      run_tool xvlog.txt [xilinx_tool xvlog] -prj files.prj -i .
      run_tool xelab.txt [xilinx_tool xelab] -timescale 1ns/1ps -s board_snap xil_defaultlib.conv_axi_lite_tb
      set log [run_tool xsim.txt [xilinx_tool xsim] board_snap -R]
   } err]
   cd $here

   if {$rc} {
      puts "### BOARD_SIM $name ERROR $err"
      lappend failed $name
   } elseif {[regexp {TEST PASSED} $log]} {
      foreach line [regexp -all -inline -line {^\[BOARD\].*$} $log] { puts "   $line" }
      puts "### BOARD_SIM $name PASSED"
   } else {
      foreach line [regexp -all -inline -line {^(\[BOARD\]|TEST).*$} $log] { puts "   $line" }
      puts "### BOARD_SIM $name FAILED (log [file join $dir xsim.txt])"
      lappend failed $name
   }
}

if {[llength $failed]} { error "board wrapper test failed: $failed" }
puts "### BOARD_SIM all builds passed"

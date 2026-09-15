#------------------------------------------------------------------------------
# bitstream.tcl - PYNQ-Z2 board demo bitstream (bonus: board demonstration)
#
#   vivado -mode batch -source fpga/scripts/bitstream.tcl [-tclargs N 3 W 32 K 1 RELU 0]
#
# Block design "system": Zynq processing_system7 (FCLK_CLK0 = 100 MHz), AXI
# interconnect, proc_sys_reset, M_AXI (AXI4-Lite) exported at 0x43C00000 / 1 MB.
# Top level conv_demo_top = system_wrapper + conv_axi_lite (+ conv_system).
#
# Output: fpga/bitstream/
#   conv_demo.bit  conv_demo.hwh   the PYNQ overlay pair (same base name)
#   conv_demo.txt                  build configuration and address map
#   reports/                       utilization, timing, power of the demo build
#   build/                         the Vivado project (not needed on the board)
#------------------------------------------------------------------------------
source [file join [file dirname [info script]] config.tcl]

set BASE_ADDR  0x43C00000
# The block design's generated IP paths are ~150 characters deep and Windows
# refuses paths over 260, so on Windows a project under a long checkout goes to
# %TEMP%\conv_demo_build instead (override with BUILD <dir>). The overlay and
# the reports are copied into fpga/bitstream either way.
if {$CFG(BUILD) ne ""} {
   set BUILD_DIR [file normalize $CFG(BUILD)]
} elseif {$::tcl_platform(platform) eq "windows" && [string length [file join $BIT_DIR build]] > 100} {
   set BUILD_DIR [file normalize [file join $::env(TEMP) conv_demo_build]]
} else {
   set BUILD_DIR [file join $BIT_DIR build]
}
puts "### BITSTREAM project directory $BUILD_DIR"
set BIT_REPORT [file join $BIT_DIR reports]

catch {close_design}
catch {close_project}
file mkdir $BIT_DIR $BIT_REPORT

create_project -force conv_demo $BUILD_DIR -part $PART
set_property target_language Verilog [current_project]

add_files -norecurse [concat $RTL_FILES [glob [file join $BOARD_DIR rtl *.sv]]]
add_files -fileset constrs_1 -norecurse [list [file join $BOARD_DIR constraints pynq_z2.xdc]]

# ---- block design ------------------------------------------------------------
proc latest_ip {name} {
   set defs [lsort [get_ipdefs -all -filter "NAME == $name"]]
   if {![llength $defs]} { error "IP $name not found in the Vivado catalog" }
   return [lindex $defs end]
}

create_bd_design system

set ps [create_bd_cell -type ip -vlnv [latest_ip processing_system7] processing_system7_0]
set_property -dict [list \
   CONFIG.PCW_USE_M_AXI_GP0 {1} \
   CONFIG.PCW_EN_CLK0_PORT {1} \
   CONFIG.PCW_EN_RST0_PORT {1} \
   CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
] $ps
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
   -config {make_external "FIXED_IO, DDR" Master "Disable" Slave "Disable"} $ps

set rst [create_bd_cell -type ip -vlnv [latest_ip proc_sys_reset] rst_ps7_100M]
set ic  [create_bd_cell -type ip -vlnv [latest_ip axi_interconnect] axi_interconnect_0]
set_property CONFIG.NUM_MI {1} $ic

set m_axi [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI]
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.ADDR_WIDTH {32} CONFIG.DATA_WIDTH {32} \
                         CONFIG.FREQ_HZ {100000000}] $m_axi
set clk_port [create_bd_port -dir O -type clk clk_100]
set_property -dict [list CONFIG.FREQ_HZ {100000000} CONFIG.ASSOCIATED_BUSIF {M_AXI} \
                         CONFIG.ASSOCIATED_RESET {rst_n}] $clk_port
# Polarity is taken from the connected peripheral_aresetn (active low).
set rst_port [create_bd_port -dir O -type rst rst_n]

connect_bd_net [get_bd_pins $ps/FCLK_CLK0] [get_bd_pins $ps/M_AXI_GP0_ACLK] \
   [get_bd_pins $rst/slowest_sync_clk] [get_bd_pins $ic/ACLK] [get_bd_pins $ic/S00_ACLK] \
   [get_bd_pins $ic/M00_ACLK] $clk_port
connect_bd_net [get_bd_pins $ps/FCLK_RESET0_N] [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $rst/interconnect_aresetn] [get_bd_pins $ic/ARESETN]
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] [get_bd_pins $ic/S00_ARESETN] \
   [get_bd_pins $ic/M00_ARESETN] $rst_port
connect_bd_intf_net [get_bd_intf_pins $ps/M_AXI_GP0] [get_bd_intf_pins $ic/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins $ic/M00_AXI] $m_axi

assign_bd_address
set seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces $ps/Data]]
set_property range 1M $seg
set_property offset $BASE_ADDR $seg

validate_bd_design
save_bd_design

set bd_file [get_files system.bd]
generate_target all $bd_file
add_files -norecurse [list [make_wrapper -files $bd_file -top]]

set_property top conv_demo_top [current_fileset]
set_property generic "WINDOW_SIZE=$CFG(N) INPUT_SIZE=$CFG(W) NUM_KERNELS=$CFG(K) ENABLE_RELU=$CFG(RELU)" [current_fileset]
update_compile_order -fileset sources_1

# ---- synthesis, implementation, bitstream ---------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs $CFG(JOBS)
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
   error "bitstream run failed - see [file join $BUILD_DIR conv_demo.runs impl_1 runme.log]"
}

open_run impl_1
report_utilization -file [file join $BIT_REPORT utilization.txt]
report_utilization -hierarchical -hierarchical_depth 3 -file [file join $BIT_REPORT utilization_hier.txt]
report_timing_summary -max_paths 10 -file [file join $BIT_REPORT timing_summary.txt]
set_units -power mW
report_power -file [file join $BIT_REPORT power.txt]
set t [report_timing_summary -no_header -no_detailed_paths -return_string]
set wns ?
regexp {WNS\(ns\)\s+TNS\(ns\)[^\n]*\n[^\n]*\n\s*([-0-9.]+)} $t -> wns

set bit [lindex [glob -nocomplain [file join $BUILD_DIR conv_demo.runs impl_1 *.bit]] 0]
set hwh [lindex [glob -nocomplain [file join $BUILD_DIR conv_demo.srcs sources_1 bd system hw_handoff system.hwh]] 0]
if {$bit eq "" || $hwh eq ""} { error "bitstream or hardware handoff missing in $BUILD_DIR" }
file copy -force $bit [file join $BIT_DIR conv_demo.bit]
file copy -force $hwh [file join $BIT_DIR conv_demo.hwh]

set fh [open [file join $BIT_DIR conv_demo.txt] w]
puts $fh "conv_demo overlay (PYNQ-Z2, $PART), built [clock format [clock seconds] -format {%Y-%m-%d %H:%M}] with [version -short]"
puts $fh "conv_system: WINDOW_SIZE=$CFG(N) INPUT_SIZE=$CFG(W) NUM_KERNELS=$CFG(K) ENABLE_RELU=$CFG(RELU)"
puts $fh "fabric clock: FCLK_CLK0 100 MHz, WNS $wns ns"
puts $fh "conv_axi_lite: AXI4-Lite at [format 0x%08X $BASE_ADDR], range 1 MB (register map in fpga/board/rtl/conv_axi_lite.sv)"
close $fh

puts "### BITSTREAM [file join $BIT_DIR conv_demo.bit] (WNS $wns ns at 100 MHz)"

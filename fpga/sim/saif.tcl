# xsim batch script: record the switching activity of the whole DUT for one
# benchmark frame. Run from the benchmark's simulation directory.
open_saif conv.saif
log_saif [get_objects -r /conv_system_power_tb/u_dut/*]
run -all
close_saif
quit

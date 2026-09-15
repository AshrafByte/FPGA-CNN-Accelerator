# conv_system standalone build (competition figure of merit).
# 250 MHz. The flow scripts copy this file into the run directory and replace
# the period with the PERIOD argument (default 4.000 ns).
create_clock -name clk -period 6.250 [get_ports clk]

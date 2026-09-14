# PYNQ-Z2 board demo. The processing system pins (DDR, MIO) need no
# constraints and the 100 MHz fabric clock FCLK_CLK0 is constrained by the
# processing_system7 IP itself. Only the four user LEDs are used.
#   LD0 all weights loaded   LD1 streaming   LD2 frame done   LD3 heartbeat
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {leds[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {leds[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {leds[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {leds[3]}]

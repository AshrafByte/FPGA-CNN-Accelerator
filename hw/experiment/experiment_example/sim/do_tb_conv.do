vsim -voptargs=+acc work.conv_accelerator_tb

add wave -r /conv_accelerator_tb/*

run -all

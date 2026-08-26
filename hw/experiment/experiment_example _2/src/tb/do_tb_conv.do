vsim -voptargs=+acc work.conv_accelerator_app2_tb

add wave -r /conv_accelerator_app2_tb/*

run -all

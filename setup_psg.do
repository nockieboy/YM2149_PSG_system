transcript on
if {[file exists work]} {
	vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -work work {YM2149_PSG_system_tb.sv}
vsim -t 1ps -L work -voptargs="+acc"  YM2149_PSG_system_tb

restart -force -nowave

# This line shows only the variable name instead of the full path and which module it was in
config wave -signalnamewidth 1


add wave -divider     "IN: System Control"
add wave -hexadecimal PSG/reset_n
add wave -hexadecimal PSG/wr_n
add wave -hexadecimal PSG/addr
add wave -hexadecimal PSG/data

add wave -divider     "IN: Clock"
add wave -hexadecimal PSG/clk
add wave -hexadecimal PSG/p_stb

add wave -divider     "OUT: YM2149 Waveform"
add wave -hexadecimal PSG/sample_stb

add wave -divider
add wave -unsigned -analog -min -0   -max 255  -height 50  PSG/sound_A

add wave -divider
add wave -unsigned -analog -min -0   -max 255  -height 50  PSG/sound_B

add wave -divider
add wave -unsigned -analog -min -0   -max 255  -height 50  PSG/sound_C

add wave -divider
add wave -unsigned -analog -min -0   -max 1023 -height 50  PSG/sound_mix

add wave -divider
add wave -unsigned -analog -min -0   -max 255  -height 50  PSG/sound_D

add wave -divider
add wave -unsigned -analog -min -0   -max 255  -height 50  PSG/sound_E

add wave -divider
add wave -unsigned -analog -min -0   -max 255  -height 50  PSG/sound_F


add wave -divider     "OUT: Left"
add wave -decimal -analog -min -32768  -max 32768  -height 200  PSG/sound
add wave -divider     "OUT: Right"
add wave -decimal -analog -min -32768  -max 32768  -height 200  PSG/sound_right

add wave -divider     "OUT: I2S TX"
add wave -hexadecimal PSG/i2s_sclk
add wave -hexadecimal PSG/i2s_lrclk
add wave -hexadecimal PSG/i2s_data


do run_psg.do

transcript on
if {[file exists work]} {
	vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -work work {YM2149_PSG_system_tb.sv}
vsim -t 1ps -L work -voptargs="+acc"  YM2149_Render_DAC_tb

restart -force -nowave

# This line shows only the variable name instead of the full path and which module it was in
config wave -signalnamewidth 1


add wave -divider     "OUT: YM2149 Waveform"

add wave -unsigned -analog -min -0   -max 1023  -height 593  PSG/sound_A

do run_dac.do

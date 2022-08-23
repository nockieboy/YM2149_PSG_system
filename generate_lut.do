transcript on
if {[file exists work]} {
	vdel -lib work -all
}
vlib work
vmap work work

vlog -sv -work work {BHG_jt49_exp_tablegen.v}
vsim -t 1ns -L work -voptargs="+acc"  BHG_jt49_exp_tablegen

run -all

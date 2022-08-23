vlog -sv -work work {YM2149_PSG_system_tb.sv}

restart -force
run -all

wave cursor active
wave refresh
wave zoomfull
view signals

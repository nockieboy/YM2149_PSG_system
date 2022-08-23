vlog -sv -work work {YM2149_PSG_system_tb.sv}

restart -force
run -all

wave cursor active
wave refresh
wave zoomrange 0ms 50ms
view signals

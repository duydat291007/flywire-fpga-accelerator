# create_project.tcl - make a normal Vivado GUI project (.xpr) from this repository.
#
# The scripted flow (build.tcl, xsim_run.sh) does not need a project. This is for
# working in the Vivado GUI: Flow Navigator buttons, schematics, waveforms,
# Hardware Manager. Source files are referenced in place (not copied), so edits
# in rtl/ show up in the project and vice versa.
#
# Run from the repository root:
#   vivado -mode batch -source scripts/vivado/create_project.tcl
# or inside the Vivado Tcl console:  cd ~/fly_fpga ; source scripts/vivado/create_project.tcl
#
# Result: build/vivado_gui/fly_fpga.xpr  (open with File > Project > Open...)

set part xc7a35tcpg236-1
set root [file normalize [file join [file dirname [info script]] .. ..]]
set proj_dir [file join $root build vivado_gui]

create_project fly_fpga $proj_dir -part $part -force
set_property target_language Verilog [current_project]

# ---- design sources (same list and order as build.tcl) ----
set rtl {
    rtl/common/fly_cfg_pkg.sv
    rtl/core/systolic_pe.sv rtl/core/systolic_array.sv rtl/core/weight_memory.sv
    rtl/core/mvu_systolic.sv rtl/core/mvu_serial.sv
    rtl/neural/lif_update.sv rtl/neural/lif_pipe.sv rtl/neural/fly_world.sv rtl/neural/fly_core.sv
    rtl/uart/uart_tx.sv rtl/uart/telemetry.sv
    rtl/board/input_conditioner.sv rtl/board/basys3_top.sv
}
set files {}
foreach f $rtl { lappend files [file join $root $f] }
add_files -fileset sources_1 $files
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] *.sv]
# FlyWire weight ROM, loaded by fly_core with $readmemh
add_files -fileset sources_1 [file join $root rtl/common/network_weights.mem]
set_property top basys3_top [get_filesets sources_1]
# default configuration = the measured one (4x4 systolic, banked, 2 weight buffers)
set_property generic {ENGINE_SYSTOLIC=1 ROWS=4 COLS=4 BANKED=1 WBUF=2} [get_filesets sources_1]

# ---- constraints ----
add_files -fileset constrs_1 [file join $root constraints/basys3.xdc]

# ---- simulation: closed-loop FlyWire trace test with assertions ----
set sim {
    tb/sva/mvu_sva.sv tb/sva/mvu_binds.sv tb/sva/fly_sva.sv
    tb/integration/tb_fly_core.sv
}
set sfiles {}
foreach f $sim { lappend sfiles [file join $root $f] }
add_files -fileset sim_1 $sfiles
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_fly_core [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
# absolute paths, because the GUI simulator runs inside build/vivado_gui/...
set trace [file join $root tests/vectors/fly_trace.txt]
set rom   [file join $root rtl/common/network_weights.mem]
set_property generic "TRACE=\"$trace\" ROM_PATH=\"$rom\"" [get_filesets sim_1]
# run to $finish (the 700-step test takes several minutes); log only top-level signals
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {false} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Created [file join $proj_dir fly_fpga.xpr]"
puts "Open it with File > Project > Open, then use Run Simulation / Run Synthesis / Generate Bitstream."
close_project

# build.tcl - non-project Vivado flow: synthesis, implementation, reports,
# and (for the board top) a bitstream.
#
# Usage, from the repository root:
#   vivado -mode batch -nojournal -nolog -source scripts/vivado/build.tcl -tclargs <config> [top|mvu]
#
#   top  (default): full basys3_top with constraints/basys3.xdc, bitstream written
#   mvu           : the matrix-vector unit alone, out of context, 100 MHz clock,
#                   for a like-for-like comparison of accelerator configurations
#
# Configs: serial | sys2x2_simple | sys2x2_banked | sys4x4_simple | sys4x4_banked
#          | sys4x4_banked_wbuf2 | sys4x4_banked_wbuf3 | sys8x8_banked_wbuf2
#
# Output: build/vivado/<target>_<config>/ (reports, checkpoint, bitstream) and a
# one-line summary appended to reports/impl/results.csv by collect_impl.py.

set part xc7a35tcpg236-1
set cfg  [lindex $argv 0]
set tgt  [expr {[llength $argv] > 1 ? [lindex $argv 1] : "top"}]

array set cfgs {
    serial               {ENGINE_SYSTOLIC 0 ROWS 4 COLS 4 BANKED 1 WBUF 2}
    sys2x2_simple        {ENGINE_SYSTOLIC 1 ROWS 2 COLS 2 BANKED 0 WBUF 1}
    sys2x2_banked        {ENGINE_SYSTOLIC 1 ROWS 2 COLS 2 BANKED 1 WBUF 2}
    sys4x4_simple        {ENGINE_SYSTOLIC 1 ROWS 4 COLS 4 BANKED 0 WBUF 1}
    sys4x4_banked        {ENGINE_SYSTOLIC 1 ROWS 4 COLS 4 BANKED 1 WBUF 1}
    sys4x4_banked_wbuf2  {ENGINE_SYSTOLIC 1 ROWS 4 COLS 4 BANKED 1 WBUF 2}
    sys4x4_banked_wbuf3  {ENGINE_SYSTOLIC 1 ROWS 4 COLS 4 BANKED 1 WBUF 3}
    sys8x8_banked_wbuf2  {ENGINE_SYSTOLIC 1 ROWS 8 COLS 8 BANKED 1 WBUF 2}
}
if {![info exists cfgs($cfg)]} {
    puts "ERROR: unknown config '$cfg'. Choose one of: [lsort [array names cfgs]]"
    exit 1
}
array set P $cfgs($cfg)

set root [file normalize [file join [file dirname [info script]] .. ..]]
set out  [file join $root build vivado ${tgt}_${cfg}]
file mkdir $out
cd $root

set mvu_src {rtl/core/systolic_pe.sv rtl/core/systolic_array.sv rtl/core/weight_memory.sv
             rtl/core/mvu_systolic.sv rtl/core/mvu_serial.sv}
set all_src [concat {rtl/common/fly_cfg_pkg.sv} $mvu_src {
    rtl/neural/lif_update.sv rtl/neural/lif_pipe.sv rtl/neural/fly_world.sv rtl/neural/fly_core.sv
    rtl/uart/uart_tx.sv rtl/uart/telemetry.sv
    rtl/board/input_conditioner.sv rtl/board/basys3_top.sv}]

if {$tgt eq "top"} {
    read_verilog -sv $all_src
    read_mem rtl/common/network_weights.mem
    read_xdc constraints/basys3.xdc
    synth_design -top basys3_top -part $part \
        -generic ENGINE_SYSTOLIC=$P(ENGINE_SYSTOLIC) -generic ROWS=$P(ROWS) -generic COLS=$P(COLS) \
        -generic BANKED=$P(BANKED) -generic WBUF=$P(WBUF)
} else {
    read_verilog -sv $mvu_src
    if {$P(ENGINE_SYSTOLIC)} {
        synth_design -top mvu_systolic -part $part -mode out_of_context \
            -generic N_MAX=64 -generic ROWS=$P(ROWS) -generic COLS=$P(COLS) \
            -generic BANKED=$P(BANKED) -generic WBUF=$P(WBUF)
    } else {
        synth_design -top mvu_serial -part $part -mode out_of_context -generic N_MAX=64
    }
    # Out of context: only the clock is constrained. Port timing depends on the
    # surrounding design, so reg-to-reg paths are the meaningful comparison;
    # unconstrained port paths are listed in timing_summary.rpt.
    create_clock -name clk -period 10.000 [get_ports clk]
}

report_utilization    -file $out/post_synth_utilization.rpt
opt_design
place_design
phys_opt_design
route_design

report_utilization      -file $out/utilization.rpt
report_utilization      -hierarchical -file $out/utilization_hier.rpt
report_timing_summary   -max_paths 10 -report_unconstrained -file $out/timing_summary.rpt
report_timing           -max_paths 5 -sort_by group -file $out/critical_paths.rpt
report_clock_utilization -file $out/clock_utilization.rpt
check_timing            -verbose -file $out/check_timing.rpt
report_methodology      -file $out/methodology.rpt
report_drc              -file $out/drc.rpt
report_power            -file $out/power_ESTIMATE.rpt
report_design_analysis -logic_level_distribution -file $out/logic_levels.rpt
write_checkpoint -force $out/routed.dcp

# Failing setup endpoints grouped by module (register name without its index),
# so a timing failure points straight at the responsible logic.
set fails [get_timing_paths -setup -max_paths 100000 -nworst 1 -unique_pins -slack_lesser_than 0]
set counts [dict create]
foreach p $fails {
    set cell [get_cells -of_objects [get_property ENDPOINT_PIN $p]]
    regsub -all {\[[0-9]+\]} $cell {[*]} key
    regsub {_reg.*$} $key {_reg} key
    dict incr counts $key
}
set fh [open $out/failing_endpoints.txt w]
puts $fh "failing setup endpoints: [llength $fails]"
foreach {k v} [lsort -stride 2 -index 1 -integer -decreasing $counts] { puts $fh [format "%6d  %s" $v $k] }
close $fh

# Machine-readable summary for collect_impl.py
set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
set fh [open $out/summary.txt w]
puts $fh "config=$cfg"
puts $fh "target=$tgt"
puts $fh "vivado=[version -short]"
puts $fh "part=$part"
puts $fh "wns_ns=$wns"
puts $fh "whs_ns=$whs"
foreach {name pat} {lut "Slice LUTs" ff "Slice Registers" dsp "DSPs" bram "Block RAM Tile" lutram "LUT as Memory"} {
    set v ""
    set fr [open $out/utilization.rpt r]
    while {[gets $fr line] >= 0} {
        if {[string match "*| $pat *" $line]} {
            set f [split $line "|"]
            set v [string trim [lindex $f 2]]
            break
        }
    }
    close $fr
    puts $fh "$name=$v"
}
close $fh

if {$tgt eq "top"} {
    write_bitstream -force $out/basys3_top.bit
    # Flash image for power-on boot from the 32 Mbit Quad-SPI flash
    write_cfgmem -force -format bin -interface SPIx4 -size 4 \
        -loadbit [list up 0x0 $out/basys3_top.bit] -file $out/basys3_top.bin
    puts "Bitstream: $out/basys3_top.bit"
}
puts "Reports in $out"

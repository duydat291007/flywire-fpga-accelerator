# program_flash.tcl - write a flash image (.bin) into the Basys 3 Quad-SPI
# configuration flash, so the design loads by itself at power-on.
#
# Usage: vivado -mode batch -nojournal -nolog -source scripts/vivado/program_flash.tcl -tclargs <file.bin>
# Afterwards: set jumper JP1 to QSPI and power-cycle the board.
#
# Basys 3 boards have shipped with different 32 Mbit flash chips depending on
# the revision. The script tries the known parts in turn; programming checks
# the chip's ID, so a wrong guess fails cleanly and the next part is tried.

set bin [file normalize [lindex $argv 0]]
if {![file exists $bin]} { puts "ERROR: flash image not found: $bin"; exit 1 }

set candidates {s25fl032p-spi-x1_x2_x4 mx25l3233f-spi-x1_x2_x4 n25q32-3.3v-spi-x1_x2_x4 is25lp032d-spi-x1_x2_x4}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
if {$dev eq ""} { puts "ERROR: no xc7a35t found on the JTAG chain"; exit 1 }
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

set done 0
foreach name $candidates {
    set parts [get_cfgmem_parts -quiet $name]
    if {[llength $parts] == 0} { continue }
    puts "Trying flash part $name ..."
    create_hw_cfgmem -hw_device $dev [lindex $parts 0]
    set mem [get_property PROGRAM.HW_CFGMEM $dev]
    set_property PROGRAM.ADDRESS_RANGE  {use_file}    $mem
    set_property PROGRAM.FILES          [list $bin]   $mem
    set_property PROGRAM.PRM_FILE       {}            $mem
    set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} $mem
    set_property PROGRAM.BLANK_CHECK    0 $mem
    set_property PROGRAM.ERASE          1 $mem
    set_property PROGRAM.CFG_PROGRAM    1 $mem
    set_property PROGRAM.VERIFY         1 $mem
    set_property PROGRAM.CHECKSUM       0 $mem
    # Load Vivado's flash-programming helper design into the FPGA first
    create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
    program_hw_devices $dev
    refresh_hw_device $dev
    if {[catch {program_hw_cfgmem -hw_cfgmem $mem} err]} {
        puts "  $name did not match this board: $err"
        delete_hw_cfgmem $mem
        continue
    }
    puts "Flash programmed and verified ($name) with $bin"
    set done 1
    break
}
close_hw_manager
if {!$done} { puts "ERROR: none of the known flash parts matched: $candidates"; exit 1 }
puts "Now set jumper JP1 to QSPI and power-cycle the board: the design loads by itself."

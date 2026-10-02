# program.tcl - program the Basys 3 over JTAG with a built bitstream.
#
# Usage: vivado -mode batch -nojournal -nolog -source scripts/vivado/program.tcl -tclargs <bitfile>
# The board must be connected over its micro-USB port and powered (switch ON).

set bit [file normalize [lindex $argv 0]]
if {![file exists $bit]} { puts "ERROR: bitstream not found: $bit"; exit 1 }

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
if {$dev eq ""} { puts "ERROR: no xc7a35t found on the JTAG chain"; exit 1 }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "Programmed $dev with $bit (volatile: lost at power-off)"
close_hw_manager

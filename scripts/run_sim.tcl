source [file join [file dirname [info script]] create_project.tcl]
if {[llength $rtl_files] == 0 || [llength $sim_files] == 0} {
    error "Add your own RTL under rtl and a testbench under sim before running simulation."
}
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
puts "SIMULATION_FINISHED"

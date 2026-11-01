# No board is selected. This part only gives Vivado a simulation/project target.
set project_root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file join $project_root build vivado]
set target_part xc7k70tfbv676-1
if {[info exists ::env(FPGA_PART)] && $::env(FPGA_PART) ne ""} {
    set target_part $::env(FPGA_PART)
}
if {[llength [get_parts -quiet $target_part]] == 0} {
    error "Vivado does not have part $target_part installed. Set FPGA_PART to an installed part."
}

proc collect_hdl {directory} {
    set files {}
    foreach path [lsort [glob -nocomplain -directory $directory *]] {
        if {[file isdirectory $path]} {
            set files [concat $files [collect_hdl $path]]
        } elseif {[file extension $path] in {.v .sv .vh .svh}} {
            lappend files $path
        }
    }
    return $files
}

file mkdir $project_dir
create_project mysuperscaler $project_dir -part $target_part -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]
set rtl_files [collect_hdl [file join $project_root rtl]]
set header_files [collect_hdl [file join $project_root vpackage]]
if {[llength $header_files] > 0} {
    add_files -norecurse $header_files
    set_property file_type {Verilog Header} [get_files *.vh]
}
if {[llength $rtl_files] > 0} {
    add_files -norecurse $rtl_files
    set_property top core_cpu [get_filesets sources_1]
}
set_property include_dirs [list [file join $project_root vpackage]] [get_filesets sources_1]
set sim_files [collect_hdl [file join $project_root sim]]
if {[llength $sim_files] > 0} {
    add_files -fileset sim_1 -norecurse $sim_files
    set_property top tb_core_cpu [get_filesets sim_1]
}
set_property include_dirs [list [file join $project_root vpackage]] [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
if {[llength $rtl_files] > 0} {
    update_compile_order -fileset sources_1
}
if {[llength $sim_files] > 0} {
    update_compile_order -fileset sim_1
}
puts "PROJECT_READY [file join $project_dir mysuperscaler.xpr]"
puts "RTL_FILES [llength $rtl_files] SIM_FILES [llength $sim_files]"
puts "HEADER_FILES [llength $header_files]"

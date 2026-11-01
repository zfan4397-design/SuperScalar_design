# Run in the Tcl Console of the existing project:
# source D:/zz/mysuperscaler/scripts/add_ctrl_unit.tcl
set ctrl_scaffold_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
set ctrl_scaffold_temp [file join $ctrl_scaffold_root build tmp]
file mkdir $ctrl_scaffold_temp
set ::env(TEMP) $ctrl_scaffold_temp
set ::env(TMP) $ctrl_scaffold_temp
set ctrl_scaffold_saved_top [get_property top [get_filesets sources_1]]
set ctrl_scaffold_source [file join $ctrl_scaffold_root build vivado mysuperscaler.srcs sources_1 new ctrl_unit.v]
if {[llength [get_files -quiet $ctrl_scaffold_source]] == 0} {
    add_files -fileset sources_1 -norecurse $ctrl_scaffold_source
}
set_property file_type Verilog [get_files $ctrl_scaffold_source]
foreach ctrl_scaffold_fileset {sources_1 sim_1} {
    set ctrl_scaffold_include_dirs [get_property include_dirs [get_filesets $ctrl_scaffold_fileset]]
    set ctrl_scaffold_header_dir [file join $ctrl_scaffold_root vpackage]
    if {[lsearch -exact $ctrl_scaffold_include_dirs $ctrl_scaffold_header_dir] < 0} {
        lappend ctrl_scaffold_include_dirs $ctrl_scaffold_header_dir
        set_property include_dirs $ctrl_scaffold_include_dirs [get_filesets $ctrl_scaffold_fileset]
    }
}
if {$ctrl_scaffold_saved_top ne ""} {
    set_property top $ctrl_scaffold_saved_top [get_filesets sources_1]
}
puts "CTRL_UNIT_SOURCE_REGISTERED $ctrl_scaffold_source"
if {[catch {update_compile_order -fileset sources_1} ctrl_scaffold_error ctrl_scaffold_options]} {
    puts stderr "CTRL_UNIT_REFRESH_FAILED: Source registered; hierarchy refresh failed."
    return -options $ctrl_scaffold_options $ctrl_scaffold_error
}
puts "CTRL_UNIT_HIERARCHY_REFRESH_PASS"

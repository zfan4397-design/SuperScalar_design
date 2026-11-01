# Run in the Tcl Console of the existing project:
# source D:/zz/mysuperscaler/scripts/add_retire_ctrl.tcl
set retire_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
set retire_temp [file join $retire_root build tmp]
file mkdir $retire_temp
set ::env(TEMP) $retire_temp
set ::env(TMP) $retire_temp
set retire_saved_top [get_property top [get_filesets sources_1]]
set retire_source [file join $retire_root build vivado mysuperscaler.srcs sources_1 new retire_ctrl.v]
if {[llength [get_files -quiet $retire_source]] == 0} {
    add_files -fileset sources_1 -norecurse $retire_source
}
set_property file_type Verilog [get_files $retire_source]
foreach retire_fileset {sources_1 sim_1} {
    set retire_include_dirs [get_property include_dirs [get_filesets $retire_fileset]]
    set retire_header_dir [file join $retire_root vpackage]
    if {[lsearch -exact $retire_include_dirs $retire_header_dir] < 0} {
        lappend retire_include_dirs $retire_header_dir
        set_property include_dirs $retire_include_dirs [get_filesets $retire_fileset]
    }
}
if {$retire_saved_top ne ""} {
    set_property top $retire_saved_top [get_filesets sources_1]
}
puts "RETIRE_CTRL_SOURCE_REGISTERED $retire_source"
if {[catch {update_compile_order -fileset sources_1} retire_error retire_options]} {
    puts stderr "RETIRE_CTRL_REFRESH_FAILED: Source is registered; hierarchy refresh failed."
    return -options $retire_options $retire_error
}
puts "RETIRE_CTRL_HIERARCHY_REFRESH_PASS"

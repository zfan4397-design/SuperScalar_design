# Run in the Tcl Console of the existing project.
set clint_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
set clint_temp [file join $clint_root build tmp]
file mkdir $clint_temp
set ::env(TEMP) $clint_temp
set ::env(TMP) $clint_temp
set clint_saved_top [get_property top [get_filesets sources_1]]
set clint_source [file join $clint_root build vivado mysuperscaler.srcs sources_1 new clint.v]
if {[llength [get_files -quiet $clint_source]] == 0} {
    add_files -fileset sources_1 -norecurse $clint_source
}
set_property file_type Verilog [get_files $clint_source]
foreach clint_fileset {sources_1 sim_1} {
    set clint_include_dirs [get_property include_dirs [get_filesets $clint_fileset]]
    set clint_header_dir [file join $clint_root vpackage]
    if {[lsearch -exact $clint_include_dirs $clint_header_dir] < 0} {
        lappend clint_include_dirs $clint_header_dir
        set_property include_dirs $clint_include_dirs [get_filesets $clint_fileset]
    }
}
if {$clint_saved_top ne ""} {
    set_property top $clint_saved_top [get_filesets sources_1]
}
puts "CLINT_SOURCE_REGISTERED $clint_source"
if {[catch {update_compile_order -fileset sources_1} clint_error clint_options]} {
    puts stderr "CLINT_REFRESH_FAILED: Source registered; hierarchy refresh failed."
    return -options $clint_options $clint_error
}
puts "CLINT_HIERARCHY_REFRESH_PASS"

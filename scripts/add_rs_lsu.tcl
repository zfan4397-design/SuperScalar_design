# Run in the Tcl Console of the existing Vivado project:
# source D:/zz/mysuperscaler/scripts/add_rs_lsu.tcl
set lsu_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
# Apply only to this Vivado process and child tools; leave Windows settings intact.
# Match scripts/run.ps1: keep temporary child-process paths inside the ASCII workspace.
set lsu_temp [file join $lsu_root build tmp]
file mkdir $lsu_temp
set ::env(TEMP) $lsu_temp
set ::env(TMP) $lsu_temp
set lsu_saved_top [get_property top [get_filesets sources_1]]
set lsu_main [file join $lsu_root rtl utils rs_lsu_queue.v]
set lsu_gui [file join $lsu_root build vivado mysuperscaler.srcs sources_1 new rs_lsu_queue.v]
if {[file exists $lsu_gui]} {
    set lsu_main $lsu_gui
    set lsu_old_source [get_files -quiet [file join $lsu_root rtl utils rs_lsu_queue.v]]
    if {[llength $lsu_old_source] > 0} { remove_files $lsu_old_source }
}
set lsu_source_handle [open $lsu_main r]
set lsu_main_text [read $lsu_source_handle]
close $lsu_source_handle
set lsu_sources [list $lsu_main [file join $lsu_root vpackage fifoid_functions.vh]]
set lsu_arbiter [file join $lsu_root rtl utils age_matrix_arbiter.v]
if {[regexp -line {^\s*module\s+age_matrix_arbiter\M} $lsu_main_text]} {
    set lsu_old_arbiter [get_files -quiet $lsu_arbiter]
    if {[llength $lsu_old_arbiter] > 0} { remove_files $lsu_old_arbiter }
} else {
    lappend lsu_sources $lsu_arbiter
}
foreach lsu_file $lsu_sources {
    if {[llength [get_files -quiet $lsu_file]] == 0} {
        add_files -norecurse $lsu_file
    }
}
set_property file_type {Verilog Header} [get_files [file join $lsu_root vpackage fifoid_functions.vh]]
foreach lsu_fileset {sources_1 sim_1} {
    set lsu_include_dirs [get_property include_dirs [get_filesets $lsu_fileset]]
    set lsu_header_dir [file join $lsu_root vpackage]
    if {[lsearch -exact $lsu_include_dirs $lsu_header_dir] < 0} {
        lappend lsu_include_dirs $lsu_header_dir
        set_property include_dirs $lsu_include_dirs [get_filesets $lsu_fileset]
    }
}
if {$lsu_saved_top ne ""} {
    set_property top $lsu_saved_top [get_filesets sources_1]
}
puts "LSU_SOURCES_REGISTERED $lsu_main"
puts "LSU_TEMP_DIRECTORY $lsu_temp"
if {[catch {update_compile_order -fileset sources_1} lsu_refresh_error lsu_refresh_options]} {
    puts stderr "LSU_REFRESH_FAILED: Sources are already registered; hierarchy refresh failed."
    puts stderr "Original Vivado error: $lsu_refresh_error"
    return -options $lsu_refresh_options $lsu_refresh_error
}
puts "LSU_HIERARCHY_REFRESH_PASS"

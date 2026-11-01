# Run in the Tcl Console of the existing project:
# source D:/zz/mysuperscaler/scripts/add_rs_mul.tcl
set mul_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
set mul_temp [file join $mul_root build tmp]
file mkdir $mul_temp
set ::env(TEMP) $mul_temp
set ::env(TMP) $mul_temp
set mul_saved_top [get_property top [get_filesets sources_1]]
foreach mul_file [list \
    [file join $mul_root rtl utils rs_mul_queue.v] \
    [file join $mul_root rtl utils age_matrix_arbiter.v] \
    [file join $mul_root vpackage fifoid_functions.vh]] {
    if {[llength [get_files -quiet $mul_file]] == 0} {
        add_files -fileset sources_1 -norecurse $mul_file
    }
}
set_property file_type {Verilog Header} [get_files [file join $mul_root vpackage fifoid_functions.vh]]
foreach mul_fileset {sources_1 sim_1} {
    set mul_include_dirs [get_property include_dirs [get_filesets $mul_fileset]]
    set mul_header_dir [file join $mul_root vpackage]
    if {[lsearch -exact $mul_include_dirs $mul_header_dir] < 0} {
        lappend mul_include_dirs $mul_header_dir
        set_property include_dirs $mul_include_dirs [get_filesets $mul_fileset]
    }
}
if {$mul_saved_top ne ""} {
    set_property top $mul_saved_top [get_filesets sources_1]
}
puts "MUL_SOURCES_REGISTERED [file join $mul_root rtl utils rs_mul_queue.v]"
if {[catch {update_compile_order -fileset sources_1} mul_error mul_options]} {
    puts stderr "MUL_REFRESH_FAILED: Files are registered; hierarchy refresh failed."
    return -options $mul_options $mul_error
}
puts "MUL_HIERARCHY_REFRESH_PASS"

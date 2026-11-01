# Run in the Tcl Console of the existing project:
# source D:/zz/mysuperscaler/scripts/add_storage_modules.tcl
set storage_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
set storage_temp [file join $storage_root build tmp]
file mkdir $storage_temp
set ::env(TEMP) $storage_temp
set ::env(TMP) $storage_temp
set storage_saved_top [get_property top [get_filesets sources_1]]
foreach storage_name {store_buffer arf} {
    set storage_source [file join $storage_root build vivado mysuperscaler.srcs sources_1 new ${storage_name}.v]
    if {[llength [get_files -quiet $storage_source]] == 0} {
        add_files -fileset sources_1 -norecurse $storage_source
    }
    set_property file_type Verilog [get_files $storage_source]
    puts "STORAGE_SOURCE_REGISTERED $storage_source"
}
foreach storage_fileset {sources_1 sim_1} {
    set storage_include_dirs [get_property include_dirs [get_filesets $storage_fileset]]
    set storage_header_dir [file join $storage_root vpackage]
    if {[lsearch -exact $storage_include_dirs $storage_header_dir] < 0} {
        lappend storage_include_dirs $storage_header_dir
        set_property include_dirs $storage_include_dirs [get_filesets $storage_fileset]
    }
}
if {$storage_saved_top ne ""} {
    set_property top $storage_saved_top [get_filesets sources_1]
}
if {[catch {update_compile_order -fileset sources_1} storage_error storage_options]} {
    puts stderr "STORAGE_REFRESH_FAILED: Sources registered; hierarchy refresh failed."
    return -options $storage_options $storage_error
}
puts "STORAGE_HIERARCHY_REFRESH_PASS"

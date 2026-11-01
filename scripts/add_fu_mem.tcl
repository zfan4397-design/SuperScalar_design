# Run in the Tcl Console of the existing project:
# source D:/zz/mysuperscaler/scripts/add_fu_mem.tcl
set fumem_root [file normalize [file join [file dirname [info script]] ..]]
if {[current_project -quiet] eq ""} {
    error "Open the existing mysuperscaler project before sourcing this script."
}
set fumem_temp [file join $fumem_root build tmp]
file mkdir $fumem_temp
set ::env(TEMP) $fumem_temp
set ::env(TMP) $fumem_temp
set fumem_saved_top [get_property top [get_filesets sources_1]]
foreach fumem_name {fu_mem dff_fu store_buffer} {
    set fumem_source [file join $fumem_root build vivado mysuperscaler.srcs sources_1 new ${fumem_name}.v]
    if {[llength [get_files -quiet $fumem_source]] == 0} {
        add_files -fileset sources_1 -norecurse $fumem_source
    }
    set_property file_type Verilog [get_files $fumem_source]
    puts "FU_MEM_SOURCE_REGISTERED $fumem_source"
}
foreach fumem_fileset {sources_1 sim_1} {
    set fumem_include_dirs [get_property include_dirs [get_filesets $fumem_fileset]]
    set fumem_header_dir [file join $fumem_root vpackage]
    if {[lsearch -exact $fumem_include_dirs $fumem_header_dir] < 0} {
        lappend fumem_include_dirs $fumem_header_dir
        set_property include_dirs $fumem_include_dirs [get_filesets $fumem_fileset]
    }
}
if {$fumem_saved_top ne ""} {
    set_property top $fumem_saved_top [get_filesets sources_1]
}
if {[catch {update_compile_order -fileset sources_1} fumem_error fumem_options]} {
    puts stderr "FU_MEM_REFRESH_FAILED: Sources registered; hierarchy refresh failed."
    return -options $fumem_options $fumem_error
}
puts "FU_MEM_HIERARCHY_REFRESH_PASS"

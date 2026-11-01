source [file join [file dirname [info script]] create_project.tcl]
if {[llength $rtl_files] == 0} {
    error "Add your own RTL under rtl before running synthesis."
}
synth_design -top core_cpu -part $target_part -mode out_of_context
report_utilization -file [file join $project_root build utilization.rpt]
report_timing_summary -file [file join $project_root build timing_summary.rpt]
write_checkpoint -force [file join $project_root build core_cpu.dcp]
puts "SYNTHESIS_FINISHED"

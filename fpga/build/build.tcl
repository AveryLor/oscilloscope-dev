# Gowin EDA build script for Tang Nano 20K (GW2AR-18C)
# Run via: make build   (or: gw_sh build/build.tcl from fpga/)

set prj_name        "nano_tango"
set top_name        "top"
set device          "GW2AR-LV18QN88C8/I7"
set device_version  "C"

set script_dir   [file dirname [file normalize [info script]]]
set project_root [file dirname $script_dir]
set prj_dir      [file join $project_root gowin_project]

create_project -name $prj_name -dir $prj_dir -pn $device -device_version $device_version -force

add_file [file join $project_root rtl adc_pll.v]
add_file [file join $project_root rtl top.sv]
add_file [file join $project_root constr pins.cst]
add_file [file join $project_root constr timing.sdc]
set_option -top_module $top_name
set_option -verilog_std sysv2017

run all
run close

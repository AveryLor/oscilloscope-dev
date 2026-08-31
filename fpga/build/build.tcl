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

# scope_regs.svh is `include`d by scope_pkg.sv; add the rtl dirs to the search path.
set_option -include_path [list \
    [file join $project_root rtl] \
    [file join $project_root rtl cdc] \
    [file join $project_root rtl common]]

# Package first, then the CDC and common libraries, then the datapath, then top.
add_file [file join $project_root rtl scope_pkg.sv]

add_file [file join $project_root rtl cdc cdc_bit_sync.sv]
add_file [file join $project_root rtl cdc cdc_pulse_toggle.sv]
add_file [file join $project_root rtl cdc cdc_gray_sync.sv]
add_file [file join $project_root rtl cdc async_fifo.sv]
add_file [file join $project_root rtl cdc config_cdc.sv]
add_file [file join $project_root rtl cdc status_cdc.sv]

add_file [file join $project_root rtl common por_gen.sv]
add_file [file join $project_root rtl common reset_sync.sv]
add_file [file join $project_root rtl common debounce.sv]

add_file [file join $project_root rtl adc_pll.v]
add_file [file join $project_root rtl adc_input_cond.sv]
add_file [file join $project_root rtl timebase_decimator.sv]
add_file [file join $project_root rtl trigger_engine.sv]
add_file [file join $project_root rtl capture_buffer.sv]
add_file [file join $project_root rtl acq_ctrl_fsm.sv]
add_file [file join $project_root rtl quad_decoder.sv]
add_file [file join $project_root rtl settings_arbiter.sv]
add_file [file join $project_root rtl probe_comp_gen.sv]
add_file [file join $project_root rtl irq_gen.sv]
add_file [file join $project_root rtl record_readout_bridge.sv]
add_file [file join $project_root rtl spi_slave.sv]
add_file [file join $project_root rtl spi_protocol.sv]
add_file [file join $project_root rtl top.sv]

add_file [file join $project_root constr pins.cst]
add_file [file join $project_root constr timing.sdc]

set_option -top_module $top_name
set_option -verilog_std sysv2017

run all
run close

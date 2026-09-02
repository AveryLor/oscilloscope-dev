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

# scope_regs.svh is `include`d by scope_pkg.sv; add the rtl dirs to the search
# path. rtl/video also holds font8x16.mem for the text-overlay $readmemh.
set_option -include_path [list \
    [file join $project_root rtl] \
    [file join $project_root rtl cdc] \
    [file join $project_root rtl common] \
    [file join $project_root rtl video]]

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
add_file [file join $project_root rtl spi_slave.sv]
add_file [file join $project_root rtl spi_protocol.sv]

# HDMI 720p display subsystem. video_pkg first (imported by the rest).
add_file [file join $project_root rtl video video_pkg.sv]
add_file [file join $project_root rtl video video_clkgen.v]
add_file [file join $project_root rtl video video_timing_gen.sv]
add_file [file join $project_root rtl video pixel_delay.sv]
add_file [file join $project_root rtl video graticule_gen.sv]
add_file [file join $project_root rtl video waveform_col_ram.sv]
add_file [file join $project_root rtl video column_reducer.sv]
add_file [file join $project_root rtl video compositor.sv]
add_file [file join $project_root rtl video video_top.sv]

# Gowin DVI_TX IP: generate once in Gowin EDA (Tools -> IP Core Generator ->
# Multimedia -> DVI_TX, 1280x720@60, 24-bit RGB in, external pixel + 5x serial
# clock, RGB interface). Output to rtl/video/gowin_dvi_tx/, then uncomment the
# line below with whatever wrapper file the wizard emits. See docs/DISPLAY.md.
# add_file [file join $project_root rtl video gowin_dvi_tx dvi_tx.v]

add_file [file join $project_root rtl top.sv]

add_file [file join $project_root constr pins.cst]
add_file [file join $project_root constr timing.sdc]

set_option -top_module $top_name
set_option -verilog_std sysv2017

run all
run close

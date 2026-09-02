# FPGA_CLK: PL133 fanout of the 105 MHz ADC encode clock (AD9215-105)
create_clock -name fpga_clk -period 9.524 [get_ports {fpga_clk}]

# Onboard 27 MHz crystal: housekeeping domain (encoders, probe comp, IRQ, resets).
create_clock -name clk27 -period 37.037 [get_ports {clk}]

# ESP32 VSPI master drives this; adc_sample_clk is derived from fpga_clk by the
# rPLL. Keep this period in sync with the ESP32 SPI config in esp32/main/.
create_clock -name spi_sclk -period 25.000 [get_ports {spi_sclk}]

# HDMI pixel-clock chain (fpga/rtl/video/video_clkgen.v): the 27 MHz crystal ->
# rPLL x55 / 4 -> 371.25 MHz TMDS serial clock (CLKOUT), then CLKDIV /5 ->
# 74.25 MHz pixel clock. Gowin usually auto-derives PLL/CLKDIV outputs; these are
# explicit so the video domain is always constrained and named.
create_generated_clock -name serial_clk -source [get_ports {clk}] \
    -multiply_by 55 -divide_by 4 \
    [get_pins {u_video/u_clkgen/rpll_inst/CLKOUT}]
create_generated_clock -name pix_clk -source [get_pins {u_video/u_clkgen/rpll_inst/CLKOUT}] \
    -divide_by 5 \
    [get_pins {u_video/u_clkgen/clkdiv_inst/CLKOUT}]

# Four unrelated domains: capture (fpga_clk / rPLL), housekeeping (clk27), SPI,
# and the video pixel/serial chain. adc_sample_clk is a generated clock off
# fpga_clk; Gowin derives it from the rPLL primitive, so it travels with the
# fpga_clk group.
set_clock_groups -asynchronous \
    -group {fpga_clk} \
    -group {clk27} \
    -group {spi_sclk} \
    -group {serial_clk pix_clk}

# hw_trigger is an asynchronous input from J4; top.sv carries it through a
# two-stage synchronizer (hw_trigger_q -> hw_trigger_sync).
set_false_path -from [get_ports {hw_trigger}]

# Slow / static async I/O: the encoder inputs, the probe-comp output, the
# capture-ready IRQ output, and the spare mezzanine lines are all handled by
# synchronizers or are DC, so they carry no timing requirement.
set_false_path -from [get_ports {dial_hs_a dial_hs_b dial_hs_btn}]
set_false_path -from [get_ports {dial_ho_a dial_ho_b dial_ho_btn}]
set_false_path -from [get_ports {dial_tg_a dial_tg_b dial_tg_btn}]
set_false_path -from [get_ports {fpga_flex[*]}]
set_false_path -to   [get_ports {probe_comp fpga_irq}]

# TODO(before trusting any capture): fill in the two numbers below and
# uncomment. Without these the ADC bus has no analysed path at all and the
# timing report is clean regardless of whether capture actually works.
#
#   max = AD9215 t_PD(max) + ADC->FPGA trace delay
#   min = AD9215 t_PD(min) + ADC->FPGA trace delay
#
# t_PD from the AD9215 datasheet, trace delay from the Altium layout. These
# also set where the PSDA_SEL sample phase in fpga/rtl/adc_pll.v should sit:
# the eye opens at max and closes at 9.524 + min, so aim for the midpoint.
#
# set_input_delay -clock fpga_clk -max <max> [get_ports {adc_d[*] adc_or}]
# set_input_delay -clock fpga_clk -min <min> [get_ports {adc_d[*] adc_or}]

# TODO(before trusting SPI): once the ESP32 VSPI launch/capture timing and the
# J6 ribbon skew are measured, constrain the SPI I/O. spi_sclk is already cut
# from the other domains above, so leave these commented until the numbers exist.
#
# set_input_delay  -clock spi_sclk -max <t> [get_ports {spi_mosi}]
# set_input_delay  -clock spi_sclk -min <t> [get_ports {spi_mosi}]
# set_output_delay -clock spi_sclk -max <t> [get_ports {spi_miso}]
# set_output_delay -clock spi_sclk -min <t> [get_ports {spi_miso}]

# FPGA_CLK: PL133 fanout of the 105 MHz ADC encode clock (AD9215-105)
create_clock -name fpga_clk -period 9.524 [get_ports {fpga_clk}]

# ESP32 VSPI master drives this; adc_sample_clk is derived from fpga_clk by the
# rPLL. Keep this period in sync with the ESP32 SPI config in esp32/main/.
create_clock -name spi_sclk -period 25.000 [get_ports {spi_sclk}]

# Unrelated domains — do not analyse paths between them.
set_clock_groups -asynchronous -group {fpga_clk} -group {spi_sclk}

# hw_trigger is an asynchronous input from J4; top.sv carries it through a
# two-stage synchronizer (hw_trigger_q -> hw_trigger_sync).
set_false_path -from [get_ports {hw_trigger}]

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

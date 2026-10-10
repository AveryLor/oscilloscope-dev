# FPGA_CLK: PL133 fanout of the 100 MHz ADC encode clock (AD9215-105 run at 100 MSPS)
create_clock -name fpga_clk -period 10.000 [get_ports {fpga_clk}]

# Onboard 27 MHz crystal: housekeeping domain (encoders, probe comp, IRQ, resets).
create_clock -name clk27 -period 37.037 [get_ports {clk}]

# ESP32 VSPI master drives this; adc_sample_clk is derived from fpga_clk by the
# rPLL. Keep this period in sync with the ESP32 SPI config in esp32/main/.
create_clock -name spi_sclk -period 25.000 [get_ports {spi_sclk}]

# Three unrelated domains: capture (fpga_clk / rPLL), housekeeping (clk27) and
# SPI. adc_sample_clk is a generated clock off fpga_clk; Gowin derives it from
# the rPLL primitive, so it travels with the fpga_clk group.
# Single line: Gowin's SDC parser rejects backslash line continuations.
set_clock_groups -asynchronous -group {fpga_clk} -group {clk27} -group {spi_sclk}

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

# ADC bus input delay, relative to fpga_clk at the FPGA pin.
#   AD9215BCP-105 datasheet Table 4: tOD = 2.5 ns min / 6.5 ns max after CLK.
#   max = 6.5 + 0.5 ns allowance for ADC->FPGA trace delay
#   min = 2.5 + 0 ns trace (the shortest the trace can possibly make it)
# TODO: replace the 0.5 ns trace allowance with the real number from Altium.
# PSDA_SEL in fpga/rtl/adc_pll.v is chosen from these numbers; see the
# derivation there.
set_input_delay -clock fpga_clk -max 7.0 [get_ports {adc_d[*] adc_or}]
set_input_delay -clock fpga_clk -min 2.5 [get_ports {adc_d[*] adc_or}]

# TODO(before trusting SPI): once the ESP32 VSPI launch/capture timing and the
# J6 ribbon skew are measured, constrain the SPI I/O. spi_sclk is already cut
# from the other domains above, so leave these commented until the numbers exist.
#
# set_input_delay  -clock spi_sclk -max <t> [get_ports {spi_mosi}]
# set_input_delay  -clock spi_sclk -min <t> [get_ports {spi_mosi}]
# set_output_delay -clock spi_sclk -max <t> [get_ports {spi_miso}]
# set_output_delay -clock spi_sclk -min <t> [get_ports {spi_miso}]

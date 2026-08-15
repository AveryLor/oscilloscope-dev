# FPGA_CLK: PL133 fanout of the 100 MHz ADC encode clock (AD9215-105)
create_clock -name fpga_clk -period 9.524 [get_ports {fpga_clk}]

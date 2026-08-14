# ADC encode clock: AD9215-105 (105 MHz)
create_clock -name adc_enc_clk -period 9.524 [get_ports {adc_enc_clk}]

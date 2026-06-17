#===========================================================
# lunahan_ultrasound_ASIC — Timing Constraints (SDC)
#===========================================================
# Target: 50 MHz system clock, sky130 typical corner

# System clock: 16 MHz input → PLL → 50 MHz internal
create_clock -name clk_16mhz -period 62.5 [get_ports clk_16mhz_i]

# Generated clock (after PLL)
create_generated_clock -name clk_sys -source [get_ports clk_16mhz_i] \
    -divide_by 8 -multiply_by 25 [get_pins u_pll/clk_out]

# ADC clock: 1.2 MHz
create_generated_clock -name clk_adc -source [get_ports clk_16mhz_i] \
    -divide_by 41 [get_pins u_rx_ctrl/adc_clk]

# Clock uncertainty
set_clock_uncertainty -setup 0.1 [get_clocks clk_sys]
set_clock_uncertainty -hold  0.05 [get_clocks clk_sys]

# Clock transition
set_clock_transition -max 0.2 [get_clocks clk_sys]
set_clock_transition -min 0.05 [get_clocks clk_sys]

# Input delays (external interfaces)
set_input_delay -clock clk_sys -max 2.0 [get_ports uart_rx_i]
set_input_delay -clock clk_sys -min 1.0 [get_ports uart_rx_i]
set_input_delay -clock clk_sys -max 3.0 [get_ports adc_data_i*]
set_input_delay -clock clk_sys -min 1.5 [get_ports adc_data_i*]

# Output delays
set_output_delay -clock clk_sys -max 3.0 [get_ports uart_tx_o]
set_output_delay -clock clk_sys -min 1.5 [get_ports uart_tx_o]
set_output_delay -clock clk_sys -max 2.0 [get_ports tx_pulse_o*]
set_output_delay -clock clk_sys -min 1.0 [get_ports tx_pulse_o*]

# False paths (asynchronous)
set_false_path -from [get_ports rst_n_i]
set_false_path -to [get_ports gpio_io*]

# Max fanout
set_max_fanout 20 [current_design]

# Max capacitance
set_max_capacitance 0.1 [current_design]

# Max transition
set_max_transition 0.5 [current_design]

# Operating conditions (TT corner, 25°C, 1.8V)
set_operating_conditions -library sky130_fd_sc_hd__tt_025C_1v80

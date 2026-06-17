#===========================================================
# lunahan_ultrasound_ASIC — OpenROAD Physical Design Flow
#===========================================================
# Target: sky130 (SkyWater 130 nm)
# Flow: Synthesis (Yosys) → Floorplan → Place → CTS → Route → GDS
#===========================================================

# --- Load PDK configuration ---
source $env(PDK_ROOT)/sky130A/libs.tech/openroad/common/init.tcl

# --- Read design ---
read_lef $env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/techlef/sky130_fd_sc_hd.tlef
read_lef $env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lef/sky130_fd_sc_hd.lef

# Read synthesized Verilog (from Yosys)
read_verilog ../digital/lunahan_core/ultrasound_top.sv
read_verilog ../digital/tx_controller/tx_controller.sv
read_verilog ../digital/rx_controller/rx_controller.sv

# Read liberty files
read_liberty $env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
read_liberty $env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ss_100C_1v60.lib
read_liberty $env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__ff_n40C_1v95.lib

# Link design
link_design ultrasound_asic_top

# --- Read SDC constraints ---
read_sdc ../phys/constraints.sdc

#===========================================================
# Floorplan
#===========================================================
# Die area: ~4mm × 4mm = 16 mm² (with margin for analog + pads)
initialize_floorplan \
    -die_area  {0 0 4000 4000} \
    -core_area {200 200 3800 3800} \
    -site       unithddbl

# Place macros (SRAM, analog block keep-out regions)
# SRAM: 0.15 mm² area
# Analog blocks are placed separately (not in this digital flow)

# Place I/O pads
place_pins -hor_layers {met2 met4} -ver_layers {met3 met5}

#===========================================================
# Power Grid
#===========================================================
# VDD_DIG = 1.8V core power
# VSS = ground

# Define power domains
set_voltage_domain -name CORE -power VDD_DIG -ground VSS

# Create power grid
# Vertical stripes on met4, horizontal on met5
add_global_connection -net VDD_DIG -pin_pattern {^VDD$} -power
add_global_connection -net VSS -pin_pattern {^VSS$} -ground

# Power ring
pdngen::specify_grid -grid metal5_metal4_grid

#===========================================================
# Placement
#===========================================================

# Global placement
global_placement -density 0.65

# Detailed placement
detailed_placement

# Check placement legality
check_placement

#===========================================================
# Clock Tree Synthesis (CTS)
#===========================================================

# Define clock
create_clock -name clk_sys -period 20.0 [get_ports clk_16mhz_i]
set_clock_uncertainty 0.1 [get_clocks clk_sys]
set_clock_transition 0.2 [get_clocks clk_sys]

# Build clock tree
clock_tree_synthesis \
    -root_buf sky130_fd_sc_hd__clkbuf_16 \
    -buf_list sky130_fd_sc_hd__clkbuf_16 \
    -sink_clustering_enable

#===========================================================
# Routing
#===========================================================

# Global routing
global_route

# Detailed routing
detailed_route

#===========================================================
# Post-Route Optimization
#===========================================================

# Fix hold violations
repair_design

# Fill cells (decoupling caps, fillers)
insert_stdcell_filler \
    -fill_cells "sky130_fd_sc_hd__fill_1 sky130_fd_sc_hd__fill_2 sky130_fd_sc_hd__fill_4 sky130_fd_sc_hd__fill_8"

#===========================================================
# Verification & Reports
#===========================================================

# Timing report
report_checks -path_delay min_max -format full_clock_expanded
report_wns
report_tns

# Power report
report_power

# Area report
report_design_area

# DRC check
check_design -type drc

#===========================================================
# Output
#===========================================================

# Write GDSII
write_gds ultrasound_asic_top.gds

# Write final netlist
write_verilog ultrasound_asic_top_final.v

# Write SPEF (parasitics)
write_spef ultrasound_asic_top.spef

# Write DEF
write_def ultrasound_asic_top.def

puts "==================================="
puts "  Physical Design Flow Complete"
puts "  Output: ultrasound_asic_top.gds"
puts "==================================="

*===========================================================
* lunahan_ultrasound_ASIC — PMU Transistor-Level Schematic
*===========================================================
* Boost Converter (3.3V→6-14V) + Dual LDO (1.8V)
* PDK: sky130 HV (High-Voltage devices)
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

*===========================================================
* BANDGAP REFERENCE (BROKAW CELL)
*===========================================================
.SUBCKT BANDGAP VREF VDD VSS
* Brokaw bandgap with startup circuit
* Generates stable 1.2V reference

* Startup circuit
MSTART NSTART VDD VDD VDD sky130_fd_pr__pfet_01v8 W=1u L=20u
RSTART NSTART VSS 1MEG
MN_ST NSTART VBG VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.5u

* PTAT current generator
Q1 N1 N1 VSS pnp10 M=1
Q2 N2 N1 VSS pnp10 M=8  ; 8:1 ratio for delta-Vbe

R1 N3 VSS 7.2k   ; Sets PTAT current
R2 N2 N3 7.2k    ; Matched to R1 for symmetry

* Opamp to equalize N1 and N2 voltages
MP1 N4 VBP VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.5u
MP2 N5 VBP VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.5u
MN1 N4 N1 TAIL VSS sky130_fd_pr__nfet_01v8 W=20u L=0.3u
MN2 N5 N2 TAIL VSS sky130_fd_pr__nfet_01v8 W=20u L=0.3u
MN_TAIL TAIL VBN VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=1u

* PMOS mirror load
MP_LD1 N4 N4 VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.5u
MP_LD2 N5 N4 VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.5u
* Output (VBP = opamp output, drives PMOS current sources)
MP_OUT VBP N5 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.5u

* VREF output (VREF = Vbe + K·ΔVbe)
* Mirror PTAT current to output
MP_REF1 VBG VBP VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.5u
Q3 VREF VBG VSS pnp10 M=1
R3 VREF VBG 60k   ; K·ΔVbe = PTAT voltage
R4 VBG VSS 60k    ; Forms VREF = Vbe + 2·ΔVbe ≈ 1.2V

.ENDS BANDGAP

*===========================================================
* TYPE-III ERROR AMPLIFIER (for Boost Converter)
*===========================================================
.SUBCKT ERRAMP_BOOST INP INN COMP_OUT VDD VSS
* Two-stage OTA with type-III compensation network

* First stage: folded cascode
MP1 N1 VBP VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.3u
MP2 N2 VBP VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.3u
MN1 N1 INP N3 VSS sky130_fd_pr__nfet_01v8 W=20u L=0.3u
MN2 N2 INN N3 VSS sky130_fd_pr__nfet_01v8 W=20u L=0.3u
MN3 N3 VBN VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=1u

* Folded cascode load
MP_CAS1 N4 VBN_CAS VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.3u
MP_CAS2 COMP_OUT VBN_CAS VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.3u
MN_CAS1 N1 N4 VSS VSS sky130_fd_pr__nfet_01v8 W=8u L=0.3u
MN_CAS2 N2 N4 VSS VSS sky130_fd_pr__nfet_01v8 W=8u L=0.3u

* Second stage
MP_OUT COMP_OUT VBP VDD VDD sky130_fd_pr__pfet_01v8 W=20u L=0.5u
MN_OUT COMP_OUT VBN VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=0.5u

* Type-III compensation
C1 COMP_OUT N_COMP1 10p
R1 N_COMP1 N_COMP2 50k
C2 N_COMP2 VSS 100p
R2 COMP_OUT N_COMP3 5k
C3 N_COMP3 VSS 5p

.ENDS ERRAMP_BOOST

*===========================================================
* PWM COMPARATOR + RAMP GENERATOR
*===========================================================
.SUBCKT PWM_MODULATOR VERR RAMP PWM_OUT VDD VSS
* Comparator: differential pair + latch
MP1 N1 RAMP TAIL VDD sky130_fd_pr__pfet_01v8 W=8u L=0.3u
MP2 N2 VERR TAIL VDD sky130_fd_pr__pfet_01v8 W=8u L=0.3u
MN1 N1 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.5u
MN2 N2 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.5u
MTAIL TAIL VBN VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=0.5u

* Latch for clean digital output
MP_L1 N3 N2 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.18u
MN_L1 N3 N2 VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.18u
MP_L2 PWM_OUT N3 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.18u
MN_L2 PWM_OUT N3 VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.18u

.ENDS PWM_MODULATOR

*===========================================================
* BOOST CONVERTER POWER STAGE
*===========================================================
.SUBCKT BOOST_POWER PWM VIN VOUT VSS
* NMOS switch (low-side)
MN_SW SW VIN_GATE VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=5000u L=0.5u M=4

* Level shifter for gate drive (3.3V→5V)
* (simplified; real uses bootstrap or charge-pump gate drive)
XLS_GATE PWM VIN_GATE VOUT VDDLV VSS LEVEL_SHIFTER_5V

* Schottky diode (synchronous rectifier — PMOS for efficiency)
MP_RECT VOUT RECT_GATE SW VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=5000u L=0.5u M=4

* Synchronous rectifier control
* RECT_GATE = !PWM (with dead-time)
XINV_RECT PWM RECT_GATE_RAW VDDLV VSS INV_CHAIN4
XLS_RECT RECT_GATE_RAW RECT_GATE VDDHV VDDLV VSS LEVEL_SHIFTER_5V

* Output capacitor + ESR
COUT VOUT VSS 10u
RESR VOUT VOUT_SENSE 0.05

* Inductor (off-chip)
* Connected externally between VIN and SW
.ENDS BOOST_POWER

*===========================================================
* LDO — 1.8V OUTPUT
*===========================================================
.SUBCKT LDO_1V8 VIN VOUT VREF VDD VSS
* PMOS pass transistor
MPASS VIN GATE_LDO VOUT VIN sky130_fd_pr__pfet_01v8 W=2000u L=0.15u M=8

* Feedback divider
RFB_TOP VOUT VFB 120k
RFB_BOT VFB VSS 180k  ; VFB = VOUT × 180/300 = 0.6·VOUT

* Error amplifier (two-stage)
XERRAMP VREF VFB GATE_LDO VIN VSS ERRAMP_SIMPLE

* Output capacitor
CLDO VOUT VSS 1u
RESR_LDO VOUT VSS 0.1

.ENDS LDO_1V8

*===========================================================
* SIMPLE ERROR AMPLIFIER (for LDO)
*===========================================================
.SUBCKT ERRAMP_SIMPLE INP INN OUT VDD VSS
MP1 N1 VBP VDD VDD sky130_fd_pr__pfet_01v8 W=5u L=0.3u
MP2 OUT VBP VDD VDD sky130_fd_pr__pfet_01v8 W=5u L=0.3u
MN1 N1 INP N2 VSS sky130_fd_pr__nfet_01v8 W=10u L=0.3u
MN2 OUT INN N2 VSS sky130_fd_pr__nfet_01v8 W=10u L=0.3u
MN3 N2 VBN VSS VSS sky130_fd_pr__nfet_01v8 W=5u L=1u
* Compensation
CCOMP OUT N1 5p
RCOMP OUT N1 2k
.ENDS ERRAMP_SIMPLE

*===========================================================
* BIAS NETWORK for PMU
*===========================================================
.SUBCKT PMU_BIAS VREF VBP VBN VBN_CAS VDD VSS
* Bandgap
XBANDGAP VREF VDD VSS BANDGAP

* Constant-gm bias from bandgap
MP_B1 NBIAS VBP VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=1u
MP_B2 VBP VBP VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=1u
MN_B1 NBIAS NBIAS VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=2u
MN_B2 VBN NBIAS VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=2u M=4
RBIAS VBP NBIAS 20k

* Cascode bias
MP_CAS VBN_CAS VBP VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=1u
MN_CAS VBN_CAS VBN VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.5u

.ENDS PMU_BIAS

*===========================================================
* LEVEL SHIFTER 5V (for boost gate drive)
*===========================================================
.SUBCKT LEVEL_SHIFTER_5V IN OUT VDDHV VDDLV VSS
MP1 OUT OUTN VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=4u L=0.5u
MP2 OUTN OUT VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=4u L=0.5u
MN1 OUT IN VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=2u L=0.5u
MPINV INN IN VDDLV VDDLV sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MNINV INN IN VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MN2 OUTN INN VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=2u L=0.5u
.ENDS LEVEL_SHIFTER_5V

*===========================================================
* FULL PMU
*===========================================================
.SUBCKT PMU VIN VDD_TX VDD_ANA VDD_DIG VREF_OUT VSS

* --- Bias + Bandgap ---
XBIAS VREF VBP VBN VBN_CAS VIN VSS PMU_BIAS

* --- Boost Converter (VIN → VDD_TX 6-14V) ---
* Feedback divider (set for 12V nominal)
RFB_TX_TOP VDD_TX VFB_TX 100k
RFB_TX_BOT VFB_TX VSS 11k  ; VFB = VDD_TX × 11/111 ≈ 1.19V @ 12V

* Error amplifier
XERR_TX VREF VFB_TX COMP_TX VIN VSS ERRAMP_BOOST

* PWM modulator (40 kHz ramp + comparator)
XRAMP VIN RAMP VSS RAMP_GEN
XPWM COMP_TX RAMP PWM_TX VIN VSS PWM_MODULATOR

* Power stage
XBOOST_PWR PWM_TX VIN VDD_TX VSS BOOST_POWER

* --- LDO for Analog 1.8V ---
XLDO_ANA VIN VDD_ANA VREF VIN VSS LDO_1V8

* --- LDO for Digital 1.8V ---
XLDO_DIG VIN VDD_DIG VREF VIN VSS LDO_1V8

* VREF output (for monitoring)
X_BUF VREF VREF_OUT VIN VSS  ; unity-gain buffer

.ENDS PMU

*===========================================================
* TESTBENCH
*===========================================================
VIN VIN 0 DC 3.3
XPMU VIN VDD_TX VDD_ANA VDD_DIG VREF 0 PMU

ILOAD_ANA VDD_ANA 0 15m
ILOAD_DIG VDD_DIG 0 10m
ILOAD_TX VDD_TX 0 20m

.OP
.TRAN 1u 2m UIC

.MEAS TRAN VANA AVG V(VDD_ANA) FROM=0.5m TO=2m
.MEAS TRAN VDIG AVG V(VDD_DIG) FROM=0.5m TO=2m
.MEAS TRAN VTX AVG V(VDD_TX) FROM=0.5m TO=2m
.MEAS TRAN EFF PARAM='(V(VDD_ANA)*15m+V(VDD_DIG)*10m+V(VDD_TX)*20m)/(3.3*I(VIN))'

.END

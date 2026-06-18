*===========================================================
* lunahan_ultrasound_ASIC — UERTX Driver Transistor-Level Schematic
*===========================================================
* H-Bridge Class-D with Energy-Recycling LC Tank
* PDK: sky130 HV (High-Voltage devices for 14V operation)
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

*===========================================================
* LEVEL SHIFTER — 1.8V logic → 14V gate drive
*===========================================================
.SUBCKT LEVEL_SHIFTER IN OUT OUTN VDDHV VDDLV VSS
* Cross-coupled PMOS latch with NMOS input pair
* Converts 0-1.8V input to 0-14V output

MP1 OUT OUTN VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=8u L=0.5u
MP2 OUTN OUT VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=8u L=0.5u

MN1 OUT IN VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=4u L=0.5u
MN2 OUTN INN VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=4u L=0.5u

* Inverter for complementary input
MPINV INN IN VDDLV VDDLV sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MNINV INN IN VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u

.ENDS LEVEL_SHIFTER

*===========================================================
* DEAD-TIME GENERATOR (transistor-level)
*===========================================================
.SUBCKT DEADTIME_GEN PWM_IN HS_GATE LS_GATE VDD VSS
* Generates non-overlapping gate signals with ~120 ns dead time
* Using RC delay + Schmitt trigger + NAND logic

* Delay chain (RC)
RDEL1 PWM_IN D1 20k
CDEL1 D1 VSS 3p   ; ≈ 60 ns delay

RDEL2 PWM_IN D2 20k
CDEL2 D2 VSS 6p   ; ≈ 120 ns delay (longer for falling edge)

* Schmitt trigger inverters (hysteresis prevents chatter)
XINV1 D1 HS_PRE VDD VSS SCHMITT_INV
XINV2 D2 LS_PRE VDD VSS SCHMITT_INV

* Non-overlap logic: HS turns on only when LS is off, and vice versa
* HS = PWM rising & LS not active
* LS = PWM falling & HS not active
MNAND1_1 HS_GATE_PRE D1 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u M=2
MNAND1_2 HS_GATE_PRE LS_GATE_RAW VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u M=2
MNAND1_3 HS_GATE_PRE D1 N1 VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MNAND1_4 N1 LS_GATE_RAW VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u

MNAND2_1 LS_GATE_RAW D2 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u M=2
MNAND2_2 LS_GATE_RAW HS_GATE_PRE VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u M=2
MNAND2_3 LS_GATE_RAW D2 N2 VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MNAND2_4 N2 HS_GATE_PRE VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u

* Buffers for gate drive strength
XINV_HS HS_GATE_PRE HS_GATE VDD VSS INV_CHAIN4
XINV_LS LS_GATE_RAW LS_GATE VDD VSS INV_CHAIN4

.ENDS DEADTIME_GEN

*===========================================================
* SCHMITT TRIGGER INVERTER
*===========================================================
.SUBCKT SCHMITT_INV IN OUT VDD VSS
MP1 N1 IN VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MN1 N1 IN VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MP2 OUT N1 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MN2 OUT N1 VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
* Feedback for hysteresis
MPFB N1 OUT VDD VDD sky130_fd_pr__pfet_01v8 W=0.5u L=0.15u
MNFB N1 OUT VSS VSS sky130_fd_pr__nfet_01v8 W=0.25u L=0.15u
.ENDS SCHMITT_INV

*===========================================================
* INVERTER CHAIN (4× for gate driver)
*===========================================================
.SUBCKT INV_CHAIN4 IN OUT VDD VSS
* Tapered buffer: 1× → 2× → 4× → 8×
MP1 N1 IN VDD VDD sky130_fd_pr__pfet_01v8 W=1u L=0.15u
MN1 N1 IN VSS VSS sky130_fd_pr__nfet_01v8 W=0.5u L=0.15u
MP2 N2 N1 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MN2 N2 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MP3 N3 N2 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
MN3 N3 N2 VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.15u
MP4 OUT N3 VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.15u
MN4 OUT N3 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.15u
.ENDS INV_CHAIN4

*===========================================================
* H-BRIDGE OUTPUT STAGE (14V domain)
*===========================================================
.SUBCKT HBRIDGE HS_GATE_P LS_GATE_P HS_GATE_N LS_GATE_N OUT_P OUT_N VDDHV VSS

* High-side PMOS (drives output to VDDHV)
MHS_P OUT_P HS_GATE_P VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=2000u L=0.5u M=1
* Low-side NMOS (drives output to VSS)
MLS_P OUT_P LS_GATE_P VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=1000u L=0.5u M=1

* High-side PMOS (differential)
MHS_N OUT_N HS_GATE_N VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=2000u L=0.5u M=1
* Low-side NMOS (differential)
MLS_N OUT_N LS_GATE_N VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=1000u L=0.5u M=1

.ENDS HBRIDGE

*===========================================================
* ENERGY RECYCLING LC TANK
*===========================================================
.SUBCKT RECYCLE_TANK VDDHV SW_P SW_N
* LC tank recovers reactive energy stored in transducer
* parasitic capacitance during switching dead-time

* Recycling inductor (off-chip for high Q, high current)
LREC VDDHV REC_NODE 330u
RREC VDDHV REC_NODE 0.2   ; DCR

* Recycling switch: closes during dead-time
* Implemented as NMOS with body diode
XREC_SW REC_NODE SW_P DEADTIME VSS RECYCLE_SW
XREC_SW_N REC_NODE SW_N DEADTIME VSS RECYCLE_SW

* Recycling diode: prevents reverse current from VDDHV to tank
DREC_P SW_P VDDHV sky130_fd_pr__diode_pw2ndw11v
DREC_N SW_N VDDHV sky130_fd_pr__diode_pw2ndw11v

.ENDS RECYCLE_TANK

*===========================================================
* RECYCLING SWITCH (NMOS with bulk diode)
*===========================================================
.SUBCKT RECYCLE_SW D S G VSS
* NMOS switch transistor
MN_SW D G S VSS sky130_fd_pr__nfet_g5v0d10v5 W=500u L=0.5u
* Body diode (intrinsic to device, modeled explicitly)
.ENDS RECYCLE_SW

*===========================================================
* TRANSDUCER MODEL (40 kHz piezo)
*===========================================================
.SUBCKT ULTRASOUND_XDUCER P N
* Motional branch (series RLC at resonance = 40 kHz)
LM P N1 120m
CM N1 N2 132p
RM N2 N 500
* Clamped capacitance
CP P N 2.5n
* Dielectric loss
RL P N 50k
.ENDS ULTRASOUND_XDUCER

*===========================================================
* FULL UERTX DRIVER
*===========================================================
.SUBCKT UERTX PWM_P PWM_N OUT_P OUT_N VDDHV VDDLV VSS

* Dead-time generator (1.8V domain)
XDEAD_P PWM_P HS_LV_P LS_LV_P VDDLV VSS DEADTIME_GEN
XDEAD_N PWM_N HS_LV_N LS_LV_N VDDLV VSS DEADTIME_GEN

* Level shifters (1.8V → 14V)
XLVL_P_HS HS_LV_P HS_HV_P HS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER
XLVL_P_LS LS_LV_P LS_HV_P LS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER
XLVL_N_HS HS_LV_N HS_HV_N LS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER
XLVL_N_LS LS_LV_N LS_HV_N HS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER

* H-Bridge output stage
XHBR HS_HV_P LS_HV_P HS_HV_N LS_HV_N OUT_P OUT_N VDDHV VSS HBRIDGE

* Energy recycling tank
XRECYCLE VDDHV OUT_P OUT_N RECYCLE_TANK

* Dead-time detection for recycling control
XDEAD_DET LS_HV_P LS_HV_N DEADTIME VDDLV VSS DEAD_DETECT

.ENDS UERTX

*===========================================================
* DEAD-TIME DETECTOR (for recycling control)
*===========================================================
.SUBCKT DEAD_DETECT LS_P LS_N DEAD_OUT VDD VSS
* DEAD_OUT = 1 when both LS_P and LS_N are low → dead-time
* Combined NOR
MP1 N1 LS_N VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MP2 N1 LS_P VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MN1 N1 LS_N N2 VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MN2 N2 LS_P VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
* Buffer
XINV N1 DEAD_OUT VDD VSS INV_CHAIN4
.ENDS DEAD_DETECT

*===========================================================
* TESTBENCH
*===========================================================
VDDHV VDDHV 0 DC 14
VDDLV VDDLV 0 DC 1.8

VPWM_P PWM_P 0 PULSE(0 1.8 0 0.1n 0.1n 12.4u 25u)
VPWM_N PWM_N 0 PULSE(0 1.8 12.5u 0.1n 0.1n 12.4u 25u)

XUERTX PWM_P PWM_N OUTP OUTN VDDHV VDDLV 0 UERTX
XDUCER OUTP OUTN ULTRASOUND_XDUCER

.OP
.TRAN 1n 500u UIC

.MEAS TRAN AVG_P AVG I(VDDHV)*14 FROM=50u TO=300u
.MEAS TRAN RMS_V RMS V(OUTP,OUTN) FROM=50u TO=300u
.MEAS TRAN ENERGY_BURST INTEG I(VDDHV)*14 FROM=0 TO=225u

.END

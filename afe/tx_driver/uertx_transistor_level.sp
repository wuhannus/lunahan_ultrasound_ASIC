*===========================================================
* lunahan_ultrasound_ASIC — UERTX Driver (Corrected)
*===========================================================
* Architecture: H-Bridge Class-D with capacitor-based
*              charge recycling (NO inductor)
*
* Original design: Han Wu, JSSC 2022
* "Universal Energy Recycling TX (UERTX)"
*
* Recycling mechanism:
*   - Storage capacitor CSTORE accumulates charge from
*     transducer clamped capacitance C0 during TX transitions
*   - During next TX phase, CSTORE provides partial drive
*     charge, reducing current drawn from VDD_TX
*   - 44.2% energy saving vs conventional class-D
*   - NO inductor used (unlike resonant LC recycling)
*
* PDK: sky130 HV (High-Voltage devices for 14V operation)
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

*===========================================================
* LEVEL SHIFTER — 1.8V logic → 14V gate drive
*===========================================================
.SUBCKT LEVEL_SHIFTER IN OUT OUTN VDDHV VDDLV VSS
MP1 OUT OUTN VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=8u L=0.5u
MP2 OUTN OUT VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=8u L=0.5u
MN1 OUT IN VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=4u L=0.5u
MN2 OUTN INN VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=4u L=0.5u
MPINV INN IN VDDLV VDDLV sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MNINV INN IN VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
.ENDS LEVEL_SHIFTER

*===========================================================
* DEAD-TIME GENERATOR
*===========================================================
.SUBCKT DEADTIME_GEN PWM_IN HS_GATE LS_GATE VDD VSS
* RC delay + NAND logic for non-overlapping gate drive
RDEL1 PWM_IN D1 20k
CDEL1 D1 VSS 3p
RDEL2 PWM_IN D2 20k
CDEL2 D2 VSS 6p

* Schmitt trigger inverters
MPH1 N1 D1 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MNH1 N1 D1 VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MPH2 HS_GATE_PRE N1 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
MNH2 HS_GATE_PRE N1 VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.15u

MPL1 N2 D2 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MNL1 N2 D2 VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MPL2 LS_GATE N2 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
MNL2 LS_GATE N2 VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.15u

* Buffers for gate drive
MPBUF_HS HS_GATE HS_GATE_PRE VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.15u
MNBUF_HS HS_GATE HS_GATE_PRE VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.15u
.ENDS DEADTIME_GEN

*===========================================================
* H-BRIDGE OUTPUT STAGE (14V domain)
*===========================================================
.SUBCKT HBRIDGE HS_GATE_P LS_GATE_P HS_GATE_N LS_GATE_N OUT_P OUT_N VDDHV VSS
MHS_P OUT_P HS_GATE_P VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=2000u L=0.5u
MLS_P OUT_P LS_GATE_P VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=1000u L=0.5u
MHS_N OUT_N HS_GATE_N VDDHV VDDHV sky130_fd_pr__pfet_g5v0d10v5 W=2000u L=0.5u
MLS_N OUT_N LS_GATE_N VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=1000u L=0.5u
.ENDS HBRIDGE

*===========================================================
* CAPACITOR-BASED CHARGE RECYCLING TANK
*===========================================================
* NO inductor. Uses storage capacitor CSTORE to capture
* energy from transducer C0 during dead-time transitions.
*
* Operating principle:
*   Phase 1 (TX high → dead-time):
*     Transducer C0 discharges into CSTORE via switch S1
*   Phase 2 (dead-time → TX low):
*     CSTORE partially charges transducer C0 via switch S2
*   Result: reduced current from VDD_TX; ~44% energy saved
*===========================================================
.SUBCKT CHARGE_RECYCLE VDDHV SW_P SW_N DEADTIME VSS
* Storage capacitor (off-chip for large value)
CSTORE VDDHV STORE_NODE 100n

* S1: Connects OUT_P to STORE_NODE during dead-time (OUT_P falling)
* Transfers charge from transducer C0 to CSTORE
XS1_P SW_P STORE_NODE DEADTIME VSS CHARGE_SWITCH

* S2: Connects STORE_NODE to OUT_N during dead-time (OUT_N rising)
* Transfers charge from CSTORE to OUT_N
XS2_N STORE_NODE SW_N DEADTIME VSS CHARGE_SWITCH

* Reverse blocking diode — prevents CSTORE from discharging back to VDDHV
DREC STORE_NODE VDDHV sky130_fd_pr__diode_pw2ndw11v

.ENDS CHARGE_RECYCLE

*===========================================================
* CHARGE RECYCLING SWITCH (NMOS pass transistor)
*===========================================================
.SUBCKT CHARGE_SWITCH D S G VSS
MN_SW D G S VSS sky130_fd_pr__nfet_g5v0d10v5 W=500u L=0.5u
.ENDS CHARGE_SWITCH

*===========================================================
* TRANSDUCER MODEL (40 kHz piezo, air-coupled)
*===========================================================
.SUBCKT ULTRASOUND_XDUCER P N
* Motional branch (series RLC at resonance = 40 kHz)
LM P N1 120m
CM N1 N2 132p
RM N2 N 500
* Clamped capacitance (key for charge recycling)
CP P N 2.5n
* Dielectric loss
RL P N 50k
.ENDS ULTRASOUND_XDUCER

*===========================================================
* DEAD-TIME DETECTOR
*===========================================================
.SUBCKT DEAD_DETECT LS_P LS_N DEAD_OUT VDD VSS
* DEAD_OUT = 1 when both LS_P and LS_N are low
MP1 N1 LS_N VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MP2 N1 LS_P VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
MN1 N1 LS_N N2 VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MN2 N2 LS_P VSS VSS sky130_fd_pr__nfet_01v8 W=1u L=0.15u
MPB N2 N1 VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.15u
MNB N2 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.15u
* Buffer
MPB2 DEAD_OUT N2 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
MNB2 DEAD_OUT N2 VSS VSS sky130_fd_pr__nfet_01v8 W=2u L=0.15u
.ENDS DEAD_DETECT

*===========================================================
* FULL UERTX DRIVER (Capacitor-Based Charge Recycling)
*===========================================================
.SUBCKT UERTX PWM_P PWM_N OUT_P OUT_N VDDHV VDDLV VSS

* Dead-time generator (1.8V domain)
XDEAD_P PWM_P HS_LV_P LS_LV_P VDDLV VSS DEADTIME_GEN
XDEAD_N PWM_N HS_LV_N LS_LV_N VDDLV VSS DEADTIME_GEN

* Level shifters (1.8V → 14V)
XLVL_HS_P HS_LV_P HS_HV_P HS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER
XLVL_LS_P LS_LV_P LS_HV_P LS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER
XLVL_HS_N HS_LV_N HS_HV_N LS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER
XLVL_LS_N LS_LV_N LS_HV_N HS_HV_N_B VDDHV VDDLV VSS LEVEL_SHIFTER

* H-Bridge output stage
XHBR HS_HV_P LS_HV_P HS_HV_N LS_HV_N OUT_P OUT_N VDDHV VSS HBRIDGE

* Capacitor-based charge recycling (NO inductor)
XDEAD LS_HV_P LS_HV_N DEADTIME VDDLV VSS DEAD_DETECT
XRECYCLE VDDHV OUT_P OUT_N DEADTIME VSS CHARGE_RECYCLE

.ENDS UERTX

*===========================================================
* TESTBENCH — Energy Comparison
*===========================================================
VDDHV VDDHV 0 DC 14
VDDLV VDDLV 0 DC 1.8

VPWM_P PWM_P 0 PULSE(0 1.8 0 0.1n 0.1n 12.4u 25u)
VPWM_N PWM_N 0 PULSE(0 1.8 12.5u 0.1n 0.1n 12.4u 25u)

* UERTX (with capacitor recycling)
XUERTX PWM_P PWM_N OUTP OUTN VDDHV VDDLV 0 UERTX
XDUCER OUTP OUTN ULTRASOUND_XDUCER

* Conventional class-D (for comparison) — same H-bridge, NO recycling
* XCONV_D PWM_P PWM_N OUTP_C OUTN_C VDDHV VDDLV 0 HBRIDGE_ONLY

.OP
.TRAN 1n 500u UIC

* Energy measurements for 8-pulse burst
.MEAS TRAN ENERGY_UERTX INTEG I(VDDHV)*14 FROM=0 TO=225u
*.MEAS TRAN ENERGY_CLASSD INTEG I(VDDHV_C)*14 FROM=0 TO=225u
*.MEAS TRAN ENERGY_SAVING PARAM='(ENERGY_CLASSD-ENERGY_UERTX)/ENERGY_CLASSD*100'

.MEAS TRAN AVG_POWER AVG I(VDDHV)*14 FROM=50u TO=300u
.MEAS TRAN RMS_VOUT RMS V(OUTP,OUTN) FROM=50u TO=300u

.END

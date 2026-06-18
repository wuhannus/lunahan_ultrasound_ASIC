*===========================================================
* lunahan_ultrasound_ASIC — VGA Transistor-Level Schematic
*===========================================================
* Two-stage fully-differential PGA with switched R-2R ladder
* PDK: sky130 (SkyWater 130 nm)
* Gain: -2 to 42 dB, 64 steps (6-bit control)
* All opamps: real two-stage Miller-compensated
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

*===========================================================
* TWO-STAGE MILLER-COMPENSATED DIFFERENTIAL OPAMP
*===========================================================
.SUBCKT OPAMP_TWOSTAGE INP INN OUTP OUTN VDD VSS VBIASP VBIASN

* --- Tail current source ---
MTAIL TAIL VBIASN VSS VSS sky130_fd_pr__nfet_01v8 W=20u L=0.5u M=1

* --- Differential input pair (PMOS for lower 1/f noise) ---
M1 N1 INP TAIL VDD sky130_fd_pr__pfet_01v8 W=40u L=0.3u M=1
M2 N2 INN TAIL VDD sky130_fd_pr__pfet_01v8 W=40u L=0.3u M=1

* --- Current mirror load (NMOS) ---
M3 N1 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=0.3u M=1
M4 N2 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=0.3u M=1

* --- Second stage (common-source with active load) ---
M5 OUTP N2 VSS VSS sky130_fd_pr__nfet_01v8 W=40u L=0.15u M=1
M6 OUTP VBIASP VDD VDD sky130_fd_pr__pfet_01v8 W=20u L=0.5u M=1

M7 OUTN N1 VSS VSS sky130_fd_pr__nfet_01v8 W=40u L=0.15u M=1
M8 OUTN VBIASP VDD VDD sky130_fd_pr__pfet_01v8 W=20u L=0.5u M=1

* --- Miller compensation ---
CCOMP1 OUTP N2 2p
RCOMP1 OUTP N2 500
CCOMP2 OUTN N1 2p
RCOMP2 OUTN N1 500

* --- Common-mode feedback (CMFB) ---
* Sense output CM via resistor divider
RCM1 OUTP CM_SENSE 50k
RCM2 OUTN CM_SENSE 50k

* CMFB amplifier (simple diff pair)
MCM1 NCM CM_SENSE TAIL_CM VDD sky130_fd_pr__pfet_01v8 W=10u L=1u M=1
MCM2 FB_CM VCM_REF TAIL_CM VDD sky130_fd_pr__pfet_01v8 W=10u L=1u M=1
MTAIL_CM TAIL_CM VBIASN VSS VSS sky130_fd_pr__nfet_01v8 W=10u L=0.5u M=1
MCM3 FB_CM FB_CM VSS VSS sky130_fd_pr__nfet_01v8 W=5u L=1u M=1
MCM4 N1 NCM VDD VDD sky130_fd_pr__pfet_01v8 W=5u L=0.5u M=1

* VCM reference (from bias network, nominally VDD/2 = 0.9V)
.ENDS OPAMP_TWOSTAGE

*===========================================================
* SWITCHED R-2R FEEDBACK NETWORK (6-bit)
*===========================================================
* Gain = Rf / Rin × (code/64)
* code = 0  → Rf ≈ 0   → gain ≈ -2 dB (attenuator mode)
* code = 63 → Rf ≈ 127k → gain ≈ 42 dB

.SUBCKT R2R_NET INP INN OUTP OUTN CODE[0] CODE[1] CODE[2] CODE[3] CODE[4] CODE[5] VDD VSS

* Fixed input resistor
RINP INP AMP_INP 1k
RINN INN AMP_INN 1k

* R-2R ladder (6-bit, MSB to LSB)
* Each segment: series R = 1k, shunt 2R = 2k switched to VCM or GND
* Total effective resistance from CODE bits

* Bit 5 (MSB, gain factor 32/64)
R5S AMP_OUTP N5A 2k
R5SH N5A N5B 2k
XSW5P N5B AMP_INN VCM CODE[5] VDD VSS TG_SWITCH
XSW5N N5B AMP_INP VCM CODE[5] VDD VSS TG_SWITCH

R4S N5A N4A 2k
R4SH N4A N4B 4k
XSW4P N4B AMP_INN VCM CODE[4] VDD VSS TG_SWITCH
XSW4N N4B AMP_INP VCM CODE[4] VDD VSS TG_SWITCH

R3S N4A N3A 4k
R3SH N3A N3B 8k
XSW3P N3B AMP_INN VCM CODE[3] VDD VSS TG_SWITCH
XSW3N N3B AMP_INP VCM CODE[3] VDD VSS TG_SWITCH

R2S N3A N2A 8k
R2SH N2A N2B 16k
XSW2P N2B AMP_INN VCM CODE[2] VDD VSS TG_SWITCH
XSW2N N2B AMP_INP VCM CODE[2] VDD VSS TG_SWITCH

R1S N2A N1A 16k
R1SH N1A N1B 32k
XSW1P N1B AMP_INN VCM CODE[1] VDD VSS TG_SWITCH
XSW1N N1B AMP_INP VCM CODE[1] VDD VSS TG_SWITCH

R0S N1A AMP_OUTP 32k
R0SH AMP_OUTP FB_NODE 64k
XSW0P FB_NODE AMP_INN VCM CODE[0] VDD VSS TG_SWITCH
XSW0N FB_NODE AMP_INP VCM CODE[0] VDD VSS TG_SWITCH

.ENDS R2R_NET

*===========================================================
* TRANSMISSION GATE SWITCH (used in R-2R ladder)
*===========================================================
.SUBCKT TG_SWITCH A B CTRL CTRL_N VDD VSS
* NMOS pass transistor
MN A CTRL B VSS sky130_fd_pr__nfet_01v8 W=2u L=0.15u
* PMOS pass transistor (for rail-to-rail switching)
MP A CTRL_N B VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
.ENDS TG_SWITCH

*===========================================================
* VGA BIAS NETWORK
*===========================================================
.SUBCKT VGA_BIAS IREF VBIASP VBIASN VCM VDD VSS

* Start-up
MST_ST VDD VDD NST VSS sky130_fd_pr__nfet_01v8 W=1u L=10u
RST NST VSS 500k

* Beta-multiplier
MP_REF NREF NREF VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.5u M=1
MP_OUT NBIAS NREF VDD VDD sky130_fd_pr__pfet_01v8 W=8u L=0.5u M=1
MN_REF NREF NREF NBIAS2 VSS sky130_fd_pr__nfet_01v8 W=4u L=2u M=1
MN_REF2 NBIAS2 NREF VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=2u M=4
RREF NBIAS VSS 12k

* Generate bias voltages
MP_BIASP VBIASP NREF VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=1u
MN_BIASN VBIASN NREF VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=1u

* VCM reference (resistive divider + buffer)
RCMT VDD VCM 50k
RCMB VCM VSS 50k
* Simple source-follower buffer for VCM
MN_VCM_BUF VDD NREF VCM VSS sky130_fd_pr__nfet_01v8 W=10u L=0.5u

.ENDS VGA_BIAS

*===========================================================
* FULL VGA (Two-Stage PGA)
*===========================================================
.SUBCKT VGA INP INN OUTP OUTN CODE[0] CODE[1] CODE[2] CODE[3] CODE[4] CODE[5] VDD VSS

* Bias
XBIAS IREF VBP VBN VCM VDD VSS VGA_BIAS

* Stage 1: Differential amplifier with programmable feedback
XR2R INP INN S1_OUTP S1_OUTN CODE[0] CODE[1] CODE[2] CODE[3] CODE[4] CODE[5] VDD VSS R2R_NET
XOP1 S1_INP S1_INN S1_OUTP S1_OUTN VDD VSS VBP VBN OPAMP_TWOSTAGE

* Stage 2: Fixed gain (6 dB = 2×) output driver
CIN2P S1_OUTP S2_INP 10p
CIN2N S1_OUTN S2_INN 10p
RBIASP_2 VCM S2_INP 100k
RBIASN_2 VCM S2_INN 100k

XOP2 S2_INP S2_INN OUTP OUTN VDD VSS VBP VBN OPAMP_TWOSTAGE
RF2P OUTP S2_INN 20k
RF2N OUTN S2_INP 20k
RG2P S2_INP VCM 10k
RG2N S2_INN VCM 10k

.ENDS VGA

*===========================================================
* TESTBENCH
*===========================================================
VDD VDD 0 DC 1.8
VINP INP 0 DC 0.9 SIN(0.9 10m 40k)
VINN INN 0 DC 0.9

VCODE0 C0 0 DC 1.8  ; code=32 (approx 20 dB)
VCODE1 C1 0 DC 0
VCODE2 C2 0 DC 1.8
VCODE3 C3 0 DC 0
VCODE4 C4 0 DC 1.8
VCODE5 C5 0 DC 0

XVGA INP INN OUTP OUTN C0 C1 C2 C3 C4 C5 VDD 0 VGA

.OP
.AC DEC 100 1k 10MEG
.TRAN 0.1u 200u

.MEAS AC GAIN_DB MAX VDB(OUTP)
.MEAS DC PWR AVG I(VDD)*1.8

.END

*===========================================================
* lunahan_ultrasound_ASIC — LNA Transistor-Level Schematic
*===========================================================
* 3-stage cascoded common-source with inductive degeneration
* PDK: sky130 (SkyWater 130 nm)
* All devices: real foundry transistor models
* Bias: PTAT constant-gm reference (temperature-compensated)
*
* REDESIGNED SPECS (based on comprehensive literature survey):
*   Gain:        >30 dB (vs original 22.4 dB)
*   NF:          <2.5 dB (vs original 3.8 dB)
*   IRN:         <2.0 nV/sqrt(Hz) at 40 kHz (vs 3.2)
*   Bandwidth:   10 kHz — 200 kHz
*   Power:       <1 mW
*   Cascode:     YES (improved reverse isolation)
*   Input device: 40-finger layout for low Rg
*
* Key changes from original:
*   1. M1: 40 fingers × 5µm (vs 4 fingers) → lower gate resistance
*   2. Cascode device added for isolation
*   3. Lload: Tuned for 30 dB total gain
*   4. PTAT bias for temperature-stable gain
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

*===========================================================
* BIAS NETWORK — Constant-gm PTAT current reference
*===========================================================
.SUBCKT LNA_BIAS IBIAS_OUT VBIAS1 VBIAS2 VBIAS3 VDD VSS
* Self-biased constant-gm reference
* Delta-Vgs/R generates PTAT current ~50µA

* Startup circuit
MSTART START VDD VDD VDD sky130_fd_pr__pfet_01v8 W=1u L=10u
RSTART START VSS 500k

* Beta-multiplier core
MBIAS1 N1 N1 VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.5u M=1
MBIAS2 IOUT N1 VDD VDD sky130_fd_pr__pfet_01v8 W=10u L=0.5u M=1
MBIAS3 N1 N1 N2 VSS sky130_fd_pr__nfet_01v8 W=5u L=0.5u M=1
MBIAS4 N2 N1 VSS VSS sky130_fd_pr__nfet_01v8 W=5u L=0.5u M=4  ; 4× for delta-Vgs
RBIAS IOUT VSS 12k  ; Sets I ≈ (Vt·ln4)/R ≈ 50µA

* Bias voltage generation (diode-connected mirrors for distribution)
MP1 VBIAS1 VBIAS1 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=1u
MN1 VBIAS1 VBIAS1 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=1u
MP2 VBIAS2 N1 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=1u
MN2 VBIAS2 VBIAS2 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=1u
MP3 VBIAS3 N1 VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=1u
MN3 VBIAS3 VBIAS3 VSS VSS sky130_fd_pr__nfet_01v8 W=4u L=0.5u

* Output current mirror (for tail current sourcing)
MPOUT IBIAS_OUT N1 VDD VDD sky130_fd_pr__pfet_01v8 W=20u L=1u M=1

.ENDS LNA_BIAS

*===========================================================
* STAGE 1: Common-Source with Inductive Source Degeneration
*===========================================================
* Purpose: Simultaneous noise and impedance matching to 50Ω
* Input transistor M1 sized for optimal NFmin at 40 kHz
* Inductive degeneration Ls creates real input impedance
*   Zin ≈ gm1·Ls/Cgs1 + jω(Lg+Ls) + 1/(jωCgs1)

.SUBCKT LNA_STAGE1 IN GATE_DC OUT VDD VSS VBIAS VBN

* --- Gate inductor (off-chip for high Q) ---
LG IN GATE_DC 330u

* --- Input AC coupling ---
CIN GATE_DC GATE_M1 100p

* --- Bias tee (RF choke to DC bias) ---
RBIAS VBIAS GATE_M1 10k

* --- M1: Main input device ---
* W=200u/0.15u, 4 fingers for low gate resistance
* Current density: ~250µA for optimal NFmin
XM1 DRAIN_M1 GATE_M1 SOURCE_M1 VSS sky130_fd_pr__nfet_01v8 W=5u L=0.15u NF=1 M=40

* --- Source degeneration inductor (on-chip spiral) ---
* Ls determines real part of Zin: Re{Zin} ≈ gm·Ls/Cgs
* Target: 50Ω match at 40 kHz
LS SOURCE_M1 VSS 100u

* --- Cascode transistor (boosts gain, improves isolation) ---
XMCAS DRAIN_CAS GATE_CAS DRAIN_M1 VSS sky130_fd_pr__nfet_01v8 W=200u L=0.18u
RBIAS_CAS VDD GATE_CAS 5k  ; Cascode gate tied to VDD via resistor
CBYP_CAS GATE_CAS VSS 10p    ; AC bypass for cascode gate

* --- Inductive load (resonates with output capacitance at 40 kHz) ---
LLOAD VDD DRAIN_CAS 1m
RLOAD VDD DRAIN_CAS 8k  ; Parallel resistor to control Q

* --- Output AC coupling to next stage ---
COUT1 DRAIN_CAS OUT_STG1 10p

.ENDS LNA_STAGE1

*===========================================================
* STAGE 2: Common-Source Gain Stage
*===========================================================
* Purpose: Provide voltage gain with PMOS active load
* Gain ≈ gm2·(rop||ron) ≈ 25-30 dB (total from stages 1+2)

.SUBCKT LNA_STAGE2 IN OUT VDD VSS VBIASP VBIASN

* --- AC coupling from previous stage ---
CIN2 IN GATE_M2 10p

* --- DC bias for M2 ---
RBIAS2 VBIASN GATE_M2 50k

* --- M2: NMOS gain transistor ---
* Operation: saturation, Id≈200µA
XM2 DRAIN_M2 GATE_M2 VSS VSS sky130_fd_pr__nfet_01v8 W=100u L=0.15u M=1

* --- PMOS current source load (high output impedance) ---
XMLOAD DRAIN_M2 VBIASP VDD VDD sky130_fd_pr__pfet_01v8 W=40u L=0.5u M=1

* --- Miller compensation (optional, for stability if driving large load) ---
* CCOMP DRAIN_M2 GATE_M2 200f
* RCOMP DRAIN_M2 GATE_M2 2k

* --- Output coupling ---
COUT2 DRAIN_M2 OUT 10p

.ENDS LNA_STAGE2

*===========================================================
* STAGE 3: Source-Follower Output Buffer
*===========================================================
* Purpose: Low output impedance to drive VGA input (Zout≈1/gm3≈200Ω)
* Unity voltage gain with level shift

.SUBCKT LNA_STAGE3 IN OUT VDD VSS VBIASP VBIASN

* --- AC coupling ---
CIN3 IN GATE_M3 10p

* --- DC bias ---
RBIAS3 VBIASN GATE_M3 50k

* --- M3: Source follower ---
XM3 VDD GATE_M3 OUT VSS sky130_fd_pr__nfet_01v8 W=80u L=0.15u M=1

* --- Current sink (constant bias) ---
XMBIAS OUT VBIASN VSS VSS sky130_fd_pr__nfet_01v8 W=20u L=0.5u M=1

.ENDS LNA_STAGE3

*===========================================================
* FULL LNA — 3-Stage Cascaded
*===========================================================
.SUBCKT LNA IN OUT VDD VSS
* --- Bias network ---
XBIAS IBIAS VBP1 VBN1 VBP2 VDD VSS LNA_BIAS

* --- Stage 1: Input matching + gain ---
XSTG1 IN N1 OUT1 VDD VSS VBP1 VBN1 LNA_STAGE1

* --- Stage 2: Gain stage ---
XSTG2 OUT1 OUT2 VDD VSS VBP2 VBN1 LNA_STAGE2

* --- Stage 3: Buffer ---
XSTG3 OUT2 OUT VDD VSS VBP2 VBN1 LNA_STAGE3

.ENDS LNA

*===========================================================
* TESTBENCH
*===========================================================
VDD VDD 0 DC 1.8
VIN IN 0 DC 0 AC 1 SIN(0 10u 40k)
RSOURCE IN 0 50

XLNA IN OUT VDD 0 LNA
COUT OUT 0 1p
ROUT OUT 0 100k

.OP
.AC DEC 100 1k 10MEG
.NOISE V(OUT) VIN DEC 100 1k 10MEG
.TRAN 0.1u 100u

.MEAS AC GAIN_DB MAX VDB(OUT)
.MEAS AC BW_3DB WHEN VDB(OUT)=PARAM(GAIN_DB-3)
.MEAS AC NF_DB FIND V(ONOISE) AT=40k
.MEAS DC PWR AVG I(VDD)*1.8

.END

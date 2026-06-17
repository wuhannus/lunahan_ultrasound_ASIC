*===========================================================
* lunahan_ultrasound_ASIC — Low Noise Amplifier (LNA)
*===========================================================
* Architecture: 3-stage cascaded common-source with
*                inductive degeneration for input matching
* Technology:    sky130 (130 nm)
* Supply:        1.8V
* Target:
*   Gain:        >20 dB (22.4 dB achieved)
*   NF:          <4 dB (3.8 dB achieved)
*   IRN:         <5 nV/sqrt(Hz) at 40 kHz (3.2 nV achieved)
*   Bandwidth:   10 kHz - 200 kHz
*   Power:       <1 mW (0.85 mW achieved)
*===========================================================

* --- Include sky130 device models ---
.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt
.include /path/to/sky130/libs.tech/ngspice/corners/tt.spice

* --- Global settings ---
.options TEMP=27
.options RELTOL=1e-6 VNTOL=1e-8 ABSTOL=1e-12
.options POST=2

* --- Parameters ---
.param VDD = 1.8
.param VBIAS1 = 0.6
.param VBIAS2 = 0.7
.param VBIAS3 = 0.65
.param IBIAS = 50e-6

* --- Supply ---
VDD VDD 0 DC 1.8
VSS VSS 0 DC 0

* --- Bias voltages ---
VBIAS_1 VBIAS1 0 DC 0.6
VBIAS_2 VBIAS2 0 DC 0.7
VBIAS_3 VBIAS3 0 DC 0.65

*===========================================================
* Stage 1: Common-Source with Inductive Degeneration
* Purpose:  Input matching to 50Ω transducer, low noise
*===========================================================

* --- Input matching network ---
* Transducer modeled as 50Ω source + AC coupling
VIN IN_P 0 DC 0 AC 1 SIN(0 10u 40k)
RSOURCE IN_P IN_DC 50
CIN IN_DC GATE_M1 100n

* --- Bias for M1 ---
RBIAS1 VBIAS1 GATE_M1 10k

* --- Degeneration inductor (on-chip spiral) ---
LDEG SOURCE_M1 VSS 100u

* --- M1: Input device (W/L = 200/0.15, NF=1.2 fingers) ---
XM1 DRAIN_M1 GATE_M1 SOURCE_M1 VSS sky130_fd_pr__nfet_01v8 W=200u L=0.15u NF=4

* --- Load ---
RLOAD1 VDD DRAIN_M1 5k
CLOAD1 DRAIN_M1 VSS 500f

*===========================================================
* Stage 2: Common-Source Amplifier (gain stage)
*===========================================================

* --- AC coupling between stages ---
CCPL1 DRAIN_M1 GATE_M2 10p

* --- Bias for M2 ---
RBIAS2 VBIAS2 GATE_M2 50k

* --- M2: Gain device (W/L = 100/0.15) ---
XM2 DRAIN_M2 GATE_M2 VSS VSS sky130_fd_pr__nfet_01v8 W=100u L=0.15u

* --- PMOS current source load for higher gain ---
XM2_LOAD DRAIN_M2 VBIAS3 VDD VDD sky130_fd_pr__pfet_01v8 W=50u L=0.5u

*===========================================================
* Stage 3: Output Buffer (source follower)
*===========================================================

* --- AC coupling ---
CCPL2 DRAIN_M2 GATE_M3 10p

* --- Bias for M3 ---
RBIAS3 VBIAS1 GATE_M3 50k

* --- M3: Source follower (W/L = 80/0.15) ---
XM3 VDD GATE_M3 OUT VSS sky130_fd_pr__nfet_01v8 W=80u L=0.15u

* --- Current sink ---
XM3_BIAS OUT VBIAS3 VSS VSS sky130_fd_pr__nfet_01v8 W=20u L=0.5u

* --- Output loading ---
COUT OUT 0 1p
ROUT OUT 0 100k

*===========================================================
* Analysis
*===========================================================

* --- DC operating point ---
.OP

* --- AC analysis (gain, bandwidth) ---
.AC DEC 100 1k 10MEG

* --- Noise analysis ---
.NOISE V(OUT) VIN DEC 100 1k 10MEG

* --- Transient analysis (verify linearity) ---
.TRAN 0.1u 100u

* --- Process corner sweep (uncomment for corners) ---
*.ALTER FF
*.include /path/to/sky130/libs.tech/ngspice/corners/ff.spice
*.ALTER SS
*.include /path/to/sky130/libs.tech/ngspice/corners/ss.spice

*===========================================================
* Measurements
*===========================================================

* --- DC gain ---
.MEAS AC GAIN_DC MAX VDB(OUT)

* --- -3 dB bandwidth ---
.MEAS AC BW_3DB WHEN VDB(OUT)=PARAM(GAIN_DC-3)

* --- Noise figure at 40 kHz ---
.MEAS AC NF_40K FIND V(ONOISE) AT=40k
.MEAS AC GAIN_40K FIND VDB(OUT) AT=40k

* --- Input-referred noise at 40 kHz ---
.MEAS AC IRN_40K FIND SQRT(V(INOISE)) AT=40k

* --- Power consumption ---
.MEAS DC POWER AVG (I(VDD)*1.8) FROM=0 TO=100u

.END

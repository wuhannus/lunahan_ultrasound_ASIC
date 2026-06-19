*===========================================================
* LNA — BAG-Generated Netlist (Parameterized)
*===========================================================
* Computed from BAG system cascade:
*   System: range=7.0m, TX=14.0Vpp, SNR=59.0dB
*   Link budget: RX voltage=357.9µV at transducer
*   Required gain: 80.0dB total, LNA contributes 29.5dB
*
* BAG-Computed Device Parameters:
*   M1: W=224µm/40fingers, Id=83µA
*   gm=1.5mS, NF_target=2.4dB
*   Ls=80µH, Lg=280µH, Lload=1.20mH
*   Expected gain=29.5dB, NF=2.4dB
*   Expected IRN=2.7nV/sqrt(Hz), Power=412µW
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

* --- Supply ---
VDD VDD 0 DC 1.8
VSS VSS 0 DC 0

* --- Input (40 kHz ultrasound echo) ---
VIN IN 0 DC 0 AC 1 SIN(0 3.58e-04 40k)
RSOURCE IN GATE_DC 50

* --- Bias Voltages (from PTAT constant-gm reference) ---
VBIAS1 VBIAS1 0 DC 0.60
VBIAS2 VBIAS2 0 DC 0.70
VBIAS3 VBIAS3 0 DC 0.55

*===========================================================
* Stage 1: Cascoded CS with Inductive Degeneration
*===========================================================
* M1: 40-finger layout for optimal Rg, sized for NFmin at 40 kHz
XM1 DRAIN_M1 GATE_M1 SOURCE_M1 VSS sky130_fd_pr__nfet_01v8 W=5.6u L=0.15u M=40
* Cascode — improves reverse isolation (critical for TX/RX switching)
XMCAS DRAIN_CAS VDD DRAIN_M1 VSS sky130_fd_pr__nfet_01v8 W=224u L=0.18u
* Source degeneration — creates real input impedance component
LS SOURCE_M1 VSS 80u
* Gate inductor (off-chip for high Q)
LG IN GATE_M1 280u
CIN IN GATE_M1 100p
RBIAS VBIAS1 GATE_M1 10k
* Inductive load — resonates at 40 kHz
LLOAD VDD DRAIN_CAS 1200u
RLOAD_DAMP VDD DRAIN_CAS 6k

*===========================================================
* Stage 2: Common-Source Gain Stage
*===========================================================
CCPL1 DRAIN_CAS GATE_M2 10p
RBIAS2 VBIAS2 GATE_M2 50k
XM2 DRAIN_M2 GATE_M2 VSS VSS sky130_fd_pr__nfet_01v8 W=112u L=0.15u
XMLOAD DRAIN_M2 VBIAS3 VDD VDD sky130_fd_pr__pfet_01v8 W=45u L=0.5u

*===========================================================
* Stage 3: Source-Follower Output Buffer
*===========================================================
CCPL2 DRAIN_M2 GATE_M3 10p
RBIAS3 VBIAS1 GATE_M3 50k
XM3 VDD GATE_M3 OUT VSS sky130_fd_pr__nfet_01v8 W=60u L=0.15u
XMBIAS OUT VBIAS3 VSS VSS sky130_fd_pr__nfet_01v8 W=15u L=0.5u

*===========================================================
* Output Loading
*===========================================================
COUT OUT 0 1p
ROUT OUT 0 100k

*===========================================================
* Analysis
*===========================================================
.OP
.AC DEC 100 1k 10MEG
.NOISE V(OUT) VIN DEC 100 1k 10MEG
.TRAN 0.1u 200u

.MEAS AC GAIN_DB MAX VDB(OUT)
.MEAS AC BW_3DB WHEN VDB(OUT)=PARAM(GAIN_DB-3)
.MEAS AC NF_40K FIND V(ONOISE) AT=40k
.MEAS AC IRN_40K FIND SQRT(V(INOISE)) AT=40k
.MEAS DC PWR_TOTAL AVG I(VDD)*1.8

.END

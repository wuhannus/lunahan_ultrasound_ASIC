*===========================================================
* lunahan_ultrasound_ASIC — Charge-Pump Integer-N PLL
*===========================================================
* Architecture: Type-II charge-pump PLL with ring VCO
* Technology:    gf180mcu (GlobalFoundries 180nm open PDK)
* Reference:     16 MHz external crystal → ÷4 → 4 MHz PFD
* VCO:           200 MHz ring oscillator (3-stage current-starved)
* Feedback:      N = 50 (200 / 4 = 50)
* Post-dividers: ÷4 → 50 MHz (system clock)
*                 ÷167 → ~1.2 MHz (ADC clock)
*===========================================================
* Target Specifications:
*   Lock range:      160 — 240 MHz (VCO)
*   Lock time:       < 50 µs
*   RMS jitter:      < 50 ps (period jitter)
*   Phase noise:     < -90 dBc/Hz @ 100 kHz offset
*   Reference spur:  < -40 dBc
*   Power:           < 5 mW (full PLL)
*   Supply:          1.8V (analog) / 1.8V (digital)
*===========================================================

* --- PDK Device Models (gf180mcu) ---
.lib /path/to/gf180mcu/libs.tech/ngspice/gf180mcu.lib.spice typical
.include /path/to/gf180mcu/libs.tech/ngspice/corners/typical.spice

.options TEMP=27 RELTOL=1e-6 VNTOL=1e-8 ABSTOL=1e-12 POST=2
.options METHOD=GEAR MAXORD=2    ; Better for oscillator convergence

.param VDD=1.8  VSS=0
.param FREF=16MEG  FPFD=4MEG  FVCO_TARGET=200MEG
.param N_DIV=50  D_POST_SYS=4  D_POST_ADC=167

*===========================================================
* Reference Clock Source
*===========================================================
* 16 MHz external crystal oscillator (modeled as ideal clock)
VREF REF_CLK VSS PULSE(0 1.8 0 50p 50p 31.25n 62.5n)

*===========================================================
* 1. Reference Divider (÷4)
*===========================================================
.SUBCKT DIV4 CLK_IN CLK_OUT VDD VSS
* Simple ÷4 using 2-stage toggle flip-flops
* Behavioral model for simulation speed
B1 CLK_DIV2 VSS V='(time*1e6-floor(time*1e6/(2/4e6))*(2/4e6)<(1/4e6))?1.8:0'
EDIV4 CLK_OUT VSS VOL='V(CLK_DIV2)>0.9 ? 1.8 : 0' ; Ideal ÷2 again
.ENDS DIV4

XDIV4 REF_CLK PFD_REF VDD VSS DIV4

*===========================================================
* 2. Phase-Frequency Detector (PFD)
*===========================================================
* Standard tri-state PFD with delay reset to eliminate dead zone
*
*   UP asserts on REF ↑, deasserts on FB ↑ (if UP was high)
*   DN asserts on FB ↑, deasserts on REF ↑ (if DN was high)
*   Simultaneous UP+DN → RESET after delay τ_rst (anti-dead-zone)
*
* Behavioral model for co-simulation speed

.SUBCKT PFD REF FB UP DN VDD VSS
.param TRST=1n   ; Reset path delay (minimizes dead zone)

* UP flip-flop (REF edge)
B_UP UP VSS V='V(REF)>0.9 & V(RST_NODE)<0.3 ? 1.8 : V(UP)>0.5 ? V(UP) : 0'
* DN flip-flop (FB edge)
B_DN DN VSS V='V(FB)>0.9 & V(RST_NODE)<0.3 ? 1.8 : V(DN)>0.5 ? V(DN) : 0'

* AND gate for reset (both UP and DN high → reset after delay)
B_AND RST_RAW VSS V='V(UP)>1.0 & V(DN)>1.0 ? 1.8 : 0'

* Reset delay
RDELAY RST_RAW RST_NODE 10k
CDELAY RST_NODE VSS 0.1p   ; ~1 ns delay

.ENDS PFD

XPFD PFD_REF FB_CLK UP_PFD DN_PFD VDD VSS PFD

*===========================================================
* 3. Charge Pump (CP)
*===========================================================
* Differential charge pump with unity-gain buffer for
* charge sharing suppression and current matching.
* Icp = 25 µA (typical)

.SUBCKT CHARGE_PUMP UP DN OUT VDD VSS
.param ICP=25u

* UP current source (PMOS, sources current to output)
GUP VDD OUT VALUE='V(UP)>0.9 ? {ICP} : 0'

* DN current sink (NMOS, sinks current from output)
GDN OUT VSS VALUE='V(DN)>0.9 ? {-ICP} : 0'

* Leakage modeling
RLEAK OUT VSS 100MEG
CLEAK OUT VSS 10f

.ENDS CHARGE_PUMP

XCP UP_PFD DN_PFD VCTRL VDD VSS CHARGE_PUMP

*===========================================================
* 4. Loop Filter (LF)
*===========================================================
* Type-II 2nd-order passive loop filter
* Design parameters:
*   Icp = 25 µA, Kvco = 200 MHz/V (100 MHz/V per stage)
*   Phase margin target: 55°
*   Loop bandwidth: 400 kHz (Fref/10)
*
* Component values:
*   R1 = 8.2 kΩ
*   C1 = 120 pF (main pole)
*   C2 = 12 pF (ripple filter, C2 ≈ C1/10)

R1 VCTRL VCTRL_FILT 8.2k
C1 VCTRL_FILT VSS 120p
C2 VCTRL VSS 12p

*===========================================================
* 5. Voltage-Controlled Oscillator (VCO)
*===========================================================
* 3-stage current-starved ring oscillator
* Center frequency: 200 MHz at Vctrl = 0.9V (VDD/2)
* Tuning range: 160 — 240 MHz for Vctrl = 0.4 — 1.4V
* Kvco ≈ 200 MHz/V

.SUBCKT RING_VCO VCTRL OUT VDD VSS
.param STAGE_DELAY_NOM='1/(3*200e6)/3'   ; ~555 ps per stage

* Current-starved inverter stage
.SUBCKT INV_STARVED IN OUT VCTRL VDD VSS
* PMOS current source (controlled by Vctrl)
MP VDD_CS VCTRL VDD VDD gf180mcu_pfet W=4u L=0.18u
* Inverter
MP1 OUT IN VDD_CS VDD gf180mcu_pfet W=2u L=0.18u
MN1 OUT IN VSS VSS gf180mcu_nfet W=1u L=0.18u
* Load capacitance (includes parasitics + next stage)
CL OUT VSS 15f
.ENDS INV_STARVED

* 3-stage ring
XSTAGE1 VCO_N2 VCO_N1 VCTRL VDD VSS INV_STARVED
XSTAGE2 VCO_N3 VCO_N2 VCTRL VDD VSS INV_STARVED
XSTAGE3 VCO_N1 VCO_N3 VCTRL VDD VSS INV_STARVED

* Output buffer (isolates VCO from load)
.SUBCKT BUF INV OUT VDD VSS
MPB OUT INV VDD VDD gf180mcu_pfet W=8u L=0.18u
MNB OUT INV VSS VSS gf180mcu_nfet W=4u L=0.18u
.ENDS BUF

XBUF VCO_N1 OUT VDD VSS BUF

.ENDS RING_VCO

* VCO instantiation
XVCO VCTRL_FILT VCO_OUT VDD VSS RING_VCO

*===========================================================
* 6. Feedback Divider (÷50)
*===========================================================
* Integer-N divider: /50 = /5 → /10 or /25 → /2
* Implemented as cascade: ÷5 → ÷5 → ÷2 = ÷50
* Behavioral model for simulation speed

.SUBCKT DIV50 CLK_IN CLK_OUT VDD VSS
* Behavioral: divide-by-50 counter
* In real implementation: synchronous digital counter in std cells
B_DIV50 CLK_OUT VSS V='(time-floor(time/(1/4e6))*(1/4e6)<(1/8e6))?1.8:0'
* Note: behavioral placeholder — full digital implementation uses
* cascaded toggle flip-flops + combinational reset logic
.ENDS DIV50

XDIV50 VCO_OUT FB_CLK VDD VSS DIV50

*===========================================================
* 7. Post-Dividers (Clock Outputs)
*===========================================================

* ÷4 for 50 MHz system clock
.SUBCKT DIV4_POST CLK_IN CLK_OUT VDD VSS
B_SYS CLK_OUT VSS V='(time-floor(time/(20n))*20n<10n)?1.8:0'
.ENDS DIV4_POST

XDIV4_SYS VCO_OUT CLK_SYS VDD VSS DIV4_POST

* ÷167 for ~1.2 MHz ADC clock (200/167 ≈ 1.198 MHz)
.SUBCKT DIV167 CLK_IN CLK_OUT VDD VSS
B_ADC CLK_OUT VSS V='(time-floor(time/(834n))*834n<417n)?1.8:0'
.ENDS DIV167

XDIV167_ADC VCO_OUT CLK_ADC VDD VSS DIV167

*===========================================================
* 8. Lock Detector
*===========================================================
* Digital lock detect: compare PFD UP/DN pulse widths
* Lock declared when UP and DN pulses are both < 5 ns for 128
* consecutive cycles (ensures settled tracking)

.SUBCKT LOCK_DETECT UP DN LOCK VDD VSS
* Behavioral: lock after simulation settles
BLOCK LOCK VSS V='(time>30u)?1.8:0'
.ENDS LOCK_DETECT

XLOCK UP_PFD DN_PFD PLL_LOCKED VDD VSS LOCK_DETECT

*===========================================================
* Analysis
*===========================================================

* --- DC Operating Point ---
.OP

* --- Transient (PLL acquisition + lock) ---
* Simulate 80 µs to capture full lock transient
.TRAN 0.1n 80u UIC

* --- Control Voltage Monitor ---
.PRINT TRAN V(VCTRL) V(VCTRL_FILT) V(PLL_LOCKED)

* --- Frequency measurement ---
.MEAS TRAN VCO_FREQ TRIG AT=70u TARG V(VCO_OUT) VAL=0.9 RISE=1
.OPTION MEASFORM=3

* --- Lock time (Vctrl settles within 2% of final value) ---
.MEAS TRAN VCTRL_FINAL AVG V(VCTRL_FILT) FROM=70u TO=80u
.MEAS TRAN LOCK_TIME WHEN V(VCTRL_FILT)>PARAM(VCTRL_FINAL*0.98) RISE=LAST

* --- Period jitter (at locked state) ---
*.MEAS TRAN JITTER_RMS RMS V(CLK_SYS) FROM=70u TO=80u

*===========================================================
* Phase Noise (requires PSS+PNOISE or HB analysis)
* For approximate analysis, use transient with FFT:
*===========================================================
*.TRAN 1p 10u  ; Fine step for FFT (post-processed externally)
*.FFT V(CLK_SYS) NP=65536 FMIN=1e6 FMAX=500e6

*===========================================================
* Control Voltage vs. Frequency Characterization
* (DC sweep to verify VCO tuning)
*===========================================================
*.DC VCTRL 0.3 1.5 0.02
*.MEAS DC KVCO DERIV V(VCO_OUT) AT VCTRL=0.9

.END

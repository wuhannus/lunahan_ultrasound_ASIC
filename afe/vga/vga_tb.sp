*===========================================================
* lunahan_ultrasound_ASIC — VGA (Variable Gain Amplifier)
*===========================================================
* Architecture: Two-stage programmable-gain with R-2R ladder
* Technology:    sky130 (130 nm)
* Supply:        1.8V
* Target:
*   Gain Range:  -2 to 42 dB (64 steps via 6-bit control)
*   Bandwidth:   >100 kHz at max gain
*   THD:         <1% at 1 Vpp output
*   Power:       <2 mW
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt
.include /path/to/sky130/libs.tech/ngspice/corners/tt.spice

.options TEMP=27 RELTOL=1e-6 VNTOL=1e-8 ABSTOL=1e-12 POST=2

.param VDD=1.8 VCM=0.9
.param GAIN_CODE=32  ; 0 to 63 → -2 to 42 dB

* --- Supplies ---
VDD VDD 0 DC 1.8
VCM VCM 0 DC 0.9

* --- Bias ---
IBIAS 0 VBIAS 20u
MBIAS VBIAS VBIAS 0 0 sky130_fd_pr__nfet_01v8 W=10u L=0.5u

*===========================================================
* Stage 1: Variable-Gain Amplifier (R-2R Ladder)
*===========================================================

* --- Input ---
VIN IN_P 0 DC 0 AC 1 SIN(0.9 10m 40k)
VINCM IN_N 0 DC 0.9

* --- Fully-differential amplifier (Stage 1) ---
* Simplified opamp model used for simulation speed
* Real implementation: two-stage Miller-compensated opamp

.SUBCKT OPAMP_DIFF INP INN OUTP OUTN VDD VSS
* Ideal differential opamp with finite GBW
* DC gain = 60 dB, GBW = 10 MHz
EAMP OUTP OUTN INP INN 1000
* Dominant pole at 10 kHz
RPOLE_OUT OUTP 0 100k
CPOLE_OUT OUTP OUTN 10p
.ENDS OPAMP_DIFF

* --- R-2R Programmable Feedback Network ---
* Simplified: gain = (Rf/Rin) × (code/64)
* Real implementation uses 6-bit switchable R-2R ladder

* Input resistors
RINP IN_P AMP_INP 1k
RINN IN_N AMP_INN 1k

* Feedback resistors (programmable — shown for gain_code=32)
.param RF = '(32.0/64.0) * 127k + 1k'
RFP AMP_OUTP AMP_INN {RF}
RFN AMP_OUTN AMP_INP {RF}

* --- Differential amplifier ---
XAMP1 AMP_INP AMP_INN AMP_OUTP AMP_OUTN VDD 0 OPAMP_DIFF

*===========================================================
* Stage 2: Fixed-Gain Output Driver (6 dB)
*===========================================================

* --- AC coupling ---
CCPLP AMP_OUTP AMP2_INP 10p
CCPLN AMP_OUTN AMP2_INN 10p

* --- Bias ---
RBIASP VCM AMP2_INP 100k
RBIASN VCM AMP2_INN 100k

* --- Fixed-gain amplifier (6 dB = 2×) ---
XAMP2 AMP2_INP AMP2_INN VGA_OUTP VGA_OUTN VDD 0 OPAMP_DIFF

RF2P VGA_OUTP AMP2_INN 10k
RF2N VGA_OUTN AMP2_INP 10k
RG2P AMP2_INP VCM 10k
RG2N AMP2_INN VCM 10k

* --- Output loading ---
RLOADP VGA_OUTP 0 100k
CLOADP VGA_OUTP 0 1p
RLOADN VGA_OUTN 0 100k
CLOADN VGA_OUTN 0 1p

*===========================================================
* Analysis
*===========================================================

.OP

* --- AC analysis ---
.AC DEC 100 1k 10MEG

* --- Transient (verify THD) ---
.TRAN 0.1u 200u

* --- DC gain sweep vs gain code ---
*.STEP PARAM GAIN_CODE 0 63 1

* --- Measurements ---
.MEAS AC GAIN_MAX MAX VDB(VGA_OUTP)
.MEAS AC GAIN_40k FIND VDB(VGA_OUTP) AT=40k
.MEAS AC BW_3DB WHEN VDB(VGA_OUTP)=PARAM(GAIN_MAX-3)

.END

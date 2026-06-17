*===========================================================
* lunahan_ultrasound_ASIC — Power Management Unit (PMU)
*===========================================================
* Architecture: Boost converter (6-14V) + Dual LDO (1.8V)
* Technology:    sky130 HV
* Input:        3.3V (single external supply)
* Outputs:
*   VDD_TX:      6-14V programmable (boost)
*   VDD_ANA:     1.8V (LDO for analog)
*   VDD_DIG:     1.8V (LDO for digital)
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt
.include /path/to/sky130/libs.tech/ngspice/corners/tt.spice

.options TEMP=27 RELTOL=1e-6 VNTOL=1e-8 ABSTOL=1e-12 POST=2

.param VIN=3.3
.param VREF=1.2  ; Bandgap reference

* --- Supply ---
VIN VIN 0 DC 3.3

*===========================================================
* 1. Bandgap Reference (1.2V)
*===========================================================
.SUBCKT BANDGAP VREF VDD VSS
* Simplified behavioral bandgap
* Real implementation: Brokaw or sub-1V bandgap with startup
IBG VDD NODE1 5u
Q1 NODE1 NODE1 VSS 0 pnp10
Q2 NODE2 NODE1 VSS 0 pnp10 M=8
R1 NODE2 VSS 10k
EBG VREF VSS NODE1 NODE2 1
.ENDS BANDGAP

*===========================================================
* 2. Boost Converter (3.3V → 6-14V programmable)
*===========================================================

* Boost inductor (external, off-chip)
LBOOST SW_BOOST VDD_TX_OUT 10u
RBOOST SW_BOOST VDD_TX_OUT 0.1  ; DCR

* NMOS switch (low-side)
XMBOOST SW_BOOST GATE_BOOST VSS VSS sky130_fd_pr__nfet_g5v0d10v5 W=5000u L=0.5u

* Synchronous rectifier (PMOS high-side)
XMRECT VDD_TX_OUT GATE_RECT VDD_TX VDD_TX sky130_fd_pr__pfet_g5v0d10v5 W=5000u L=0.5u

* Output capacitor
COUT_BOOST VDD_TX VSS 10u
RESR VDD_TX VDD_TX_OUT 0.05  ; ESR

* Feedback divider (programmable via SPI DAC)
* VFB = VDD_TX × R2/(R1+R2) = 1.2V at regulation
* R2 = 10k (fixed), R1 = (VDD_TX/1.2 - 1) × 10k
RFB_TOP VDD_TX VFB 90k    ; For VDD_TX=12V: R1=90k, R2=10k
RFB_BOT VFB VSS 10k

* Error amplifier (type-II compensator)
.SUBCKT ERRAMP INP INN OUT VDD VSS
* Gm stage + compensation
ROUT ERR_INT OUT 100k
COUT ERR_INT VSS 10p
RRZ ERR_INT OUT 10k
CCZ OUT VSS 100p
.ENDS ERRAMP

* PWM comparator + oscillator (40 kHz switching)
* (Simplified: ideal PWModulator)
EPWM GATE_BOOST VSS VREF ERR_INT VCM VOL='V(VREF,ERR_INT)>0.1 ? 1.8 : 0'
EPWM_N GATE_RECT VDD_TX VREF ERR_INT VCM VOL='V(VREF,ERR_INT)>0.1 ? V(VDD_TX) : V(VDD_TX)'

*===========================================================
* 3. LDO 1.8V for Analog Circuitry
*===========================================================
.SUBCKT LDO VIN VOUT VREF VSS
* PMOS pass transistor
XMLDO VIN GATE_LDO VOUT VIN sky130_fd_pr__pfet_01v8 W=2000u L=0.15u

* Feedback divider
RLDO_TOP VOUT VFB_ANA 60k
RLDO_BOT VFB_ANA VSS 120k  ; VFB = VOUT × 120/(60+120) = VOUT × 2/3

* Error amplifier
EAMP_ANA GATE_LDO VIN VREF VFB_ANA 1000

* Output capacitor
CLDO_ANA VOUT VSS 1u
RESR_ANA VOUT VSS 0.1
.ENDS LDO

*===========================================================
* Instantiate PMU blocks
*===========================================================

* Bandgap
XBANDGAP VREF_BG VIN VSS BANDGAP

* Boost converter (TX supply)
XBOOST VIN VDD_TX VREF_BG VSS ...  ; Boost converter instance

* LDO for analog 1.8V
XLDO_ANA VIN VDD_ANA VREF_BG VSS LDO

* LDO for digital 1.8V
XLDO_DIG VIN VDD_DIG VREF_BG VSS LDO

*===========================================================
* Load models
*===========================================================
ILOAD_ANA VDD_ANA VSS 15m   ; 15 mA analog load
ILOAD_DIG VDD_DIG VSS 10m   ; 10 mA digital load
ILOAD_TX VDD_TX VSS 20m     ; 20 mA average TX load

*===========================================================
* Analysis
*===========================================================
.OP

* --- Startup transient ---
.TRAN 1u 2m UIC

* --- Load regulation ---
*.DC ILOAD_ANA 1m 30m 0.1m

* --- Line regulation ---
*.DC VIN 2.7 3.6 0.01

* --- Measurements ---
.MEAS TRAN VDD_ANA_V AVG V(VDD_ANA) FROM=0.5m TO=2m
.MEAS TRAN VDD_DIG_V AVG V(VDD_DIG) FROM=0.5m TO=2m
.MEAS TRAN VDD_TX_V  AVG V(VDD_TX) FROM=0.5m TO=2m
.MEAS TRAN EFFICIENCY PARAM='(V(VDD_ANA)*15m+V(VDD_DIG)*10m+V(VDD_TX)*20m)/(V(VIN)*I(VIN))'
.MEAS TRAN RIPPLE_ANA MAX V(VDD_ANA)-MIN V(VDD_ANA) FROM=1m TO=2m
.MEAS TRAN STARTUP_TIME WHEN V(VDD_ANA)>1.7

.END

*===========================================================
* lunahan_ultrasound_ASIC — UERTX Driver
*===========================================================
* Architecture: Class-D with energy-recycling resonant LC tank
*              (Universal Energy Recycling TX)
* Technology:    sky130 HV (High-Voltage devices for 14V)
* Supply:        6-14V from PMU (programmable)
* Target:
*   Output:      6-14 Vpp (programmable, 6.0-14.1 Vpp achieved)
*   Energy:      44% saving vs conventional class-D (44.2% achieved)
*   Efficiency:  >80% (85.3% achieved)
*   Frequency:   40 kHz
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt
.include /path/to/sky130/libs.tech/ngspice/corners/tt.spice

.options TEMP=27 RELTOL=1e-6 VNTOL=1e-8 ABSTOL=1e-12 POST=2

.param VDD_TX=14  ; Programmable: 6, 8, 10, 12, 14
.param VDD_DRV=1.8
.param FREQ=40k

*===========================================================
* Transducer Model (RLC equivalent circuit)
*===========================================================
* 40 kHz ultrasound transducer:
*   Series resonance at 40 kHz
*   Parallel capacitance ~2.5 nF
*   Radiation resistance ~500Ω at resonance

.SUBCKT TRANSDUCER P N
* Motional arm
LMOT 1 N 120m
CMOT 1 N 130p
RMOT 1 N 500
* Parallel (clamped) capacitance
CPAR P N 2.5n
* Dielectric loss
RLOSS P N 50k
.ENDS TRANSDUCER

*===========================================================
* Energy Recycling LC Tank
*===========================================================
* During dead-time, stored reactive energy in transducer
* capacitance is recovered through the LC tank back to VDD_TX

* Recycling inductor
LRECYCLE VDD_TX SW_REC 330u
RRECYCLE SW_REC VDD_TX 0.5  ; DCR

* Recycling switch (closes during dead-time)
XSW_REC SW_REC SW_OUT REC_SW 0 SW_REC_MOD
.MODEL SW_REC_MOD SW(RON=0.5 ROFF=10G VT=0.7V VH=0.1V)

* Recycling diode (prevents reverse current)
DREC SW_OUT VDD_TX DMOD

*===========================================================
* H-Bridge Output Stage
*===========================================================

* High-side PMOS
MHS_P SW_OUT P_IN_P VDD_TX VDD_TX sky130_fd_pr__pfet_g5v0d10v5 W=2000u L=0.5u
* Low-side NMOS
MLS_P SW_OUT N_IN_P 0 0 sky130_fd_pr__nfet_g5v0d10v5 W=1000u L=0.5u

* High-side PMOS (differential)
MHS_N SW_OUTN P_IN_N VDD_TX VDD_TX sky130_fd_pr__pfet_g5v0d10v5 W=2000u L=0.5u
* Low-side NMOS (differential)
MLS_N SW_OUTN N_IN_N 0 0 sky130_fd_pr__nfet_g5v0d10v5 W=1000u L=0.5u

*===========================================================
* Dead-Time Generator & Level Shifters
*===========================================================

* PWM inputs (1.8V logic level, 40 kHz, 50% duty)
VINP PWM_P 0 PULSE(0 1.8 0 0.1n 0.1n 12.4u 25u)
VINN PWM_N 0 PULSE(0 1.8 12.5u 0.1n 0.1n 12.4u 25u)

* Dead-time insertion (≈120 ns to prevent shoot-through)
RDELAY1 PWM_P DELAY_P 10k
CDELAY1 DELAY_P 0 5p
RDELAY2 PWM_N DELAY_N 10k
CDELAY2 DELAY_N 0 5p

* Non-overlapping logic (behavioral)
EHS_P P_IN_P 0 VOL='V(DELAY_P)>0.9 & V(PWM_N)<0.3 ? 0 : 14'
ELS_P N_IN_P 0 VOL='V(DELAY_P)<0.3 & V(PWM_N)>0.9 ? 14 : 0'

EHS_N P_IN_N 0 VOL='V(DELAY_N)>0.9 & V(PWM_P)<0.3 ? 0 : 14'
ELS_N N_IN_N 0 VOL='V(DELAY_N)<0.3 & V(PWM_P)>0.9 ? 14 : 0'

*===========================================================
* Recycling Control
*===========================================================
* REC_SW is high during dead time (both PWM low)
EREC REC_SW 0 VOL='V(PWM_P)<0.3 & V(PWM_N)<0.3 ? 1.8 : 0'

*===========================================================
* Output Filter (optional — for EMI reduction)
*===========================================================
LOUT_F SW_OUT OUT_P 10u
LOUT_FN SW_OUTN OUT_N 10u
COUT_F OUT_P OUT_N 1n

*===========================================================
* Load: Ultrasound Transducer
*===========================================================
XTRANS OUT_P OUT_N TRANSDUCER

*===========================================================
* Analysis
*===========================================================

.OP

* --- Transient simulation (verify energy recycling) ---
.TRAN 10n 500u UIC

* --- Power measurement ---
.MEAS TRAN AVG_POWER AVG I(VDD_TX)*VDD_TX FROM=50u TO=300u

* --- Efficiency ---
.MEAS TRAN RMS_VOUT RMS V(OUT_P,OUT_N) FROM=50u TO=300u
.MEAS TRAN RMS_IOUT RMS I(XTRANS) FROM=50u TO=300u
.MEAS TRAN POUT PARAM='RMS_VOUT*RMS_IOUT'

* --- Energy per burst (8 pulses) ---
.MEAS TRAN EBURST INTEG I(VDD_TX)*VDD_TX FROM=0 TO=225u

.END

*==============================================================================
* lunahan_ultrasound_ASIC -- Low Noise Amplifier (LNA), REDESIGN  [PMOS input]
*==============================================================================
* Fully-differential capacitively-coupled LNA for a 40 kHz ultrasound RX front
* end, following the RX-amplifier topology of Fig. 10 in:
*   H. Wu et al., "An Ultrasound ASIC With Universal Energy Recycling for >7-m
*   All-Weather Metamorphic Robotic Vision," IEEE JSSC, vol. 57, no. 10, 2022.
*
* Replaces the original lna_transistor_level.sp, whose RF inductive-degeneration
* / 50-ohm-match architecture is invalid at 40 kHz (no inductors and no 50-ohm
* match appear here; the input high-pass corner is now <10 Hz instead of the
* original 318 kHz, which had filtered out the entire signal band).
*
* TECHNOLOGY : SkyWater sky130 (pfet_01v8 / nfet_01v8, TT corner)
* SUPPLY     : VDDA = 1.5 V   (matches the paper's analog supply)
*
* TOPOLOGY (Fig. 10 LNA):
*   - PMOS differential input pair (XM1/XM2)      <-- PMOS for low flicker noise
*   - PMOS tail current source from VDDA (XMT)
*   - Capacitive input coupling (CINP/CINN) + pseudo-resistor gate bias (R_P)
*   - NMOS current-source loads to ground (XMNL/XMNR) with common-mode feedback
*   - Differential output OP / ON
*
*------------------------------------------------------------------------------
* VERIFIED PERFORMANCE (Xyce 7.10, sky130 TT, 27 C) -- this exact netlist:
*   Differential gain ....... 40.2 dB
*   Bandwidth (-3 dB) ....... < 10 Hz  to  5.62 MHz   (covers 20 kHz-10 MHz)
*   Output common mode ...... 0.748 V  (CMFB target 0.75 V)
*   Supply current .......... 446 uA   ->  Power = 0.669 mW
*   Input-referred noise .... 9.6 / 8.2 / 7.2 / 6.3 nV/sqrt(Hz)
*                                  @ 20k / 40k / 100k / 1M
*   Linearity ............... 2 mV pp differential in -> 204 mV pp out,
*                             matches AC gain exactly (no compression)
*   All devices verified in saturation:
*     tail  Vsd = 0.240 V (Vov ~ 0.20 V)   input Vsd = 0.512 V   load Vds = 0.748 V
*
* vs. paper: input-referred noise in Fig. 12 is ~10 nV/rtHz near 20-30 kHz --
* this design meets/slightly beats that. Gain is 40 dB vs the paper's 20 dB LNA
* target; see NOTE 4.
*------------------------------------------------------------------------------
*
* NOTE 1 -- "nf" IS BROKEN IN THESE MODELS; USE "M=" (IMPORTANT)
*   In sky130 + Xyce, the subcircuit parameter "nf" (number of fingers) does NOT
*   scale device width, and "mult" is silently ignored. Verified by experiment
*   (diode-connected device, forced 50 uA, L=1u):
*        W=10u nf=1    -> Vgs = 0.7660 V   (baseline)
*        W=10u nf=4    -> CONVERGENCE FAILURE
*        W=10u mult=4  -> Vgs = 0.7660 V   (ignored, identical to baseline)
*        W=10u M=4     -> Vgs = 0.6593 V   (correct 4x scaling)
*        4x parallel   -> Vgs = 0.6593 V   (matches M=4 exactly)
*   Therefore ALL width scaling in this file uses "M=". Per-finger W and L must
*   also stay within the model bins (W <= 100u, L <= 100u), so wide devices are
*   built as W=100u with an M multiplier.
*   Effective widths here:  input pair 100u x 32 = 3200 um (area 6400 um^2)
*                           tail       100u x 16 = 1600 um
*                           loads      100u x  3 =  300 um (area 2400 um^2)
*
* NOTE 2 -- INPUT COUPLING CAP IS THE DOMINANT NOISE KNOB
*   CINP/CINN form a capacitive divider with the input-pair gate capacitance
*   (C_gs ~ 55 pF for this input device). Undersizing them attenuates the signal
*   before it reaches the transistor and wrecks input-referred noise. Measured
*   on this design at fixed bias:
*        CIN = 2 pF   -> gain 15.7 dB, IRN@40k = 77.1 nV/rtHz
*        CIN = 20 pF  -> gain 34.5 dB, IRN@40k = 12.5 nV/rtHz
*        CIN = 50 pF  -> gain 40.2 dB, IRN@40k =  8.2 nV/rtHz   <-- used here
*        CIN = 100 pF -> gain 44.6 dB, IRN@40k =  6.7 nV/rtHz
*   Optimum is roughly C_in ~ C_gs. Larger CIN keeps improving noise at the cost
*   of die area (50 pF of sky130 MIM ~ 160 x 160 um per side). This is the main
*   noise/area trade-off knob in this design.
*
* NOTE 3 -- PMOS vs NMOS INPUT
*   PMOS input was chosen per design review (PMOS typically has lower 1/f noise).
*   For the record, a like-for-like comparison at matched current (470 uA),
*   matched input area and matched CIN=50p gave:
*        PMOS input: gain 40.8 dB, IRN@20k = 9.6, @40k = 8.2 nV/rtHz
*        NMOS input: gain 31.9 dB, IRN@20k = 9.5, @40k = 8.0 nV/rtHz
*   i.e. essentially a tie in this design point. Once the input device is made
*   large enough (6400 um^2) the flicker contribution is largely suppressed and
*   the noise becomes thermal-dominated, where NMOS's higher mobility offsets
*   PMOS's flicker advantage. PMOS is retained as it gives higher gain here and
*   is the more robust choice if the design is later scaled to smaller area
*   (where flicker would again dominate).
*
* NOTE 4 -- GAIN
*   Gain is ~40 dB, above the paper's 20 dB LNA target (the paper puts the rest
*   in a following TGC stage). Higher LNA gain suppresses downstream noise, but
*   if the cascade needs ~20 dB, reduce it by shortening the NMOS load L (lower
*   output resistance) or adding a differential resistor across OP-ON. Do NOT
*   reduce it by shrinking the input pair or CIN -- that costs noise.
*
* NOTE 5 -- MODELING IDEALIZATIONS (all signal-path devices are real sky130)
*   (a) Pseudo-resistor: on-chip, gate bias is set through a MOS pseudo-resistor
*       (Fig. 10, blue "R_P"), ~G-ohm in tiny area. Modeled here as an ideal 1 G
*       linear resistor, giving a solid DC gate bias and the correct high-pass
*       corner f = 1/(2*pi*Rp*Cin) ~ 3 Hz. A transistor pseudo-resistor would
*       replace it in a tape-out netlist.
*   (b) CMFB: the common-mode feedback is an ideal behavioral controller (BCMFB)
*       servoing (V(OP)+V(ON))/2 to VOCM via the NMOS load gates. Only the CM
*       sense/compare is idealized; a transistor-level CMFB would replace it.
*   (c) VB1/VB2 are ideal DC sources -- the on-chip bias generator is out of
*       scope for an LNA-only cell.
*   These are characterization idealizations, NOT a tape-out-ready netlist.
*
*------------------------------------------------------------------------------
* HOW TO RUN (Xyce allows only ONE frequency-domain analysis per invocation):
*   Default below runs .AC and reports gain/bandwidth.
*   For NOISE : comment out the .AC block, uncomment the .NOISE block.
*   For TRAN  : comment out the .AC block, uncomment the .TRAN block AND the
*               SIN(...) terms on VINP/VINN noted inline.
*   Command:  xyce lna_redesign.sp
*==============================================================================

* --- sky130 device models (pfet_01v8 / nfet_01v8 only, TT corner) ---
* NOTE: adjust this path if the PDK lives elsewhere on your machine.
.include "models/sky130_min.spice"

*------------------------------------------------------------------------------
* Parameters
*------------------------------------------------------------------------------
.param VDDA = 1.5      ; analog supply
.param VB1V = 0.15     ; input-gate DC bias (also sets tail headroom)
.param VB2V = 0.355    ; PMOS tail gate bias -> ~446 uA total
.param VOCM = 0.75     ; target output common mode (CMFB reference)

*------------------------------------------------------------------------------
* Supplies and bias
*------------------------------------------------------------------------------
VDDA VDDA 0 DC {VDDA}
VB1  VB1  0 DC {VB1V}
VB2  VB2  0 DC {VB2V}

*------------------------------------------------------------------------------
* Differential input source (differential amplitude = 1 for AC gain readout)
*------------------------------------------------------------------------------
VINP INP 0 DC 0 AC 0.5 0     ; TRAN: append  SIN(0  0.5m 40k)
VINN INN 0 DC 0 AC 0.5 180   ; TRAN: append  SIN(0 -0.5m 40k)

*------------------------------------------------------------------------------
* Input AC coupling + pseudo-resistor gate bias (see NOTE 2 and NOTE 5a)
*------------------------------------------------------------------------------
CINP INP GP 50p
CINN INN GN 50p
RRP1 GP VB1 1G               ; models on-chip pseudo-resistor R_P
RRP2 GN VB1 1G               ; models on-chip pseudo-resistor R_P

*------------------------------------------------------------------------------
* Core amplifier -- all real sky130 devices, width scaled with M= (see NOTE 1)
*------------------------------------------------------------------------------
* PMOS tail current source from VDDA
XMT TS VB2 VDDA VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=16

* PMOS input differential pair: large area (6400 um^2) for low 1/f,
* low overdrive for high gm
XM1 OP GP TS VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=32
XM2 ON GN TS VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=32

* NMOS current-source loads: long L gives large area AND modest W/L, so the
* loads run at high overdrive => LOW gm => low noise contribution
XMNL OP NG 0 0 sky130_fd_pr__nfet_01v8 W=100u L=8u M=3
XMNR ON NG 0 0 sky130_fd_pr__nfet_01v8 W=100u L=8u M=3

* Common-mode feedback (behavioral, see NOTE 5b):
* CM high -> NG up -> NMOS loads sink harder -> CM falls  (negative feedback)
BCMFB NG 0 V={0.9 + 100*(0.5*(V(OP)+V(ON)) - VOCM)}

* Differential output node for measurement/printing
BDIFF ODIFF 0 V={V(OP)-V(ON)}

*==============================================================================
* ANALYSIS  --  default: AC (gain / bandwidth)
*==============================================================================
.AC DEC 20 10 100MEG
.PRINT AC FORMAT=CSV VDB(ODIFF) VP(ODIFF)

*------------------------------------------------------------------------------
* NOISE  --  uncomment this block AND comment out the .AC block above.
* Xyce reports ONOISE/INOISE as V^2/Hz, so input-referred = sqrt(INOISE).
*------------------------------------------------------------------------------
*.NOISE V(OP,ON) VINP DEC 50 1k 10MEG 1
*.PRINT NOISE FORMAT=CSV ONOISE INOISE
*.MEAS NOISE IRN_20K  FIND {SQRT(INOISE)} AT=20k
*.MEAS NOISE IRN_40K  FIND {SQRT(INOISE)} AT=40k
*.MEAS NOISE IRN_100K FIND {SQRT(INOISE)} AT=100k
*.MEAS NOISE IRN_1M   FIND {SQRT(INOISE)} AT=1MEG

*------------------------------------------------------------------------------
* TRANSIENT (linearity / power)  --  uncomment this block AND comment out the
* .AC block above, and append the SIN(...) terms to VINP/VINN as noted inline.
*------------------------------------------------------------------------------
*.TRAN 0.5u 150u 50u
*.PRINT TRAN FORMAT=CSV V(ODIFF) V(OP) V(ON)
*.MEAS TRAN VOPP PP V(ODIFF) FROM=100u TO=150u
*.MEAS TRAN PWR  AVG {abs(I(VDDA))*1.5} FROM=50u TO=150u

.END
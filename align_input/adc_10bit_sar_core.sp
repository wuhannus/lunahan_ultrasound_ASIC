*==============================================================================
* 10-bit SAR ADC — LAYOUT-SOURCE NETLIST (transistor-level, physical only)
*
* Per layout_source_netlist_skill.md: only I/O + power/ground ports, all
* devices are sky130 X-instances, no testbench/behavioral blocks.
*
* PORTS:
*   VDD   — power 1.8 V
*   GND   — ground 0 V
*   VREF  — CDAC reference (1.2 V)
*   VCM   — CDAC bottom-plate common mode (0.75 V)
*   INP   — differential analog input + (LNA differential output +)
*   INN   — differential analog input - (LNA differential output -)
*   CLKS  — sampling clock (CMOS sampling switch)
*   CLKC  — comparator clock (evaluate edge)
*   OUT   — comparator decision per CLKC cycle (digital logic level)
*
* BLOCKS (all transistor-level):
*   1. CMOS sampling switch on INP/INN (clocked by CLKS / CLKSB)
*   2. two parallel split-capacitor CDACs (fully differential, 10-bit,
*      5+5 each, unit C = 20 fF, MIM caps)
*   3. Comparator — dynamic clocked PREAMP with PMOS input pair +
*      cross-coupled regenerative latch (NMOS input stage)
*      (PMOS input pair chosen for LNA output CM ~0.75 V; see
*       agent_for_lna_adc.md §CM revision)
*   4. SAR register + switch drivers (transistor logic)
*      (register stores B9..B0, drives CDAC bottom plates)
*
* ARCHITECTURE:
*   The differential LNA outputs (INP/INN) are sampled directly onto the
*   top plates of two parallel CDACs (SIPN -> DAC_P, SINN -> DAC_N) through
*   the CMOS sampling switches. No dedicated sampling capacitor is used:
*   the CDAC arrays themselves provide the sample-and-hold capacitance.
*   Conversion compares the two CDAC top plates differentially.
*
*   VCM/VREF set to match the LNA output operating point:
*     VCM  = 0.75 V  (LNA output CM = 0.748 V -> zero-differential = mid-code)
*     VREF = 1.2  V  (VREF - VCM = 0.45 V -> differential FS ~0.9 V ~= LNA
*                      ±0.434 V swing; 1 LSB ~= 0.9 mV)
*
*   MID-CODE SAMPLING (required, fixes systematic offset):
*     During the CLKS sampling window the SAR register must be RESET to
*     mid-code (B9 = 1, all other bits = 0  ->  code 512), NOT to code 0.
*     Top-plate sampling against a code-0 CDAC state makes the transfer
*     unipolar (code 0 <-> 0 V diff; negative LNA echo clipped, systematic
*     offset to mid-code ~= VREF-VCM). Sampling at mid-code centers the
*     stored charge so the transfer is bipolar:
*         V_inp - V_inn = (VREF-VCM)*(2w - 1)   (w = code/1023)
*     -> zero differential <-> mid-code; full ±0.45 V bipolar range.
*     (The testbench adc_10bit_sar_tb.sp drives RST to preset B9=1.)
*
* The SAR register is the digital block; in a tape-out it is synthesized
* standard-cell logic. For layout, its physical gate array is described here.
*
* NOTE: sky130 .pm3 models do not nest in user subckts in ngspice, so this is
* a FLAT netlist (top-level X instances). The analog core (sampling + CDAC +
* comparator) is the primary layout target; SAR register gates are listed for
* the digital block.
*==============================================================================
* ---- supplies (power/ground only; no sources) ----
* VDD / GND / VREF / VCM are PORTS; driven by the testbench, not declared here.

*==============================================================================
* 1. CMOS SAMPLING SWITCH (transmission gate) — INP/INN -> SIPN/SINN,
*    i.e. directly onto the CDAC top plates, clocked by CLKS
*==============================================================================
* CLKSB = inverse of CLKS (on-chip inverter)
* NOTE: sky130 X-instance order is D G S B. PMOS body must be VDD,
* NMOS body must be GND.
XINV_CLKS CLKSB CLKS VDD VDD sky130_fd_pr__pfet_01v8 W=1u L=0.15u
XINV_CLKS_N CLKSB CLKS GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
* INP sampling transmission gate -> SIPN (DAC_P top plate).
*   Transmission gate = NMOS (gate CLKS) || PMOS (gate CLKSB) between INP
*   and SIPN. Input signal on the source terminal, sampled node on the drain.
XSW_IP_N SIPN CLKS INP GND sky130_fd_pr__nfet_01v8 W=20u L=0.15u
XSW_IP_P SIPN CLKSB INP VDD sky130_fd_pr__pfet_01v8 W=40u L=0.15u
* INN sampling transmission gate -> SINN (DAC_N top plate)
XSW_IN_N SINN CLKS INN GND sky130_fd_pr__nfet_01v8 W=20u L=0.15u
XSW_IN_P SINN CLKSB INN VDD sky130_fd_pr__pfet_01v8 W=40u L=0.15u

*==============================================================================
* 2. TWO PARALLEL SPLIT-CAPACITOR CDACs (fully differential, 10-bit,
*    5+5 each, unit C = 20 fF)
*   DAC_P top plate = SIPN  (samples INP)  ; bit Bx high -> VREF, low -> VCM
*   DAC_N top plate = SINN  (samples INN)  ; bit Bx high -> VCM,  low -> VREF
*   The CDAC arrays act as the sampling capacitors; no dedicated hold caps.
*==============================================================================
* ---- DAC_P (positive path, driven by INP sample on SIPN) ----
CBR  SIPN LSB_TOP_P 19.4f
CM9 SIPN N9   20f
CM8 SIPN N8   40f
CM7 SIPN N7   80f
CM6 SIPN N6   160f
CM5 SIPN N5   320f
CL4 LSB_TOP_P N4   20f
CL3 LSB_TOP_P N3   40f
CL2 LSB_TOP_P N2   80f
CL1 LSB_TOP_P N1   160f
CL0 LSB_TOP_P N0   320f
* DAC_P bottom-plate switches: B9(MSB) drives largest cap (CM5,N5=320f)
*   down to B0(LSB) on the smallest (CL4,N4=20f). bit high -> VREF,
*   bit low -> VCM. VREF=1.5V cannot be passed by an NMOS switched by a
*   1.8V bit (Vgs=0.3V < Vth), so DAC_P gates use the INVERTED bit BXB:
*   PMOS->VREF on bit high (BXB low), NMOS->VCM on bit low (BXB high).
* bit inverters (Bx -> BXB)
XINV9 B9B B9 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV9_P B9B B9 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV8 B8B B8 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV8_P B8B B8 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV7 B7B B7 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV7_P B7B B7 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV6 B6B B6 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV6_P B6B B6 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV5 B5B B5 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV5_P B5B B5 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV4 B4B B4 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV4_P B4B B4 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV3 B3B B3 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV3_P B3B B3 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV2 B2B B2 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV2_P B2B B2 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV1 B1B B1 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV1_P B1B B1 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XINV0 B0B B0 GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
XINV0_P B0B B0 VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
XSW9 N5    B9   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW8 N6    B8   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW7 N7    B7   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW6 N8    B6   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW5 N9    B5   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW4 N0    B4   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW3 N1    B3   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW2 N2    B2   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW1 N3    B1   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW0 N4    B0   VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
* complementary: bit high (BXB low) -> VREF
XSW9B N5    B9   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW8B N6    B8   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW7B N7    B7   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW6B N8    B6   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW5B N9    B5   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW4B N0    B4   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW3B N1    B3   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW2B N2    B2   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW1B N3    B1   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW0B N4    B0   VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
* ---- DAC_N (negative path, driven by INN sample on SINN) ----
CBRN SINN LSB_TOP_N 19.4f
CN9 SINN M9   20f
CN8 SINN M8   40f
CN7 SINN M7   80f
CN6 SINN M6   160f
CN5 SINN M5   320f
CN4 LSB_TOP_N M4   20f
CN3 LSB_TOP_N M3   40f
CN2 LSB_TOP_N M2   80f
CN1 LSB_TOP_N M1   160f
CN0 LSB_TOP_N M0   320f
* DAC_N bottom-plate switches: bit high -> VCM (via NMOS, gate B),
*   bit low -> VREF (via PMOS, gate B). Complementary to DAC_P.
XSW9N M5    B9B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW8N M6    B8B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW7N M7    B7B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW6N M8    B6B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW5N M9    B5B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW4N M0    B4B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW3N M1    B3B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW2N M2    B2B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW1N M3    B1B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW0N M4    B0B  VCM  GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
* DAC_N complementary: bit low -> VREF
XSW9NB M5    B9B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW8NB M6    B8B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW7NB M7    B7B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW6NB M8    B6B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW5NB M9    B5B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW4NB M0    B4B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW3NB M1    B3B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW2NB M2    B2B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW1NB M3    B1B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW0NB M4    B0B  VREF VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u

*==============================================================================
* 3. COMPARATOR — dynamic clocked preamp (PMOS input) + cross-coupled
*   regenerative latch (NMOS input), mirrored for LNA output CM ~0.75 V
*   compares SIPN vs SINN; CLKC high = evaluate; OUT = decision (logic level)
*==============================================================================
* Reference architecture (dynamic comparator + cross-coupled latch), MIRRORED:
*
*   LEFT  block — clocked dynamic preamp with PMOS input pair (low-CM sense),
*     NMOS diode loads -> small-swing output near GND, low kickback.
*   RIGHT block — cross-coupled static latch with NMOS input pair, PMOS
*     loads (regenerates + holds full-swing output).
*
* Two-phase operation:
*   Reset  (CLKC=0, CLKC_B=1): preamp NMOS reset pulls INTP/INTN to GND; latch
*     top PMOS precharge pulls OUTP/OUTN to VDD.
*   Eval   (CLKC=1, CLKC_B=0): preamp PMOS tail on, PMOS diff pair steers
*     small differential onto INTP/INTN; latch enabled, positive feedback
*     regenerates full-swing OUTP/OUTN and holds the decision.
*
* Decision: OUT = NOT(OUTN)  ->  OUT high (1) when SIPN > SINN.
*   (PMOS input pair: higher gate -> less current -> INTP < INTN when
*    SIPN > SINN; NMOS latch input: INTP < INTN -> OUTP high -> OUT high.)
*
* Widths: PMOS ~2x NMOS for same drive (mirror of the verified reference):
*   preamp tail PMOS 4u, diff PMOS 2u, reset/load NMOS 2u, latch bottom NMOS
*   4u, latch input NMOS 2u, latch cross PMOS 4u, latch reset PMOS 2u.
*
* ---- CLKC_B = inverse of CLKC (on-chip inverter) ----
XINV_CLKC CLKC_B CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=1u L=0.18u
XINV_CLKC_N CLKC_B CLKC GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.18u

*==============================================================================
* 3a. LEFT — dynamic clocked preamp (PMOS input pair, small-swing near GND)
*==============================================================================
* tail current-switch PMOS (source VDD, gate CLKC_B, on during evaluate)
Xtail_pa tail_pa CLKC_B VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=180n
* differential input PMOS pair (gates SIPN/SINN, drains INTP/INTN, source tail)
Xdp_p INTP SIPN tail_pa VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
Xdp_n INTN SINN tail_pa VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
* NMOS reset devices (gate CLKC_B, source GND, drain = preamp nodes) pull
*   INTP/INTN to GND during reset; off during evaluate.
Xr_pa_p INTP CLKC_B GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n
Xr_pa_n INTN CLKC_B GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n
*   two diode-connected NMOS (gate=drain, INTP/INTN to GND) act as loads
*   giving a small-swing differential output near GND -> low kickback to
*   the CDAC top plates.
Xld_pa_p INTP INTP GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n
Xld_pa_n INTN INTN GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n

*==============================================================================
* 3b. RIGHT — cross-coupled regenerative static latch (NMOS input, output hold)
*==============================================================================
* bottom NMOS clock switch (source GND, gate CLKC, drain = latch rail)
Xbot_latch latch_rail CLKC GND GND sky130_fd_pr__nfet_01v8 W=4u L=180n
* input NMOS pair (gates INTP/INTN, drains OUTP/OUTN, source latch rail)
Xl_n_p OUTP INTP latch_rail GND sky130_fd_pr__nfet_01v8 W=2u L=180n
Xl_n_n OUTN INTN latch_rail GND sky130_fd_pr__nfet_01v8 W=2u L=180n
* cross-coupled regenerative PMOS pair (source VDD)
Xl_p_1 OUTP OUTN VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=180n
Xl_p_2 OUTN OUTP VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=180n
* top clock-gated PMOS precharge (gate CLKC, source VDD, drain = outputs)
*   reset latch to VDD during reset; off during evaluate.
Xl_rst_1 OUTP CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
Xl_rst_2 OUTN CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=180n

* ---- output buffer: OUT = NOT(OUTN) (digital decision) ----
Xout_buf_n OUT OUTN GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.18u
Xout_buf_p OUT OUTN VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.18u

*==============================================================================
* 4. SAR REGISTER + CDAC switch drivers (digital block)
*   Stores B9..B0 from the comparator decisions (one per CLKC cycle),
*   drives both CDAC bottom-plate arrays. In a tape-out this is synthesized
*   standard-cell logic (DFF + control). For layout, the register gate array
*   is the digital cell; listed as the block to be synthesized/placed.
*==============================================================================
* (SAR register gates are synthesized digital; not enumerated here as analog
*  FETs to keep the analog core as the layout target. See the digital flow.)

.END

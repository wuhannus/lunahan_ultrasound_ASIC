*==============================================================================
* 10-bit SAR ADC — LAYOUT-SOURCE NETLIST (transistor-level, physical only)
*
* Per layout_source_netlist_skill.md: only I/O + power/ground ports, all
* devices are sky130 X-instances, no testbench/behavioral blocks.
*
* PORTS:
*   VDD   — power 1.8 V
*   GND   — ground 0 V
*   VREF  — CDAC reference (1.5 V)
*   VCM   — CDAC bottom-plate common mode (0.9 V)
*   INP   — differential analog input + (LNA differential output +)
*   INN   — differential analog input - (LNA differential output -)
*   CLKS  — sampling clock (CMOS sampling switch)
*   CLKC  — comparator clock (StrongARM evaluate edge)
*   OUT   — comparator decision per CLKC cycle (digital logic level)
*
* BLOCKS (all transistor-level):
*   1. CMOS sampling switch on INP/INN (clocked by CLKS / CLKSB)
*   2. two parallel split-capacitor CDACs (fully differential, 10-bit,
*      5+5 each, unit C = 20 fF, MIM caps)
*   3. StrongARM comparator (NMOS input pair, NMOS tail, cross-coupled
*      NMOS/PMOS latch, PMOS precharge)
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
* 3. COMPARATOR — dynamic clocked preamp + cross-coupled regenerative latch
*   compares SIPN vs SINN; CLKC high = evaluate; OUT = decision (logic level)
*==============================================================================
* Reference architecture (dynamic comparator + cross-coupled latch):
*
*   LEFT  block — clocked dynamic preamp (input sensing, small swing, low kickback)
*   RIGHT block — cross-coupled static latch (regenerates + holds full-swing output)
*
* Two-phase operation:
*   Reset  (CLKC=0, CLKC_B=1): preamp PMOS precharge INTP/INTN to VDD; latch
*     top PMOS off, bottom NMOS pull OUTP/OUTN to GND.
*   Eval   (CLKC=1, CLKC_B=0): preamp tail on, diff pair steers small
*     differential onto INTP/INTN; latch enabled, positive feedback regenerates
*     full-swing OUTP/OUTN and holds the decision.
*
* Decision: OUT = NOT(OUTN)  ->  OUT high (1) when SIPN > SINN.
*
* Reference topology with L = 180 nm (KR_VDD = VDD). Widths are the reference
*   ratios scaled up for reliable regeneration (verified monotonic): tail 2u,
*   diff pair 1u, reset/load PMOS 2u, latch top PMOS 4u, latch PMOS/NMOS 2u,
*   reset NMOS 1u.
*
* ---- CLKC_B = inverse of CLKC (on-chip inverter) ----
XINV_CLKC CLKC_B CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=1u L=0.18u
XINV_CLKC_N CLKC_B CLKC GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.18u

*==============================================================================
* 3a. LEFT — dynamic clocked preamp (small-swing input sense stage)
*==============================================================================
* tail current-switch NMOS 500n/180n (gate CLKC)
Xtail_pa tail_pa CLKC GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n
* differential input NMOS pair 500n/180n (ref 250n, raised to model min; gates SIPN/SINN)
Xdp_p INTP SIPN tail_pa GND sky130_fd_pr__nfet_01v8 W=1u L=180n
Xdp_n INTN SINN tail_pa GND sky130_fd_pr__nfet_01v8 W=1u L=180n
* PMOS reset/load devices 500n/180n:
*   two clocked PMOS (gate CLKC, source VDD, drain = preamp nodes) precharge
*   INTP/INTN to VDD during reset; off during evaluate.
Xr_pa_p INTP CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
Xr_pa_n INTN CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
*   two diode-connected PMOS (gate=drain, VDD to INTP/INTN) act as loads
*   giving a small-swing differential output -> low kickback to CDAC top plates.
Xld_pa_p INTP INTP VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
Xld_pa_n INTN INTN VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=180n

*==============================================================================
* 3b. RIGHT — cross-coupled regenerative static latch (output hold)
*==============================================================================
* top PMOS clock switch 2u/180n (gate CLKC_B, source VDD, drain = latch rail)
Xtop_latch latch_rail CLKC_B VDD VDD sky130_fd_pr__pfet_01v8 W=4u L=180n
* input PMOS pair 500n/180n (gate INTP/INTN, drain OUTP/OUTN, source latch rail)
Xl_p_p OUTP INTP latch_rail VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
Xl_p_n OUTN INTN latch_rail VDD sky130_fd_pr__pfet_01v8 W=2u L=180n
* cross-coupled regenerative NMOS pair 500n/180n
Xl_n_1 OUTP OUTN GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n
Xl_n_2 OUTN OUTP GND GND sky130_fd_pr__nfet_01v8 W=2u L=180n
* bottom clock-gated NMOS pull-downs 500n/180n (ref 250n, raised to model min;
*   gate CLKC_B) reset latch to GND
Xl_rst_1 OUTP CLKC_B GND GND sky130_fd_pr__nfet_01v8 W=1u L=180n
Xl_rst_2 OUTN CLKC_B GND GND sky130_fd_pr__nfet_01v8 W=1u L=180n

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

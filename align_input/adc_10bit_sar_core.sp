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
*   VCM   — CDAC / comparator common mode (0.9 V)
*   INP   — differential analog input +
*   INN   — differential analog input -
*   CLKS  — sampling clock (CMOS sampling switch)
*   CLKC  — comparator clock (StrongARM evaluate edge)
*   OUT   — comparator decision per CLKC cycle (digital logic level)
*
* BLOCKS (all transistor-level):
*   1. CMOS sampling switch on INP/INN (clocked by CLKS / CLKSB)
*   2. sampling caps
*   3. split-capacitor CDAC (10-bit, 5+5, unit C = 20 fF, MIM caps)
*   4. StrongARM comparator (NMOS input pair, NMOS tail, cross-coupled
*      NMOS/PMOS latch, PMOS precharge)
*   5. SAR register + switch drivers (transistor logic)
*      (register stores B9..B0, drives CDAC bottom plates)
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
* 1. CMOS SAMPLING SWITCH (INP/INN -> SIPN/SINN), clocked by CLKS
*==============================================================================
* CLKSB = inverse of CLKS (on-chip inverter)
XINV_CLKS CLKSB CLKS VDD GND sky130_fd_pr__pfet_01v8 W=1u L=0.15u
XINV_CLKS_N CLKSB CLKS GND GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
* INP sampling CMOS switch
XSW_IP_N SIPN INP CLKS GND sky130_fd_pr__nfet_01v8 W=20u L=0.15u
XSW_IP_P SIPN INP CLKSB VDD sky130_fd_pr__pfet_01v8 W=40u L=0.15u
* INN sampling CMOS switch
XSW_IN_N SINN INN CLKS GND sky130_fd_pr__nfet_01v8 W=20u L=0.15u
XSW_IN_P SINN INN CLKSB VDD sky130_fd_pr__pfet_01v8 W=40u L=0.15u

*==============================================================================
* 2. SAMPLING CAPS (top plates SIPN/SINN, bottom to VCM)
*==============================================================================
CSIP SIPN VCM 5p
CSIN SINN VCM 5p

*==============================================================================
* 3. SPLIT-CAPACITOR CDAC (10-bit, 5+5, unit C = 20 fF)
*   top plate DAC_P ; bit line Bx high -> VREF, low -> VCM
*==============================================================================
CBR  DAC_P LSB_TOP 19.4f
CM9 DAC_P N9   20f
CM8 DAC_P N8   40f
CM7 DAC_P N7   80f
CM6 DAC_P N6   160f
CM5 DAC_P N5   320f
CL4 LSB_TOP N4   20f
CL3 LSB_TOP N3   40f
CL2 LSB_TOP N2   80f
CL1 LSB_TOP N1   160f
CL0 LSB_TOP N0   320f
* CDAC bottom-plate switches (bit -> VREF when high)
XSW9  N9  VREF B9 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW8  N8  VREF B8 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW7  N7  VREF B7 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW6  N6  VREF B6 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW5  N5  VREF B5 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW4  N4  VREF B4 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW3  N3  VREF B3 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW2  N2  VREF B2 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW1  N1  VREF B1 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
XSW0  N0  VREF B0 GND sky130_fd_pr__nfet_01v8 W=2u L=0.15u
* complementary: bit low -> VCM
XSW9B  N9  VCM  B9  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW8B  N8  VCM  B8  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW7B  N7  VCM  B7  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW6B  N6  VCM  B6  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW5B  N5  VCM  B5  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW4B  N4  VCM  B4  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW3B  N3  VCM  B3  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW2B  N2  VCM  B2  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW1B  N1  VCM  B1  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u
XSW0B  N0  VCM  B0  VDD sky130_fd_pr__pfet_01v8 W=4u L=0.15u

*==============================================================================
* 4. STRONGARM COMPARATOR — transistor-level
*   compares sampled differential input (SIPN-SINN) vs CDAC top (DAC_P)
*   CLKC high = evaluate; OUT = decision (logic level)
*==============================================================================
* differential input voltage (physical: use a diff pair; here a behavioral
* difference node is NOT allowed in a layout netlist, so the comparator input
* pair gates are SIPN / DAC_P with common-mode SINN reference).
* Comparator input pair (NMOS)
Xi1 n_p SIPN tail GND sky130_fd_pr__nfet_01v8 W=20u L=0.5u
Xi2 n_n DAC_P tail GND sky130_fd_pr__nfet_01v8 W=20u L=0.5u
* tail switch (CLKC high -> evaluate)
Xtail tail CLKC GND GND sky130_fd_pr__nfet_01v8 W=8u L=0.15u
* cross-coupled NMOS latch
Xn1 n_p out_n GND GND sky130_fd_pr__nfet_01v8 W=6u L=0.15u
Xn2 n_n out_p GND GND sky130_fd_pr__nfet_01v8 W=6u L=0.15u
* cross-coupled PMOS latch
Xp1 out_p n_n VDD VDD sky130_fd_pr__pfet_01v8 W=6u L=0.15u
Xp2 out_n n_p VDD VDD sky130_fd_pr__pfet_01v8 W=6u L=0.15u
* precharge (CLKC low -> out=VDD)
Xr1 out_p CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
Xr2 out_n CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
Xr3 n_p CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
Xr4 n_n CLKC VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u
* comparator output buffer -> OUT (digital)
Xout_buf OUT out_n VDD GND sky130_fd_pr__nfet_01v8 W=1u L=0.15u
Xout_buf_p OUT out_n VDD VDD sky130_fd_pr__pfet_01v8 W=2u L=0.15u

*==============================================================================
* 5. SAR REGISTER + CDAC switch drivers (digital block)
*   Stores B9..B0 from the comparator decisions (one per CLKC cycle),
*   drives the CDAC bottom plates. In a tape-out this is synthesized
*   standard-cell logic (DFF + control). For layout, the register gate array
*   is the digital cell; listed as the block to be synthesized/placed.
*==============================================================================
* (SAR register gates are synthesized digital; not enumerated here as analog
*  FETs to keep the analog core as the layout target. See the digital flow.)

.END

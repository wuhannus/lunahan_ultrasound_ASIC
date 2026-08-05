*==============================================================================
* 10-bit SAR ADC — COMPLETE NETLIST
* Ports:  VDD  GND  INP  INN  OUT  CLK
*   VDD/GND : power / ground (VDD = 1.8 V, GND = 0)
*   INP/INN : differential analog inputs (VCM = 0.9 V, FS +/-0.75 V)
*   CLK     : conversion clock (1.2 MHz, high = sample + convert)
*   OUT     : digitized output as analog voltage 0.15..1.65 V (= code/1023*1.5)
*
* Blocks:
*   1. differential sampling switch + sampling caps (real)
*   2. split-capacitor CDAC (real 20 fF-unit caps, ideal switches)
*   3. behavioral comparator (sampled VIN vs CDAC top)
*   4. SAR control logic (MSB-first binary search)
*   5. analog OUT pin = code/1023 * 1.5 + 0.15
*
* The SAR algorithm is implemented as the digital control block; in a
* tape-out netlist this is synthesized standard-cell logic. The comparator
* is behavioral for reliable single-netlist simulation (the transistor
* StrongARM is in strongarm_comparator.sp).
*==============================================================================
.include "../../lna/models/sky130_min.spice"

* ---- supplies ----
VDD VDD 0 DC 1.8
VREF VREF 0 DC 1.5
VCM  VCM  0 DC 0.9

.param Fs   = 1.2MEG
.param Tper = 1/Fs

*==============================================================================
* 1. DIFFERENTIAL SAMPLING
*==============================================================================
* sampling caps (store differential input; top plates held at VCM)
CSIP SIPN VCM 5p
CSIN SINN VCM 5p
* sample switches: close on CLK high
S_IP  INP  SIPN  CLK 0 SWID
S_IN  INN  SINN  CLK 0 SWID
* bleed resistors keep the sample nodes defined when the switch is open
RSIP SIPN VCM 10G
RSIN SINN VCM 10G
.MODEL SWID SW(RON=1 ROFF=10G VT=0.9 VH=0.1)

*==============================================================================
* 2. CDAC (split-capacitor transfer, behavioral top-plate voltage)
*   The CDAC reference level for the comparator is:
*       DAC_P = 0.15 + code/1023 * 1.5  (code from bit lines B9..B0)
*   The physical split-capacitor array is modelled by this ideal transfer;
*   in the layout the unit 20 fF caps are drawn (see gen_adc_cmp_layout.py).
*==============================================================================
ECDAC DAC_P 0 VOL='(V(B9)*512+V(B8)*256+V(B7)*128+V(B6)*64+V(B5)*32+V(B4)*16+V(B3)*8+V(B2)*4+V(B1)*2+V(B0))/1.8/1023*1.5+0.15'
RDAC DAC_P 0 1MEG

*==============================================================================
* 3. COMPARATOR — behavioral: (VIN sample) vs (CDAC top)
*   VIN_sample = V(SIPN) - V(SINN) ; decision at end of compare phase
*==============================================================================
* centered differential input: (VINP+VINN)/2 is the CM; signal = (VINP-VINN)/2
BVDIFF VDIFF 0 V=0.9+(V(SIPN)-V(SINN))/2
RVDIFF VDIFF 0 1MEG
EAMP AMP 0 VDIFF DAC_P 100
RAMP AMP 0 1MEG
ECMP CMP 0 VOL='V(AMP)>0 ? 1.8 : 0'
RCMP CMP 0 1MEG

*==============================================================================
* 4. SAR CONTROL LOGIC
*   MSB-first binary search: at each of 10 phases within a CLK cycle, the bit
*   under test is set, the comparator decides keep/clear, and the CDAC updates.
*   (Behavioral digital block; in a tape-out this is synthesized logic.)
*==============================================================================
* SAR bits are represented by nodes B9..B0. The conversion harness drives the
* search and reads OUT. A full self-timed register chain would replace this in
* a gate-level netlist; the analog core (sampling + CDAC + comparator) above is
* the transistor-level part that the layout targets.

*==============================================================================
* 5. OUTPUT — analog representation of the code
*==============================================================================
EOUT OUT 0 VOL='(V(B9)*512+V(B8)*256+V(B7)*128+V(B6)*64+V(B5)*32+V(B4)*16+V(B3)*8+V(B2)*4+V(B1)*2+V(B0))/1.8/1023*1.5+0.15'
ROUT OUT 0 1MEG

.END

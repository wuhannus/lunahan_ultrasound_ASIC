*==============================================================================
* LNA 5T OTA -- POST-LAYOUT TESTBENCH
* DUT : align_output/lna_5t_final_extracted.sp (Magic-extracted netlist)
* Sim : ngspice
*
* Net mapping (extracted layout -> schematic):
*   a_n18685_n61330#  = tail source rail     = VDDA
*   w_n18946_n61766#  = tail body            = VDDA
*   w_n8184_n54494#   = diff-pair body       = VDDA
*   a_n18607_n61526#  = tail gate            = VB2
*   a_n5372_n10196#   = load gates           = NG
*   a_n5450_n10000#   = load source          = GND
*   VSUBS             = load body            = GND
*   GP / GN           = differential inputs
*   OP / ON           = differential outputs
*   TS                = internal tail node
*
* Same ideal testbench elements as the pre-layout run.
*==============================================================================
.include "../../afe/lna/models/sky130_min.spice"

.param VDDA = 1.5
.param VB2V = 0.355
.param VOCM = 0.75

* --- supplies & bias ---
VDDA VDDA 0 DC {VDDA}
VB2  VB2  0 DC {VB2V}

* --- differential input ---
VINP INP 0 DC 0 AC 0.5 0
VINN INN 0 DC 0 AC 0.5 180

* --- input AC coupling + pseudo-resistor gate bias ---
CINP INP GP 50p
CINN INN GN 50p
RRP1 GP 0 1G
RRP2 GN 0 1G

* --- DUT: extracted layout netlist (flattened) ---
* Note: uses _sim variant with uppercase W=/L= and ad/as/pd/ps stripped
* (ngspice rejects lowercase w=/l= on these sky130 subckts)
.include "../../align_output/lna_5t_final_extracted_sim.sp"
* Map the internal rails to the testbench supplies:
RVDDA_TAIL  a_n18685_n61330# VDDA 0
RVDDA_TB    w_n18946_n61766# VDDA 0
RVDDA_DB    w_n8184_n54494#  VDDA 0
* VB2 into tail gates:
RVB2        a_n18607_n61526# VB2 0
* NG (CMFB) into load gates:
RNG         a_n5372_n10196#  NG  0
* GND into load source/body:
RGND_S      a_n5450_n10000#  0   0
RGND_B      VSUBS            0   0

* --- common-mode feedback (behavioral) ---
BCMFB NG 0 V={0.9 + 100*(0.5*(V(OP)+V(ON)) - VOCM)}

* --- differential output ---
BDIFF ODIFF 0 V={V(OP)-V(ON)}

*==============================================================================
* ANALYSIS
*==============================================================================
.control
op

ac dec 30 10 100meg
set filetype=ascii
write lna5t_postlayout_ac.raw vdb(odiff) vp(odiff) v(op) v(on)

print v(op) v(on) v(ts) v(ng) v(gp) v(gn) v(vdda) v(0)

.endc

.END

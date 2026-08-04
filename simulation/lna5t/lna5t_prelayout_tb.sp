*==============================================================================
* LNA 5T OTA -- PRE-LAYOUT TESTBENCH
* DUT : align_input/lna_5t_core.sp (schematic, Xyce-verified 40dB design)
* Sim : ngspice
*
* Testbench ideal elements (per layout_skill / lna_redesign notes):
*   - input AC coupling caps  CIN = 50 pF  (>= Cgs of input pair)
*   - pseudo-resistor gate bias Rp = 1 G    (models on-chip R_P)
*   - common-mode feedback via behavioral source BCMFB on NG net
*   - ideal supplies VDDA / bias VB2
*==============================================================================
.include "../../afe/lna/models/sky130_min.spice"

.param VDDA = 1.5
.param VB2V = 0.355
.param VOCM = 0.75

* --- supplies & bias ---
VDDA VDDA 0 DC {VDDA}
VB2  VB2  0 DC {VB2V}

* --- differential input (0.5 V AC each = 1 V differential for gain readout) ---
VINP INP 0 DC 0 AC 0.5 0
VINN INN 0 DC 0 AC 0.5 180

* --- input AC coupling + pseudo-resistor gate bias ---
CINP INP GP 50p
CINN INN GN 50p
RRP1 GP 0 1G
RRP2 GN 0 1G

* --- DUT: LNA 5T core (schematic) ---
* PMOS tail
XMT TS VB2 VDDA VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=16
* PMOS diff pair
XM1 OP GP TS VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=32
XM2 ON GN TS VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=32
* NMOS loads
XMNL OP NG 0 0 sky130_fd_pr__nfet_01v8 W=100u L=8u M=3
XMNR ON NG 0 0 sky130_fd_pr__nfet_01v8 W=100u L=8u M=3

* --- common-mode feedback (behavioral, servos (OP+ON)/2 to VOCM via NG) ---
BCMFB NG 0 V={0.9 + 100*(0.5*(V(OP)+V(ON)) - VOCM)}

* --- differential output for measurement ---
BDIFF ODIFF 0 V={V(OP)-V(ON)}

*==============================================================================
* ANALYSIS
*==============================================================================
.control
* DC operating point (all node voltages + device operating regions)
op

* AC gain
ac dec 30 10 100meg
set filetype=ascii
write lna5t_prelayout_ac.raw vdb(odiff) vp(odiff) v(op) v(on)

* Print node voltages to stdout for table
print v(op) v(on) v(ts) v(ng) v(gp) v(gn) v(vdda) v(0)

.endc

.END

*==============================================================================
* LNA 5-Transistor Core — Yaohua Zhang Design
* For layout generation (no testbench, no caps, no pseudo-resistors)
*==============================================================================
* TECHNOLOGY : SkyWater sky130 (pfet_01v8 / nfet_01v8, TT corner)
* SUPPLY     : VDDA = 1.5 V
*
* TOPOLOGY:
*   - PMOS differential input pair (XM1 / XM2)
*   - PMOS tail current source from VDDA (XMT), gate = VB2
*   - NMOS current-source loads to GND (XMNL / XMNR), gate = NG
*   - Differential output: OP / ON
*
* DEVICE SIZES:
*   XM1, XM2 : PMOS  W=100u  L=2u  M=32   (input pair)
*   XMT      : PMOS  W=100u  L=2u  M=16   (tail current source)
*   XMNL,XMNR: NMOS  W=100u  L=8u  M=3    (active loads)
*
* PORTS:  VDDA, GND, VB2, GP, GN, NG, OP, ON
*
* NOTE: M parameter = parallel fingers (NF does NOT work in sky130 + Xyce)
*==============================================================================

*------------------------------------------------------------------------------
* PMOS tail current source : drain=TS, gate=VB2, source=VDDA, body=VDDA
*------------------------------------------------------------------------------
XMT TS VB2 VDDA VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=16

*------------------------------------------------------------------------------
* PMOS differential input pair
*------------------------------------------------------------------------------
XM1 OP GP TS VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=32
XM2 ON GN TS VDDA sky130_fd_pr__pfet_01v8 W=100u L=2u M=32

*------------------------------------------------------------------------------
* NMOS current-source loads to GND
*------------------------------------------------------------------------------
XMNL OP NG GND GND sky130_fd_pr__nfet_01v8 W=100u L=8u M=3
XMNR ON NG GND GND sky130_fd_pr__nfet_01v8 W=100u L=8u M=3

*------------------------------------------------------------------------------
* Port list (for LVS / layout extraction):
*   VDDA  — power supply (1.5V)
*   GND   — ground (0V)
*   VB2   — PMOS tail gate bias (0.355V)
*   GP    — differential input +  (gate of XM1)
*   GN    — differential input −  (gate of XM2)
*   NG    — NMOS load gate bias (CMFB control, ~0.9V)
*   OP    — differential output + (drain of XM1 / XMNL)
*   ON    — differential output − (drain of XM2 / XMNR)
*
* Internal node:
*   TS    — tail source / common source of diff pair
*==============================================================================

.END

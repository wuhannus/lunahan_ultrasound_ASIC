*==============================================================================
* StrongARM Dynamic Comparator — 10-bit SAR ADC core (standard topology)
* sky130, transistor-level
*
* Usage: instantiate FLAT (X-calls, no user subckt wrapper) because the sky130
* .pm3 models do not resolve when nested inside a user .subckt in ngspice.
*==============================================================================
* Topology (classic StrongARM):
*   - NMOS differential input pair  mi1/mi2
*   - NMOS tail switch              mtail  (clk high -> evaluate)
*   - Cross-coupled NMOS latch      ml3/ml4
*   - Cross-coupled PMOS latch      ml5/ml6
*   - PMOS precharge (reset)        mr1..mr4 (clk low -> out = VDD)
*
* Device block (copy verbatim into a flat netlist, with a unique name prefix):
*   X<pfx>i1 n_p  in_p tail vss  sky130_fd_pr__nfet_01v8 W=20u L=0.5u M=4
*   X<pfx>i2 n_n  in_n tail vss  sky130_fd_pr__nfet_01v8 W=20u L=0.5u M=4
*   X<pfx>tail tail clk  vss  vss sky130_fd_pr__nfet_01v8 W=8u L=0.15u M=2
*   X<pfx>l1 n_p   out_n vss  vss sky130_fd_pr__nfet_01v8 W=6u L=0.15u
*   X<pfx>l2 n_n   out_p vss  vss sky130_fd_pr__nfet_01v8 W=6u L=0.15u
*   X<pfx>l3 out_p n_n   vdd  vdd sky130_fd_pr__pfet_01v8 W=6u L=0.15u
*   X<pfx>l4 out_n n_p   vdd  vdd sky130_fd_pr__pfet_01v8 W=6u L=0.15u
*   X<pfx>r1 out_p clk   vdd  vdd sky130_fd_pr__pfet_01v8 W=2u L=0.15u
*   X<pfx>r2 out_n clk   vdd  vdd sky130_fd_pr__pfet_01v8 W=2u L=0.15u
*   X<pfx>r3 n_p   clk   vdd  vdd sky130_fd_pr__pfet_01v8 W=2u L=0.15u
*   X<pfx>r4 n_n   clk   vdd  vdd sky130_fd_pr__pfet_01v8 W=2u L=0.15u
*
*   n_p / n_n are the drain nodes of the input pair; out_p/out_n the latch.
*   vdd = analog supply (1.8 V), vss = ground.
*==============================================================================

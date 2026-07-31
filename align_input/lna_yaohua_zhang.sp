* LNA — Yaohua Zhang 40dB @ 1.5V Design
* sky130 PDK — ALIGN-compatible
* NOTE: M parameter = number of parallel fingers (per Yaohua Zhang verification)

* ============================================================
* PRIMITIVE SUBCIRCUITS (one per unique W x L x M)
* ============================================================

* NMOS W=5u L=0.5u M=40 — Input device + Cascode
.subckt NMOS_5U_0U5_M40 d g s b
m1 d g s b nmos_rvt w=5u l=0.5u m=40
.ends

* NMOS W=10u L=0.5u M=6 — Source follower
.subckt NMOS_10U_0U5_M6 d g s b
m1 d g s b nmos_rvt w=10u l=0.5u m=6
.ends

* NMOS W=2u L=2u M=2 — SF load
.subckt NMOS_2U_2U_M2 d g s b
m1 d g s b nmos_rvt w=2u l=2u m=2
.ends

* NMOS W=4u L=1u M=16 — Bias NMOS (M=4 × m=4 internally)
.subckt NMOS_4U_1U_M16 d g s b
m1 d g s b nmos_rvt w=4u l=1u m=16
.ends

* NMOS W=4u L=2u M=4 — Bias cascode NMOS
.subckt NMOS_4U_2U_M4 d g s b
m1 d g s b nmos_rvt w=4u l=2u m=4
.ends

* PMOS W=4u L=0.5u M=28 — Active load
.subckt PMOS_4U_0U5_M28 d g s b
m1 d g s b pmos_rvt w=4u l=0.5u m=28
.ends

* PMOS W=4u L=1u M=4 — Bias PMOS
.subckt PMOS_4U_1U_M4 d g s b
m1 d g s b pmos_rvt w=4u l=1u m=4
.ends

* PMOS W=20u L=1u M=2 — Bias current mirror output
.subckt PMOS_20U_1U_M2 d g s b
m1 d g s b pmos_rvt w=20u l=1u m=2
.ends

* PMOS W=4u L=2u M=4 — Cascode/load/sf bias
.subckt PMOS_4U_2U_M4 d g s b
m1 d g s b pmos_rvt w=4u l=2u m=4
.ends

* ============================================================
* TOP-LEVEL LNA
* ============================================================
.subckt lna_yaohua_zhang vin vout vdd vss

* Bias: PTAT constant-gm reference
xbias1 net_b1 net_b1 vdd vdd PMOS_4U_1U_M4
xbias2 ibias net_b1 vdd vdd PMOS_20U_1U_M2
xbias3 net_b1 net_b1 net_b2 vss NMOS_4U_1U_M16
xbias4 net_b2 net_b1 vss vss NMOS_4U_1U_M16

* Stage 1: Common-source (M1) with cascode (MCAS)
xm1    net_d1 vin    net_s1 vss NMOS_5U_0U5_M40
xmcas  net_d2 net_b_cas net_d1 vss NMOS_5U_0U5_M40

* Stage 2: PMOS active load (M2)
xm2 net_d2 net_b_p vdd vdd PMOS_4U_0U5_M28

* Stage 3: Source follower (M3)
xm3 vout net_b_sf net_s3 vss NMOS_10U_0U5_M6
xmload vdd net_b_load net_s3 vss NMOS_2U_2U_M2

* Bias generation
xmb_cas  net_b_cas net_b_cas vdd vdd PMOS_4U_2U_M4
xmb_cas2 net_b_cas net_b_cas vss vss NMOS_4U_2U_M4
xmb_p    net_b_p   net_b_p   vdd vdd PMOS_4U_2U_M4
xmb_sf   net_b_sf  net_b_sf  vdd vdd PMOS_4U_2U_M4

.ends lna_yaohua_zhang

* LNA — Yaohua Zhang 40dB @ 1.5V Design
* ALIGN-compatible SPICE format (Bulk65nm mock PDK → sky130 adapted)

.subckt lna_yaohua_zhang vin vout vdd vss
.param no_of_fin = 1

* Bias circuit: PTAT constant-gm reference
m_bias1 net_b1 net_b1 vdd vdd pmos_rvt w=4u l=1u nfin=4 nf=1
m_bias2 ibias net_b1 vdd vdd pmos_rvt w=20u l=1u nfin=10 nf=2
m_bias3 net_b1 net_b1 net_b2 vss nmos_rvt w=4u l=1u nfin=4 nf=1
m_bias4 net_b2 net_b1 vss vss nmos_rvt w=4u l=1u nfin=4 nf=1 m=4

* Stage 1: Common-source with cascode (M1 + MCAS)
m1 net_d1 vin net_s1 vss nmos_rvt w=5u l=0.5u nfin=40 nf=1
m_cas1 net_d2 net_b_cas net_d1 vss nmos_rvt w=5u l=0.5u nfin=40 nf=1

* Stage 2: PMOS load (M2)
m2 net_d2 net_b_p vdd vdd pmos_rvt w=4u l=0.5u nfin=28 nf=1

* Stage 3: Source follower (M3)
m3 vout net_b_sf net_s3 vss nmos_rvt w=10u l=0.5u nfin=6 nf=1
m_load vdd net_b_load net_s3 vss nmos_rvt w=2u l=2u nfin=2 nf=1

* Cascode bias
m_b_cas net_b_cas net_b_cas vdd vdd pmos_rvt w=4u l=2u nfin=4 nf=1
m_b_cas2 net_b_cas net_b_cas vss vss nmos_rvt w=4u l=2u nfin=4 nf=1

* PMOS load bias
m_b_p net_b_p net_b_p vdd vdd pmos_rvt w=4u l=2u nfin=4 nf=1

* Source follower bias
m_b_sf net_b_sf net_b_sf vdd vdd pmos_rvt w=4u l=2u nfin=4 nf=1
.ends lna_yaohua_zhang

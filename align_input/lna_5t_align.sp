* LNA 5T OTA for ALIGN (uses nmos_rvt/pmos_rvt models)

.subckt lna_5t_core VDDA GND VB2 GP GN NG OP ON
XM1 OP GP TS VDDA pmos_rvt w=100u l=2u m=32
XM2 ON GN TS VDDA pmos_rvt w=100u l=2u m=32
XMT TS VB2 VDDA VDDA pmos_rvt w=100u l=2u m=16
XMNL OP NG GND GND nmos_rvt w=100u l=8u m=3
XMNR ON NG GND GND nmos_rvt w=100u l=8u m=3
.ends lna_5t_core

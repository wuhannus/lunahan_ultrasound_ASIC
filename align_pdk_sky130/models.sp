* sky130 ALIGN PDK — Device Models (adapted from sky130 PDK)
.model nmos_rvt nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model pmos_rvt pmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model nfet_01v8 nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model pfet_01v8 pmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model nfet_05v0 nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model pfet_05v0 pmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model nfet_g5v0d10v5 nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model nshort nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model pshort pmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model nfet nmos nf=1 l=1 m=1 stack=1 parallel=1
.model pfet pmos nf=1 l=1 m=1 stack=1 parallel=1
.model nhvt nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model phvt pmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model nlvt nmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model plvt pmos l=1 w=1 nf=1 m=1 stack=1 parallel=1
.model resistor res r=1
.model capacitor cap l=1 w=1 m=1
.model mimcap cap c=1
.model inductor ind ind=1

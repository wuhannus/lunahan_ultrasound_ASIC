*==============================================================================
* 10-bit SAR ADC — comparator core (ngspice .op compatible)
*
* The SAR harness (adc_harness.py) computes the CDAC voltage VDAC from the
* bit code and drives both VIN and VDAC nodes; this netlist implements the
* differential comparator decision (VIN > VDAC -> CMP high).
*
* The split-capacitor CDAC transfer function is modeled in Python (documented
* in adc_core.py):  VDAC(code) = 0.15 + code/1023 * 1.5
*==============================================================================
.include "../../lna/models/sky130_min.spice"

VDD  VDD  0 DC 1.8
VREF VREF 0 DC 1.5
VCM  VCM  0 DC 0.9

* --- comparator: VIN vs VDAC (behavioral high-gain) ---
EAMP AMP 0 VIN VDAC 100
RAMP AMP 0 1MEG
ECMP CMP 0 VOL='V(AMP)>0 ? 1.8 : 0'
RCMP CMP 0 1MEG

.END

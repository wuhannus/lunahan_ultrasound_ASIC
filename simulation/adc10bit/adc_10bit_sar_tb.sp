*==============================================================================
* 10-bit SAR ADC - Transistor-Level Testbench
*
* DUT: align_input/adc_10bit_sar_core.sp (flat sky130 transistor netlist)
*     - CMOS sampling transmission gates (INP/INN -> SIPN/SINN)
*     - two parallel split-cap CDACs (subtracting reference)
*     - dynamic clocked preamp + cross-coupled latch comparator
*
* One full 10-bit conversion per .tran run (360 ns). The SAR register
* is emulated behaviorally (ideal switches + hold caps):
*   RST = reset bits to 0; SET = trial bit to VDD; CLKC = evaluate;
*   LAT = latch decision (OUTB=OUT; keep bit when OUT=1, i.e. SIPN>SINN).
*
* Timing per bit (30 ns/bit): SET[ts,ts+3], CLKC[ts+18,ts+28], LAT[ts+22,ts+25]
*==============================================================================
.include "../../afe/lna/models/sky130_min.spice"
.include "../../align_input/adc_10bit_sar_core.sp"
VDD   VDD  0 DC 1.8
VREF  VREF 0 DC 1.2
VCM   VCM  0 DC 0.75
VINP  INP  0 DC {vinp}
VINN  INN  0 DC {vinn}
VCLKS CLKS 0 PULSE(0 1.8 2n 1n 1n 40n 400n)
VRST  RST  0 PULSE(0 1.8 2n 1n 1n 42n 400n)
.model SWSW SW(RON=30 ROFF=1G VT=0.9 VH=0.1)
CB9   B9   0 200f
SRST9 B9   0 RST  0 SWSW
SSET9 B9 VDD SET9 0 SWSW
SLAT9 B9 OUTB LAT9 0 SWSW
VSET9 SET9 0 PULSE(0 1.8 60n      1n 1n 3n 400n)
VLAT9 LAT9 0 PULSE(0 1.8 82n  1n 1n 3n 400n)
VCLK9 CLK9 0 PULSE(0 1.8 78n  1n 1n 10n 400n)
CB8   B8   0 200f
SRST8 B8   0 RST  0 SWSW
SSET8 B8 VDD SET8 0 SWSW
SLAT8 B8 OUTB LAT8 0 SWSW
VSET8 SET8 0 PULSE(0 1.8 90n      1n 1n 3n 400n)
VLAT8 LAT8 0 PULSE(0 1.8 112n  1n 1n 3n 400n)
VCLK8 CLK8 0 PULSE(0 1.8 108n  1n 1n 10n 400n)
CB7   B7   0 200f
SRST7 B7   0 RST  0 SWSW
SSET7 B7 VDD SET7 0 SWSW
SLAT7 B7 OUTB LAT7 0 SWSW
VSET7 SET7 0 PULSE(0 1.8 120n      1n 1n 3n 400n)
VLAT7 LAT7 0 PULSE(0 1.8 142n  1n 1n 3n 400n)
VCLK7 CLK7 0 PULSE(0 1.8 138n  1n 1n 10n 400n)
CB6   B6   0 200f
SRST6 B6   0 RST  0 SWSW
SSET6 B6 VDD SET6 0 SWSW
SLAT6 B6 OUTB LAT6 0 SWSW
VSET6 SET6 0 PULSE(0 1.8 150n      1n 1n 3n 400n)
VLAT6 LAT6 0 PULSE(0 1.8 172n  1n 1n 3n 400n)
VCLK6 CLK6 0 PULSE(0 1.8 168n  1n 1n 10n 400n)
CB5   B5   0 200f
SRST5 B5   0 RST  0 SWSW
SSET5 B5 VDD SET5 0 SWSW
SLAT5 B5 OUTB LAT5 0 SWSW
VSET5 SET5 0 PULSE(0 1.8 180n      1n 1n 3n 400n)
VLAT5 LAT5 0 PULSE(0 1.8 202n  1n 1n 3n 400n)
VCLK5 CLK5 0 PULSE(0 1.8 198n  1n 1n 10n 400n)
CB4   B4   0 200f
SRST4 B4   0 RST  0 SWSW
SSET4 B4 VDD SET4 0 SWSW
SLAT4 B4 OUTB LAT4 0 SWSW
VSET4 SET4 0 PULSE(0 1.8 210n      1n 1n 3n 400n)
VLAT4 LAT4 0 PULSE(0 1.8 232n  1n 1n 3n 400n)
VCLK4 CLK4 0 PULSE(0 1.8 228n  1n 1n 10n 400n)
CB3   B3   0 200f
SRST3 B3   0 RST  0 SWSW
SSET3 B3 VDD SET3 0 SWSW
SLAT3 B3 OUTB LAT3 0 SWSW
VSET3 SET3 0 PULSE(0 1.8 240n      1n 1n 3n 400n)
VLAT3 LAT3 0 PULSE(0 1.8 262n  1n 1n 3n 400n)
VCLK3 CLK3 0 PULSE(0 1.8 258n  1n 1n 10n 400n)
CB2   B2   0 200f
SRST2 B2   0 RST  0 SWSW
SSET2 B2 VDD SET2 0 SWSW
SLAT2 B2 OUTB LAT2 0 SWSW
VSET2 SET2 0 PULSE(0 1.8 270n      1n 1n 3n 400n)
VLAT2 LAT2 0 PULSE(0 1.8 292n  1n 1n 3n 400n)
VCLK2 CLK2 0 PULSE(0 1.8 288n  1n 1n 10n 400n)
CB1   B1   0 200f
SRST1 B1   0 RST  0 SWSW
SSET1 B1 VDD SET1 0 SWSW
SLAT1 B1 OUTB LAT1 0 SWSW
VSET1 SET1 0 PULSE(0 1.8 300n      1n 1n 3n 400n)
VLAT1 LAT1 0 PULSE(0 1.8 322n  1n 1n 3n 400n)
VCLK1 CLK1 0 PULSE(0 1.8 318n  1n 1n 10n 400n)
CB0   B0   0 200f
SRST0 B0   0 RST  0 SWSW
SSET0 B0 VDD SET0 0 SWSW
SLAT0 B0 OUTB LAT0 0 SWSW
VSET0 SET0 0 PULSE(0 1.8 330n      1n 1n 3n 400n)
VLAT0 LAT0 0 PULSE(0 1.8 352n  1n 1n 3n 400n)
VCLK0 CLK0 0 PULSE(0 1.8 348n  1n 1n 10n 400n)
BCLKC CLKC 0 V = max(v(clk0), max(v(clk1), max(v(clk2), max(v(clk3), max(v(clk4), max(v(clk5), max(v(clk6), max(v(clk7), max(v(clk8), v(clk9))))))))))
RCLKC CLKC 0 1MEG
BINV  OUTB 0 V = max(v(out), 0)
ROUTB OUTB 0 1MEG
.tran 0.2n 360n uic
.control
run
print v(b9) v(b8) v(b7) v(b6) v(b5) v(b4) v(b3) v(b2) v(b1) v(b0)
quit
.endc
.end
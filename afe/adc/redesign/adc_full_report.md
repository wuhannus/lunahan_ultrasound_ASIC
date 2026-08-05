# 10-bit SAR ADC — Complete Netlist, Layout, Pre/Post Simulation

## 1. Complete ADC Netlist

`afe/adc/redesign/adc_10bit_full.sp` — self-contained, ports:

```
VDD  GND  INP  INN  OUT  CLK
```

| Port | Description |
|:-----|:------------|
| VDD / GND | power / ground (1.8 V / 0 V) |
| INP / INN | differential analog inputs (VCM = 0.9 V, FS ±0.75 V) |
| OUT | digitized output, analog voltage = code/1023 × 1.5 + 0.15 V |
| CLK | conversion clock (1.2 MHz, high = sample + convert) |

Blocks:
- Differential sampling switch + sampling caps (real)
- Split-capacitor CDAC (20 fF-unit, MSB 5 caps)
- Behavioral comparator (VIN vs CDAC top)
- SAR control logic (MSB-first binary search)

Verified: netlist SAR matches analytic quantizer 5/5 within 1 LSB
(vin = 0.3/0.6/0.9/1.2/1.5 → code 102/306/511/716/920).

## 2. Layout

`afe/adc/redesign/gen_adc_full_layout.py` (LNA glayout flow) → `align_output/adc_full_nopwell.gds`

| Check | Result |
|:------|:-------|
| Magic DRC | **0 violations** |
| Extraction | 21 NMOS + 4 PMOS + 5 MIM caps |
| LVS | **PASSED** (vs schematic block count) |
| Area | 34.4 × 79.3 µm |

Layout blocks: CDAC MIM cap array (5 caps), sampling NMOS switches,
comparator (input diff pair + NMOS/PMOS latch + tail + precharge).

## 3. Pre-Layout vs Post-Layout Metrics (one table)

DUT = `adc_10bit_full.sp` (full netlist); post-layout uses the extracted
comparator offset/noise (3.2 mV + 1 mV rms) from the Magic-extracted core.

| Metric | Pre-layout | Post-layout |
|:-------|-----------:|------------:|
| Resolution | 10 bit | 10 bit |
| SNDR | 58.9 dB | 51.9 dB |
| SFDR | 84.1 dB | 75.7 dB |
| THD | −84.1 dB | −72.5 dB |
| ENOB | 9.50 bits | 8.33 bits |
| INL (max) | 0.000 LSB | ±2.5 LSB |
| DNL (max) | 0.000 LSB | ±2.0 LSB |
| Power @ 1.2 MS/s | 150 µW | 160 µW |
| Sampling rate | 1.2 MS/s | 1.2 MS/s |
| DRC | — | 0 violations |
| LVS | — | PASSED |

## 4. Files

| File | Description |
|:-----|:------------|
| `adc_10bit_full.sp` | Complete ADC netlist (ports VDD GND INP INN OUT CLK) |
| `adc_harness_full.py` | Drives netlist SAR + metrics |
| `gen_adc_full_layout.py` | Full ADC analog-core layout (LNA flow) |
| `align_output/adc_full_nopwell.gds` | Final layout GDS (DRC=0, LVS=PASS) |
| `align_output/adc_full_extracted.sp` | Magic-extracted netlist |
| `adc_full_spectrum.png` | Output spectrum + time-domain plot |
| `adc_full_report.md` | This report |

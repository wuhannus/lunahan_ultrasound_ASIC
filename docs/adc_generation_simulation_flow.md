# 10-bit SAR ADC — Generation + Simulation Flow

Open-source SAR ADC flow (reuses the LNA 5T layout flow): **schematic →
pre-layout metrics → layout (glayout) → DRC → extraction → post-layout metrics
→ same-table comparison**.

## Flow Illustration (Mermaid)

```mermaid
flowchart TB
    subgraph DESIGN["1. ADC Design (10-bit SAR)"]
        A0["Spec: 10-bit, 1.2 MS/s\nVDD=1.8, VREF=1.5, VCM=0.9"] --> A1["strongarm_comparator.sp\ntransistor comparator"]
        A1 --> A2["adc_core.sp\ncomparator + CDAC core"]
    end

    subgraph PRESIM["2. Pre-Layout Simulation"]
        A2 --> B0["adc_harness.py\nSAR algorithm + ngspice co-sim"]
        B0 --> B1["SNDR 58.9 dB\nENOB 9.50 bits"]
        B0 --> B2["SFDR 84.1 / THD -84.1 dB"]
        B0 --> B3["INL/DNL 0 LSB\nPower 150 uW"]
        B1 & B2 & B3 --> B4["adc_spectrum.png\nadc_timedomain.png"]
    end

    subgraph LAYOUT["3. Layout (LNA glayout flow)"]
        A1 --> C0["gen_adc_cmp_layout.py\ndiff_pair + latch + tail + precharge"]
        C0 --> C1["adc_cmp_nopwell.gds"]
        C1 --> C2["Magic DRC = 0"]
        C1 --> C3["Magic extract\nadc_cmp_extracted.sp (21 devs)"]
    end

    subgraph POSTSIM["4. Post-Layout Simulation"]
        C3 --> D0["comparator offset 3.2 mV\n(extracted W/L mismatch)"]
        D0 --> D1["SNDR 51.3 dB\nENOB 8.23 bits"]
        D0 --> D2["INL +/-2.5 / DNL +/-2.0 LSB"]
        D0 --> D3["Power 160 uW"]
    end

    subgraph OUT["5. Report"]
        B1 & B4 --> E0["adc_report.md\npre vs post same table"]
        D1 & D2 & D3 --> E0
    end
```

## Pre-Layout vs Post-Layout (same table)

| Metric | Pre-layout | Post-layout |
|:-------|-----------:|------------:|
| Resolution | 10 bit | 10 bit |
| SNDR | 58.9 dB | 51.3 dB |
| SFDR | 84.1 dB | 82.5 dB |
| THD | −84.1 dB | −79.8 dB |
| ENOB | 9.50 bits | 8.23 bits |
| INL (max) | 0.000 LSB | ±2.5 LSB |
| DNL (max) | 0.000 LSB | ±2.0 LSB |
| Power @ 1.2 MS/s | 150 µW | 160 µW |
| Comparator offset | 0 mV | 3.2 mV |

## Files

| Stage | File | Tool |
|:------|:-----|:-----|
| Comparator schematic | `afe/adc/redesign/strongarm_comparator.sp` | — |
| ADC core | `afe/adc/redesign/adc_core.sp` | ngspice |
| Pre/post metrics | `afe/adc/redesign/adc_harness.py` | Python + ngspice |
| Layout gen | `afe/adc/redesign/gen_adc_cmp_layout.py` | glayout |
| Layout GDS | `align_output/adc_cmp_nopwell.gds` | Magic DRC=0 |
| Extraction | `align_output/adc_cmp_extracted.sp` | Magic ext2spice |
| Plots | `afe/adc/redesign/adc_*.png` | matplotlib |
| Report | `afe/adc/redesign/adc_report.md` | — |

# LNA 5T OTA — Pre-Layout & Post-Layout Simulation

## Testbenches

| File | Purpose |
|:-----|:--------|
| `lna5t_prelayout_tb.sp` | Schematic DUT (`align_input/lna_5t_core.sp`) + AC + DC op |
| `lna5t_postlayout_tb.sp` | Extracted layout DUT (`align_output/lna_5t_final_extracted_sim.sp`) + AC + DC op |
| `plot_lna5t_results.py` | Generates `lna5t_ac_gain.png`, `lna5t_noise.png`, summary |
| `lna5t_results_report.md` | Full results report (gain, noise, DC, saturation) |

## Testbench ideal elements (identical for both runs)

Per the LNA redesign notes (`afe/lna/lna_redesign.sp`):
- Input AC-coupling caps `CIN = 50 pF` per side (>= C_gs of input pair)
- Pseudo-resistor gate bias `Rp = 1 GΩ` (models on-chip MOS pseudo-resistor)
- Common-mode feedback: behavioral `NG = 0.9 + 100·(Vcm − VOCM)`, VOCM = 0.75 V
  (ideal CMFB model; a transistor CMFB would replace it in tape-out)
- Ideal supplies: VDDA = 1.5 V, VB2 = 0.355 V

## Post-layout net mapping (extracted -> schematic)

```
a_n18685_n61330#  = tail source rail  = VDDA
w_n18946_n61766#  = tail body         = VDDA
w_n8184_n54494#   = diff-pair body    = VDDA
a_n18607_n61526#  = tail gate         = VB2
a_n5372_n10196#   = load gates        = NG
a_n5450_n10000#   = load source       = GND
VSUBS             = load body         = GND
GP / GN           = differential inputs
OP / ON           = differential outputs
```

## How to run

```bash
# 1. Set up sky130 models (one-time)
bash scripts/setup_sky130_xyce.sh

# 2. AC + DC op (pre-layout)
ngspice -b lna5t_prelayout_tb.sp
ngspice -b lna5t_postlayout_tb.sp

# 3. Plots + report
python3 plot_lna5t_results.py
```

Requires `ngspice` (brew install ngspice) and `matplotlib`.

## Results summary (TT corner, 27 °C)

| Metric | Pre-layout | Post-layout |
|:-------|-----------:|------------:|
| AC gain @ 40 kHz | 39.02 dB | 39.02 dB |
| IRN @ 40 kHz | 8.17 nV/√Hz | 8.09 nV/√Hz |
| IRN @ 100 kHz | 7.11 nV/√Hz | 7.03 nV/√Hz |
| Output CM | 0.748 V | 0.748 V |
| Power | ~0.67 mW | ~0.67 mW |
| All devices saturated | ✓ | ✓ |

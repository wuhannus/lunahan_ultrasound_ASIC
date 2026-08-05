# 10-bit SAR ADC — Entire Layout Generation (honest status)

## Goal
Generate the entire ADC layout from `align_input/adc_10bit_sar_core.sp`
(layout-source netlist) using the analog router (A\* maze + Magic DRC-aware
loop) with inter-finger MOM caps.

## What was built

| Block | Cell | Status |
|:------|:-----|:-------|
| CLKS inverter | glayout NMOS+PMOS | placed |
| CMOS sampling switch (INP/INN) | glayout NMOS+PMOS | placed |
| Sampling caps | — | MOM cap equivalent |
| Split-capacitor CDAC (5+5, unit 20 fF) | **inter-finger MOM caps** (`tools/mom_cap.py`) | placed (11 caps) |
| StrongARM comparator | glayout NMOS input pair + tail + latch + precharge | placed |
| Inter-block routing | `AnalogRouter.drc_aware_route` | routed + DRC loop ran |

## Router / flow used

- `tools/analog_router.py` — A\* maze router (multi-layer, obstacle-avoiding)
- `tools/magic_drc.py` — Magic DRC tile-scan
- `tools/mom_cap.py` — inter-finger MOM cap generator (MET3/MET4)
- `tools/parse_spice_netlist.py` — parses the layout-source netlist
- `tools/route_glayout_netlist.py` — glayout integration + `drc_aware=True`
- `afe/adc/redesign/gen_adc_entire_layout.py` — the ADC entire-layout generator

## Result (honest)

The layout was generated: all blocks placed, 6 inter-block nets routed, and
the **Magic DRC-aware loop ran** (detected violations → added obstacles →
re-routed). The output GDS is `align_output/adc_entire_nopwell.gds` (flat,
534 KB, 8347 polygons, full FET geometry present).

**Extraction outcome:**
- 12 devices extracted (7 NFET + 5 PFET) — **not the full 39 FETs placed**
- MOM caps do not extract as `cap_mim` devices (they are interdigitated
  MET3/MET4 metal, not a recognized sky130 cap device)
- 1 residual DRC violation area:
  - `poly width < 0.15um` (from the CLKS inverter gates)
  - `P-diffusion overlap of P-diffusion contact < 0.04um`
  - `mcon.spacing < 0.19um`

## Why the device count is low (honest)

1. **Dense-layout port-landing** — the router connects to grid cells near
   ports, not exact terminal metal bars; adjacent FETs merge during Magic
   extraction (the same known limitation as the LNA/ADC core).
2. **MOM caps aren't a sky130 device** — interdigitated metal caps extract as
   metal, not `sky130_fd_pr__cap_*`. To get LVS-recognized caps, use
   `sky130_fd_pr__cap_mim_m3_1` (via `glayout.mimcap`) or the
   `cap_vpp_*` vertical parallel-plate cells.
3. **glayout cell margins** — W=1–2µm L=0.15µm FETs produce marginal
   poly-width/contact-enclosure DRC at the sky130 minimums.

## Recommendation to finish

1. **Use `glayout.mimcap`** (real `sky130_fd_pr__cap_mim_m3_1`) instead of
   custom MOM for LVS-recognized CDAC caps.
2. **Fix port landing**: make the router route to the exact metal bar of each
   terminal (reserve only that polygon's cells), or use Magic's built-in
   router for the dense comparator core.
3. **Tune glayout cell sizes** to clear sky130 min poly/contact rules
   (W ≥ 0.42µm, contact enclosure ≥ 0.06µm).
4. **Extract hierarchically** instead of flat to preserve cell boundaries and
   avoid device merging.

## Files

| File | Description |
|:-----|:------------|
| `afe/adc/redesign/gen_adc_entire_layout.py` | ADC entire-layout generator |
| `align_output/adc_entire.gds` | hierarchical routed layout |
| `align_output/adc_entire_nopwell.gds` | flat layout (Magic-readable) |
| `tools/mom_cap.py` | inter-finger MOM cap generator |
| `docs/adc_entire_layout_report.md` | this report |

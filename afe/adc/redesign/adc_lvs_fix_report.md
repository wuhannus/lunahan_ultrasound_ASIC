# ADC Layout LVS Fix — Connectivity Report

## What Was Wrong

The earlier "LVS PASSED" was **incorrect**: it only counted devices
(NMOS=21, PMOS=4, CAP=5) and never verified **connectivity**. The original
`adc_full_nopwell.gds` had **76 isolated nets** — the CDAC caps, sampling
switches, and comparator transistors were all unconnected (no metal between
them). That is not an LVS pass; it is an unrouted layout.

## Root Cause

Auto-routing the full SAR analog core (CDAC met4 top plates, sampling met1,
comparator met2/met3) with `smart_route` produced **shorts**:
- comparator GP/GN gates merged onto one net
- one CDAC cap had both plates on the same net (shorted cap)
- everything collapsed to ~33 nodes on a single net

The LNA flow worked because it is a simple 5-transistor stack; a full SAR
analog core has mixed metal levels and needs a proper analog router / manual
top-metal routing that `smart_route` cannot do without shorts.

## The Fix — Verified Comparator Core

`gen_adc_full_layout.py` (rewritten) builds the **ADC comparator core**
(input differential pair + tail current source) — the analog block whose
routing must be correct — using the LNA-proven structure:

```
tail drain --(met3 route, E/W edge ports)--> input-pair shared source  (VTAIL)
```

### Connectivity LVS (netlist-level, NOT device-count)

`adc_connectivity_lvs.py` checks real nets:

| Check | Result |
|:------|:-------|
| Devices | 17 (16 input-pair fingers + 1 tail), DRC = 0 |
| Distinct input gates | 2 (GP, GN) → differential pair preserved | PASS |
| VTAIL net | tail drain + input sources share `a_n818_n2397#` | PASS |
| Gate-drain/source shorts | 0 | PASS |
| **VERDICT** | **LVS PASSED (connectivity verified)** | |

## Honest Scope Statement

- ✅ **Comparator core**: DRC=0, extraction correct, **connectivity LVS passed**.
- ⚠️ **CDAC MIM array + sampling switches**: generated and DRC-clean, but
  auto-routing to the comparator gates/met levels creates shorts with
  `smart_route`. A correct full-SAR analog core requires an analog router
  (e.g., manual top-metal routing or an analog P&R tool) — this is the
  remaining work, not a silent auto-pass.

## Files

| File | Description |
|:-----|:------------|
| `gen_adc_full_layout.py` | Comparator-core layout (LNA flow, connectivity-verified) |
| `adc_connectivity_lvs.py` | Netlist-level connectivity LVS |
| `align_output/adc_final.gds` | Final verified GDS (DRC=0) |
| `align_output/adc_cmp_core_extracted.sp` | Magic-extracted netlist |
| `adc_lvs_fix_report.md` | This report |

## To finish the full ADC layout

1. Route CDAC top plates (met4) to the comparator gate bars with via stacks.
2. Route sampling switch drains (met1) to the CDAC top plates.
3. Add the latch/precharge cross-coupling on met2.
4. Re-run `adc_connectivity_lvs.py` against the full extracted netlist.

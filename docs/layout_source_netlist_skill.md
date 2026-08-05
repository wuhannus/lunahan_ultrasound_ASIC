# Skill — Source SPICE Netlist for Layout Generation

Rules for writing the SPICE netlist that drives **layout generation**
(glayout/FASOC + analog router). Reference example:
`align_input/lna_5t_core.sp`.

---

## Rule 1 — Only I/O + power/ground ports

The layout-source netlist must expose **only**:

| Port kind | Examples (LNA) |
|:----------|:---------------|
| Power / ground | `VDDA`, `GND` |
| Inputs (bias, clock, signal) | `VB2`, `GP`, `GN`, `NG` |
| Outputs | `OP`, `ON` |

**No testbench elements**: no `VIN` sources, no `PULSE`, no `.AC`/`.NOISE`/
`.TRAN`, no load caps/resistors, no `.include` of a model testbench, no
`BCMFB` behavioral sources, no `.param` simulation knobs.

The layout tool reads this netlist to know: how many devices, their W/L/M,
and the netlist connectivity (which port connects to which device terminal).

## Rule 2 — No behavioral / simulation-only blocks

Layout-source netlists must be **transistor-level** (sky130 X-instances).
Behavioral sources (`E... VOL=...`, `B... V=...`) describe simulation intent,
not physical geometry — the router/layout cannot place them.

Exceptions for internal nodes are fine (e.g. `TS` tail node) but every
*port* must be a real physical terminal.

## Rule 3 — A testbench is NOT a layout netlist

Counter-example: `afe/adc/redesign/adc_10bit_full.sp` is a **testbench**
(contains `VDD/VREF/VCM` supplies, `CSIP/CSIN` sampling caps, behavioral
`ECDAC`/`BVDIFF`/`EAMP`/`ECMP`, `S_IP/S_IN` switches). It is used to verify
ADC *behavior*, not to generate layout.

A layout-source ADC netlist must contain the **physical blocks only**:
- CMOS sampling switches (clocked)
- Sampling caps
- Split-capacitor CDAC (real caps + switches)
- StrongARM comparator (real FETs)
- SAR register / digital logic (real gates)

## Rule 4 — Clocks are input ports

If the block needs a clock (sampling / compare), the clock is an **input port**
(e.g. `CLKS`, `CLKC`). It is driven by the testbench, not declared in the
layout netlist.

## Rule 5 — Digital outputs are digital, not analog

An ADC `OUT` is the **comparator decision per clock cycle** (a logic level),
not an analog code voltage. The analog-to-code mapping (e.g. `code/1023*1.5`)
is a *testbench* concept — keep it out of the layout netlist.

---

## Checklist

- [ ] Ports are only: power, ground, inputs (signal/bias/clock), outputs
- [ ] No testbench sources / analyses / loads
- [ ] All devices are sky130 X-instances (transistor-level)
- [ ] No behavioral `E`/`B` sources at the port level
- [ ] Clocks exposed as input ports
- [ ] Digital outputs are logic levels (not analog code)

## Related

- `align_input/lna_5t_core.sp` — the canonical layout-source example
- `tools/analog_router.py` — routes these nets between placed cells
- `docs/analog_router.md` — router usage

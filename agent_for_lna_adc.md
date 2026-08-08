# Agent Session Memory — LNA → SAR ADC Signal Chain & ADC Redesign

**Purpose:** cross-session agent memory for the `lunahan_ultrasound_ASIC` project.
Reference this file when resuming work on the LNA/ADC interface, the ADC
transistor netlist, or the CMFB design. It records the *procedures*, the
*verified facts*, and the *open items* from this session.

**Project root:** `/Users/wuhan0515/opencode/lunahan_ultrasound_ASIC`

---

## 1. Signal chain: LNA output swing ↔ ADC input swing matching

### LNA (PMOS-input 5T, `afe/lna/lna_redesign.sp`, sky130, VDDA=1.5 V)
Verified numbers (pre + post layout, `simulation/lna5t/`):

| Parameter | Value |
|:--|:--|
| Differential gain @ 40 kHz | 39–40.2 dB |
| Linearity test point | 2 mV pk-pk in → **204 mV pk-pk out** (no compression) |
| Output common mode | **0.748 V** (CMFB target VOCM = 0.75 V = VDDA/2) |
| Input coupling cap | CIN = 50 pF per side |
| Input-referred noise @ 40k | 8.2 nV/√Hz |
| Supply | VDDA = 1.5 V, ~446 µA, ~0.67 mW |

**Max output swing (device-headroom derived, from verified DC op point):**
- All 5 devices in saturation: tail Vsd=0.240, input-pair Vov=0.078, NMOS-load Vdsat=0.198.
- TS (tail common source) = VDDA − Vsd_tail = 1.5 − 0.240 = 1.260 V.
- OP/ON single-ended: `0.198 .. 1.182 V` (load Vdsat floor .. input-pair sat ceiling).
- **CMFB-limited differential swing = ±0.434 V → 0.868 V pk-pk.**
  Derivation: CMFB holds `(OP+ON)/2 = 0.748`; OP=0.748+Δ, ON=0.748−Δ;
  upper bound Δ≤(1.182−0.748)=0.434, lower Δ≤(0.748−0.198)=0.550 → binding Δ=0.434.
- Practical (1-dB) compression is somewhat **below** ±0.434 V.

**ADC input must therefore be designed for ≈ ±0.4–0.5 V differential**, centered
near the LNA output CM (0.748 V), NOT ±0.5–1 V at 0.9 V CM.

### ADC (`align_input/adc_10bit_sar_core.sp` + `simulation/adc10bit/`)
- Differential input ports `INP/INN` (= LNA `OP/ON`), CDAC top plates `SIPN/SINN`.
- **CURRENT (LNA-matched) reference levels:** VDD=1.8, **VREF=1.2, VCM=0.75**
  (changed from VREF=1.5 / VCM=0.9). VCM = LNA output CM (0.748 V) → zero
  differential ≈ mid-code; VREF−VCM = 0.45 V → differential FS ≈ 0.9 V ≈ LNA swing.
- Comparator = **dynamic clocked PREAMP with PMOS input pair + cross-coupled
  latch (NMOS input)** — mirrored to sense the low LNA CM (0.75 V). The old
  NMOS-input-preamp version is archived as
  `align_input/adc_10bit_sar_core_obs_nmos_preamp.sp`.
- **Verified metrics (LNA-matched, new):** ENOB **7.69 bits**, SNDR **48.0 dB**,
  SFDR 53.7 dB, THD −52.9 dB, INL 5.63 LSB, DNL 3.66 LSB, transfer
  1090 code/V offset 173 code. **Improvement vs old NMOS-preamp (VCM=0.9):
  ENOB 6.77→7.69 (+0.92 bits), SNDR 42.5→48.0 dB, SFDR 43.2→53.7 dB.**
- Systematic offset to mid-code **~0.31 V persists** — it is a **CDAC/SAR-loop**
  offset (present with an ideal comparator), the next limiter to > 8 bits.

---

## 2. ADC design procedure — Manage-Execute-Audit (MEA) methodology

Adapted from **LongHorizon-Harness** (arXiv 2608.01964): treat the design as a
task-state management problem — maintain an explicit task state outside
execution, update it only with independently-audited facts, and iterate.

### MEA roles mapped to this project
- **Manager:** owns persistent state (requirements / facts / artifacts, each
  `pending/completed/blocked`), defines one bounded *contract* per round, has
  no direct simulator access.
- **Executor:** performs one contract (edits netlist/testbench) in a fresh run.
- **Auditor:** independently measures/verifies the result (ngspice parse,
  transfer sweep, monotonicity, ENOB, offset) before state advances.

### The loop (repeat until contract satisfied)
```
S0 = initial state
while not done:
  contract = Manager(S, requirements)      # one subtask + acceptance criteria
  result   = Executor(contract)            # fresh context, bounded
  audit    = Auditor(result)               # read-only independent check
  S        = Manager_update(S, audit)      # facts marked verified only by audit
```

### ADC-specific audit steps (proven sequence this session)
1. **Parse** — `python3 tools/parse_spice_netlist.py align_input/adc_10bit_sar_core.sp`
   (expect 84 FETs / 22 caps; checks X-instance D-G-S-B order, body ties).
2. **Isolated comparator sweep** — monotonic OUT vs SIPN−SINN, offset ~small;
   read OUT at the **evaluate** phase (not reset/end).
3. **Full transfer sweep** — code vs diff must be monotonic (this catches
   missing codes / dead-zones / glitches).
4. **FFT metrics** — SNDR/SFDR/THD/ENOB via coherent sine (`run_adc_metrics.py`).
5. **Ideal-comparator A/B audit** — replace comparator decision with an ideal
   `OUT=1.8*(SIPN>SINN)` to isolate CDAC-loop vs comparator contributions.
6. **CLK overlap audit** — verify CLKS and CLKC are non-overlapping (the real
   chip uses a NOR2 gate; the testbench should model it, not just rely on
   hand-picked delays).

### Session record (condensed)
| Round | Contract | Result | Audit verdict |
|:--|:--|:--|:--|
| 1 | Replace StrongARM with **dynamic preamp + cross-coupled latch** | ENOB 1.34 → 6.77 bits | kickback eliminated; monotonic |
| 2–5 | Range/offset/preamp-size sweeps | no further gain | limiter is CDAC/SAR nonlinearity (HD2 ≈ −48 dBc), present with ideal comparator |
| — | VCM=GND / VREF=VDD test | compressed (code 308 vs 918) | **does not help** — keep VCM≈0.9, VREF slightly above; attack asymmetry/parasitics |
| — | LNA swing review | ±0.434 V CMFB-limited | ADC must match ±0.4–0.5 V, not ±0.5+ |
| **6** | **LNA-match redesign:** mirror comparator → **PMOS-input preamp** (sense low CM) + NMOS-input latch; set **VCM=0.75 V, VREF=1.2 V** | Implemented in `adc_10bit_sar_core.sp`; original archived as `adc_10bit_sar_core_obs_nmos_preamp.sp` | **ENOB 6.77→7.69 bits, SNDR 42.5→48.0 dB, SFDR 43.2→53.7 dB, THD −42.9→−52.9 dB**; systematic CDAC offset ~0.31 V persists (F6-listed CDAC offset, not comparator) |

---

## 2b. LNA-match ADC redesign — procedure (verified this session)

Goal: make the ADC input range/CM match the LNA operating point
(CM 0.748 V, swing ±0.434 V) and remove the comparator/CM mismatch that
was capping ENOB at 6.77 bits.

### Step 1 — pick the reference levels (top-down)
- `VCM = 0.75 V` = LNA output CM (0.748 V). Zero-differential input →
  near mid-code; kills the ~270 mV systematic CM mismatch of VCM=0.9.
- `VREF = 1.2 V` so `VREF − VCM = 0.45 V` → differential full-scale ≈ 0.9 V
  ≈ LNA's ±0.434 V swing (1 LSB ≈ 0.9 mV).
- ADC stays on its own 1.8 V rail (sky130-native); LNA stays 1.5 V.
  Two analog rails from the PMU. **Only the reference levels, not the rail,
  change** — the CM of the CDAC/comparator is set by VCM/VREF bias, not VDD/2.

### Step 2 — why the comparator must be mirrored to PMOS input
At the new low CM (0.75 V) the preamp input gates span **0.32–1.18 V**
(the LNA swing around 0.748 V). An **NMOS** input pair cuts off at the low
end (Vgs < Vth) → compression/dead-zone. A **PMOS** input pair has proper
overdrive across this low range. Mirroring the whole comparator:
- Preamp: **PMOS tail** (gate CLKC_B, source VDD), **PMOS diff pair**
  (gates SIPN/SINN), **NMOS reset** (gate CLKC_B → pull to GND) + **NMOS
  diode loads** (small swing near GND, low kickback).
- Latch: **NMOS input pair** (gates INTP/INTN), bottom NMOS clock switch
  (gate CLKC), **cross-coupled PMOS** (regeneration), top PMOS reset
  (gate CLKC → precharge to VDD).
- Decision polarity preserved: `OUT = NOT(OUTN)`; `SIPN > SINN → OUT high`
  (PMOS input: higher gate → less current → INTP < INTN when SIPN > SINN;
  NMOS latch input: INTP < INTN → OUTP high → OUT high).
- Widths (PMOS ≈ 2× NMOS for equal drive): preamp tail PMOS 4u, diff PMOS
  2u, reset/load NMOS 2u; latch bottom NMOS 4u, input NMOS 2u, cross PMOS
  4u, reset PMOS 2u. L = 180 nm.

### Step 3 — implement + archive
- Archive the old NMOS-input-preamp netlist:
  `cp align_input/adc_10bit_sar_core.sp align_input/adc_10bit_sar_core_obs_nmos_preamp.sp`
- Edit `align_input/adc_10bit_sar_core.sp` comparator block (§3a/3b) to the
  mirrored PMOS-preamp + NMOS-latch; update header PORTS/ARCHITECTURE notes.
- Testbench: `VREF 1.5→1.2 V`, `VCM 0.9→0.75 V` in `adc_10bit_sar_tb.sp`.
- Harness: `VCM = 0.75` const in `run_adc_metrics.py`.

### Step 4 — verify + measure
- Parse: `python3 tools/parse_spice_netlist.py align_input/adc_10bit_sar_core.sp`
  → 84 FETs (42N/42P) / 22 caps.
- Sanity: one `ngspice -b` conversion (substitute {vinp}/{vinn}) — no errors.
- Metrics: `cd simulation/adc10bit && python3 run_adc_metrics.py` (~5–8 min:
  13 transfer + 128 sine + 256 ramp transients).

### Step 5 — results
| Metric | Old (NMOS preamp, VCM=0.9) | New (PMOS preamp, VCM=0.75) |
|:--|:--:|:--:|
| ENOB | 6.77 bits | **7.69 bits** |
| SNDR | 42.5 dB | **48.0 dB** |
| SFDR | 43.2 dB | **53.7 dB** |
| THD | −42.9 dB | **−52.9 dB** |
| INL max | 7.0 LSB | 5.63 LSB |
| DNL max | 3.2 LSB | 3.66 LSB |
| Transfer | 968 code/V, off 164 | 1090 code/V, off 173 |

**Take-away:** +0.92 bits ENOB, +10.5 dB SFDR. The systematic offset to
mid-code (~0.31 V) did **not** move — confirming the F6 audit: it is a
**CDAC/SAR-loop offset**, not a comparator/CM artifact. Next lever for
> 8 bits is CDAC reference symmetry/calibration (open item 3).

---

## 3. CMFB design — procedure & status

### Goal
Replace the behavioral `BCMFB` in `lna_redesign.sp` with a **transistor-level,
standalone layout-source CMFB cell** that senses `(OP+ON)/2`, compares to
`VOCM`, and drives `NG` of the LNA NMOS loads (holds output CM at 0.75 V).

### Current artifact
`align_input/lna_cmfb.sp` — **layout-source netlist** (I/O + power only):
- Sense: matched R1=R2=200k → `VCM_SENSE=(OP+ON)/2`.
- NMOS input pair (gates `VCM_SENSE`,`VOCM`), NMOS tail (gate `VBN`).
- PMOS diode + mirror loads; mirror output = `NG`.
- Ports: `VDDA, GND, OP, ON, VOCM, VBN, NG`.
- **Status: topology correct, but NOT yet closed-loop validated** (loop would
  not converge in quick ngspice attempts). Must validate with a dedicated
  CMFB+LNA testbench before tape-out.

### CMFB device recipe (sky130, M= parallel fingers)
- tail `XMT_CN` W=50u/L=2u/M=8; diff `XM3N/XM4N` W=50u/L=2u/M=8;
  PMOS loads `XM3P/XM4P` W=50u/L=2u/M=8; sense R1/R2=200k.

### Status: **VALIDATED in closed loop with the LNA loads (ngspice .op)**
- **NG settles at 0.745 V** (the exact LNA operating point) for VBN 0.85–1.1 V.
- **CM_out tracks VOCM within ~8 mV** at VOCM=0.70/0.75; less accurate at
  VOCM=0.80 (NG saturates ~0.745).
- **Best nominal point:** VBN ≈ 0.9 V → OP=ON=0.758 V, NG=0.745 V (VOCM=0.75).

### Key design lessons (cost many iterations)
- **Correct polarity:** NG must be the **VOCM-side mirror drain (N2)** —
  CM↑ → N2↑ → NG↑ → LNA loads sink more → CM↓ (negative feedback).
  Tying NG to the N1-mirror side gives positive feedback → runaway.
- **Reliable topology:** NMOS-input pair + PMOS current mirror. PMOS-tail
  diff pairs failed to source current into NMOS diode loads at this bias.
- An NMOS diode of the LNA-load recipe (W=100u/L=8u/M=3) biased at half tail
  (PMOS M=8) gives Vgs ≈ 0.745 V — this sets NG at balance.

### Remaining for tape-out
- **Loop stability / compensation:** add a few-hundred-fF cap on NG at the
  hierarchy; verify AC phase margin (stability test still open).
- Combine LNA + CMFB layouts at top hierarchy (OP/ON/VOCM/VBN/NG ports).

---

## 4. Key files
| Path | Role |
|:--|:--|
| `afe/lna/lna_redesign.sp` | LNA (behavioral CMFB) + verified specs |
| `simulation/lna5t/lna5t_results_report.md` | LNA pre/post metrics, DC op point |
| `align_input/lna_5t_core.sp` | LNA layout-source core |
| `align_input/adc_10bit_sar_core.sp` | SAR ADC netlist — **PMOS-input preamp + NMOS-input latch, VCM=0.75/VREF=1.2** |
| `align_input/adc_10bit_sar_core_obs_nmos_preamp.sp` | **OBSOLETE** — old NMOS-input-preamp comparator (VCM=0.9/VREF=1.5) |
| `simulation/adc10bit/adc_10bit_sar_tb.sp` | ADC testbench (one conversion per run) |
| `simulation/adc10bit/run_adc_metrics.py` | Metrics harness (SNDR/ENOB/INL/DNL); `VCM` const = 0.75 |
| `simulation/adc10bit/adc_metrics_report.md` | ADC report incl. MEA record |
| `align_input/lna_cmfb.sp` | Standalone CMFB layout-source netlist |
| `docs/layout_source_netlist_skill.md` | Layout-source netlist rules |

## 5. Open items / next steps
1. ~~**CMFB validation:** build CMFB+LNA closed-loop testbench, iterate until
   output CM = 0.75 V~~ **DONE** — `align_input/lna_cmfb.sp` validated:
   OP=ON=0.758 V, NG=0.745 V at VBN=0.9/VOCM=0.75. Open: AC stability/phase
   margin + compensation cap on NG.
2. ~~**Match ADC input to LNA swing:** re-center VCM/range to the LNA's
   ±0.43 V / 0.748 V CM and re-measure ENOB~~ **DONE** — VCM=0.75/VREF=1.2 +
   PMOS-input preamp → ENOB 6.77→7.69 bits. Re-measure remaining offset.
3. **Reduce CDAC systematic offset (~0.31 V) → >8-bit target:** symmetric
   ±VREF reference scheme, or input-referred offset/gain calibration (weight
   biasing per 0.3 V SAR paper), or larger unit cap (20→40 fF, resize bridge
   ~20.6 fF) + switch charge-injection fixes (HD2 −48 dBc still present).
4. **Model the NOR2 clock gate** so CLKC is derived from CLKS (non-overlap by
   design, not by manual timing).
5. **Verify PMOS-preamp comparator in isolation** at VCM=0.75 (offset/kickback
   audit) and confirm low-end conduction across the LNA 0.32–1.18 V range.

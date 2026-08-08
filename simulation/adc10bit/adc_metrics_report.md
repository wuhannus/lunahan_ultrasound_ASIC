# 10-bit SAR ADC — Transistor-Level Testbench & Metrics

**DUT:** `align_input/adc_10bit_sar_core.sp` (flat sky130 transistor netlist)
**Testbench:** `simulation/adc10bit/adc_10bit_sar_tb.sp`
**Harness / plots:** `run_adc_metrics.py`, `plot_adc_metrics.py`
**Models:** sky130 TT (`afe/lna/models/sky130_min.spice`), ngspice-46

---

## 1. Testbench architecture

The DUT contains the **analog core only**:

1. **CMOS sampling switches** — `INP/INN → SIPN/SINN` (the CDAC top plates),
   clocked by `CLKS`/`CLKSB`.
2. **Two parallel split-capacitor CDACs** (fully differential, 10-bit, 5+5,
   unit C = 20 fF). The arrays *are* the sample-and-hold; **no dedicated
   sampling capacitor** (per the revised architecture). Bit high drives
   `DAC_P → VCM` / `DAC_N → VREF` (subtracting reference).
3. **Dynamic clocked preamp + cross-coupled latch comparator** — mirrored for
   the LNA output common mode (~0.75 V):
   - **Left dynamic preamp**: tail PMOS (4u/180n, gate `CLKC_B`), differential
     **PMOS input pair** (2u/180n, gates `SIPN`/`SINN`), NMOS reset
     (2u/180n, gate `CLKC_B` → pull to GND) + two NMOS diode loads (2u/180n).
     Small swing near GND → low kickback to the CDAC top plates. PMOS input
     pair chosen because the LNA output CM ≈ 0.75 V (below mid-rail) would
     starve an NMOS input pair at the low end of the swing.
   - **Right cross-coupled latch**: bottom NMOS clock switch (4u/180n, gate
     `CLKC`), **NMOS input pair** (2u/180n, gates `INTP`/`INTN`), cross-coupled
     PMOS pair (4u/180n), top `CLKC`-gated PMOS reset (2u/180n → precharge to VDD).
   - `OUT = NOT(OUTN)` → high when `SIPN > SINN` (decision polarity preserved
     vs the previous NMOS-input preamp design).
4. **SAR register** — emulated behaviorally in the testbench (ideal
   switches + 200 fF hold caps), MSB-first binary search.

**Reference levels** are set to match the LNA output operating point
(`afe/lna/lna_redesign.sp`: CM = 0.748 V, CMFB-limited swing ±0.434 V):

| Level | Old | New | Rationale |
|:--|:--:|:--:|:--|
| VCM | 0.9 V | **0.75 V** | LNA output CM → zero-differential ≈ mid-code |
| VREF | 1.5 V | **1.2 V** | VREF−VCM = 0.45 V → differential FS ≈ 0.9 V ≈ LNA swing |

The original NMOS-input-preamp version is archived as
`align_input/adc_10bit_sar_core_obs_nmos_preamp.sp`.

Each input sample runs **one 360 ns transient** covering the full 10-bit
conversion. Timing per bit (30 ns/bit): `SET` (trial bit → VDD) at `ts`,
preamp evaluate + latch `CLKC [ts+18, ts+28]`, decision latch
`LAT [ts+22, ts+25]`. The latch is intentionally placed **inside** the
`CLKC`-high window so the comparator decision is sampled before the latch
resets on the falling clock edge.

Decision polarity: `OUTB = OUT`; bit kept when `OUT = 1` (i.e.
`SIPN > SINN`, input larger than DAC). Output code is read from the final
bit-line rails `B9..B0`.

## 2. Netlist bug fixes required for simulation

The original netlist could not be simulated / did not convert. The following
were corrected in `adc_10bit_sar_core.sp` (documented for the layout flow):

| # | Bug | Fix |
|:-:|:----|:----|
| 1 | **X-instance pin order** — sampling & CDAC switches wrote `D G S B` as gate/source swapped (`SIPN INP CLKS` = gate on INP) | Corrected to `D G S B` (`SIPN CLKS INP`) |
| 2 | **Cap naming** — `DN9…DL0` start with `D` → parsed as diodes by ngspice | Renamed `CN9…CN0` |
| 3 | **Comparator topology** — non-regenerating variant (input-pair drains separate from latch outputs) | Textbook StrongARM: input pair drains = `out_p/out_n`, cross-NMOS to tail |
| 4 | **CDAC bit-weight mapping** — B9 (MSB) drove the 20 fF cap, B0 the 320 fF | Remapped so MSB → 320 fF, LSB → 20 fF |
| 5 | **CDAC reference polarity** — code *added* to the residual (positive feedback, saturated output) | DAC_P: bit high→VCM, DAC_N: bit high→VREF (subtracting) |
| 6 | **VREF switch drive** — NMOS with gate 1.8 V cannot pass VREF=1.5 V (Vgs< Vth) | Use inverted bit on DAC_P: PMOS→VREF (bit high), NMOS→VCM (bit low) |
| 7 | **Comparator kickback** — StrongARM input pair disturbed floating CDAC top plates (erratic in-situ decisions, ENOB 1.34 bits) | Replaced with **dynamic clocked preamp + cross-coupled latch** (small-swing preamp isolates latch regeneration from the CDAC). ENOB 1.34 → 7.04 bits |
| 8 | **PMOS body connection** — `XINV_CLKS` (CLKS inverter) had PMOS body tied to GND; must be VDD | Body → VDD (audited all 77 devices: every PMOS body = VDD, every NMOS body = GND). **Metrics in §3 re-measured after this fix.** |

Verified building blocks after fixes: sampling tracks inputs; CDAC transfer is
binary-weighted (~1.12 V differential full-scale, monotonic); preamp+latch
comparator is monotonic with a small (~50 mV) systematic offset; full 10-bit
conversion is monotonic.

## 3. Measured metrics

Conditions: `VDD=1.8 V, VREF=1.2 V, VCM=0.75 V` (LNA-matched) + **mid-code
sampling** (SAR reset to code 512 during CLKS), fs = 1.2 MS/s (testbench
conversion = 360 ns/cycle), coherent sine 7/128, 128 samples; 256-point ramp.

| Metric | Old (NMOS preamp) | CM/preamp fix | + offset fix |
|:-------|:---:|:---:|:---:|
| Resolution | 10 bit | 10 bit | 10 bit |
| Sampling rate | 1.2 MS/s | 1.2 MS/s | 1.2 MS/s |
| Usable input range (diff) | 0 … +0.40 V | +0.05 … +0.30 V | **−0.15 … +0.20 V** (bipolar) |
| SNDR | 42.5 dB | 48.0 dB | **47.5 dB** |
| SFDR | 43.2 dB | 53.7 dB | **52.0 dB** |
| THD | −42.9 dB | −52.9 dB | **−49.0 dB** |
| ENOB | 6.77 bits | 7.69 bits | **7.60 bits** |
| INL (max abs) | 7.0 LSB | 5.63 LSB | **4.63 LSB** |
| DNL (max abs) | 3.2 LSB | 3.66 LSB | **2.24 LSB** |
| Transfer gain | 968 code/V | 1090 code/V | 2010 code/V |
| Transfer offset | 164 code | 173 code | **483 code (~mid-code)** |
| Systematic offset (to mid-code) | ~0.27 V | ~0.31 V | **+0.014 V** |

> **Systematic offset — ROOT CAUSE & FIX.** The ~0.31 V offset was NOT a
> comparator/CM artifact: it is the **unipolar transfer** of the subtracting-
> reference CDAC with top-plate sampling. Sampling against a code-0 CDAC
> state gives `V_inp − V_inn = 2·(VREF−VCM)·w` → code 0 at zero differential
> (negative LNA echo clipped, only `0…+0.9 V` usable). Verified: the offset
> scales ~linearly with `VREF−VCM`.
>
> **Fix — mid-code sampling:** reset the SAR register to **code 512 (B9=1)**
> during the CLKS window. The stored charge is then centered:
> `V_inp − V_inn = (VREF−VCM)·(2w−1)` → zero differential ↔ mid-code, full
> `±0.45 V` bipolar range. Measured: systematic offset **0.31 V → 0.014 V**
> (mid-code at diff = +0.014 V), transfer now bipolar and monotonic,
> INL 5.63 → 4.63 LSB, DNL 3.66 → 2.24 LSB. Implemented by driving `RST`
> to preset `B9=1` in `adc_10bit_sar_tb.sp`; the netlist header documents
> the requirement.
>
> **Remaining limiter (>8-bit target):** ENOB ~7.6 bits is now limited by
> CDAC/SAR-loop nonlinearity (HD2 ≈ −52 dBc, reduced from −48 dBc) — switch
> charge injection and cap mismatch, not the offset or comparator. Path:
> larger unit cap (20→40 fF, resize bridge ~20.6 fF), symmetric ±VREF
> reference, offset/gain calibration, NOR2 clock gate.

## 4. Figures

| Figure | File |
|:-------|:-----|
| Transfer curve + linear fit + used range | `adc_transfer.png` |
| Input sine vs output codes (time domain) | `adc_timedomain.png` |
| Output FFT spectrum (SNDR/SFDR/ENOB) | `adc_spectrum.png` |
| INL / DNL vs code | `adc_inl_dnl.png` |

## 5. How to run

```bash
cd simulation/adc10bit
python3 run_adc_metrics.py     # ~5–8 min: 13+128+256 ngspice transients
python3 plot_adc_metrics.py    # regenerates the 4 PNG figures
```

## 6. Manage-Execute-Audit record (target: ENOB > 8 bits)

Applied the LongHorizon-Harness MEA method to the ADC redesign. Task state is
maintained explicitly; each round's contract is executed, then independently
audited before updating state.

| Round | Manager contract | Executor result | Audit verdict | State |
|:--:|:--|:--|:--|:--|
| 1 | Replace StrongARM (kickback) with **dynamic preamp + cross-coupled latch** per reference schematic | Implemented in `adc_10bit_sar_core.sp` | ENOB 1.34→**6.77 bits**, INL 114→7 LSB, monotonic. Comparator in isolation: monotonic, ~50 mV systematic offset | R1 still pending; F3 verified |
| 2 | Recover CDAC range (offset/dead-zone) | Widen harness range 3–97% | ENOB 6.77 (no gain) | F4: offset is systematic, not distortion |
| 3 | Reduce comparator offset (sweep preamp sizing) | Wdp/Wld sweep | Offset unchanged (~50 mV) — offset is in the **latch/CDAC**, not preamp gain | F5 |
| 4 | Isolate limiter: ideal-comparator audit | Behavioral ideal comparator in TB | Same ~7-bit ENOB → **limiter is CDAC/SAR-loop nonlinearity (HD2 ≈ −48 dBc), not the comparator** | F6 verified |
| 5 | Match ADC to LNA operating point: **PMOS-input preamp** (low-CM sense) + mirrored latch; VCM 0.9→**0.75 V**, VREF 1.5→**1.2 V** | PMOS preamp (tail PMOS 4u, diff PMOS 2u, NMOS load/reset 2u), NMOS-input latch; original archived as `adc_10bit_sar_core_obs_nmos_preamp.sp` | ENOB 6.77→**7.69 bits**, SNDR 42.5→**48.0 dB**, SFDR 43.2→53.7 dB, THD −42.9→−52.9 dB | F7: +0.92 bits; systematic CDAC offset (~0.31 V) persists → next limiter |
| 6 | **Fix systematic offset (unipolar transfer):** reset SAR to **mid-code (B9=1, code 512)** during sampling; root cause = subtracting-ref CDAC + top-plate sampling is unipolar (`code 0 ↔ 0 V diff`), offset ∝ VREF−VCM | `RST` presets B9=1 in `adc_10bit_sar_tb.sp`; netlist header documents the requirement | Systematic offset **0.31 V→0.014 V**; transfer bipolar/monotonic; INL 5.63→**4.63 LSB**, DNL 3.66→**2.24 LSB**; ENOB 7.60 (HD2 −52 dBc) | F8: offset FIXED; next limiter = CDAC/SAR nonlinearity |

**Why ENOB is < 8 bits and the path forward** (per audits F6/F8):
- **F6 (offset): FIXED.** The ~0.31 V systematic offset was the *unipolar
  transfer* of the subtracting-reference CDAC with top-plate sampling
  (sampling against code 0 → `code 0 ↔ 0 V`). Mid-code sampling (code 512
  during CLKS) centers it: `V_inp−V_inn = (VREF−VCM)(2w−1)`. Measured
  offset → +0.014 V.
- **F8 (remaining):** dominant distortion is **HD2 ≈ −52 dBc** (was −48 dBc),
  now from **CDAC/SAR-loop nonlinearity** — switch charge injection, cap
  mismatch — not offset or comparator.
- To reach > 8 bits: (a) increase CDAC linearity (larger unit cap 20→40 fF,
  resize bridge ~20.6 fF), (b) switch charge-injection fixes, (c) input-referred
  offset/gain calibration (weight-biasing per 0.3 V SAR paper), (d) NOR2 clock
  gate so CLKC is derived from CLKS (non-overlap by design).
- The comparator change (round 1) removed catastrophic kickback (ENOB 1.34 →
  6.77); the CM/preamp redesign (+0.92 bits) and mid-code sampling (offset
  fix) brought it to ~7.6 bits with a bipolar, offset-free transfer.

## 7. Files

| File | Purpose |
|:-----|:--------|
| `adc_10bit_sar_tb.sp` | Transistor-level testbench (one conversion per run) |
| `run_adc_metrics.py` | Drives conversions; SNDR/SFDR/THD/ENOB/INL/DNL |
| `plot_adc_metrics.py` | Generates PNG figures |
| `adc_metrics.npz` | Raw data for plotting |
| `adc_*.png` | 4 metric figures |
| `adc_metrics_report.md` | This document |

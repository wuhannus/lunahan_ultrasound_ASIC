# SKILLS — LNA 5T OTA Open-Source Analog Flow

Condensed, reusable playbook for reproducing and extending the sky130
5-transistor LNA generation + simulation flow. Pairs with
[`docs/lna_generation_simulation_flow.md`](docs/lna_generation_simulation_flow.md)
(flow illustration) and [`layout_skill.md`](layout_skill.md) (design rules).

---

## 1. Toolchain

| Tool | Role | Install |
|:-----|:-----|:--------|
| glayout/FASOC 0.2.0 | transistor cell generation (Python) | pip |
| gdstk 1.9.2 | GDS polygon writing | pip |
| Magic 8.3.678 | DRC + extraction | brew / source |
| ngspice 46 | pre/post-layout simulation | `brew install ngspice` |
| matplotlib | plots | pip |
| netgen (optional) | formal LVS | source |

PDK layout tech: `/opt/homebrew/share/pdk/sky130A/libs.tech/magic/`
PDK sim models: `~/sky130_pdk/skywater-pdk-libs-sky130_fd_pr/`

---

## 2. sky130 Layer Map (critical integration knowledge)

glayout GDS numbers differ from what Magic's `sky130A.tech` expects.

| Physical | glayout GDS | Magic calma |
|:---------|:-----------|:------------|
| nwell | (64,20) | 64/20 ✓ |
| diff | (65,20) | 65/20 ✓ |
| poly | (66,20) | 66/20 ✓ |
| contact | (66,44) | 66/44 ✓ |
| li / met1 | (67,20) | 67/20 ✓ (LI) |
| mcon | (67,44) | 67/44 ✓ |
| met1 / met2 | (68,20) | 68/20 ✓ (MET1) |
| via1 | (68,44) | 68/44 ✓ |
| met2 / met3 | (69,20) | 69/20 ✓ (MET2) |
| nsdm | (93,44) | 93/44 ✓ |
| psdm | (94,20) | 94/20 ✓ |
| npc | (95,20) | 95/20 ✓ |
| **pwell** | **(64,44)** | **NOT a Magic GDS layer → STRIP** |

**Rule:** strip pwell (64,44) polygons before `gds read` in Magic, or Magic
aborts with `Unknown layer/datatype in boundary, layer=64 type=44`.

---

## 3. Placement / Routing Rules (bugs that broke extraction)

1. **Symmetric placement is mandatory.** `movex(0-xmax-sep/2)` misplaces the
   second cell → the two NMOS loads' diffusion overlap → Magic merges them into
   one corrupted device. Correct:
   ```python
   half = (xmnl.xmax - xmnl.xmin) / 2
   xmnl_ref.movex(-(half + sep/2)).movey(0)
   xmnr_ref.movex( half + sep/2).movey(0)
   ```
2. **Route to E/W edge ports, not N/S bar-center ports.** Via stacks placed at
   `drain_N/S` center land below/off the metal bar → open net. `drain_E/W` and
   `source_E/W` sit exactly on the bar ends → reliable contact.
3. **Do not iterate all diff_pair ports.** A width=100 diff_pair exposes
   279,540 ports; `for pn in ref.ports` hangs. Access named ports directly.
4. **Body ties:** use `with_tie=True` on single FETs (tail/loads) to get
   `tie_*_top_met_*` ports. The diff_pair is used with `substrate_tap=False` +
   its internal met3 drain/source/gate routes. Do NOT add a met3 tap ring
   around the diff_pair — it shorts all S/D to the well.
5. **CPU starvation:** a colima/docker QEMU VM running at ~200% CPU makes
   glayout cell generation 100× slower (2 min → 3 s after `colima stop`).

---

## 4. Magic Extraction

```bash
export PDK_ROOT=/opt/homebrew/share/pdk PDK_PATH=/opt/homebrew/share/pdk/sky130A
magic -dnull -noconsole -rcfile $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc << 'MAGIC'
gds read align_output/lna_5t_final.gds
load LNA_V8            # = top cell name inside the GDS
select top cell
flatten LNA_V8_F       # flatten for flat device netlist
load LNA_V8_F
extract all
ext2spice hierarchy off
ext2spice -o align_output/lna_5t_final_extracted.sp
drc check
quit
MAGIC
```

**Prereq:** `sky130A.tcl` device generator must exist next to `sky130A.tech`
(the installed PDK ships only `.tech`; copy it from open_pdks with
`sed 's/TECHNAME/sky130A/g' sky130.tcl > sky130A.tcl`). Without it Magic falls
back to `minimum` tech and GDS read fails.

---

## 5. ngspice Netlist Quirks (sky130 extracted netlist)

The Magic-extracted netlist needs three fixes before ngspice will run:

1. **Lowercase `w=`/`l=` break the subckt.** ngspice passes them into the
   sky130 subckt whose `.param l=1 w=1` collides (case-insensitive) →
   `could not find a valid modelname`. Convert to uppercase `W=…u L=…u`
   (add the `u` suffix — bare numbers are rejected too).
2. **Drop parasitic `C…` lines.** They reference undefined nodes (e.g. `vsubs`)
   with `**floating` comments and abort parsing.
3. **Rails map via small resistors (1 mΩ), not 0 Ω.** 0 Ω causes
   "Transient op failed, timestep too small".

Run:
```python
# tools or inline: rewrite lna_5t_final_extracted.sp -> _sim.sp
for line in src:
    if line.startswith('C'): continue
    if line.startswith('X'):
        # W=..., L=...u uppercase; drop ad=/as=/pd=/ps=
```

---

## 6. Testbench Ideal Elements

Identical for pre- and post-layout runs (per `afe/lna/lna_redesign.sp`):
- `CINP/CINN = 50 pF` (input AC coupling, ≥ C_gs of 3200 µm² input pair)
- `RRP1/RRP2 = 1 GΩ` (models on-chip MOS pseudo-resistor gate bias)
- Behavioral CMFB: `NG = 0.9 + 100*(0.5*(V(OP)+V(ON)) - 0.75)`
- Ideal supplies: `VDDA = 1.5 V`, `VB2 = 0.355 V`
- Differential AC source: `VINP AC 0.5 0`, `VINN AC 0.5 180` (1 V diff for dB readout)

Post-layout rail mapping (extracted → schematic):
```
a_n18685_n61330# = VDDA (tail source)   w_n18946_n61766# = VDDA (tail body)
w_n8184_n54494#  = VDDA (diff body)      a_n18607_n61526# = VB2 (tail gate)
a_n5372_n10196#  = NG (load gates)       a_n5450_n10000# = GND (load source)
VSUBS            = GND (load body)       GP/GN = inputs, OP/ON = outputs
```

---

## 7. Noise Extraction (ngspice)

```tcl
noise v(op,on) vinp dec 30 10 100meg
setplot noise1                    ; # "Noise Spectral Density Curves"
set filetype=ascii
write lna5t_prelayout_noise.raw   ; # vectors: inoise_spectrum, onoise_spectrum
```
- `inoise_spectrum` = input-referred noise (V/√Hz) → multiply by 1e9 for nV/√Hz.
- NF vs 50 Ω: `NF = 10*log10(inoise² / (4*kT*Rs))`.
- The `noise2` plot ("Integrated Noise") has `inoise_total`/`onoise_total` (V),
  used only for integrated checks.

---

## 8. Results (reference point)

| Metric | Pre | Post |
|:-------|----:|-----:|
| AC gain @ 40 kHz | 39.02 dB | 39.02 dB |
| IRN @ 40 kHz | 8.17 nV/√Hz | 8.09 nV/√Hz |
| OP / ON DC | 0.748 V | 0.748 V |
| Saturation | 5/5 | 5/5 |
| DRC | — | 0 |
| LVS | — | PASS |

---

## 9. One-Command Rebuild

```bash
# 1. generate layout (glayout) -> lna_5t_v8_nopwell.gds
python3 tools/gen_lna_layout_v8.py
# 2. extract + DRC (Magic)
# 3. topology LVS
python3 tools/lna_topology_lvs.py align_output/lna_5t_final_extracted.sp
# 4. simulate
ngspice -b simulation/lna5t/lna5t_prelayout_tb.sp
ngspice -b simulation/lna5t/lna5t_postlayout_tb.sp
# 5. plots
python3 simulation/lna5t/plot_lna5t_results.py
```

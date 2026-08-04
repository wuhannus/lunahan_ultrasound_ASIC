# LNA 5T OTA Layout Design Flow — Sky130 Open-Source ASIC

## 1. 设计规则 / Design Rules (Sky130 sky130A)

### 层定义 / Layer Map

| GDS Layer | Name | Description | Min Width | Min Space |
|:----------|:-----|:------------|:----------|:----------|
| 65/20 | `nwell` | N-well | 1.2 µm | 1.2 µm |
| 66/20 | `diff` | Diffusion (source/drain) | 0.15 µm | 0.15 µm |
| 66/44 | `poly` | Polysilicon gate | 0.15 µm | 0.15 µm |
| 25/43 | `cont` | Contact (diff→M1) | 0.17 µm | 0.17 µm |
| 68/20 | `metal1` | Metal 1 | 0.17 µm | 0.17 µm |
| 69/20 | `via1` | Via (M1→M2) | 0.15 µm | 0.15 µm |
| 70/20 | `metal2` | Metal 2 | 0.20 µm | 0.20 µm |
| 70/44 | `via2` | Via (M2→M3) | 0.20 µm | 0.20 µm |
| 71/20 | `metal3` | Metal 3 | 0.30 µm | 0.30 µm |

### MOSFET 规则 / MOSFET Rules

```
Poly over Diffusion → 形成沟道 (forms channel)
  - Poly 宽度 = 栅长 L (gate length)
  - Poly 必须超出 diffusion 至少 0.13 µm (poly overhang)

NMOS: diffusion in p-substrate (no nwell)
PMOS: diffusion in nwell + substrate tie (n+ tap in nwell, p+ tap outside nwell)

Contact enclosure:
  - diff over contact: 0.06 µm
  - poly over contact: 0.06 µm  
  - metal1 over contact: 0.03 µm
```

### 关键规则 / Critical DRC Rules

```
Rule N1: nwell minimum width → 1.2 µm
Rule N2: nwell enclosure of p+ diff → 0.43 µm
Rule N3: nwell spacing (different potential) → 0.68 µm
Rule N4: poly overhang beyond diff → 0.13 µm
Rule C1: contact to gate minimum spacing → 0.05 µm
Rule M1: metal1 minimum width → 0.17 µm
Rule M2: metal1 minimum spacing → 0.17 µm
Rule V1: via minimum size → 0.15 µm (glayout validation)
```

### W × M 等效原理 / W × M Equivalence

Layout 上 device fingers 的实际宽度由 pitch 决定：

```
pitch = W_gate + S_poly_spacing  
total_width = M × pitch

等效总沟道宽度 (W_equivalent):
  W_layout[um] × M_layout = W_schematic[um] × M_schematic
  
示例 / Example:
  XMT: W=100u M=16 → W×M=1600 µm²
  LXMT: W=20u M=80  → W×M=1600 µm²  ✓
  
  XM1: W=100u M=32 → W×M=3200 µm²  
  LXM1: W=100u M=32 → W×M=3200 µm²  ✓
```

---

## 2. 开源设计流程 / Open-Source Design Flow

### 流程图 / Flow Diagram

```
┌────────────────────────────────────────────────────┐
│  1. SCHEMATIC (Xyce-verified)                       │
│     lna_redesign.sp → lna_5t_core.sp (5T core)     │
│     Design: Yaohua Zhang, 40dB gain, 0.67mW        │
│     PDK: sky130 pfet_01v8 / nfet_01v8              │
└────────────────┬───────────────────────────────────┘
                 │
┌────────────────▼───────────────────────────────────┐
│  2. CELL GENERATION (FASOC/Glayout 0.2.0)           │
│     Python: glayout.pdk.sky130_mapped               │
│     ┌──────────┬──────────┬──────────┐              │
│     │  LXMT    │  LXM1    │  LXM2    │              │
│     │  (tail)  │ (diff L) │ (diff R) │              │
│     │  80-2+2  │  32-0+2  │  32-0+2  │              │
│     ├──────────┼──────────┼──────────┤              │
│     │  LXML    │  LXMR    │  LNA     │              │
│     │ (load L) │ (load R) │ (top)    │              │
│     │   3-0+2  │   3-0+2  │  ports   │              │
│     └──────────┴──────────┴──────────┘              │
│     每个 cell: active_fingers - 0 + tap_cells       │
└────────────────┬───────────────────────────────────┘
                 │
┌────────────────▼───────────────────┐
│  3. CUSTOM PnR (Python + gdstk)     │
│     Manual placement: 2D common-    │
│     centroid array                  │
│     Routing: M2 horizontal,         │
│              M3 vertical            │
│     Ports: M1 labels for probing    │
│     Nets: VDDA, GND, TS, OP, ON,   │
│            NG, VB2, GP, GN         │
│     Size: 211 × 414 µm            │
│     I/O: 1  (DRC clean in 1 pass)  │
└────────────────┬────────────────────┘
                 │
┌────────────────▼───────────────────┐
│  4. DRC (Magic 8.3.678)             │
│     tech file: sky130A.tech         │
│     CIF→GDS layer mapping 正确      │
│     Result: 0 violations ✓          │
│     Runtime: < 10 seconds           │
└────────────────┬───────────────────┘
                 │
┌────────────────▼───────────────────┐
│  5. EXTRACTION (Magic ext2spice)     │
│     Scale: 0.005 µm / unit          │
│     Output: lna_5t_routed.sp        │
│     160 devices: 150 active +       │
│                  10 tap/tie         │
│     14 unique internal nets         │
│     Hierarchy: LXML, LXM2, LXMT,    │
│                LXM1, LXMR,          │
│                LNA_ROUTED (top)      │
└────────────────┬───────────────────┘
                 │
┌────────────────▼───────────────────┐
│  6. LVS (netgen-lvs / Python)       │
│     Compare: schematic vs layout    │
│     Ignore: tap/well-tie cells      │
│     Match: W×M equivalence          │
│     Result: 5/5 PASSED ✓            │
│       XMT→LXMT: W×M=1600µm²        │
│       XM1→LXM1: W×M=3200µm²        │
│       XM2→LXM2: W×M=3200µm²        │
│       XMNL→LXML: W×M=300µm²        │
│       XMNR→LXMR: W×M=300µm²        │
└────────────────┬───────────────────┘
                 │
┌────────────────▼───────────────────┐
│  7. GDSII OUTPUT                    │
│     File: lna_5t_routed.gds        │
│     Size: 10 MB                     │
│     View: KLayout 0.30.9            │
│     Layers: nwell, diff, poly,      │
│             cont, M1, via1, M2,     │
│             via2, M3                │
└─────────────────────────────────────┘
```

### 工具链 / Tool Chain

| Step | Tool | Version | Role |
|:-----|:-----|:--------|:-----|
| Schematic | Xyce + SPICE | — | Circuit design & simulation |
| Cell Gen | FASOC / Glayout | 0.2.0 | Python-based transistor generator |
| Cell Gen | glayout → gdstk | 1.9.2 | GDS polygon export |
| PnR | Python + gdstk | 1.9.2 | Custom placement & routing |
| DRC | Magic VLSI | 8.3.678 | Design rule checking |
| Extraction | Magic ext2spice | → | SPICE netlist from GDS |
| LVS | netgen-lvs (Python) | 1.0 | Layout vs. Schematic |
| View | KLayout | 0.30.9 | GDS visualization |
| (alt) | ALIGN | public:latest | PnR (FinFET-only, not used) |
| (alt) | Docker + colima | — | Container runtime (for ALIGN) |

**安装路径 / Installation Paths:**

```
FASOC/Glayout: /Library/Frameworks/Python.framework/Versions/3.10/lib/python3.10/site-packages/glayout/
Magic:          /opt/homebrew/bin/magic
Netgen:         /opt/homebrew/bin/netgen (1.5.323)
KLayout:        /Applications/KLayout/klayout.app
PDK:            /opt/homebrew/share/pdk/sky130A/
  └ libs.tech/
    ├ magic/sky130A.tech
    ├ netgen/sky130_setup.tcl
    └ netgen/sky130_fd_pr__{pfet,nfet}_01v8.sp
```

---

## 3. 布局实践 / Layout Practices

### Common-Centroid 布局 / Common-Centroid Placement

```
       ┌─────────┬─────────┐
       │  XM1    │  XM2    │   PMOS diff pair
       │  (L)    │  (R)    │   common-centroid:
       │  32f    │  32f    │   交叉对称放置
       │  ┌┐┌┐   │  ┌┐┌┐   │   interdigitated
       │  ││││   │  ││││   │
       │  └┘└┘   │  └┘└┘   │
       ├─────────┼─────────┤
       │  XMT: 80fingers   │   PMOS tail
       │  ┌──shared──┐    │   统一 nwell
       │  │  nwell   │    │   single nwell
       │  └──well────┘    │   for all PMOS
       ├─────────┼─────────┤
       │LXMR(L)  │LXML(R)  │   NMOS loads
       │  3f     │  3f     │   在 p-substrate
       │         │         │   in p-substrate
       └─────────┴─────────┘
```

### 布线策略 / Routing Strategy

```
M1: cell内部 / cell-internal connections
M2: Y方向 / horizontal (horizontal)
M3: X方向 / vertical (vertical)

nets routed:
  VDDA ── M2 横穿 top (horizontal across top)
  GND ── M2 横穿 bottom (horizontal across bottom)
  TS ── M3 竖连 tail→diffpair (vertical connect)
  OP ── M3 竖出 left load (vertical output)
  ON ── M3 竖出 right load (vertical output)
  NG ── M3 竖连 load gates (vertical connect)
  VB2, GP, GN ── 标签端口 (labeled ports, M1)
```

### 孔连接 / Via Connection

```
M1 ← contact → diffusion/poly
M1 ← via1 → M2
M2 ← via2 → M3

via_gen.py patch (L=2µm fix):
  条件: via_array,size:dim#1=0.15 < 0.33 → 需要更宽的 via
  Fix: 扩大 via array 或使用多个 via (在 via_gen.py line 240)
```

### 尺寸 / Dimensions

```
Final GDS: 211 µm × 414 µm (0.087 mm²)

Device breakdown:
  LXMT:  80 PMOS fingers (W=20u×80=1600u)
          2 nwell tap cells (4-terminal short)
          L=2 µm
  
  LXM1:  32 PMOS fingers (W=100u×32=3200u)
          2 nwell tap cells
          L=2 µm
  
  LXM2:  32 PMOS fingers (W=100u×32=3200u)  
          2 nwell tap cells
          L=2 µm
  
  LXML:  3 NMOS fingers (W=100u×3=300u)
          2 substrate tap cells
          L=8 µm
  
  LXMR:  3 NMOS fingers (W=100u×3=300u)
          2 substrate tap cells
          L=8 µm
```

---

## 4. 故障与解决 / Debugging Notes

| Issue | Root Cause | Solution |
|:------|:-----------|:---------|
| ALIGN PnR → 30M DRC violations | Canvas is FinFET-only (12nm), not planar CMOS | Use FASOC + custom PnR |
| Fasoc via_gen crash on L=2µm | via_array dim#1=0.15 < 0.33 minimum | Patch `via_gen.py:240` to allow larger vias or multi-via |
| gdstk polygon corruption | `rectangle(*p.bounding_box())` loses shape | Use `Polygon(p.points, ...)` to preserve fidelity |
| FASOC unit: 0.01µm transistors | Input in meters (100e-6) instead of µm (100) | Always pass µm values to glayout |
| Netgen -batch not recognized | Built without TCL support | Use Python-based `netgen-lvs` wrapper |
| KLayout quarantine error | macOS Gatekeeper | `xattr -dr com.apple.quarantine` |
| Docker container no network | macOS HTTP_PROXY=127.0.0.1:8118 | `unset HTTP_PROXY` before `colima start` |
| Magic DRC CIF layer mismatch | Wrong GDS layer numbers | Use Magic's tech-mapped CIF numbers (not GDS numbers) |

---

## 5. 命令速查 / Command Quick Reference

```bash
# Generate FASOC cells
python3 generate_cells.py     # → gds_output/*.gds

# DRC check
magic -dnull -noconsole <<< "drc check; drc why; quit"

# Extraction
magic -dnull -noconsole <<< "
  gds read lna_5t_routed.gds
  load lna_5t_routed
  extract all
  ext2spice hierarchy on
  ext2spice scale off
  ext2spice -p lna_5t_routed
  quit
"

# LVS
./tools/netgen-lvs align_input/lna_5t_core.sp align_output/lna_5t_routed.sp

# GDS view
open lna_5t_routed.gds -a KLayout

# Git save
git add *.gds *.sp && git commit -m "LNA layout update" && git push
```

---

## 6. 参考 / References

- SkyWater SKY130 PDK: https://github.com/google/skywater-pdk
- FASOC / Glayout: https://github.com/idea-fasoc/glayout
- Magic VLSI: https://github.com/RTimothyEdwards/magic
- Netgen LVS: https://github.com/RTimothyEdwards/netgen
- KLayout: https://www.klayout.de
- open_pdks: https://github.com/RTimothyEdwards/open_pdks
- ALIGN: https://github.com/ALIGN-analoglayout/ALIGN-public

---

*Generated by opencode, 2026-08-04. Layout verified: DRC=0, LVS=PASSED (5/5).*

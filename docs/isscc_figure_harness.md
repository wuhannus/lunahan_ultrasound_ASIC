# ISSCC-Quality Figure Harness — Key Principles from ISSCC 2025 Digest

> Based on analysis of 254 papers across 35 sessions in ISSCC 2025 Digest
> Applied to: `lunahan_ultrasound_ASIC` manuscript figures

---

## 1. ISSCC Figure Quality Standards (10 Principles)

| # | Principle | ISSCC Convention | Our Current Gap |
|---|-----------|-----------------|-----------------|
| 1 | **Hierarchical grouping** | Subsystems in labeled boundary boxes; nested clusters show ownership | ✅ Graphviz clusters do this |
| 2 | **Clean signal flow** | Arrows flow left→right or top→bottom; bidirectional use dual arrows | ⚠️ Some arrows cross clusters confusingly |
| 3 | **Sub-figure labeling** | (a), (b), (c), (d) labels in top-left of each sub-panel | ✗ Missing — all info in one diagram |
| 4 | **Inline data tables** | Performance comparison tables embedded within figure, not separate | ✗ Tables are separate captions |
| 5 | **Consistent typography** | Helvetica/Arial, title 10pt bold, body 8pt, annotation 7pt | ⚠️ Font sizes vary |
| 6 | **Minimal color, high contrast** | Mostly B&W + 1 accent color; thick lines for emphasis | ⚠️ Too many colors |
| 7 | **Self-contained** | Every figure includes its own legend, axis labels, units | ⚠️ Legends sometimes separate |
| 8 | **Chip photo/micrograph** | Die photo with area breakdown pie/bar chart | N/A (no silicon) |
| 9 | **Comparison to prior art** | Table of this work vs state-of-the-art in every paper | ✗ Only vs JSSC 2022 |
| 10 | **3-page paper structure** | Page 1=text+arch, Page 2=schematics+waveforms, Page 3=chip photo+table | N/A (tutorial format) |

## 2. Specific Figure Improvements Needed

### Figure 1 (Design Flow)
- **ISSCC style**: Left-to-right pipeline with numbered phases, simple arrows
- **Fix**: Use `rankdir=LR`, bold phase numbers, add feedback loop clearly

### Figure 2 (System Architecture)  
- **ISSCC style**: Top-level block → expand key sub-blocks inline
- **Fix**: Add sub-figure (a) full system, (b) AFE detail, (c) digital detail

### Figure 3 (LNA Schematic)
- **ISSCC style**: Transistor-level with W/L annotations, bias details
- **Fix**: Show device sizes more prominently, add small-signal model inset

### Figure 4 (PV-RXBF)
- **ISSCC style**: Pipeline with timing annotations
- **Fix**: Add latency per stage, throughput calculation inline

### Figure 5 (UERTX)
- **ISSCC style**: Power stage + control logic in separate sub-panels
- **Fix**: (a) power stage, (b) timing diagram, (c) energy comparison bar chart

### Figure 6 (Waveforms)
- **ISSCC style**: Oscilloscope-style plots with grid, axis labels
- **Fix**: Add time/voltage axes, measurement cursors, corner annotations

### Figure 7 (System Results)
- **ISSCC style**: Measurement summary table as primary, plots secondary
- **Fix**: Make comparison table the dominant element, plots supporting

## 3. ISSCC Figure Template

```
+----------------------------------------------------------+
| (a) Architecture                          (b) Schematic   |
| +---------------------------+   +----------------------+  |
| | [Block A] → [Block B] →  |   |    VDD               |  |
| |               ↓          |   |     |                |  |
| |          [Block C]       |   |  M1-+--M2--+--OUT    |  |
| +---------------------------+   +----------------------+  |
|                                                            |
| (c) Measured Waveforms       (d) Performance Summary      |
| +---------------------------+   +----------------------+  |
| |  ─── Vctrl               |   | Param | This | Prior |  |
| |  ─── Output              |   |---------------------|  |
| |  ├── 10µs/div ──┤        |   | Gain  | 30dB | 22dB |  |
| +---------------------------+   +----------------------+  |
+----------------------------------------------------------+
              Figure X: [Self-contained caption]
```

## 4. Implementation Plan

Each figure will be redrawn to:
1. Use Helvetica 10pt (title) / 8pt (body) / 7pt (annotations)
2. Sub-figures labeled (a), (b), (c), (d)
3. Inline data tables where applicable
4. Minimal B&W + single accent color (blue)
5. Clear left-to-right / top-to-bottom signal flow
6. Self-contained with legends inside figure boundary

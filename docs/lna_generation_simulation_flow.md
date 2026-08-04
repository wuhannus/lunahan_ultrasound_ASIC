# LNA 5T OTA — Generation + Simulation Flow

Open-source analog design flow for the 5-transistor LNA OTA in sky130,
covering **schematic → layout → DRC → LVS → GDSII → pre/post-layout simulation**.

---

## Flow Illustration (Mermaid)

```mermaid
flowchart TB
    subgraph DESIGN["1. Circuit Design (Xyce-verified)"]
        A0["Dr. Yaohua Zhang\n40 dB / 0.67 mW design\nlna_redesign.sp"] --> A1["5T core netlist\nlna_5t_core.sp\n(5 devices, 8 ports)"]
    end

    subgraph GEN["2. Cell Generation (glayout/FASOC)"]
        B0["diff_pair(XM1/XM2)\nwidth=100 f=16"] 
        B1["pmos tail (XMT)\nwidth=20 f=80"]
        B2["nmos loads (XMNL/XMNR)\nwidth=100 f=3"]
        A1 --> B0
        A1 --> B1
        A1 --> B2
        B0 & B1 & B2 --> B3["tools/gen_lna_layout_v8.py"]
    end

    subgraph PR["3. Placement & Routing (glayout smart_route)"]
        B3 --> C0["Symmetric placement\nmovex(±(half+sep/2))"]
        C0 --> C1["E/W edge-port routing\n(OP/ON/TS/NG/GND)"]
        C1 --> C2["Labels: VDDA GND TS OP ON GP GN VB2 NG"]
    end

    subgraph VERIFY["4. Verification (Magic + netgen)"]
        C2 --> D0["GDS: lna_5t_final.gds"]
        D0 --> D1["Magic DRC\nsky130A.tech\n= 0 violations"]
        D0 --> D2["Magic extract\nlna_5t_final_extracted.sp\n(150 devices)"]
        D2 --> D3["Topology LVS\ntools/lna_topology_lvs.py\nPASSED 5/5"]
    end

    subgraph SIM["5. Simulation (ngspice + sky130 models)"]
        D2 --> E0["pre/post testbench\nCIN=50p, Rp=1G, BCMFB"]
        E0 --> E1["AC: 39 dB @ 40 kHz"]
        E0 --> E2["NOISE: 8.1 nV/√Hz @ 40 kHz"]
        E0 --> E3["DC op + saturation table"]
        E1 & E2 & E3 --> E4["plot_lna5t_results.py\nPNG figures + report"]
    end

    subgraph OUT["6. Outputs"]
        E4 --> F0["lna5t_ac_gain.png"]
        E4 --> F1["lna5t_noise.png"]
        E4 --> F2["lna5t_results_report.md"]
        D0 --> F3["lna_5t_final.gds"]
    end
```

---

## Text Flow (step by step)

```
Schematic (lna_5t_core.sp)          schematic/2.5T, 8 ports, W×M sizes
   │
   ▼
FASOC/glayout cells (v8 generator)  diff_pair + pmos tail + nmos loads
   │   with_tie / with_dummy / substrate_tap flags
   ▼
Symmetric placement                 loads ±(half+sep/2), diff_pair mid, tail bottom
   │   (BUG FIXED: overlapping diffusion merged the 2 NMOS loads)
   ▼
Routing via glayout primitives      smart_route to E/W edge ports (vias land on bars)
   │   (BUG FIXED: N/S bar-center ports placed vias off-metal)
   ▼
GDS write + strip pwell (64,44)     pwell is not a Magic sky130A GDS layer
   │
   ├──▶ Magic DRC  ────────────────▶  0 violations
   ├──▶ Magic extract ─────────────▶  150 devices flat netlist
   ├──▶ Topology LVS ─────────────▶  PASSED (W×M + nets match schematic)
   ▼
ngspice sim (pre = core, post = extracted)
   ├──▶ .AC  ────────────────▶  39.02 dB @ 40 kHz (pre = post)
   ├──▶ .NOISE ──────────────▶  8.17 / 8.09 nV/√Hz @ 40 kHz
   ├──▶ .OP  ────────────────▶  OP=ON=0.748 V, all 5 devices saturated
   ▼
Plots + report                      PNG figures + markdown tables
```

---

## Directory / File Map

| Stage | File | Tool |
|:------|:-----|:-----|
| Schematic | `align_input/lna_5t_core.sp` | Xyce |
| Cell gen | `tools/gen_lna_layout_v8.py` | glayout/FASOC 0.2.0 |
| Layout gen | `tools/gen_lna_layout_v8.py` → `lna_5t_v8_nopwell.gds` | gdstk 1.9.2 |
| Final GDS | `align_output/lna_5t_final.gds` | Magic 8.3.678 |
| Extraction | `align_output/lna_5t_final_extracted.sp` | Magic ext2spice |
| Sim netlist | `align_output/lna_5t_final_extracted_sim.sp` | (cleaned for ngspice) |
| LVS | `tools/lna_topology_lvs.py`, `tools/netgen_lvs.py` | Python / netgen |
| Pre-layout sim | `simulation/lna5t/lna5t_prelayout_tb.sp` | ngspice 46 |
| Post-layout sim | `simulation/lna5t/lna5t_postlayout_tb.sp` | ngspice 46 |
| Plot/report | `simulation/lna5t/plot_lna5t_results.py` | matplotlib |

---

## Key Results (TT, 27 °C)

| Metric | Pre-layout | Post-layout |
|:-------|-----------:|------------:|
| AC gain @ 40 kHz | 39.02 dB | 39.02 dB |
| IRN @ 40 kHz | 8.17 nV/√Hz | 8.09 nV/√Hz |
| Noise figure (Rs=50Ω) @ 40 kHz | 19.06 dB | 18.98 dB |
| Output common mode | 0.748 V | 0.748 V |
| Power | ~0.67 mW | ~0.67 mW |
| Devices in saturation | 5/5 | 5/5 |
| DRC | — | 0 violations |
| LVS | — | PASSED |

> NF is quoted against a 50 Ω reference for completeness; the ultrasound
> transducer is high-impedance, so **input-referred noise (IRN)** is the
> relevant metric.

---

## Skills / Reusable Knowledge

See [`SKILLS.md`](../SKILLS.md) for the condensed, reusable playbook:
layer mapping, placement/routing bugs and fixes, ngspice netlist quirks,
and the exact commands for every stage.

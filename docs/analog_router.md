# Analog Router — sky130, reusable across analog blocks

A from-scratch analog router for the project's analog circuits (LNA, ADC, and
future blocks). It replaces `glayout.smart_route`, which shorts when routing
between mixed metal levels.

## Files

| File | Description |
|:-----|:------------|
| `tools/analog_router.py` | Core A* maze router (multi-layer, DRC-aware) |
| `tools/route_glayout_netlist.py` | Glayout integration (placed cells + netlist → routed GDS) |
| `tools/magic_drc.py` | Magic DRC scanner (tile-scan violation localization) |
| `tools/demo_router_lna.py` | LNA 5T routing demo |
| `afe/adc/redesign/gen_adc_routed_layout.py` | ADC comparator-core routing demo |

## Magic DRC-aware routing

The router has a **DRC-aware feedback loop** (`AnalogRouter.drc_aware_route`):

```
route all nets (A*)
   │
   ▼
write GDS → Magic DRC tile-scan (magic_drc.py)
   │
   ▼
violations? ──yes──> add violation tiles as obstacles → rip up → re-route
   │
   no
   ▼
DRC-clean (or max_iter)
```

`magic_drc.py` exploits Magic's `box → drc check → drc why` to localize
violations per tile (Magic's batch mode does not expose error coordinates via
feedback/drc listall reliably). Two Magic quirks handled:
- per-tile `drc check` (a prior full check consumes the error DB)
- box must be padded beyond the layout bbox (min-spacing errors register at
  the layout origin edge)

Verified:
```
python3 tools/magic_drc.py /tmp/drc_spacing.gds DRCAWARE   # spacing viols: >0
python3 tools/magic_drc.py /tmp/drc_loop4.gds DRCAWARE     # multi-layer: 0
```

To enable in a layout generator:
```python
route_placed_layout(comp, nets, out_gds, drc_aware=True,
                    drc_tile=2.0, drc_max_iter=4)
```

## What it does

- **A\* maze routing** on a DRC-aware grid (min-spacing inflated obstacles).
  Paths route *around* cells, never through them (unlike track routers that
  pass through and short).
- **Layer stack**: MET1 (68,20) → MET2 (69,20) → MET3 (70,20) → MET4 (71,20),
  with via stacks at layer transitions and port pads.
- **Per-segment drawing**: each monotonic run is a thin metal rectangle
  (never a fat bounding box), so L-bends don't short the corner.
- **Port clearance**: a small region is cleared around each port so a route
  can land, without merging adjacent terminals (0.35 µm).

## Verified (works correctly)

```
2-port demo (tools/analog_router self-test):
  A(MET1) → obstacle → B(MET2): route detours around obstacle, via at track
  Magic: DRC = 0, A.drain and B.gate on the SAME net, no gate-drain/source shorts
```

This proves the core is a correct, obstacle-avoiding, multi-layer router.

## Honest limitation (dense analog cores)

On the **dense** ADC comparator / LNA diff_pair (terminals ~1 µm apart), the
router's port-landing is not precise enough: the metal drawn at a port's grid
cell touches the cell's own adjacent terminals, merging devices. The extracted
netlist then shows a mass short (all PMOS on one net) even though DRC = 0.

**Root cause**: the router connects to a grid cell *near* a port, not to the
exact metal bar of that terminal. Fixing this needs per-terminal metal
matching (port → its exact polygon), i.e. the precision that commercial
analog routers (Cadence/Virtuoso analog router) provide.

## Recommendation for "real" analog routing in this project

1. **Use an established open-source analog router** instead of a hand-rolled
   one for full-density blocks. Options:
   - **Magic's built-in router** (`:route` / `route` command) — already
     installed, DRC-aware, handles sky130 well.
   - **ALIGN** (from the earlier session) — the canvas is FinFET-only, but a
     sky130-compatible analog-PnR flow is the long-term fix.
   - **OpenLane / open-pdks** analog macros.
2. For **sparse inter-block routing** (block-to-block on top metal), this
   router is usable now.
3. Fixing this router's port-landing (match port to exact polygon, then
   reserve only that polygon's cell) is a tractable next step.

## API

```python
from analog_router import AnalogRouter, MET1, MET2
r = AnalogRouter(grid=0.1, min_spacing=0.2, metal_width=0.3)
r.set_bounds(x0, y0, x1, y1)
r.add_obstacle(x0, y0, x1, y1, layer)
r.add_port("GP", MET1, x, y)
r.route_net("VTAIL", ["A", "B", "C"])
r.write_gds("routed.gds")
```

```python
# glayout integration
from route_glayout_netlist import route_placed_layout
route_placed_layout(component, netlist, "out.gds",
                    grid=0.1, spacing=0.2, metal_width=0.3)
```

## Test commands

```bash
python3 tools/analog_router.py          # self-test (obstacle-avoiding route)
python3 tools/demo_router_lna.py        # LNA 6-net routing demo
python3 afe/adc/redesign/gen_adc_routed_layout.py   # ADC 11-net demo
```

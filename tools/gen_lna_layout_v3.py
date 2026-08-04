#!/usr/bin/env python3
"""
LNA 5T OTA — v3 correct layout generation.
Fixes:
  1. Placement bug (used unmoved component bbox for stacking)
  2. Body ties added (with_tie=True) so PMOS->VDDA, NMOS->GND
  3. Routing via glayout primitives that land real vias on ports
  4. pwell (64,44) stripped on write (not a Magic sky130A GDS layer)

Topology:
  XMT  PMOS  D=TS   G=VB2  S=VDDA  B=VDDA   tail
  XM1  PMOS  D=OP   G=GP   S=TS    B=VDDA   diff L
  XM2  PMOS  D=ON   G=GN   S=TS    B=VDDA   diff R
  XMNL NMOS  D=OP   G=NG   S=GND   B=GND    load L
  XMNR NMOS  D=ON   G=NG   S=GND   B=GND    load R
"""
import os
import gdstk

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.routing.smart_route import smart_route
from glayout.backend import Component
from glayout.util.comp_utils import align_comp_to_port

pdk = sky130_mapped_pdk
pdk.activate()

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "align_output"))
os.makedirs(OUT, exist_ok=True)


def make_fet(kind, width, fingers, length):
    if kind == "nmos":
        return nmos(pdk, width=width, fingers=fingers, multipliers=1,
                    length=length, with_tie=True, with_dummy=False,
                    with_dnwell=False, with_substrate_tap=False)
    return pmos(pdk, width=width, fingers=fingers, multipliers=1,
                length=length, with_tie=True, with_dummy=False,
                dnwell=False, with_substrate_tap=False)


def route(top, p1, p2, layer="met3"):
    """Route two ports using smart_route; auto layers if layer fails."""
    try:
        comp = smart_route(pdk, p1, p2, glayer1=layer, glayer2=layer,
                           e1glayer=layer, e2glayer=layer, cglayer=layer,
                           hglayer=layer, vglayer=layer)
        top << comp
        return True
    except Exception:
        try:
            comp = smart_route(pdk, p1, p2)
            top << comp
            return True
        except Exception as e:
            print(f"  !! route {p1.name}->{p2.name}: {e}")
            return False


def find_tie_port(fet, side):
    """Find a bulk tie port on the given side (W/E/N/S) at LI/top_met."""
    candidates = [f"tie_{side}_top_met_{side}"]
    for c in candidates:
        if c in fet.ports:
            return fet.ports[c]
    # fallback: any tie port on side
    for name in fet.ports:
        if name.startswith(f"tie_{side}") and "top_met" in name:
            return fet.ports[name]
    return None


def main():
    print("Generating FETs (with tie rings)...")
    xmt = make_fet("pmos", 20, 80, 2)
    xm1 = make_fet("pmos", 100, 32, 2)
    xm2 = make_fet("pmos", 100, 32, 2)
    xmnl = make_fet("nmos", 100, 3, 8)
    xmnr = make_fet("nmos", 100, 3, 8)

    for nm, c in [("XMT", xmt), ("XM1", xm1), ("XM2", xm2),
                  ("XMNL", xmnl), ("XMNR", xmnr)]:
        print(f"  {nm}: x={c.xmin:.1f}..{c.xmax:.1f} y={c.ymin:.1f}..{c.ymax:.1f}")

    top = Component()
    sep = 3.0
    row_gap = 10.0

    # ---- Row A: loads (NMOS) ----
    xmnl_ref = top << xmnl
    xmnr_ref = top << xmnr
    xmnl_ref.movex(0 - xmnl_ref.xmax - sep / 2).movey(0)
    xmnr_ref.movex(xmnr_ref.xmin + sep / 2).movey(0)

    # ---- Row B: diff pair (PMOS) below loads ----
    y_rowb = xmnl_ref.ymin - row_gap - xm1.ymax
    xm1_ref = top << xm1
    xm2_ref = top << xm2
    xm1_ref.movey(y_rowb).movex(0 - xm1_ref.xmax - sep / 2)
    xm2_ref.movey(y_rowb).movex(xm2_ref.xmin + sep / 2)

    # ---- Row C: tail (PMOS) below diff pair ----
    y_rowc = xm1_ref.ymin - row_gap - xmt.ymax
    xmt_ref = top << xmt
    xmt_ref.movey(y_rowc).movex(0 - xmt_ref.xmax / 2)

    print(f"\nAssembled bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")
    # Sanity check gaps
    print(f"  load bottom={xmnl_ref.ymin:.1f}, diff top={xm1_ref.ymax:.1f}, gap={(xm1_ref.ymax-xmnl_ref.ymin):.1f}")
    print(f"  diff bottom={xm1_ref.ymin:.1f}, tail top={xmt_ref.ymax:.1f}, gap={(xmt_ref.ymax-xm1_ref.ymin):.1f}")

    # ============================================================
    # Routing
    # ============================================================
    # NG: xmnl.gate -> xmnr.gate  (both near y=-51, horizontal)
    route(top, xmnl_ref.ports["gate_E"], xmnr_ref.ports["gate_W"], "met2")

    # OP: xm1.drain(N) -> xmnl.drain(S)  vertical
    route(top, xm1_ref.ports["drain_N"], xmnl_ref.ports["drain_S"], "met3")

    # ON: xm2.drain(N) -> xmnr.drain(S)
    route(top, xm2_ref.ports["drain_N"], xmnr_ref.ports["drain_S"], "met3")

    # TS: xmt.drain -> xm1.source & xm2.source
    route(top, xmt_ref.ports["drain_S"], xm1_ref.ports["source_S"], "met3")
    route(top, xmt_ref.ports["drain_S"], xm2_ref.ports["source_S"], "met3")

    # GND: nmos sources (both near y=+50) + bulk ties
    route(top, xmnl_ref.ports["source_N"], xmnr_ref.ports["source_N"], "met2")
    # body ties of loads to GND
    for ref in (xmnl_ref, xmnr_ref):
        t = find_tie_port(ref, "S")
        if t:
            route(top, xmnr_ref.ports["source_N"], t, "met2")

    # VDDA: pmos source (tail) + pmos body ties
    # tail source is at top; route to each diff-pair body tie
    for ref in (xm1_ref, xm2_ref):
        t = find_tie_port(ref, "N")
        if t:
            route(top, xmt_ref.ports["source_N"], t, "met2")
    # tail body tie
    t = find_tie_port(xmt_ref, "N")
    if t:
        route(top, xmt_ref.ports["source_N"], t, "met2")

    print("\nRouting complete. Writing GDS...")
    top.name = "LNA_V3"
    top.write_gds(os.path.join(OUT, "lna_5t_v3.gds"))

    # Strip pwell (64,44) which Magic sky130A does not define
    lib = gdstk.read_gds(os.path.join(OUT, "lna_5t_v3.gds"))
    removed = 0
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
            removed += 1
    lib.write_gds(os.path.join(OUT, "lna_5t_v3_nopwell.gds"))
    print(f"Wrote lna_5t_v3_nopwell.gds (removed {removed} pwell polys)")


if __name__ == "__main__":
    main()

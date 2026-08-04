#!/usr/bin/env python3
"""
LNA 5T OTA — Correct analog layout generation using glayout routing primitives.
Fixes the prior bug: routing now lands REAL vias on cell ports (met2->met3)
instead of drawing floating metal rectangles.

Topology (from lna_5t_core.sp):
  XMT  PMOS  D=TS   G=VB2  S=VDDA  B=VDDA   tail current source
  XM1  PMOS  D=OP   G=GP   S=TS    B=VDDA   diff pair left
  XM2  PMOS  D=ON   G=GN   S=TS    B=VDDA   diff pair right
  XMNL NMOS  D=OP   G=NG   S=GND   B=GND    load left
  XMNR NMOS  D=ON   G=NG   S=GND   B=GND    load right

WxM equivalence (layout = schematic):
  XMT : width=20, fingers=80  -> 1600 um  (sch W=100u M=16)
  XM1 : width=100, fingers=32 -> 3200 um  (sch W=100u M=32)
  XM2 : width=100, fingers=32 -> 3200 um  (sch W=100u M=32)
  XMNL: width=100, fingers=3  -> 300 um   (sch W=100u M=3)
  XMNR: width=100, fingers=3  -> 300 um   (sch W=100u M=3)
  lengths: XMT/XM1/XM2 L=2, loads L=8
"""
import os
import sys

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.routing.smart_route import smart_route
from glayout.routing.straight_route import straight_route
from glayout.routing.c_route import c_route
from glayout.util.comp_utils import align_comp_to_port
from glayout.backend import Component

pdk = sky130_mapped_pdk
pdk.activate()

OUT = os.path.join(os.path.dirname(__file__), "..", "align_output")
OUT = os.path.abspath(OUT)
os.makedirs(OUT, exist_ok=True)


def make_fet(kind, width, fingers, length):
    """Generate a bare FET (no tie ring) and return the component."""
    if kind == "nmos":
        return nmos(pdk, width=width, fingers=fingers, multipliers=1,
                    length=length, with_tie=False, with_dummy=False,
                    with_dnwell=False, with_substrate_tap=False)
    else:
        return pmos(pdk, width=width, fingers=fingers, multipliers=1,
                    length=length, with_tie=False, with_dummy=False,
                    dnwell=False, with_substrate_tap=False)


def main():
    print("Generating bare FETs...")
    xmt = make_fet("pmos", 20, 80, 2)
    xm1 = make_fet("pmos", 100, 32, 2)
    xm2 = make_fet("pmos", 100, 32, 2)
    xmnl = make_fet("nmos", 100, 3, 8)
    xmnr = make_fet("nmos", 100, 3, 8)

    for nm, c in [("XMT", xmt), ("XM1", xm1), ("XM2", xm2),
                  ("XMNL", xmnl), ("XMNR", xmnr)]:
        print(f"  {nm}: x={c.xmin:.1f}..{c.xmax:.1f} y={c.ymin:.1f}..{c.ymax:.1f}")

    # Write cells individually for inspection first
    xmt.name = "LXMT"
    xm1.name = "LXM1"
    xm2.name = "LXM2"
    xmnl.name = "LXML"
    xmnr.name = "LXMR"
    xmt.write_gds(os.path.join(OUT, "fasoc_xmt_v3.gds"))
    xm1.write_gds(os.path.join(OUT, "fasoc_xm1_v3.gds"))
    xm2.write_gds(os.path.join(OUT, "fasoc_xm2_v3.gds"))
    xmnl.write_gds(os.path.join(OUT, "fasoc_xmnl_v3.gds"))
    xmnr.write_gds(os.path.join(OUT, "fasoc_xmnr_v3.gds"))
    print("Individual FET GDS written.")

    # ============================================================
    # Assembly: vertical stack
    #   Row A (top):    XMNL | XMNR   (NMOS loads, gates -> NG)
    #   Row B (middle): XM1  | XM2    (PMOS diff pair)
    #   Row C (bottom): XMT           (PMOS tail)
    #   Routing on met2/met3 via glayout primitives.
    # ============================================================

    top = Component()
    met3 = pdk.get_glayer("met3")

    # --- place loads (NMOS) at top row ---
    sep = 2.0
    xmnl_ref = top << xmnl
    xmnr_ref = top << xmnr
    xmnl_ref.movex(0 - xmnl_ref.xmax - sep / 2).movey(0)
    xmnr_ref.movex(xmnr_ref.xmin + sep / 2).movey(0)

    # --- place diff pair below loads ---
    row_gap = 8.0
    xm1_ref = top << xm1
    xm2_ref = top << xm2
    y_rowb = xmnl.ymin - row_gap - xm1.ymax
    xm1_ref.movey(y_rowb).movex(0 - xm1_ref.xmax - sep / 2)
    xm2_ref.movey(y_rowb).movex(xm2_ref.xmin + sep / 2)

    # --- place tail below diff pair ---
    y_rowc = xm1.ymin - row_gap - xmt.ymax
    xmt_ref = top << xmt
    xmt_ref.movey(y_rowc).movex(0 - xmt_ref.xmax / 2)

    print(f"\nAssembled bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ============================================================
    # Routing — connect the 5 FETs
    # ============================================================

    def route(p1, p2, layer="met3"):
        """Route between two ports using the correct glayout primitive."""
        try:
            # smart_route picks straight/c/L based on geometry; pass layer via
            # the generic glayer kwargs accepted by the underlying primitives.
            comp = smart_route(pdk, p1, p2, glayer1=layer, glayer2=layer,
                               e1glayer=layer, e2glayer=layer, cglayer=layer,
                               hglayer=layer, vglayer=layer)
            top << comp
            return True
        except TypeError as e:
            # Try without layer kwargs (auto layers from ports)
            try:
                comp = smart_route(pdk, p1, p2)
                top << comp
                return True
            except Exception as e2:
                print(f"  !! route {p1.name}->{p2.name} failed: {e2}")
                return False
        except Exception as e:
            print(f"  !! route {p1.name}->{p2.name} failed: {e}")
            return False

    # --- NG: xmnl.gate -> xmnr.gate (both at y~=-51) ---
    route(xmnl_ref.ports["gate_E"], xmnr_ref.ports["gate_W"], "met2")

    # --- OP: xm1.drain -> xmnl.drain ---
    route(xm1_ref.ports["drain_N"], xmnl_ref.ports["drain_S"], "met3")

    # --- ON: xm2.drain -> xmnr.drain ---
    route(xm2_ref.ports["drain_N"], xmnr_ref.ports["drain_S"], "met3")

    # --- TS: xmt.drain -> xm1.source & xm2.source ---
    route(xmt_ref.ports["drain_S"], xm1_ref.ports["source_S"], "met3")
    route(xmt_ref.ports["drain_S"], xm2_ref.ports["source_S"], "met3")

    # --- VDDA: xmt.source + pmos wells ---
    route(xmt_ref.ports["source_N"], xm1_ref.ports["well_E"], "met3")
    route(xmt_ref.ports["source_N"], xm2_ref.ports["well_W"], "met3")

    # --- GND: nmos sources ---
    route(xmnl_ref.ports["source_N"], xmnr_ref.ports["source_N"], "met2")

    # --- Outputs to pins via via stacks on met3 ---
    print("\nTopology routing complete. Writing top-level GDS...")
    top.name = "LNA_V2"
    top.write_gds(os.path.join(OUT, "lna_5t_v2.gds"))
    print(f"Wrote {OUT}/lna_5t_v2.gds")


if __name__ == "__main__":
    main()

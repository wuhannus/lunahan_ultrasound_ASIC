#!/usr/bin/env python3
"""
LNA 5T OTA — v4 correct layout using glayout's proven diff_pair cell.

Strategy:
  - XM1/XM2 differential pair  -> glayout diff_pair (internal common-centroid,
    source shorting, drain routing to met3, gate bars to met3)
  - XMT tail (PMOS)            -> bare pmos
  - XMNL/XMNR loads (NMOS)     -> bare nmos
  - Connect everything on met3 using glayout routing primitives (real vias).

diff_pair port mapping:
  drain_routeTL_BR_con_*  = OP   (left input drain, TL and BR devices)
  drain_routeTR_BL_con_*  = ON   (right input drain)
  PLUSgateroute_*         = GP   (gate of left input)
  MINUSgateroute_*        = GN   (gate of right input)
  source_routeE/W_con_*   = TS   (shorted sources = tail node)
"""
import os
import gdstk

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.cells.elementary.diff_pair.diff_pair import diff_pair
from glayout.routing.smart_route import smart_route
from glayout.backend import Component

pdk = sky130_mapped_pdk
pdk.activate()
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "align_output"))


def route(top, p1, p2, layer="met3"):
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


def strip_pwell(gds_in, gds_out):
    lib = gdstk.read_gds(gds_in)
    removed = 0
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
            removed += 1
    lib.write_gds(gds_out)
    return removed


def main():
    print("Generating components...")
    # Diff pair: width=100, fingers=16 each side -> total 32 fingers per input
    # (matches schematic M=32 for XM1/XM2)
    dp = diff_pair(pdk, width=100, fingers=16, length=2, n_or_p_fet=False,
                   substrate_tap=False, dummy=False)
    print(f"  diff_pair: x={dp.xmin:.1f}..{dp.xmax:.1f} y={dp.ymin:.1f}..{dp.ymax:.1f}")

    # Tail: XMT W=20 f=80 -> W*M=1600 (sch W=100u M=16)
    xmt = pmos(pdk, width=20, fingers=80, multipliers=1, length=2,
               with_tie=True, with_dummy=False, dnwell=False, with_substrate_tap=False)
    print(f"  XMT: x={xmt.xmin:.1f}..{xmt.xmax:.1f} y={xmt.ymin:.1f}..{xmt.ymax:.1f}")

    # Loads: W=100 f=3 -> W*M=300 (sch W=100u M=3)
    xmnl = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=True, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    xmnr = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=True, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    print(f"  XMNL: x={xmnl.xmin:.1f}..{xmnl.xmax:.1f} y={xmnl.ymin:.1f}..{xmnl.ymax:.1f}")

    top = Component()
    sep = 3.0
    row_gap = 12.0

    # ---- Row A (top): loads XMNL | XMNR ----
    xmnl_ref = top << xmnl
    xmnr_ref = top << xmnr
    xmnl_ref.movex(0 - xmnl_ref.xmax - sep / 2).movey(0)
    xmnr_ref.movex(xmnr_ref.xmin + sep / 2).movey(0)

    # ---- Row B (middle): diff pair ----
    y_rowb = xmnl_ref.ymin - row_gap - dp.ymax
    dp_ref = top << dp
    dp_ref.movey(y_rowb).movex(0)

    # ---- Row C (bottom): tail XMT ----
    y_rowc = dp_ref.ymin - row_gap - xmt.ymax
    xmt_ref = top << xmt
    xmt_ref.movey(y_rowc).movex(0)

    print(f"\nAssembled bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")
    print(f"  loads bottom={xmnl_ref.ymin:.1f}, diff top={dp_ref.ymax:.1f}, gap={(dp_ref.ymax-xmnl_ref.ymin):.1f}")
    print(f"  diff bottom={dp_ref.ymin:.1f}, tail top={xmt_ref.ymax:.1f}, gap={(xmt_ref.ymax-dp_ref.ymin):.1f}")

    # ============================================================
    # Routing (all on met3 where possible; met2 for short hops)
    # ============================================================
    # NG: loads gate
    route(top, xmnl_ref.ports["gate_E"], xmnr_ref.ports["gate_W"], "met2")

    # OP: diff left drain -> xmnl drain
    route(top, dp_ref.ports["drain_routeTL_BR_con_S"], xmnl_ref.ports["drain_N"], "met3")

    # ON: diff right drain -> xmnr drain
    route(top, dp_ref.ports["drain_routeTR_BL_con_S"], xmnr_ref.ports["drain_N"], "met3")

    # TS: tail drain -> diff source (VTAIL)
    route(top, xmt_ref.ports["drain_N"], dp_ref.ports["source_routeE_con_S"], "met3")

    # VDDA: tail source -> tail body tie (with_tie gives tie_N_top_met_N)
    route(top, xmt_ref.ports["source_N"], xmt_ref.ports["tie_N_top_met_N"], "met2")

    # GND: loads source -> loads body ties
    route(top, xmnl_ref.ports["source_N"], xmnr_ref.ports["source_N"], "met2")
    route(top, xmnl_ref.ports["source_N"], xmnl_ref.ports["tie_N_top_met_N"], "met2")
    route(top, xmnr_ref.ports["source_N"], xmnr_ref.ports["tie_N_top_met_N"], "met2")

    # Diff pair body: add a met3 well tie to VDDA via tapring on met3
    # The diff_pair was built with substrate_tap=False; add an nwell tap ring
    # using met3 so it routes on the same metal as everything else.
    from glayout.primitives.guardring import tapring
    from glayout.util.comp_utils import evaluate_bbox
    from glayout.primitives.via_gen import via_stack
    from glayout.routing.straight_route import straight_route
    try:
        w = abs(dp_ref.xmax - dp_ref.xmin) + 2.0
        h = abs(dp_ref.ymax - dp_ref.ymin) + 2.0
        ntr = tapring(pdk, enclosed_rectangle=(w, h),
                      sdlayer="n+s/d", horizontal_glayer="met3", vertical_glayer="met3")
        ntr_ref = top << ntr
        ntr_ref.move((dp_ref.xmin + w/2 - (ntr_ref.xmax+ntr_ref.xmin)/2,
                      dp_ref.ymin + h/2 - (ntr_ref.ymax+ntr_ref.ymin)/2))
        tie_port = [p for p in ntr_ref.ports.values() if p.layer == (69, 20)][0]
        route(top, xmt_ref.ports["source_N"], tie_port, "met3")
        print("  diff_pair nwell tap ring added")
    except Exception as e:
        print(f"  !! tapring: {e}")

    # ============================================================
    # Top-level pins (labels + small met3 squares for LVS)
    # ============================================================
    pin_layer = (69, 20)  # met3
    label_layer = (69, 5)  # met3 label
    pins = {
        "VDDA": xmt_ref.ports["source_N"].center,
        "GND": xmnl_ref.ports["source_N"].center,
        "TS": dp_ref.ports["source_routeE_con_S"].center,
        "OP": dp_ref.ports["drain_routeTL_BR_con_S"].center,
        "ON": dp_ref.ports["drain_routeTR_BL_con_S"].center,
        "GP": dp_ref.ports["PLUSgateroute_W_con_S"].center,
        "GN": dp_ref.ports["MINUSgateroute_W_con_S"].center,
        "VB2": xmt_ref.ports["gate_S"].center,
        "NG": xmnl_ref.ports["gate_E"].center,
    }
    from glayout.backend import rectangle
    sq = rectangle(size=(0.4, 0.4), layer=pin_layer, centered=True)
    for nm, (cx, cy) in pins.items():
        sq_ref = top << sq
        sq_ref.move((cx, cy))

    print("\nWriting GDS...")
    top.name = "LNA_V4"
    top.write_gds(os.path.join(OUT, "lna_5t_v4.gds"))
    removed = strip_pwell(os.path.join(OUT, "lna_5t_v4.gds"),
                          os.path.join(OUT, "lna_5t_v4_nopwell.gds"))
    print(f"Wrote lna_5t_v4_nopwell.gds (removed {removed} pwell)")


if __name__ == "__main__":
    main()

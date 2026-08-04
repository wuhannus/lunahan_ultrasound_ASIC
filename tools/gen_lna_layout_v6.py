#!/usr/bin/env python3
"""
LNA 5T OTA — v6. Route to E/W edge ports (vias land on metal bars reliably).
diff_pair (XM1/XM2) + tail (XMT) + loads (XMNL/XMNR).

Topology:
  XMT  PMOS  D=TS   G=VB2  S=VDDA  B=VDDA
  XM1  PMOS  D=OP   G=GP   S=TS    B=VDDA   (diff_pair left)
  XM2  PMOS  D=ON   G=GN   S=TS    B=VDDA   (diff_pair right)
  XMNL NMOS  D=OP   G=NG   S=GND   B=GND    load left
  XMNR NMOS  D=ON   G=NG   S=GND   B=GND    load right
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
    dp = diff_pair(pdk, width=100, fingers=16, length=2, n_or_p_fet=False,
                   substrate_tap=False, dummy=False)
    xmt = pmos(pdk, width=20, fingers=80, multipliers=1, length=2,
               with_tie=True, with_dummy=False, dnwell=False, with_substrate_tap=False)
    xmnl = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=True, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    xmnr = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=True, with_dummy=False, with_dnwell=False, with_substrate_tap=False)

    top = Component()
    sep, row_gap = 3.0, 12.0

    # Row A: loads
    xmnl_ref = top << xmnl
    xmnr_ref = top << xmnr
    xmnl_ref.movex(0 - xmnl_ref.xmax - sep / 2).movey(0)
    xmnr_ref.movex(xmnr_ref.xmin + sep / 2).movey(0)

    # Row B: diff pair
    dp_ref = top << dp
    dp_ref.movey(xmnl_ref.ymin - row_gap - dp.ymax).movex(0)

    # Row C: tail
    xmt_ref = top << xmt
    xmt_ref.movey(dp_ref.ymin - row_gap - xmt.ymax).movex(0)

    print(f"\nbbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ============================================================
    # Signal routing — E/W edge ports
    # ============================================================
    # NG: load gates (gate_E -> gate_W horizontal on met2)
    route(top, xmnl_ref.ports["gate_E"], xmnr_ref.ports["gate_W"], "met2")

    # OP: diff left drain -> xmnl drain (edge port)
    route(top, dp_ref.ports["drain_routeTL_BR_con_S"], xmnl_ref.ports["drain_W"], "met3")

    # ON: diff right drain -> xmnr drain
    route(top, dp_ref.ports["drain_routeTR_BL_con_S"], xmnr_ref.ports["drain_E"], "met3")

    # TS: tail drain -> diff source (VTAIL). Tail drain at met1 bar top.
    route(top, xmt_ref.ports["drain_W"], dp_ref.ports["source_routeW_con_S"], "met3")
    route(top, xmt_ref.ports["drain_E"], dp_ref.ports["source_routeE_con_S"], "met3")

    # GND: loads source short + body ties
    route(top, xmnl_ref.ports["source_W"], xmnr_ref.ports["source_E"], "met2")
    route(top, xmnl_ref.ports["source_W"], xmnl_ref.ports["tie_W_top_met_W"], "met2")
    route(top, xmnr_ref.ports["source_E"], xmnr_ref.ports["tie_E_top_met_E"], "met2")

    # VDDA: tail source -> tail body tie
    route(top, xmt_ref.ports["source_W"], xmt_ref.ports["tie_W_top_met_W"], "met2")
    route(top, xmt_ref.ports["source_E"], xmt_ref.ports["tie_E_top_met_E"], "met2")

    # ============================================================
    # Labels for LVS (met3 pin labels)
    # ============================================================
    labels = {
        "VDDA": xmt_ref.ports["source_N"].center,
        "GND": xmnl_ref.ports["source_N"].center,
        "TS": dp_ref.ports["source_routeE_con_S"].center,
        "OP": dp_ref.ports["drain_routeTL_BR_con_S"].center,
        "ON": dp_ref.ports["drain_routeTR_BL_con_S"].center,
        "GP": dp_ref.ports["PLUSgateroute_W_con_S"].center,
        "GN": dp_ref.ports["MINUSgateroute_W_con_S"].center,
        "VB2": xmt_ref.ports["gate_W"].center,
        "NG": xmnl_ref.ports["gate_E"].center,
    }
    from glayout.backend import rectangle
    for nm, (cx, cy) in labels.items():
        sq = rectangle(size=(0.4, 0.4), layer=(69, 20), centered=True)
        sq_ref = top << sq
        sq_ref.move((cx, cy))

    print("\nWriting GDS...")
    top.name = "LNA_V6"
    top.write_gds(os.path.join(OUT, "lna_5t_v6.gds"))

    # Add labels via gdstk (top cell only), then strip pwell
    lib = gdstk.read_gds(os.path.join(OUT, "lna_5t_v6.gds"))
    for cell in lib.cells:
        if cell.name == "LNA_V6":
            for nm, (cx, cy) in labels.items():
                cell.add(gdstk.Label(nm, (cx, cy), layer=69, texttype=5))
            # remove the square pin polygons placed at label points? keep them.
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
    lib.write_gds(os.path.join(OUT, "lna_5t_v6_nopwell.gds"))
    print("Wrote lna_5t_v6_nopwell.gds")


if __name__ == "__main__":
    main()

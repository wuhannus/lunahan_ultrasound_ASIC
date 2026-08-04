#!/usr/bin/env python3
"""
LNA 5T OTA — v5 minimal assembly.
- diff_pair (XM1/XM2) + bare tail (XMT) + bare loads (XMNL/XMNR)
- Route ONLY the inter-cell signal nets via glayout routing.
- NO extra tap ring around diff_pair (it shorted everything).
- Power/ground routed to the FET tie ports (met2).
- No floating pin squares.
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
    # Inter-cell signal routing (met3 for long vertical runs)
    # ============================================================
    # NG: load gates
    route(top, xmnl_ref.ports["gate_E"], xmnr_ref.ports["gate_W"], "met2")

    # OP: diff TL/BL drain (left input) -> xmnl drain
    route(top, dp_ref.ports["drain_routeTL_BR_con_S"], xmnl_ref.ports["drain_N"], "met3")

    # ON: diff TR/BR drain (right input) -> xmnr drain
    route(top, dp_ref.ports["drain_routeTR_BL_con_S"], xmnr_ref.ports["drain_N"], "met3")

    # TS: tail drain -> diff source (VTAIL)
    route(top, xmt_ref.ports["drain_N"], dp_ref.ports["source_routeE_con_S"], "met3")

    # GND: load sources shorted + body ties
    route(top, xmnl_ref.ports["source_N"], xmnr_ref.ports["source_N"], "met2")
    route(top, xmnl_ref.ports["source_N"], xmnl_ref.ports["tie_N_top_met_N"], "met2")
    route(top, xmnr_ref.ports["source_N"], xmnr_ref.ports["tie_N_top_met_N"], "met2")

    # VDDA: tail source -> tail body tie
    route(top, xmt_ref.ports["source_N"], xmt_ref.ports["tie_N_top_met_N"], "met2")

    # Tail body tie well net also needs to be VDDA; tie its well via met2.
    # (with_tie puts the well tap on the tie_N_top_met port already)

    print("\nWriting GDS...")
    top.name = "LNA_V5"
    top.write_gds(os.path.join(OUT, "lna_5t_v5.gds"))
    removed = strip_pwell(os.path.join(OUT, "lna_5t_v5.gds"),
                          os.path.join(OUT, "lna_5t_v5_nopwell.gds"))
    print(f"Wrote lna_5t_v5_nopwell.gds (removed {removed} pwell)")


if __name__ == "__main__":
    main()

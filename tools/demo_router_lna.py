#!/usr/bin/env python3
"""
demo_router_lna.py — route the LNA 5T with the new analog maze router.
Placement mirrors the verified LNA (tools/gen_lna_layout_v8.py):
  loads (NMOS) top, diff_pair middle, tail (PMOS) bottom.
Nets mirror lna_5t_core.sp.
"""
import os
import sys

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.cells.elementary.diff_pair.diff_pair import diff_pair
from glayout.backend import Component

pdk = sky130_mapped_pdk
pdk.activate()

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from route_glayout_netlist import route_placed_layout

OUT = os.path.abspath(os.path.join(HERE, "..", "align_output"))


def main():
    print("Generating LNA cells...")
    ipair = diff_pair(pdk, width=100, fingers=16, length=2, n_or_p_fet=False,
                      substrate_tap=False, dummy=False)
    xmt = pmos(pdk, width=20, fingers=80, multipliers=1, length=2,
               with_tie=True, with_dummy=False, dnwell=False, with_substrate_tap=False)
    xmnl = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    xmnr = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)

    top = Component()
    sep, row_gap = 3.0, 12.0

    half = (xmnl.xmax - xmnl.xmin) / 2
    xmnl_ref = top << xmnl; xmnl_ref.movex(-(half + sep / 2)).movey(0); xmnl_ref.name = "XMNL"
    xmnr_ref = top << xmnr; xmnr_ref.movex(half + sep / 2).movey(0); xmnr_ref.name = "XMNR"
    dp_ref = top << ipair; dp_ref.movey(xmnl_ref.ymin - row_gap - ipair.ymax).movex(0); dp_ref.name = "DP"
    xmt_ref = top << xmt; xmt_ref.movey(dp_ref.ymin - row_gap - xmt.ymax).movex(0); xmt_ref.name = "XMT"

    print(f"LNA bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    nets = {
        "NG": [(xmnl_ref, "gate_E"), (xmnr_ref, "gate_W")],
        "OP": [(dp_ref, "drain_routeTL_BR_con_S"), (xmnl_ref, "drain_W")],
        "ON": [(dp_ref, "drain_routeTR_BL_con_S"), (xmnr_ref, "drain_E")],
        "TS": [(xmt_ref, "drain_W"), (dp_ref, "source_routeW_con_S")],
        "GND": [(xmnl_ref, "source_W"), (xmnr_ref, "source_E")],
        "VDDA": [(xmt_ref, "source_E"), (xmt_ref, "source_W")],
    }
    print("Routing nets:", list(nets.keys()))
    route_placed_layout(top, nets, os.path.join(OUT, "lna_router_demo.gds"),
                        "LNA_ROUTED", grid=0.1, spacing=0.2, metal_width=0.3)


if __name__ == "__main__":
    main()

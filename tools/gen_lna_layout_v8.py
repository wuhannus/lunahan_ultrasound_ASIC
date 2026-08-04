#!/usr/bin/env python3
"""
LNA 5T OTA — v8. glayout smart_route to E/W edge ports (proven in V4E test).
No manual gdstk, no pin squares, no tap rings around the diff_pair.

Proven: smart_route(diff.drain_routeTL_BR_con_S -> load.drain_W) creates OP.
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
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
    lib.write_gds(gds_out)


def main():
    print("Generating...")
    dp = diff_pair(pdk, width=100, fingers=16, length=2, n_or_p_fet=False,
                   substrate_tap=False, dummy=False)
    xmt = pmos(pdk, width=20, fingers=80, multipliers=1, length=2,
               with_tie=True, with_dummy=False, dnwell=False, with_substrate_tap=False)
    xmnl = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    xmnr = nmos(pdk, width=100, fingers=3, multipliers=1, length=8,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)

    top = Component()
    sep, row_gap = 3.0, 12.0
    # Correct symmetric placement around x=0
    half = (xmnl.xmax - xmnl.xmin) / 2
    xmnl_ref = top << xmnl
    xmnr_ref = top << xmnr
    xmnl_ref.movex(-(half + sep / 2)).movey(0)
    xmnr_ref.movex(half + sep / 2).movey(0)
    dp_ref = top << dp
    dp_ref.movey(xmnl_ref.ymin - row_gap - dp.ymax).movex(0)
    xmt_ref = top << xmt
    xmt_ref.movey(dp_ref.ymin - row_gap - xmt.ymax).movex(0)
    print(f"load gap: {xmnr_ref.xmin - xmnl_ref.xmax:.1f}")
    print(f"bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # --- NG: load gates (met2 horizontal) ---
    route(top, xmnl_ref.ports["gate_E"], xmnr_ref.ports["gate_W"], "met2")

    # --- OP: diff left drain -> load L drain (edge port) ---
    route(top, dp_ref.ports["drain_routeTL_BR_con_S"], xmnl_ref.ports["drain_W"], "met3")

    # --- ON: diff right drain -> load R drain ---
    route(top, dp_ref.ports["drain_routeTR_BL_con_S"], xmnr_ref.ports["drain_E"], "met3")

    # --- TS: tail drain -> diff source ---
    route(top, xmt_ref.ports["drain_W"], dp_ref.ports["source_routeW_con_S"], "met3")
    route(top, xmt_ref.ports["drain_E"], dp_ref.ports["source_routeE_con_S"], "met3")

    # --- GND: loads source short ---
    route(top, xmnl_ref.ports["source_W"], xmnr_ref.ports["source_E"], "met2")

    # --- VDDA: tail source (leave, label only) ---

    # Labels via gdstk on top cell
    labels = {
        "VDDA": xmt_ref.ports["source_N"].center,
        "GND": xmnl_ref.ports["source_N"].center,
        "TS": dp_ref.ports["source_routeW_con_S"].center,
        "OP": dp_ref.ports["drain_routeTL_BR_con_S"].center,
        "ON": dp_ref.ports["drain_routeTR_BL_con_S"].center,
        "GP": dp_ref.ports["PLUSgateroute_W_con_S"].center,
        "GN": dp_ref.ports["MINUSgateroute_W_con_S"].center,
        "VB2": xmt_ref.ports["gate_W"].center,
        "NG": xmnl_ref.ports["gate_E"].center,
    }

    print("Writing GDS...")
    top.name = "LNA_V8"
    top.write_gds(os.path.join(OUT, "lna_5t_v8.gds"))
    lib = gdstk.read_gds(os.path.join(OUT, "lna_5t_v8.gds"))
    for cell in lib.cells:
        if cell.name == "LNA_V8":
            for nm, (cx, cy) in labels.items():
                cell.add(gdstk.Label(nm, (float(cx), float(cy)), layer=69, texttype=5))
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
    lib.write_gds(os.path.join(OUT, "lna_5t_v8_nopwell.gds"))
    print("Wrote lna_5t_v8_nopwell.gds")


if __name__ == "__main__":
    main()

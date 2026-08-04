#!/usr/bin/env python3
"""
ADC StrongARM comparator layout — generated with the LNA glayout flow.
Blocks:
  - input differential pair   (NMOS diff_pair, common-centroid)
  - tail switch               (NMOS, single)
  - cross-coupled latch       (NMOS + PMOS pairs)
  - precharge reset           (PMOS pair)

Uses the same conventions as tools/gen_lna_layout_v8.py:
  symmetric placement, strip pwell(64,44), route via glayout primitives.
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

OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "align_output"))
os.makedirs(OUT, exist_ok=True)


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
    print("Generating comparator cells...")
    # input diff pair: NMOS, width=10u, 4 fingers/side (common-centroid)
    ipair = diff_pair(pdk, width=10, fingers=4, length=0.5, n_or_p_fet=True,
                      substrate_tap=False, dummy=False)
    # latch NMOS pair (cross-coupled) - two singles
    lat_n = nmos(pdk, width=6, fingers=1, multipliers=1, length=0.15,
                 with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    # latch PMOS pair
    lat_p = pmos(pdk, width=6, fingers=1, multipliers=1, length=0.15,
                 with_tie=False, with_dummy=False, dnwell=False, with_substrate_tap=False)
    # tail NMOS
    tail = nmos(pdk, width=8, fingers=1, multipliers=1, length=0.15,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    # precharge PMOS
    pre = pmos(pdk, width=2, fingers=1, multipliers=1, length=0.15,
               with_tie=False, with_dummy=False, dnwell=False, with_substrate_tap=False)

    print(f"  ipair: {ipair.xmin:.1f}..{ipair.xmax:.1f}  {ipair.ymin:.1f}..{ipair.ymax:.1f}")
    print(f"  tail : {tail.xmin:.1f}..{tail.xmax:.1f}  {tail.ymin:.1f}..{tail.ymax:.1f}")
    print(f"  lat_n: {lat_n.xmin:.1f}..{lat_n.xmax:.1f}  {lat_n.ymin:.1f}..{lat_n.ymax:.1f}")

    top = Component()
    sep, row_gap = 2.0, 4.0

    # Row A (top): precharge PMOS + latch PMOS
    pre_l = top << pre
    pre_r = top << pre
    half = (pre.xmax - pre.xmin) / 2
    pre_l.movex(-(half + sep / 2)).movey(0)
    pre_r.movex(half + sep / 2).movey(0)

    # Row B: latch NMOS (below precharge)
    yB = pre_l.ymin - row_gap - lat_n.ymax
    latn_l = top << lat_n
    latn_r = top << lat_n
    halfn = (lat_n.xmax - lat_n.xmin) / 2
    latn_l.movex(-(halfn + sep / 2)).movey(yB)
    latn_r.movex(halfn + sep / 2).movey(yB)

    # Row C: input diff pair
    yC = latn_l.ymin - row_gap - ipair.ymax
    ip_ref = top << ipair
    ip_ref.movey(yC).movex(0)

    # Row D: tail
    yD = ip_ref.ymin - row_gap - tail.ymax
    tail_ref = top << tail
    tail_ref.movey(yD).movex(0)

    print(f"\nComparator bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ---- routing (minimal - just tie key nodes) ----
    # tail source -> ipair shared source (VTAIL): route tail drain to ipair source
    # (diff_pair has source_route ports)
    route(top, tail_ref.ports["drain_N"], ip_ref.ports["source_routeW_con_S"], "met3")
    route(top, tail_ref.ports["drain_N"], ip_ref.ports["source_routeE_con_S"], "met3")

    print("\nWriting GDS...")
    top.name = "ADC_CMP"
    top.write_gds(os.path.join(OUT, "adc_cmp.gds"))
    strip_pwell(os.path.join(OUT, "adc_cmp.gds"), os.path.join(OUT, "adc_cmp_nopwell.gds"))
    print("Wrote adc_cmp_nopwell.gds")


if __name__ == "__main__":
    main()

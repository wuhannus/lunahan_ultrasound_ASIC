#!/usr/bin/env python3
"""
ADC analog-core layout — generated with the LNA glayout flow.
Blocks:
  - comparator: input diff_pair + tail + latch (NMOS/PMOS) + precharge
  - sampling: NMOS switches + MIM sampling caps
  - CDAC: MIM capacitor array (split-capacitor weights)

Same conventions as the LNA flow: symmetric placement, strip pwell(64,44).
"""
import os
import gdstk

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.primitives.mimcap import mimcap
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
    print("Generating ADC analog-core cells...")
    # comparator input diff pair (NMOS)
    ipair = diff_pair(pdk, width=10, fingers=4, length=0.5, n_or_p_fet=True,
                      substrate_tap=False, dummy=False)
    # latch / tail / precharge (single FETs)
    lat_n = nmos(pdk, width=6, fingers=1, multipliers=1, length=0.15,
                 with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    lat_p = pmos(pdk, width=6, fingers=1, multipliers=1, length=0.15,
                 with_tie=False, with_dummy=False, dnwell=False, with_substrate_tap=False)
    tail = nmos(pdk, width=8, fingers=1, multipliers=1, length=0.15,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    pre = pmos(pdk, width=2, fingers=1, multipliers=1, length=0.15,
               with_tie=False, with_dummy=False, dnwell=False, with_substrate_tap=False)
    # sampling switches (NMOS)
    sw = nmos(pdk, width=20, fingers=1, multipliers=1, length=0.15,
              with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    # CDAC caps (unit 20 fF -> MIM 5x5 um)
    cap = mimcap(pdk, size=(5.0, 5.0))

    print(f"  ipair: {ipair.xmin:.1f}..{ipair.xmax:.1f}  {ipair.ymin:.1f}..{ipair.ymax:.1f}")
    print(f"  cap  : {cap.xmin:.1f}..{cap.xmax:.1f}  {cap.ymin:.1f}..{cap.ymax:.1f}")
    print(f"  sw   : {sw.xmin:.1f}..{sw.xmax:.1f}  {sw.ymin:.1f}..{sw.ymax:.1f}")

    top = Component()
    sep, row_gap = 2.0, 4.0

    # Row A: CDAC cap array (MSB weights C,2C,4C,8C,16C -> 5 caps)
    cap_refs = []
    cap_w = cap.xmax - cap.xmin
    for i in range(5):
        r = top << cap
        r.movex((i - 2) * (cap_w + sep)).movey(0)
        cap_refs.append(r)

    # Row B: sampling switches (below caps)
    yB = cap_refs[0].ymin - row_gap - sw.ymax
    sw_refs = []
    for i in range(2):
        r = top << sw
        half = (sw.xmax - sw.xmin) / 2
        r.movex(-(half + sep / 2) if i == 0 else (half + sep / 2)).movey(yB)
        sw_refs.append(r)

    # Row C: comparator latch (NMOS + PMOS cross-coupled) + precharge
    yC = sw_refs[0].ymin - row_gap - lat_n.ymax
    latn_l = top << lat_n
    latn_r = top << lat_n
    halfn = (lat_n.xmax - lat_n.xmin) / 2
    latn_l.movex(-(halfn + sep / 2)).movey(yC)
    latn_r.movex(halfn + sep / 2).movey(yC)

    yC2 = latn_l.ymin - row_gap - lat_p.ymax
    latp_l = top << lat_p
    latp_r = top << lat_p
    halfp = (lat_p.xmax - lat_p.xmin) / 2
    latp_l.movex(-(halfp + sep / 2)).movey(yC2)
    latp_r.movex(halfp + sep / 2).movey(yC2)

    # precharge PMOS
    yC3 = latp_l.ymin - row_gap - pre.ymax
    pre_l = top << pre
    pre_r = top << pre
    halfpr = (pre.xmax - pre.xmin) / 2
    pre_l.movex(-(halfpr + sep / 2)).movey(yC3)
    pre_r.movex(halfpr + sep / 2).movey(yC3)

    # Row D: input diff pair
    yD = pre_l.ymin - row_gap - ipair.ymax
    ip_ref = top << ipair
    ip_ref.movey(yD).movex(0)

    # Row E: tail
    yE = ip_ref.ymin - row_gap - tail.ymax
    tail_ref = top << tail
    tail_ref.movey(yE).movex(0)

    print(f"\nADC core bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ---- minimal routing: tail -> ipair source ----
    route(top, tail_ref.ports["drain_N"], ip_ref.ports["source_routeW_con_S"], "met3")
    route(top, tail_ref.ports["drain_N"], ip_ref.ports["source_routeE_con_S"], "met3")

    print("\nWriting GDS...")
    top.name = "ADC_FULL"
    top.write_gds(os.path.join(OUT, "adc_full.gds"))
    strip_pwell(os.path.join(OUT, "adc_full.gds"), os.path.join(OUT, "adc_full_nopwell.gds"))
    print("Wrote adc_full_nopwell.gds")


if __name__ == "__main__":
    main()

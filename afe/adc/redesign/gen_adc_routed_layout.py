#!/usr/bin/env python3
"""
gen_adc_routed_layout.py — full ADC analog-core layout using the NEW analog
router (track-based Manhattan, tools/analog_router.py).

Blocks placed:
  - comparator input diff_pair (NMOS)
  - tail NMOS
  - sampling switches (2 NMOS)
  - CDAC MIM caps (5)
  - latch / precharge FETs

Nets (matching adc_10bit_full.sp topology):
  - VTAIL:  tail.drain <-> ipair source_route (both E/W)
  - INP:    sw_l drain <-> cap0 top
  - INN:    sw_r drain <-> cap1 top
  - GP:     ipair PLUSgate <-> cap2 top
  - GN:     ipair MINUSgate <-> cap3 top
  - CDAC:   caps bottom plates together

Outputs: align_output/adc_routed.gds (+ strip pwell) for DRC/LVS.
"""
import os
import sys

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.primitives.mimcap import mimcap
from glayout.cells.elementary.diff_pair.diff_pair import diff_pair
from glayout.backend import Component

pdk = sky130_mapped_pdk
pdk.activate()

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "..", "tools")))
from route_glayout_netlist import route_placed_layout, write_cells_to_gds

OUT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "align_output"))


def strip_pwell(gds_in, gds_out):
    import gdstk
    lib = gdstk.read_gds(gds_in)
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
    lib.write_gds(gds_out)


def main():
    print("Generating ADC cells...")
    ipair = diff_pair(pdk, width=10, fingers=4, length=0.5, n_or_p_fet=True,
                      substrate_tap=False, dummy=False)
    tail = nmos(pdk, width=8, fingers=1, multipliers=1, length=0.15,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    lat_n = nmos(pdk, width=6, fingers=1, multipliers=1, length=0.15,
                 with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    lat_p = pmos(pdk, width=6, fingers=1, multipliers=1, length=0.15,
                 with_tie=False, with_dummy=False, dnwell=False, with_substrate_tap=False)
    pre = pmos(pdk, width=2, fingers=1, multipliers=1, length=0.15,
               with_tie=False, with_dummy=False, dnwell=False, with_substrate_tap=False)
    sw = nmos(pdk, width=20, fingers=1, multipliers=1, length=0.15,
              with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    cap = mimcap(pdk, size=(5.0, 5.0))

    top = Component()
    sep, row_gap = 3.0, 6.0

    # Row A: CDAC caps (5)
    cap_w = cap.xmax - cap.xmin
    cap_refs = []
    for i in range(5):
        r = top << cap
        r.movex((i - 2) * (cap_w + sep)).movey(0)
        r.name = f"CAP{i}"
        cap_refs.append(r)

    # Row B: sampling switches
    yB = cap_refs[0].ymin - row_gap - sw.ymax
    sw_l = top << sw
    sw_r = top << sw
    halfsw = (sw.xmax - sw.xmin) / 2
    sw_l.movex(-(halfsw + sep / 2)).movey(yB); sw_l.name = "SW_L"
    sw_r.movex(halfsw + sep / 2).movey(yB); sw_r.name = "SW_R"

    # Row C: comparator (diff pair + tail + latch + precharge)
    yC = sw_l.ymin - row_gap - ipair.ymax
    ip_ref = top << ipair
    ip_ref.movey(yC).movex(0); ip_ref.name = "IPAIR"

    yD = ip_ref.ymin - row_gap - tail.ymax
    tail_ref = top << tail
    tail_ref.movey(yD).movex(0); tail_ref.name = "TAIL"

    # latch + precharge (named, placed beside comparator)
    latn_l = top << lat_n
    latn_l.movex(ip_ref.xmin - lat_n.xmax - sep).movey(ip_ref.ymax); latn_l.name = "LATN_L"
    latn_r = top << lat_n
    latn_r.movex(ip_ref.xmax + sep).movey(ip_ref.ymax); latn_r.name = "LATN_R"
    latp_l = top << lat_p
    latp_l.movex(ip_ref.xmin - lat_p.xmax - sep).movey(ip_ref.ymin - row_gap - lat_p.ymax); latp_l.name = "LATP_L"
    latp_r = top << lat_p
    latp_r.movex(ip_ref.xmax + sep).movey(ip_ref.ymin - row_gap - lat_p.ymax); latp_r.name = "LATP_R"
    pre_l = top << pre
    pre_l.movex(ip_ref.xmin - pre.xmax - sep).movey(ip_ref.ymin - 2*row_gap - pre.ymax); pre_l.name = "PRE_L"
    pre_r = top << pre
    pre_r.movex(ip_ref.xmax + sep).movey(ip_ref.ymin - 2*row_gap - pre.ymax); pre_r.name = "PRE_R"

    print(f"ADC bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ============ NETLIST ============
    nets = {
        # tail drain -> input pair shared source (VTAIL)
        "VTAIL": [(tail_ref, "drain_E"), (ip_ref, "source_routeE_con_S"),
                  (tail_ref, "drain_W"), (ip_ref, "source_routeW_con_S")],
        # sampling -> CDAC top plates
        "INP": [(sw_l, "drain_E"), (cap_refs[0], "top_met_E")],
        "INN": [(sw_r, "drain_E"), (cap_refs[1], "top_met_E")],
        # CDAC top -> comparator gates
        "GP": [(cap_refs[2], "top_met_W"), (ip_ref, "PLUSgateroute_W_con_S")],
        "GN": [(cap_refs[3], "top_met_W"), (ip_ref, "MINUSgateroute_W_con_S")],
        # latch cross-coupling
        "OP": [(ip_ref, "drain_routeTL_BR_con_S"), (latn_r, "gate_E")],
        "ON": [(ip_ref, "drain_routeTR_BL_con_S"), (latn_l, "gate_E")],
        "LATCHL": [(latn_l, "drain_E"), (latp_l, "gate_E")],
        "LATCHR": [(latn_r, "drain_E"), (latp_r, "gate_E")],
        "PRECH_L": [(pre_l, "drain_E"), (latp_l, "drain_E")],
        "PRECH_R": [(pre_r, "drain_E"), (latp_r, "drain_E")],
    }

    print("Routing nets:", list(nets.keys()))
    route_placed_layout(top, nets, os.path.join(OUT, "adc_routed.gds"),
                        "ADC_ROUTED", grid=0.1, spacing=0.2, metal_width=0.3)
    strip_pwell(os.path.join(OUT, "adc_routed.gds"), os.path.join(OUT, "adc_routed_nopwell.gds"))
    print("Wrote adc_routed_nopwell.gds")


if __name__ == "__main__":
    main()

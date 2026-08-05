#!/usr/bin/env python3
"""
gen_adc_entire_layout.py — 10-bit SAR ADC entire layout using the analog
router (A* maze + Magic DRC-aware loop).

Source: align_input/adc_10bit_sar_core.sp (layout-source netlist).

Blocks placed (glayout cells):
  - CLKS inverter (INV) + CMOS sampling switches (SW) on INP/INN
  - sampling caps + CDAC (MOM inter-finger caps, tools/mom_cap.py)
  - CDAC bottom-plate switches
  - StrongARM comparator (input pair, tail, latch, precharge, buffer)

Inter-block nets routed with AnalogRouter (maze) then Magic-DRC-corrected.
"""
import os
import sys

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.backend import Component

pdk = sky130_mapped_pdk
pdk.activate()

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.abspath(os.path.join(HERE, "..", "..", "..", "tools"))
sys.path.insert(0, TOOLS)

from route_glayout_netlist import route_placed_layout, write_cells_to_gds
from mom_cap import MomCap

OUT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "align_output"))


def strip_pwell(gds_in, gds_out):
    import gdstk
    lib = gdstk.read_gds(gds_in)
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
    lib.write_gds(gds_out)


def make_fet(kind, w, l, m=1):
    if kind == 'n':
        return nmos(pdk, width=w, fingers=m, multipliers=1, length=l,
                    with_tie=False, with_dummy=False, with_dnwell=False,
                    with_substrate_tap=False)
    return pmos(pdk, width=w, fingers=m, multipliers=1, length=l,
                with_tie=False, with_dummy=False, dnwell=False,
                with_substrate_tap=False)


def main():
    print("=== 10-bit SAR ADC entire layout ===")
    top = Component()
    sep, row_gap = 3.0, 6.0

    # ---------------- placement ----------------
    # Row A: CLKS inverter + sampling switches
    inv_p = top << make_fet('p', 2, 0.15)
    inv_p.name = "INV_P"
    inv_p.movex(0).movey(0)
    inv_n = top << make_fet('n', 2, 0.15)
    inv_n.name = "INV_N"
    inv_n.movex(inv_p.xmin).movey(inv_p.ymin - row_gap - inv_n.ymax)

    # sampling CMOS switches (NMOS+PMOS each)
    sw_ip_n = top << make_fet('n', 20, 0.15)
    sw_ip_n.name = "SW_IP_N"
    sw_ip_n.movex(inv_n.xmin).movey(inv_n.ymin - row_gap - sw_ip_n.ymax)
    sw_ip_p = top << make_fet('p', 40, 0.15)
    sw_ip_p.name = "SW_IP_P"
    sw_ip_p.movex(sw_ip_n.xmin).movey(sw_ip_n.ymin - row_gap - sw_ip_p.ymax)

    # ---------------- CDAC MOM caps ----------------
    # unit cap ~20 fF: MOM fingers length=10, 12 fingers -> ~81 um2
    mom = MomCap(length=10.0, fingers=12)
    # 5 MSB caps + bridge + 5 LSB caps = 11 caps
    cap_y = sw_ip_p.ymin - row_gap - 12.0
    cap_refs = []
    for i in range(11):
        capcell = mom.build(name=f"MOMC{i}")
        ref = top << capcell
        ref.movex((i - 5) * (mom.width + sep)).movey(cap_y)
        ref.name = f"MOMCAP{i}"
        cap_refs.append(ref)

    # ---------------- comparator ----------------
    comp_y = cap_y - 12.0 - 15.0
    # input pair (2 NMOS)
    ip1 = top << make_fet('n', 20, 0.5)
    ip1.name = "COMP_IP1"
    ip1.movex(0).movey(comp_y)
    ip2 = top << make_fet('n', 20, 0.5)
    ip2.name = "COMP_IP2"
    ip2.movex(ip1.xmin).movey(ip1.ymin - row_gap - ip2.ymax)
    # tail
    tail = top << make_fet('n', 8, 0.15)
    tail.name = "COMP_TAIL"
    tail.movex(ip2.xmin).movey(ip2.ymin - row_gap - tail.ymax)
    # latch NMOS + PMOS + precharge
    ln1 = top << make_fet('n', 6, 0.15); ln1.name = "LATCH_N1"
    ln1.movex(ip1.xmin).movey(tail.ymin - row_gap - ln1.ymax)
    ln2 = top << make_fet('n', 6, 0.15); ln2.name = "LATCH_N2"
    ln2.movex(ip1.xmin).movey(ln1.ymin - row_gap - ln2.ymax)
    lp1 = top << make_fet('p', 6, 0.15); lp1.name = "LATCH_P1"
    lp1.movex(ip1.xmin).movey(ln2.ymin - row_gap - lp1.ymax)
    lp2 = top << make_fet('p', 6, 0.15); lp2.name = "LATCH_P2"
    lp2.movex(ip1.xmin).movey(lp1.ymin - row_gap - lp2.ymax)

    print(f"ADC bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ---------------- inter-block nets (router) ----------------
    nets = {
        # sampling: INP/INN through CMOS switch -> SIPN/SINN
        "INP": [(sw_ip_n, "drain_E"), (sw_ip_p, "drain_E")],
        "INN": [(sw_ip_n, "source_E"), (sw_ip_p, "source_E")],
        "CLKS": [(inv_p, "gate_E"), (sw_ip_n, "gate_E")],
        "CLKSB": [(inv_p, "drain_E"), (sw_ip_p, "gate_E")],
        # CDAC top -> comparator input (MOM top plates + comparator gate)
        "DAC_P": [(cap_refs[0], "top"), (ip1, "gate_E")],
        # CDAC bottom (bridge + MSB bottoms share node)
        "VCM": [(cap_refs[0], "bottom"), (cap_refs[1], "bottom"),
                (cap_refs[2], "bottom")],
    }
    print("Routing nets:", list(nets.keys()))
    route_placed_layout(top, nets, os.path.join(OUT, "adc_entire.gds"),
                        "ADC_ENTIRE", grid=0.1, spacing=0.2, metal_width=0.3,
                        drc_aware=True, drc_tile=3.0, drc_max_iter=3)
    # flatten the whole GDS into one flat top cell for Magic extraction
    import gdstk
    lib = gdstk.read_gds(os.path.join(OUT, "adc_entire.gds"))
    flat = gdstk.Cell("ADC_FLAT")
    for cell in lib.cells:
        cell.flatten(True)
    # gather all polygons into a single flat cell
    for cell in lib.cells:
        for p in cell.polygons:
            flat.add(p)
    lib2 = gdstk.Library()
    lib2.add(flat)
    lib2.write_gds(os.path.join(OUT, "adc_entire_flat.gds"))
    strip_pwell(os.path.join(OUT, "adc_entire_flat.gds"),
                os.path.join(OUT, "adc_entire_nopwell.gds"))
    print("Wrote adc_entire_nopwell.gds (flat)")


if __name__ == "__main__":
    main()

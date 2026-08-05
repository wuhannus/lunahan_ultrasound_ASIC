#!/usr/bin/env python3
"""
gen_adc_entire_layout.py — 10-bit SAR ADC entire layout with the analog router.

Source: align_input/adc_10bit_sar_core.sp (layout-source netlist).

Key rules (per user):
  1. LVS pass is the delivery gate.
  2. Port labels MUST be present (met3 text) so Magic sees the ports.
  3. MOM caps are BLACK-BOXED during LVS (parasitic two-terminal caps).
  4. All nets from the netlist are routed between the placed cells.

Flow:
  place cells (glayout FETs + MOM caps) -> route nets (AnalogRouter maze
  + Magic DRC-aware) -> add met3 port labels -> write GDS -> Magic extract
  -> connectivity LVS (MOM caps black-boxed).
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

from route_glayout_netlist import route_placed_layout
from mom_cap import MomCap

OUT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "align_output"))
NETLIST = os.path.abspath(os.path.join(HERE, "..", "..", "..", "align_input", "adc_10bit_sar_core.sp"))


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


def place_blocks(top):
    """Place all FET/cap cells; return dict of named refs and port anchors."""
    refs = {}
    sep, row_gap = 4.0, 8.0

    # CLKS inverter
    inv_p = top << make_fet('p', 2, 0.15); inv_p.name = "INV_P"; inv_p.movex(0).movey(0)
    inv_n = top << make_fet('n', 2, 0.15); inv_n.name = "INV_N"
    inv_n.movex(inv_p.xmin).movey(inv_p.ymin - row_gap - inv_n.ymax)
    refs['inv_p'] = inv_p
    refs['inv_n'] = inv_n

    # sampling switches (CMOS)
    sw_ip_n = top << make_fet('n', 20, 0.15); sw_ip_n.name = "SW_IP_N"
    sw_ip_n.movex(inv_n.xmin).movey(inv_n.ymin - row_gap - sw_ip_n.ymax)
    sw_ip_p = top << make_fet('p', 40, 0.15); sw_ip_p.name = "SW_IP_P"
    sw_ip_p.movex(sw_ip_n.xmin).movey(sw_ip_n.ymin - row_gap - sw_ip_p.ymax)
    sw_in_n = top << make_fet('n', 20, 0.15); sw_in_n.name = "SW_IN_N"
    sw_in_n.movex(sw_ip_n.xmin).movey(sw_ip_p.ymin - row_gap - sw_in_n.ymax)
    sw_in_p = top << make_fet('p', 40, 0.15); sw_in_p.name = "SW_IN_P"
    sw_in_p.movex(sw_in_n.xmin).movey(sw_in_n.ymin - row_gap - sw_in_p.ymax)
    refs['sw_ip_n'] = sw_ip_n
    refs['sw_ip_p'] = sw_ip_p
    refs['sw_in_n'] = sw_in_n
    refs['sw_in_p'] = sw_in_p

    # MOM caps (CDAC: 5 MSB + bridge + 5 LSB = 11 caps)
    mom = MomCap(length=10.0, fingers=12)
    cap_y = sw_in_p.ymin - row_gap - 12.0
    cap_refs = []
    for i in range(11):
        capcell = mom.build(name=f"MOMC{i}")
        r = top << capcell
        r.movex((i - 5) * (mom.width + sep)).movey(cap_y)
        r.name = f"MOMCAP{i}"
        cap_refs.append(r)
    refs['cap'] = cap_refs

    # comparator
    cy = cap_y - 12.0 - 15.0
    ip1 = top << make_fet('n', 20, 0.5); ip1.name = "COMP_IP1"; ip1.movex(0).movey(cy)
    ip2 = top << make_fet('n', 20, 0.5); ip2.name = "COMP_IP2"
    ip2.movex(ip1.xmin).movey(ip1.ymin - row_gap - ip2.ymax)
    tail = top << make_fet('n', 8, 0.15); tail.name = "COMP_TAIL"
    tail.movex(ip2.xmin).movey(ip2.ymin - row_gap - tail.ymax)
    refs['ip1'] = ip1
    refs['ip2'] = ip2
    refs['tail'] = tail

    return refs


def main():
    print("=== 10-bit SAR ADC entire layout (LVS-gated) ===")
    top = Component()
    refs = place_blocks(top)
    print(f"ADC bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ---- nets: route port labels INTO the device terminals ----
    # each port is anchored at a real device terminal so the label connects
    nets = {
        # power/ground to device bodies
        "VDD": [(refs['sw_ip_p'], "source_E"), (refs['sw_in_p'], "source_E")],
        "GND": [(refs['sw_ip_n'], "source_E"), (refs['sw_in_n'], "source_E"),
                (refs['tail'], "source_E")],
        # CMOS sampling switch: INP/INN through NMOS+PMOS -> SIPN/SINN
        "INP": [(refs['sw_ip_n'], "drain_E"), (refs['sw_ip_p'], "drain_E")],
        "INN": [(refs['sw_in_n'], "drain_E"), (refs['sw_in_p'], "drain_E")],
        "CLKS": [(refs['sw_ip_n'], "gate_E"), (refs['sw_in_n'], "gate_E")],
        "CLKSB": [(refs['sw_ip_p'], "gate_E"), (refs['sw_in_p'], "gate_E")],
        # CDAC top -> comparator input
        "DAC_P": [(refs['cap'][0], "top"), (refs['ip1'], "gate_E")],
        "VCM": [(refs['cap'][0], "bottom"), (refs['cap'][1], "bottom")],
        # comparator input pair sources (shared tail)
        "TAIL_N": [(refs['ip1'], "source_E"), (refs['ip2'], "source_E"),
                   (refs['tail'], "drain_E")],
        # comparator output + clocks
        "OUT": [(refs['ip1'], "drain_E")],
        "CLKC": [(refs['tail'], "gate_E")],
        "VREF": [(refs['cap'][2], "bottom")],
    }
    print("Routing nets:", list(nets.keys()))
    route_placed_layout(top, nets, os.path.join(OUT, "adc_entire.gds"),
                        "ADC_ENTIRE", grid=0.1, spacing=0.2, metal_width=0.3,
                        drc_aware=True, drc_tile=3.0, drc_max_iter=3)

    # ---- add met3 port labels to the final routed GDS ----
    # the DRC-aware loop flattened everything into one cell; add labels there
    import gdstk
    lib = gdstk.read_gds(os.path.join(OUT, "adc_entire.gds"))
    tc = lib.cells[0]   # single flat cell
    anchor = {
        "VDD": refs['sw_ip_p'].ports["source_E"].center,
        "GND": refs['tail'].ports["source_E"].center,
        "INP": refs['sw_ip_n'].ports["drain_E"].center,
        "INN": refs['sw_in_n'].ports["drain_E"].center,
        "CLKS": refs['sw_ip_n'].ports["gate_E"].center,
        "CLKC": refs['tail'].ports["gate_E"].center,
        "OUT": refs['ip1'].ports["drain_E"].center,
        "VREF": refs['cap'][2].ports["bottom"].center,
        "VCM": refs['cap'][0].ports["bottom"].center,
    }
    # label on the device terminal metal layer (MET1=68) so Magic ties the
    # label to the device net, plus a met3 text label for port visibility
    for nm, (x, y) in anchor.items():
        tc.add(gdstk.Label(nm, (float(x), float(y)), layer=68, texttype=16))
        tc.add(gdstk.Label(nm, (float(x), float(y)), layer=70, texttype=20))
        tc.add(gdstk.rectangle((float(x) - 0.2, float(y) - 0.2),
                               (float(x) + 0.2, float(y) + 0.2),
                               layer=68, datatype=20))
        tc.add(gdstk.rectangle((float(x) - 0.2, float(y) - 0.2),
                               (float(x) + 0.2, float(y) + 0.2),
                               layer=70, datatype=20))
    lib.write_gds(os.path.join(OUT, "adc_entire.gds"))
    strip_pwell(os.path.join(OUT, "adc_entire.gds"),
                os.path.join(OUT, "adc_entire_nopwell.gds"))
    print("Wrote adc_entire_nopwell.gds with port labels at device terminals")


if __name__ == "__main__":
    main()

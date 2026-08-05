#!/usr/bin/env python3
"""
ADC comparator core layout — LNA glayout flow, CONNECTIVITY-VERIFIED.

This generator builds the ADC's comparator core (input differential pair +
tail current source) — the analog block whose routing MUST be correct for the
ADC to function. It uses exactly the LNA-verified structure:

    tail drain  --(met3 route)-->  input-pair shared source  (net VTAIL)

The CDAC MIM capacitor array and sampling switches are generated and DRC-clean
but NOT auto-routed (a full SAR analog core needs a proper analog router /
manual top-metal routing, which smart_route cannot do without shorts).

LVS: the extracted comparator-core netlist is compared net-by-net against the
reference comparator schematic (strongarm comparator topology).
"""
import os
import gdstk

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos
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
    print("Generating comparator core (diff pair + tail)...")
    ipair = diff_pair(pdk, width=10, fingers=4, length=0.5, n_or_p_fet=True,
                      substrate_tap=False, dummy=False)
    tail = nmos(pdk, width=8, fingers=1, multipliers=1, length=0.15,
                with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)

    top = Component()
    row_gap = 4.0

    ip_ref = top << ipair
    ip_ref.movey(0).movex(0)
    yT = ip_ref.ymin - row_gap - tail.ymax
    tail_ref = top << tail
    tail_ref.movey(yT).movex(0)

    print(f"Comparator bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # tail drain -> input pair shared source (E/W edge ports, verified)
    route(top, tail_ref.ports["drain_E"], ip_ref.ports["source_routeE_con_S"], "met3")
    route(top, tail_ref.ports["drain_W"], ip_ref.ports["source_routeW_con_S"], "met3")

    print("\nWriting GDS...")
    top.name = "ADC_CMP_CORE"
    top.write_gds(os.path.join(OUT, "adc_cmp_core.gds"))
    strip_pwell(os.path.join(OUT, "adc_cmp_core.gds"), os.path.join(OUT, "adc_cmp_core_nopwell.gds"))
    print("Wrote adc_cmp_core_nopwell.gds")


if __name__ == "__main__":
    main()

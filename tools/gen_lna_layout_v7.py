#!/usr/bin/env python3
"""
LNA 5T OTA — v7. Manual gdstk routing with exact Magic layer numbers.
Cells come from glayout (standalone-verified). Routing drawn by hand with
MET1=68/20, MET2=69/20, via1=68/44 so vias land exactly on cell bars.

Layer plan (Magic sky130A):
  64/20 nwell   65/20 diff   66/20 poly   66/44 cont
  67/20 li      68/20 met1   68/44 via1   69/20 met2
  93/44 nsdm    94/20 psdm   95/20 npc
"""
import os
import gdstk

os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
from glayout.primitives.fet import nmos, pmos
from glayout.cells.elementary.diff_pair.diff_pair import diff_pair
from glayout.backend import Component

pdk = sky130_mapped_pdk
pdk.activate()
OUT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "align_output"))

MET1 = (68, 20)
MET2 = (69, 20)
VIA1 = (68, 44)
LABEL = (69, 5)


def strip_pwell(gds_in, gds_out):
    lib = gdstk.read_gds(gds_in)
    for cell in lib.cells:
        for p in [p for p in cell.polygons if p.layer == 64 and p.datatype == 44]:
            cell.remove(p)
    lib.write_gds(gds_out)


def hline(cell, x0, x1, y, layer=MET1, w=0.30):
    cell.add(gdstk.rectangle((float(x0), float(y - w / 2)), (float(x1), float(y + w / 2)),
                             layer=layer[0], datatype=layer[1]))


def vline(cell, x, y0, y1, layer=MET1, w=0.30):
    cell.add(gdstk.rectangle((float(x - w / 2), float(y0)), (float(x + w / 2), float(y1)),
                             layer=layer[0], datatype=layer[1]))


def via(cell, x, y, size=0.20):
    cell.add(gdstk.rectangle((float(x - size / 2), float(y - size / 2)),
                             (float(x + size / 2), float(y + size / 2)),
                             layer=VIA1[0], datatype=VIA1[1]))


def main():
    print("Generating components...")
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

    # Row A: loads (no tie)
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

    print(f"bbox: x={top.xmin:.1f}..{top.xmax:.1f} y={top.ymin:.1f}..{top.ymax:.1f}")

    # ============================================================
    # Manual routing (gdstk on Magic layers)
    # Access ports directly (diff_pair has 279k ports - no full dict)
    # ============================================================
    MW = 0.5  # routing metal width

    # --- NG: load gates (horizontal met1) ---
    gL = xmnl_ref.ports["gate_E"].center
    gR = xmnr_ref.ports["gate_W"].center
    hline(top, min(gL[0], gR[0]), max(gL[0], gR[0]), gL[1], MET1, MW)

    # --- GND: load sources short (horizontal met1) ---
    sL = xmnl_ref.ports["source_W"].center
    sR = xmnr_ref.ports["source_E"].center
    hline(top, sL[0], sR[0], sL[1], MET1, MW)

    # --- OP: diff TL drain -> load L drain ---
    # met2 vertical down the load-drain X, stub met2 horizontally to diff port
    op_dp = dp_ref.ports["drain_routeTL_BR_con_S"].center
    op_ld = xmnl_ref.ports["drain_W"].center
    vx = op_ld[0]                        # met2 at load drain X
    vline(top, vx, op_dp[1], op_ld[1], MET2, MW)
    via(top, vx, op_ld[1])               # via onto load drain met1 bar
    via(top, vx, op_dp[1])               # via onto diff met3 port
    # horizontal met2 stub from diff port to the vertical (at same Y as op_dp)
    if abs(op_dp[0] - vx) > 0.01:
        hline(top, min(op_dp[0], vx), max(op_dp[0], vx), op_dp[1], MET2, MW)

    # --- ON: diff TR drain -> load R drain ---
    on_dp = dp_ref.ports["drain_routeTR_BL_con_S"].center
    on_ld = xmnr_ref.ports["drain_E"].center
    vx2 = on_ld[0]
    vline(top, vx2, on_dp[1], on_ld[1], MET2, MW)
    via(top, vx2, on_ld[1])
    via(top, vx2, on_dp[1])
    if abs(on_dp[0] - vx2) > 0.01:
        hline(top, min(on_dp[0], vx2), max(on_dp[0], vx2), on_dp[1], MET2, MW)

    # --- TS: tail drain -> diff source (met2 vertical at tail drain X) ---
    ts_t = xmt_ref.ports["drain_W"].center
    ts_dp = dp_ref.ports["source_routeW_con_S"].center
    vx3 = ts_t[0]
    vline(top, vx3, ts_t[1], ts_dp[1], MET2, MW)
    via(top, vx3, ts_t[1])
    via(top, vx3, ts_dp[1])
    if abs(ts_dp[0] - vx3) > 0.01:
        hline(top, min(ts_dp[0], vx3), max(ts_dp[0], vx3), ts_dp[1], MET2, MW)

    # ============================================================
    # Labels (met2 texttype 5)
    # ============================================================
    labels = {
        "VDDA": xmt_ref.ports["source_N"].center,
        "GND": (sL[0], sL[1]),
        "TS": ts_dp,
        "OP": op_dp,
        "ON": on_dp,
        "GP": dp_ref.ports["PLUSgateroute_W_con_S"].center,
        "GN": dp_ref.ports["MINUSgateroute_W_con_S"].center,
        "VB2": xmt_ref.ports["gate_W"].center,
        "NG": (gL[0], gL[1]),
    }
    for nm, (cx, cy) in labels.items():
        top.add(gdstk.Label(nm, (float(cx), float(cy)), layer=69, texttype=5))
        top.add(gdstk.rectangle((float(cx) - 0.15, float(cy) - 0.15),
                                (float(cx) + 0.15, float(cy) + 0.15),
                                layer=MET2[0], datatype=MET2[1]))

    print("\nWriting GDS...")
    top.name = "LNA_V7"
    top.write_gds(os.path.join(OUT, "lna_5t_v7.gds"))
    strip_pwell(os.path.join(OUT, "lna_5t_v7.gds"), os.path.join(OUT, "lna_5t_v7_nopwell.gds"))
    print("Wrote lna_5t_v7_nopwell.gds")


if __name__ == "__main__":
    main()

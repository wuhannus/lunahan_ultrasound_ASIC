#!/usr/bin/env python3
"""
route_glayout_netlist.py — route a placed glayout analog circuit with the
analog_router. Reads placed references (ports + geometry) and a netlist, emits
DRC-aware multi-layer routing merged with the placed cells.

Usage (from a layout generator):
  from route_glayout_netlist import route_placed_layout
  route_placed_layout(
      component,       # glayout Component with placed refs (names set!)
      netlist,         # {net: [(ref, "port_name"), ...]}
      out_gds,
      grid=0.05, spacing=0.1, width=0.2)
"""
import os
import gdstk
import numpy as np

from analog_router import AnalogRouter, ALL_LAYERS


def _layer_index_of(router, layer_num):
    for i, L in enumerate(ALL_LAYERS):
        if L[0] == layer_num:
            return i
    return None


def _poly_layer(poly):
    """poly from get_polygons(by_spec=True) is (layer, datatype, points) or (layer, points)."""
    if len(poly) == 3:
        return poly[0], poly[1], np.array(poly[2], dtype=float)
    elif len(poly) == 2:
        return poly[0], 20, np.array(poly[1], dtype=float)
    return None


def route_placed_layout(component, netlist, out_gds, top_cell="ROUTED",
                        grid=0.1, spacing=0.2, metal_width=0.3, via_size=0.2,
                        extra_obstacles=None):
    refs = list(component.references)
    if not refs:
        raise ValueError("component has no placed references")

    # ---- bounds ----
    xs, ys = [], []
    for ref in refs:
        bb = np.array(ref.bbox, dtype=float)
        xs += [bb[0][0], bb[1][0]]
        ys += [bb[0][1], bb[1][1]]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)

    r = AnalogRouter(grid=grid, min_spacing=spacing, metal_width=metal_width,
                     via_size=via_size)
    r.set_bounds(x0, y0, x1, y1)

    # ---- obstacles: write cells to GDS then read back geometry ----
    _tmp = "/tmp/_cells_for_router.gds"
    write_cells_to_gds(component, _tmp, top_cell="CELLS")
    _lib = gdstk.read_gds(_tmp)
    for _cell in _lib.cells:
        for _poly in _cell.polygons:
            li = _layer_index_of(r, _poly.layer)
            if li is None:
                continue
            bb = _poly.bounding_box()
            r.add_obstacle(bb[0][0], bb[0][1], bb[1][0], bb[1][1], li)
    # also flatten any nested refs in the top cell
    for _cell in _lib.cells:
        _cell.flatten(True)
        for _poly in _cell.polygons:
            li = _layer_index_of(r, _poly.layer)
            if li is None:
                continue
            bb = _poly.bounding_box()
            r.add_obstacle(bb[0][0], bb[0][1], bb[1][0], bb[1][1], li)

    if extra_obstacles:
        for x0o, y0o, x1o, y1o, lyr in extra_obstacles:
            r.add_obstacle(x0o, y0o, x1o, y1o, lyr)

    # ---- ports: ONLY the ports actually named in the netlist ----
    # (registering every metal port of a diff_pair/cell adds hundreds of pads
    #  that merge into a MET1 blob and short everything)
    used = set()
    for port_refs in netlist.values():
        for ref, p in port_refs:
            used.add((id(ref), p))
    for ref in refs:
        rname = ref.name
        for pname, port in ref.ports.items():
            if (id(ref), pname) not in used:
                continue
            if port.layer[1] != 20:
                continue
            if _layer_index_of(r, port.layer[0]) is None:
                continue
            r.add_port(f"{rname}.{pname}", port.layer,
                       float(port.center[0]), float(port.center[1]))

    # ---- route nets ----
    for net, port_refs in netlist.items():
        names = [f"{ref.name}.{p}" for ref, p in port_refs]
        r.route_net(net, names)

    # ---- write GDS: placed cells + routing (via gdsfactory for nested refs) ----
    out = component.copy()
    out.name = top_cell
    for poly in r.polys + r.vias:
        pts = np.array(poly.points, dtype=float)
        out.add_polygon(pts, layer=(poly.layer, poly.datatype))
    out.write_gds(out_gds)
    print(f"Wrote {out_gds}: {len(r.polys)} metal + {len(r.vias)} via polys, {len(netlist)} nets")
    return r


def write_cells_to_gds(component, path, top_cell="CELLS"):
    # write via gdsfactory (handles nested refs), read back with gdstk
    tmp = component.copy()
    tmp.name = top_cell
    tmp.write_gds(path)
    print(f"Wrote {path}")


if __name__ == "__main__":
    os.environ.setdefault("PDK_ROOT", "/opt/homebrew/share/pdk")
    from glayout.pdk.sky130_mapped.sky130_mapped import sky130_mapped_pdk
    from glayout.primitives.fet import nmos
    from glayout.backend import Component

    pdk = sky130_mapped_pdk
    a = nmos(pdk, width=5, fingers=1, multipliers=1, length=0.5,
             with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    b = nmos(pdk, width=5, fingers=1, multipliers=1, length=0.5,
             with_tie=False, with_dummy=False, with_dnwell=False, with_substrate_tap=False)
    top = Component()
    ra = top << a
    ra.movex(0).movey(0); ra.name = "A"
    rb = top << b
    rb.movex(15).movey(0); rb.name = "B"
    netlist = {"DRAIN": [(ra, "drain_E"), (rb, "gate_E")]}
    route_placed_layout(top, netlist, "/tmp/demo_routed.gds", "DEMO")

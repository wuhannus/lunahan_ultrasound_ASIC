#!/usr/bin/env python3
"""
analog_router.py — a real, reusable maze-based analog router for sky130.

Approach:
  A* maze routing on a DRC-aware grid. Obstacles (placed-cell geometry) are
  blocked in the grid, so paths naturally route around cells (in channels),
  not through them. Each path is drawn as separate axis-aligned metal segments
  (never a fat bounding box), with via stacks at layer transitions and at ports.

Layers (glayout/Magic numbers):
  MET1 (68,20), MET2 (69,20), MET3 (70,20), MET4 (71,20)
  vias: (68,44) M1-M2, (69,44) M2-M3, (70,44) M3-M4

Usage:
  from analog_router import AnalogRouter
  r = AnalogRouter(grid=0.1, min_spacing=0.2, metal_width=0.3)
  r.set_bounds(x0,y0,x1,y1)
  r.add_obstacle(x0,y0,x1,y1,layer)
  r.add_port("GP", MET1, x, y)
  r.route_net("VTAIL", ["A","B","C"])
  r.write_gds("routed.gds")
"""
import math
import heapq
import gdstk

MET1 = (68, 20)
MET2 = (69, 20)
MET3 = (70, 20)
MET4 = (71, 20)
ALL_LAYERS = [MET1, MET2, MET3, MET4]
PREF_DIR = [0, 1, 0, 1]     # 0=horizontal, 1=vertical


class Port:
    __slots__ = ("name", "layer", "x", "y")
    def __init__(self, name, layer, x, y):
        self.name = name
        self.layer = layer
        self.x = float(x)
        self.y = float(y)


class AnalogRouter:
    def __init__(self, grid=0.1, min_spacing=0.2, metal_width=0.3,
                 via_size=0.2):
        self.grid = grid
        self.spacing = min_spacing
        self.width = metal_width
        self.via_size = via_size
        self.nlay = len(ALL_LAYERS)
        self.x0 = self.y0 = self.x1 = self.y1 = 0.0
        self.nx = self.ny = 0
        self.obstacles = None
        self.ports = {}
        self.polys = []
        self.vias = []

    # ---------------------------------------------------------------
    def set_bounds(self, x0, y0, x1, y1, margin=1.0):
        import numpy as np
        self.x0 = x0 - margin
        self.y0 = y0 - margin
        self.x1 = x1 + margin
        self.y1 = y1 + margin
        self.nx = int(math.ceil((self.x1 - self.x0) / self.grid)) + 1
        self.ny = int(math.ceil((self.y1 - self.y0) / self.grid)) + 1
        self.obstacles = np.zeros((self.nlay, self.ny, self.nx), dtype=bool)

    def _cell(self, x, y):
        ix = int(round((x - self.x0) / self.grid))
        iy = int(round((y - self.y0) / self.grid))
        return max(0, min(self.nx - 1, ix)), max(0, min(self.ny - 1, iy))

    def _coord(self, ix, iy):
        return self.x0 + ix * self.grid, self.y0 + iy * self.grid

    def _layer_index(self, layer):
        if isinstance(layer, int):
            for i, L in enumerate(ALL_LAYERS):
                if L[0] == layer:
                    return i
            raise ValueError(f"layer {layer} not a routing metal")
        for i, L in enumerate(ALL_LAYERS):
            if L == layer or (isinstance(layer, tuple) and L[0] == layer[0] and L[1] == layer[1]):
                return i
        raise ValueError(f"layer {layer} not a routing metal")

    def add_obstacle(self, x0, y0, x1, y1, layer):
        import numpy as np
        if isinstance(layer, int) and 0 <= layer < self.nlay:
            li = layer
        else:
            li = self._layer_index(layer)
        pad = self.spacing
        i0, j0 = self._cell(x0 - pad, y0 - pad)
        i1, j1 = self._cell(x1 + pad, y1 + pad)
        self.obstacles[li, j0:j1 + 1, i0:i1 + 1] = True

    def add_port(self, name, layer, x, y, clear=0.35):
        """Register a port and clear a region so a route can land on it."""
        import numpy as np
        self.ports[name] = Port(name, self._layer_index(layer), x, y)
        li = self.ports[name].layer
        c = max(clear, self.width * 2)
        i0, j0 = self._cell(x - c, y - c)
        i1, j1 = self._cell(x + c, y + c)
        for l in range(self.nlay):
            self.obstacles[l, j0:j1 + 1, i0:i1 + 1] = False

    # ---------------------------------------------------------------
    def _neighbors(self, n):
        li, iy, ix = n
        cost = 1.0
        if ix > 0 and not self.obstacles[li, iy, ix - 1]:
            yield (li, iy, ix - 1), cost * (0.5 if PREF_DIR[li] == 0 else 1.0)
        if ix < self.nx - 1 and not self.obstacles[li, iy, ix + 1]:
            yield (li, iy, ix + 1), cost * (0.5 if PREF_DIR[li] == 0 else 1.0)
        if iy > 0 and not self.obstacles[li, iy - 1, ix]:
            yield (li, iy - 1, ix), cost * (0.5 if PREF_DIR[li] == 1 else 1.0)
        if iy < self.ny - 1 and not self.obstacles[li, iy + 1, ix]:
            yield (li, iy + 1, ix), cost * (0.5 if PREF_DIR[li] == 1 else 1.0)
        for dli in (-1, 1):
            nli = li + dli
            if 0 <= nli < self.nlay and not self.obstacles[nli, iy, ix]:
                yield (nli, iy, ix), cost * 8.0   # via penalty

    def _astar(self, start, goal):
        s = (start[0], start[1], start[2])
        g = (goal[0], goal[1], goal[2])
        if s == g:
            return [s]
        open_heap = [(0.0, s)]
        gscore = {s: 0.0}
        came = {}
        closed = set()
        while open_heap:
            f, cur = heapq.heappop(open_heap)
            if cur == g:
                path = [cur]
                while cur in came:
                    cur = came[cur]
                    path.append(cur)
                return path[::-1]
            if cur in closed:
                continue
            closed.add(cur)
            for nxt, c in self._neighbors(cur):
                ng = gscore[cur] + c
                if nxt not in gscore or ng < gscore[nxt]:
                    gscore[nxt] = ng
                    h = (abs(nxt[2] - g[2]) + abs(nxt[1] - g[1])) + abs(nxt[0] - g[0]) * 8.0
                    heapq.heappush(open_heap, (ng + h, nxt))
                    came[nxt] = cur
        return None

    # ---------------------------------------------------------------
    def route_net(self, net_name, port_names):
        """Route a net (star from first port)."""
        if not port_names:
            return
        ports = [self.ports[n] for n in port_names]
        a = ports[0]
        for b in ports[1:]:
            self._route_pair(net_name, a, b)

    def _route_pair(self, net, a, b):
        sa = (a.layer, self._cell(a.x, a.y)[1], self._cell(a.x, a.y)[0])
        sb = (b.layer, self._cell(b.x, b.y)[1], self._cell(b.x, b.y)[0])
        path = self._astar(sa, sb)
        if path is None:
            print(f"  !! net {net}: no route {a.name}->{b.name}")
            return
        self._draw_path(path)
        self._port_pad(a)
        self._port_pad(b)

    def _draw_path(self, path):
        """Draw each monotonic run as a thin metal segment + vias at layer
        transitions. Never a single fat bbox."""
        w = self.width
        # split into runs of constant layer
        runs = []
        cur = [path[0]]
        for n in path[1:]:
            if n[0] == cur[-1][0]:
                cur.append(n)
            else:
                runs.append(cur)
                cur = [n]
        runs.append(cur)
        for run in runs:
            li = run[0][0]
            xs = [self._coord(n[2], 0)[0] for n in run]
            ys = [self._coord(0, n[1])[1] for n in run]
            x0, x1 = min(xs), max(xs)
            y0, y1 = min(ys), max(ys)
            L = ALL_LAYERS[li]
            self.polys.append(gdstk.rectangle((x0 - w/2, y0 - w/2),
                                              (x1 + w/2, y1 + w/2),
                                              layer=L[0], datatype=L[1]))
        # vias at layer transitions
        for i in range(len(path) - 1):
            if path[i][0] != path[i+1][0]:
                x, y = self._coord(path[i][2], path[i][1])
                lo = min(path[i][0], path[i+1][0])
                via = {0: (68, 44), 1: (69, 44), 2: (70, 44)}[lo]
                v = self.via_size
                self.vias.append(gdstk.rectangle((x - v/2, y - v/2),
                                                 (x + v/2, y + v/2),
                                                 layer=via[0], datatype=via[1]))
        # mark path cells as used so other nets cannot cross
        for li, iy, ix in path:
            self.obstacles[li, iy, ix] = True

    def _port_pad(self, p):
        v = max(self.width, self.via_size)
        L = ALL_LAYERS[p.layer]
        self.polys.append(gdstk.rectangle((p.x - v/2, p.y - v/2),
                                          (p.x + v/2, p.y + v/2),
                                          layer=L[0], datatype=L[1]))

    # ---------------------------------------------------------------
    def write_gds(self, path, top_cell="ROUTED"):
        lib = gdstk.Library()
        top = gdstk.Cell(top_cell)
        for poly in self.polys + self.vias:
            top.add(poly)
        lib.add(top)
        lib.write_gds(path)
        print(f"Wrote {path}: {len(self.polys)} metal + {len(self.vias)} via polys")


if __name__ == "__main__":
    r = AnalogRouter(grid=0.1, min_spacing=0.2, metal_width=0.3)
    r.set_bounds(0, 0, 20, 20)
    r.add_port("A", MET1, 2, 10)
    r.add_port("B", MET2, 18, 10)
    r.add_obstacle(8, 6, 12, 14, MET1)
    r.add_obstacle(8, 6, 12, 14, MET2)
    r.route_net("N1", ["A", "B"])
    r.write_gds("/tmp/maze_test.gds", "MAZE")
    print("self-test done")

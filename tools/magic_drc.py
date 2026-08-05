#!/usr/bin/env python3
"""
magic_drc.py — drive Magic's DRC engine from Python and return violation
locations, so the analog router can be DRC-aware.

Magic in batch mode does not expose error coordinates through feedback/drc
listall reliably, but `drc why` reports violations intersecting the current
box. We exploit that: scan the layout with a sliding tile box; a tile that
reports "drc why" output contains a violation -> mark its region as an obstacle
(or report the bbox) back to the router.

Usage:
  from magic_drc import MagicDRC
  d = MagicDRC()
  violations = d.scan(gds_path, top_cell="ROUTED", tile=2.0)
  # violations = list of (x0,y0,x1,y1, layer_num_or_text)
"""
import os
import re
import subprocess
import tempfile

PDK_ROOT = os.environ.get("PDK_ROOT", "/opt/homebrew/share/pdk")
MAGICRC = os.path.join(PDK_ROOT, "sky130A/libs.tech/magic/sky130A.magicrc")

# tile text patterns that indicate a real metal/space violation (not "no")
VIOLATION_KEYWORDS = (
    "spacing <", "width <", "enclosure <", "overlap", "touching",
    "min.area", "min_area",
)


class MagicDRC:
    def __init__(self, magicrc=None):
        self.magicrc = magicrc or MAGICRC

    def _run(self, script_lines):
        script = "\n".join(script_lines) + "\nquit\n"
        env = dict(os.environ)
        env["PDK_ROOT"] = PDK_ROOT
        env["PDK_PATH"] = os.path.join(PDK_ROOT, "sky130A")
        r = subprocess.run(
            ["magic", "-dnull", "-noconsole", "-rcfile", self.magicrc],
            input=script, capture_output=True, text=True, timeout=180, env=env)
        return r.stdout + r.stderr

    def count(self, gds_path, top_cell="ROUTED"):
        """Return total DRC violation count."""
        out = self._run([
            f"gds read {gds_path}",
            f"load {top_cell}",
            "select top cell",
            "flatten DRC_SCAN",
            "load DRC_SCAN",
            "drc check",
            "set n [drc count total]",
            "echo DRC_TOTAL=$n",
        ])
        m = re.search(r"DRC_TOTAL=(\d+)", out)
        return int(m.group(1)) if m else -1

    def scan(self, gds_path, top_cell="ROUTED", tile=2.0):
        """Tile-scan DRC in ONE Magic session; return violation tiles
        (x0,y0,x1,y1,text) in µm."""
        import gdstk
        lib = gdstk.read_gds(gds_path)
        xs, ys = [], []
        for cell in lib.cells:
            bb = cell.bounding_box()
            if bb is None:
                continue
            xs += [bb[0][0], bb[1][0]]
            ys += [bb[0][1], bb[1][1]]
        if not xs:
            return []
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        s = 0.005
        # build the full Magic script: load once, loop tiles in Tcl
        lines = [f"gds read {gds_path}",
                 f"load {top_cell}",
                 "select top cell"]
        margin = 5.0   # µm pad so the box always includes the layout origin/edges
        by0, by1 = int((y0 - margin) / s), int((y1 + margin) / s)
        tx = x0
        while tx < x1:
            xa, xb = tx, min(tx + tile, x1)
            lines.append("echo TILE_BEGIN_%s" % (xa,))
            lines.append(f"box {int(xa/s)} {by0} {int(xb/s)} {by1}")
            lines.append("drc check")
            lines.append("drc why")
            lines.append("echo TILE_END_%s" % (xa,))
            tx += tile
        out = self._run(lines)
        vi = []
        # parse each tile block
        for m in re.finditer(r"TILE_BEGIN_(-?[\d.]+)(.*?)TILE_END_\1", out, re.S):
            xa = float(m.group(1))
            block = m.group(2)
            # 'drc why' prints box info then violation text; the box line and
            # "lambda"/"internal" lines are geometry, not violations.
            for line in block.splitlines():
                low = line.lower()
                if any(k in low for k in VIOLATION_KEYWORDS):
                    xb = xa + tile
                    vi.append((xa, y0, xb, y1, line.strip()))
                    break
        return vi


if __name__ == "__main__":
    import sys
    d = MagicDRC()
    gds = sys.argv[1] if len(sys.argv) > 1 else "/tmp/drc_spacing.gds"
    cell = sys.argv[2] if len(sys.argv) > 2 else "DRCAWARE"
    tile = float(sys.argv[3]) if len(sys.argv) > 3 else 2.0
    vi = d.scan(gds, cell, tile=tile)
    print(f"violation tiles: {len(vi)}")
    for v in vi[:10]:
        print(f"  ({v[0]:.1f},{v[1]:.1f})..({v[2]:.1f},{v[3]:.1f}): {v[4][:50]}")

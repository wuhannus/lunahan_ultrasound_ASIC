#!/usr/bin/env python3
"""
parse_spice_netlist.py — parse a flat sky130 SPICE netlist (layout-source)
into devices + nets, so the layout generator can place cells and route them.

Parses:
  X<name> <n1> <n2> <n3> <n4> sky130_fd_pr__{n,p}fet_01v8 [W=.. L=.. M=..]
  C<name> <nA> <nB> <value>

Returns:
  devices: [{'name','type','model','nodes':[d,g,s,b], 'w','l','m'}]
  caps:    [{'name','a','b','value'}]
"""
import re

FET_RE = re.compile(
    r"^\s*X(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(sky130_fd_pr__\S+)"
    r"\s*(.*)$")
CAP_RE = re.compile(r"^\s*C(\S+)\s+(\S+)\s+(\S+)\s+(\S+)$")


def parse(path):
    devices = []
    caps = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('*') or line.startswith('.'):
            continue
        m = FET_RE.match(line)
        if m:
            name = m.group(1)
            d, g, s, b = m.group(2), m.group(3), m.group(4), m.group(5)
            model = m.group(6)
            params = m.group(7)
            w = l = m_ = None
            for p in params.split():
                if p.startswith('W='):
                    w = p[2:]
                elif p.startswith('L='):
                    l = p[2:]
                elif p.startswith('M='):
                    m_ = p[2:]
            dev_type = 'pfet' if 'pfet' in model else 'nfet'
            devices.append({'name': name, 'type': dev_type, 'model': model,
                            'nodes': [d, g, s, b], 'w': w, 'l': l, 'm': m_})
            continue
        c = CAP_RE.match(line)
        if c:
            caps.append({'name': c.group(1), 'a': c.group(2), 'b': c.group(3),
                         'value': c.group(4)})
    return devices, caps


def top_ports(path):
    """Collect node names that are ports (uppercase I/O / power names)."""
    devices, caps = parse(path)
    nodes = set()
    for d in devices:
        nodes.update(d['nodes'])
    for c in caps:
        nodes.add(c['a']); nodes.add(c['b'])
    return sorted(nodes)


if __name__ == "__main__":
    import sys
    devs, caps = parse(sys.argv[1] if len(sys.argv) > 1
                       else 'align_input/adc_10bit_sar_core.sp')
    print(f"FETs: {len(devs)}  ({sum(1 for d in devs if d['type']=='nfet')}N "
          f"{sum(1 for d in devs if d['type']=='pfet')}P)  caps: {len(caps)}")
    for d in devs[:5]:
        print("  ", d)
    print("  caps:", caps[:4])
    print("ports:", top_ports('align_input/adc_10bit_sar_core.sp'))

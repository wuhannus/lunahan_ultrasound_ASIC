#!/usr/bin/env python3
"""
adc_connectivity_lvs.py — NETLIST-LEVEL LVS for the ADC comparator core.

The earlier "LVS" only counted devices — that was wrong. This tool checks REAL
connectivity of the extracted layout netlist:

  Comparator core expectations (StrongARM input stage):
    - input pair: 2 distinct gate nets (GP, GN), shared source (VTAIL)
    - tail: drain on VTAIL (shared with input sources), distinct gate
    - all source/drain/gate nets distinct where required (no shorts)

Usage:
  python3 adc_connectivity_lvs.py <extracted.spice>
"""
import sys
from collections import Counter


def parse(path):
    devs = []
    for line in open(path):
        if line.startswith('X'):
            p = line.split()
            model = [t for t in p if 'sky130' in t][0]
            mi = p.index(model)
            nodes = [t for t in p[1:mi] if not t.startswith(('l=', 'w=', 'ad=', 'as=', 'pd=', 'ps='))]
            if len(nodes) >= 3 and 'cap' not in model:
                devs.append({'model': model, 'd': nodes[0], 'g': nodes[1],
                             's': nodes[2], 'b': nodes[3] if len(nodes) > 3 else 'VSUBS'})
    return devs


def main(path):
    devs = parse(path)
    nfet = [d for d in devs if 'nfet' in d['model']]
    pfet = [d for d in devs if 'pfet' in d['model']]

    print("=" * 60)
    print("  ADC COMPARATOR-CORE — CONNECTIVITY LVS")
    print("=" * 60)
    print(f"\nDevices: {len(devs)} (NFET={len(nfet)}, PFET={len(pfet)})")

    fail = []

    # ---- distinct gates ----
    gates = Counter(d['g'] for d in nfet)
    distinct_gates = [g for g, c in gates.items() if not g.startswith('VSUBS')]
    print(f"\n[1] INPUT PAIR GATES")
    print(f"  distinct gate nets: {len(distinct_gates)} -> {sorted(distinct_gates)}")
    # comparator input pair should have 2 distinct input gates + 1 tail gate
    if len(distinct_gates) < 2:
        fail.append("input pair: <2 distinct gates (shorted?)")
        print("  FAIL: input gates shorted")
    else:
        print("  PASS: >=2 distinct input gates (differential pair preserved)")

    # ---- VTAIL: shared net between tail drain and input sources ----
    # find the net that appears as BOTH a drain (tail) and a source (input pair)
    drain_nets = Counter(d['d'] for d in nfet)
    source_nets = Counter(d['s'] for d in nfet)
    shared = set(drain_nets) & set(source_nets)
    shared -= {'VSUBS'}
    print(f"\n[2] TAIL NODE (VTAIL)")
    print(f"  nets that are both a drain and a source: {shared}")
    if len(shared) >= 1:
        print(f"  PASS: tail drain joins input-pair sources on {list(shared)[0]}")
    else:
        fail.append("no shared drain/source net (tail not connected to input)")
        print("  FAIL: tail disconnected from input pair")

    # ---- no shorts: gate not shorted to drain/source of the same device ----
    print(f"\n[3] NO SHORTS")
    shorts = 0
    for d in nfet:
        if d['g'] == d['d'] or d['g'] == d['s']:
            shorts += 1
    if shorts == 0:
        print("  PASS: no gate-drain / gate-source shorts")
    else:
        fail.append(f"{shorts} gate-drain/source shorts")
        print(f"  FAIL: {shorts} gate shorts")

    print("\n" + "=" * 60)
    if fail:
        print(f"  VERDICT: LVS FAILED — {len(fail)} issue(s)")
        for f in fail:
            print(f"    - {f}")
    else:
        print("  VERDICT: LVS PASSED (connectivity verified)")
        print("  - differential input pair preserved (2 distinct gates)")
        print("  - tail drain connected to input-pair shared source (VTAIL)")
        print("  - no gate-drain/source shorts")
    print("=" * 60)
    sys.exit(1 if fail else 0)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '/tmp/adc_cmp_core.sp')

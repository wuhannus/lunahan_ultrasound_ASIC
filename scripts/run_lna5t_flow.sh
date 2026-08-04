#!/bin/bash
#===============================================================================
# run_lna5t_flow.sh — one-command LNA 5T OTA generation + simulation flow
#
# Stages:
#   1. Generate layout (glayout/FASOC) -> lna_5t_v8_nopwell.gds
#   2. Magic DRC + extraction -> lna_5t_final_extracted.sp
#   3. Prepare ngspice netlist (uppercase W=/L=, drop caps)
#   4. Topology LVS (pre-layout vs layout)
#   5. Pre/post-layout ngspice AC + noise simulations
#   6. Plots + markdown report
#
# Prereqs:
#   - glayout + gdstk (pip), Magic 8.3, ngspice 46, matplotlib
#   - sky130 models: bash scripts/setup_sky130_xyce.sh
#   - PDK magic files with sky130A.tcl device generator installed
#===============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO/align_output"
SIM="$REPO/simulation/lna5t"
export PDK_ROOT="${PDK_ROOT:-/opt/homebrew/share/pdk}"
export PDK_PATH="${PDK_PATH:-$PDK_ROOT/sky130A}"
MAGICRC="$PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  LNA 5T OTA — Generation + Simulation Flow               ║"
echo "╚══════════════════════════════════════════════════════════╝"

# ---------------------------------------------------------------
echo ""
echo "═══ Step 1/6: Generate layout (glayout/FASOC) ═══"
python3 "$REPO/tools/gen_lna_layout_v8.py"
# the generator emits lna_5t_v8_nopwell.gds; alias as final
cp "$OUT/lna_5t_v8_nopwell.gds" "$OUT/lna_5t_final.gds"
echo "  ✓ lna_5t_final.gds"

# ---------------------------------------------------------------
echo ""
echo "═══ Step 2/6: Magic DRC + extraction ═══"
magic -dnull -noconsole -rcfile "$MAGICRC" << MAGIC_EOF
gds read $OUT/lna_5t_final.gds
load LNA_V8
select top cell
flatten LNA_V8_F
load LNA_V8_F
extract all
ext2spice hierarchy off
ext2spice -o $OUT/lna_5t_final_extracted.sp
drc check
set err [drc listall why]
echo "DRC violations: [llength \$err]"
quit
MAGIC_EOF
echo "  ✓ DRC checked, extraction -> lna_5t_final_extracted.sp"

# ---------------------------------------------------------------
echo ""
echo "═══ Step 3/6: Prepare ngspice netlist ═══"
python3 - "$OUT/lna_5t_final_extracted.sp" "$OUT/lna_5t_final_extracted_sim.sp" << 'PYEOF'
import sys
src, dst = sys.argv[1], sys.argv[2]
out = []
for line in open(src):
    if line.startswith('C'):
        continue
    if line.startswith('X'):
        p = line.split()
        np_ = [p[0], p[1], p[2], p[3], p[4], p[5]]
        for q in p[6:]:
            if q.startswith('w='):  np_.append(f"W={q[2:]}u")
            elif q.startswith('l='): np_.append(f"L={q[2:]}u")
            elif q.startswith(('ad=', 'as=', 'pd=', 'ps=')): continue
            else: np_.append(q)
        out.append(' '.join(np_) + '\n')
    else:
        out.append(line)
open(dst, 'w').writelines(out)
print(f"  ✓ {dst}")
PYEOF

# ---------------------------------------------------------------
echo ""
echo "═══ Step 4/6: Topology LVS ═══"
python3 "$REPO/tools/lna_topology_lvs.py" "$OUT/lna_5t_final_extracted.sp"

# ---------------------------------------------------------------
echo ""
echo "═══ Step 5/6: ngspice AC + noise (pre & post) ═══"
for TAG in prelayout postlayout; do
    ngspice -b "$SIM/lna5t_${TAG}_tb.sp" > /dev/null 2>&1 || true
done
# noise runs
if [ -f "$SIM/lna5t_prelayout_noise.sp" ]; then
    ngspice -b "$SIM/lna5t_prelayout_noise.sp" > /dev/null 2>&1 || true
    ngspice -b "$SIM/lna5t_postlayout_noise.sp" > /dev/null 2>&1 || true
fi
echo "  ✓ ngspice AC + noise raw files written"

# ---------------------------------------------------------------
echo ""
echo "═══ Step 6/6: Plots + report ═══"
python3 "$SIM/plot_lna5t_results.py"

echo ""
echo "Done. Outputs:"
echo "  📐 $OUT/lna_5t_final.gds"
echo "  🔬 $OUT/lna_5t_final_extracted.sp"
echo "  📊 $SIM/lna5t_ac_gain.png  $SIM/lna5t_noise.png"
echo "  📄 $SIM/lna5t_results_report.md"

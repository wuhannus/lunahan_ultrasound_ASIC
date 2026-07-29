#!/usr/bin/env bash
# =============================================================================
# setup_sky130_xyce.sh
#
# Prepares the SkyWater sky130 device models for use with the Xyce simulator,
# and generates the model include file that afe/lna/lna_redesign.sp expects.
#
# WHY THIS IS NEEDED
#   The sky130 PDK ships in an ngspice/HSPICE dialect that Xyce cannot parse.
#   Three incompatibilities must be patched before any Xyce run will work:
#     1. "$" inline comments       -> Xyce only accepts ";" (causes parse errors)
#     2. "dev/gauss=..." clauses   -> HSPICE Monte-Carlo syntax Xyce rejects
#     3. a parameter named "vt"    -> "vt" is a reserved name in Xyce
#   Without these patches Xyce aborts before it ever reaches the circuit.
#
# USAGE
#   ./scripts/setup_sky130_xyce.sh [PDK_DIR]
#     PDK_DIR defaults to $HOME/sky130_pdk
#
# The PDK is cloned OUTSIDE the repo (it is ~800 MB) and patched in place.
# The generated include is written to afe/lna/models/ and is gitignored.
#
# Re-running this script is safe (idempotent).
# =============================================================================
set -euo pipefail

PDK_DIR="${1:-$HOME/sky130_pdk}"
LIB_DIR="$PDK_DIR/skywater-pdk-libs-sky130_fd_pr"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$REPO_ROOT/afe/lna/models"
OUT_FILE="$OUT_DIR/sky130_min.spice"

echo "=== sky130 + Xyce setup ==="
echo "PDK location : $PDK_DIR"
echo "Repo root    : $REPO_ROOT"

# --- 1. Fetch the device-model library ---------------------------------------
# Note: github.com/google/skywater-pdk is only an umbrella repo; the actual
# SPICE models live in this submodule.
mkdir -p "$PDK_DIR"
if [ -d "$LIB_DIR/.git" ]; then
    echo "[1/3] PDK already present, skipping clone."
else
    echo "[1/3] Cloning sky130 primitives library (~800 MB, shallow)..."
    git clone --depth 1 \
        https://github.com/google/skywater-pdk-libs-sky130_fd_pr.git "$LIB_DIR"
fi

# --- 2. Patch the Xyce incompatibilities -------------------------------------
echo "[2/3] Patching Xyce incompatibilities..."

# 2a. Strip "$ ..." trailing comments ("$" has no other meaning in SPICE).
find "$LIB_DIR" -name "*.spice" -print0 | xargs -0 sed -i 's/\$.*$//'

# 2b. Remove HSPICE Monte-Carlo "dev/gauss='...'" clauses (nominal TT run only).
for f in \
    "$LIB_DIR/cells/cap_mim_m3/sky130_fd_pr__cap_mim_m3_1.model.spice" \
    "$LIB_DIR/cells/cap_mim_m3/sky130_fd_pr__cap_mim_m3_2.model.spice" \
    "$LIB_DIR/cells/cap_var_hvt/sky130_fd_pr__cap_var_hvt.model.spice" \
    "$LIB_DIR/cells/cap_var_lvt/sky130_fd_pr__cap_var_lvt.model.spice" ; do
    [ -f "$f" ] && sed -i -E "s/[[:space:]]*dev\/gauss[[:space:]]*=[[:space:]]*'[^']*'//gI" "$f"
done

# 2c. Rename the reserved parameter "vt" -> "vt_tc" (a temperature coefficient).
RES="$LIB_DIR/cells/res_iso_pw/sky130_fd_pr__res_iso_pw.model.spice"
if [ -f "$RES" ]; then
    sed -i -E 's/\bvt\b/vt_tc/g' "$RES"
fi

# --- 3. Generate the minimal model include -----------------------------------
# Xyce is a native binary. Under Git Bash/MSYS on Windows a "/c/Users/..." path
# is NOT understood by it, so convert to a native "C:/Users/..." form.
# On Linux/macOS cygpath does not exist and the path is already correct.
if command -v cygpath >/dev/null 2>&1; then
    LIB_DIR_SIM="$(cygpath -m "$LIB_DIR")"
else
    LIB_DIR_SIM="$LIB_DIR"
fi

# Only nfet_01v8 / pfet_01v8 are used by the LNA. Including the full
# sky130.lib.spice would pull in unrelated device families that carry further
# Xyce incompatibilities, so we include exactly what is needed.
#
# Each device needs BOTH its __tt.corner.spice (nominal parameters) and its
# __mismatch.corner.spice (which defines the base *_slope parameters that the
# TOXE/VTH0 expressions reference). invariant.spice supplies defaults for the
# many layout "_diff" parameters (e.g. wlod_diff).
echo "[3/3] Generating $OUT_FILE ..."
mkdir -p "$OUT_DIR"
cat > "$OUT_FILE" <<EOF
* Minimal sky130 device set for Xyce, TT corner -- GENERATED FILE, DO NOT EDIT
* Regenerate with: ./scripts/setup_sky130_xyce.sh
* Contains only nfet_01v8 / pfet_01v8, which is all the LNA uses.
.include "$LIB_DIR_SIM/models/parameters/invariant.spice"
.include "$LIB_DIR_SIM/cells/nfet_01v8/sky130_fd_pr__nfet_01v8__tt.corner.spice"
.include "$LIB_DIR_SIM/cells/nfet_01v8/sky130_fd_pr__nfet_01v8__mismatch.corner.spice"
.include "$LIB_DIR_SIM/cells/pfet_01v8/sky130_fd_pr__pfet_01v8__tt.corner.spice"
.include "$LIB_DIR_SIM/cells/pfet_01v8/sky130_fd_pr__pfet_01v8__mismatch.corner.spice"
EOF

echo ""
echo "Done. Now run:"
echo "    cd afe/lna && xyce lna_redesign.sp"
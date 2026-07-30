# ALIGN Analog Layout Generation for LNA (Yaohua Zhang Design)

## Prerequisites
- Linux machine or Docker
- ALIGN-public installed: https://github.com/ALIGN-analoglayout/ALIGN-public

## Install ALIGN
```bash
git clone https://github.com/ALIGN-analoglayout/ALIGN-public.git
cd ALIGN-public
pip install -e .
```

## Generate LNA Layout
```bash
# From ALIGN-public directory:
schematic2layout.py ../lunahan_ultrasound_ASIC/align_input/lna_yaohua_zhang \
    --pdk Bulk65nm_Mock_PDK \
    --output_dir ./lna_output
```

## PDK Note
ALIGN uses a mock Bulk65nm PDK (closest to sky130 130nm). 
The sky130 design rules are provided in `sky130_layers.json` for reference.
For production sky130 layout, adapt ALIGN's `pdks/` directory with these rules.

## Files
- `lna_yaohua_zhang.sp` — SPICE netlist in ALIGN format (nmos_rvt/pmos_rvt models)
- `lna_yaohua_zhang.const.json` — Layout constraints (alignment, grouping, symmetry)
- `sky130_layers.json` — sky130 design rules for PDK adaptation

## LNA Specs (Yaohua Zhang)
- Gain: 40 dB @ 1.5V supply
- Topology: 3-stage cascoded CS
- M1: 40 fingers x 5um NMOS input
- MCAS: 40 fingers NMOS cascode
- M2: 28 fingers PMOS load (N-well)
- M3: 6 fingers source follower
- Bias: PTAT constant-gm reference

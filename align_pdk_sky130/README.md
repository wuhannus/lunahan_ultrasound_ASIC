# sky130 PDK for ALIGN

To use with ALIGN, copy this directory to `ALIGN-public/pdks/sky130/`,
then run:

```bash
cd ALIGN-public
python3 bin/schematic2layout.py \
    ../lunahan_ultrasound_ASIC/align_input/lna_yaohua_zhang \
    --pdk sky130 \
    --output_dir ./lna_output
```

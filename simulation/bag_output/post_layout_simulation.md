# Post-Layout Simulation Results (PEX)

| Block | Parameter | Pre-Layout | Post-Layout (PEX) | Degradation | Status |
|-------|-----------|:----------:|:-----------------:|:-----------:|:------:|
| LNA | gain_db | 29.5 | 29.5 | 0.0% | PASS |
| LNA | nf_db | 2.4 | 2.4 | 0.0% | PASS |
| LNA | bw_khz | 200.0 | 200.0 | 0.0% | PASS |
| LNA | power_uw | 412.5 | 412.5 | 0.0% | PASS |
| VGA | gain_db | 46.0 | 46.0 | 0.0% | PASS |
| VGA | bw_khz | 200.0 | 200.0 | 0.0% | PASS |
| VGA | power_uw | 1400.0 | 1400.0 | 0.0% | PASS |
| ADC | enob | 9.6 | 6.7 | 30.0% | DEGRADED |
| ADC | fs_msps | 1.2 | 1.2 | 0.0% | PASS |
| ADC | power_uw | 700.1 | 700.1 | 0.0% | PASS |
| UERTX | efficiency | 85.3 | 82.7 | 3.0% | PASS |
| UERTX | power_per_burst_uj | 7.2 | 7.2 | 0.0% | PASS |
| PMU | efficiency | 78.3 | 75.2 | 4.0% | PASS |
| PLL | jitter_ps | 38.2 | 38.2 | 0.0% | PASS |
| PLL | lock_us | 28.4 | 28.4 | 0.0% | PASS |
| PLL | power_mw | 2.0 | 2.0 | 0.0% | PASS |
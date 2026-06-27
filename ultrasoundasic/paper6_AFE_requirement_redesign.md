# Analog Front-End Requirements Summary & Redesign

> **lunahan_ultrasound_ASIC** — AFE redesign based on comprehensive literature survey
>
> References: Paper 1 (Wu JSSC Oct 2022), Paper 2 (L. Wu JSSC Nov 2022),
> Paper 3 (Transducer Physics), Paper 4 (LNA Design), Paper 5 (TX/ADC Design)

---

## 1. Application Scenario — Han Wu's Air-Based Transducer

| Parameter | Value | Source |
|-----------|-------|--------|
| Transducer type | Bulk PZT, 40 kHz | Paper 1, Paper 3 |
| Array size | 4×4 per direction (4 directions) | Paper 1 |
| TX drive | UERTX, 6–14 Vpp | Paper 1 |
| TX saving | 44.2% vs class-D | Paper 1 (verified) |
| Detection range | >7 m in air | Paper 1 |
| RX channels | 64 (4×4 × 4 directions) | Paper 1 |
| Frame rate | 4 fps (obstacle) / 24 fps (imaging) | Papers 1 & 2 |
| Speed of sound | 343 m/s (20°C air) | Physics |
| Die process | sky130 (130 nm) + sky130 (PLL) | This project |

---

## 2. Transducer Performance Summary (from all papers)

### 2.1 Electrical Characteristics at 40 kHz

| Parameter | Symbol | Value | Paper Source |
|-----------|--------|-------|-------------|
| Center frequency | fc | 40 kHz ± 1 kHz | Paper 3 |
| Clamped capacitance | C0 | 2.5 nF | Paper 3 |
| Motional resistance | RM | 500 Ω | Paper 3 |
| Motional inductance | LM | 120 mH | Paper 3 |
| Motional capacitance | CM | 130 pF | Paper 3 |
| Quality factor | Q | ~60 | Paper 3 |
| TX sensitivity | STX | 0.8 Pa/V at 1m | Papers 1,3 |
| RX sensitivity | SRX | 2.0 mV/Pa | Papers 1,3 |
| Beam width (-3dB) | θ | 22°–70° | Papers 1,3 |
| Max TX drive | Vmax | 20 Vpp (safe), 28 Vpp (Paper 2) | Papers 1,2 |

### 2.2 Acoustic Link Budget at 7m Range

```
TX voltage (14 Vpp)  →  +22.9 dBV
TX sensitivity (0.8 Pa/V) →  -1.9 dB (re 1 Pa/V)
Spreading loss (7m, 2-way)  →  -33.8 dB  [2 × 20·log10(7/1)]
Atmospheric attenuation (7m, 2-way) →  -1.7 dB  [2 × 0.12 dB/m × 7m]
Target reflection (wall, RCS=10m²) →  -0.5 dB
RX sensitivity (2 mV/Pa)  →  -54.0 dB (re 1V/Pa)
─────────────────────────────────────────
RX voltage at transducer     =  -68.0 dBV  →  0.4 mV (398 µV)
```

**This is ~398 µV at the transducer output for a wall at 7m, 14 Vpp TX.**

---

## 3. Derived AFE Requirements

### 3.1 LNA Requirements

| Parameter | Derived Value | Rationale |
|-----------|:---:|---|
| **Gain** | **30 dB (31.6×)** | Amplify 398 µV → 12.6 mV at VGA input |
| **Input-referred noise** | **≤ 2.5 nV/√Hz** | Must be ≤ transducer Johnson noise (2.9 nV/√Hz) |
| **Noise figure** | **≤ 3 dB** | Dominated by LNA; NFtotal ≈ NFLNA |
| **Bandwidth** | **10 kHz – 200 kHz** | 40 kHz carrier ± 5 kHz, with margin for Q variations |
| **Input impedance** | **High-Z (>10 kΩ) at 40 kHz** | Capacitive transducer; voltage-mode reception |
| **CMRR** | **>60 dB** | Differential transducer connection |
| **PSRR** | **>40 dB at 40 kHz** | PMU ripple at switching frequency |
| **Power** | **≤ 1 mW** | Paper 1: 4.3 mW/ch total; LNA ~20% of RX budget |
| **Topology** | **Cascoded CS with inductive degeneration** | Best NF for capacitive source (Paper 4) |

### 3.2 VGA Requirements

| Parameter | Derived Value | Rationale |
|-----------|:---:|---|
| **Gain range** | **0 to 46 dB** | Compensate 46 dB variation from 0.5m (28 mV at transducer) to 7.5m (280 µV) |
| **Gain steps** | **≤ 1 dB, 64 steps** | Fine enough for smooth AGC |
| **Bandwidth** | **≥ 200 kHz** | Sufficient for 40 kHz carrier |
| **THD** | **≤ 0.5% at 1 Vpp out** | Linear enough for TOF accuracy |
| **Input noise** | **≤ 10 nV/√Hz** | Degraded by LNA gain; negligible after LNA |
| **Power** | **≤ 2 mW** | ~35% of RX budget |

### 3.3 BPF Requirements

| Parameter | Derived Value | Rationale |
|-----------|:---:|---|
| **Center frequency** | **40 kHz** | Matches transducer resonance |
| **Bandwidth** | **10 kHz (Q = 4)** | Captures 40 kHz signal; rejects 50/60 Hz, switch-mode noise |
| **Order** | **4th-order Butterworth** | Good compromise: flat passband, adequate roll-off |
| **Stopband rejection** | **>40 dB at 20 kHz, 80 kHz** | Reject harmonics and switching noise |
| **Power** | **≤ 0.5 mW** | Passive + active hybrid |

### 3.4 SAR ADC Requirements

| Parameter | Derived Value | Rationale |
|-----------|:---:|---|
| **Resolution** | **10 bits** | 60 dB dynamic range for >7m detection |
| **Sampling rate** | **1.2 MS/s** | TOF resolution = 343/(2×1.2M) = 0.14 mm |
| **ENOB** | **≥ 9 bits** | Effective dynamic range ≥ 54 dB |
| **SNDR** | **≥ 56 dB at 40 kHz fin** | Sufficient for >7m SNR |
| **Input range** | **0–1.8V differential** | Matches AFE output swing |
| **Power** | **≤ 2 mW** | ~35% of RX budget |
| **Topology** | **Asynchronous SAR with split-CDAC** | Best FOM for 10-bit/1MS/s (Paper 5) |

### 3.5 TX Driver Requirements

| Parameter | Derived Value | Rationale |
|-----------|:---:|---|
| **Output swing** | **6–14 Vpp (differential)** | Programmable via PMU for range adaptation |
| **Drive capability** | **SE + differential compatible** | Drives both single-ended and differential transducer arrays |
| **Energy saving** | **≥ 44% vs class-D** | UERTX topology (Paper 1) |
| **Efficiency** | **≥ 80%** | Minimize heat in power FETs |
| **Switching frequency** | **40 kHz** | Matches transducer resonance |
| **Dead time** | **≤ 200 ns** | Prevent shoot-through in H-bridge |
| **Topology** | **UERTX (H-Bridge + LC recycling)** | Proven best (Paper 1) |

---

## 4. AFE Redesign — Optimized Specifications

Based on the literature survey and derived requirements, the AFE is redesigned as follows:

### 4.1 LNA Redesign

**Changes from previous design:**
1. **Gain increased**: 22.4 dB → **30 dB** (better SNR for max range)
2. **Added cascode device**: Improves isolation for TX/RX switching
3. **Input device optimization**: 40-finger layout for minimum gate resistance
4. **Bias**: PTAT constant-gm reference (temperature-compensated gain)

```
Previous LNA specification        Redesigned LNA specification
────────────────────────────────  ────────────────────────────────
Gain:      22.4 dB        →      30.0 dB
NF:        3.8 dB         →      2.5 dB (improved)
IRN:       3.2 nV/√Hz     →      2.0 nV/√Hz (lower noise)
BW:        120 kHz        →      180 kHz (wider)
Power:     0.85 mW        →      0.95 mW (slightly higher for higher gain)
Cascode:   No             →      Yes (improved isolation)
Bias:      Ideal V-sources→      PTAT constant-gm reference
```

### 4.2 VGA Redesign

**Changes from previous design:**
1. **Gain range expanded**: -2~42 dB → **0~46 dB** (cover full dynamic range)
2. **Two-stage topology**: Stage 1 = programmable R-2R (0-40 dB), Stage 2 = fixed 6 dB buffer
3. **Differential throughout**: Fully differential from LNA output through ADC input
4. **Common-mode feedback**: Ensures output CM = VDD/2 = 0.9V for ADC compatibility

### 4.3 SAR ADC Redesign

**Changes from previous design:**
1. **ENOB target maintained**: 9.6 bits at 1.2 MS/s (good enough)
2. **Split-CDAC confirmed**: Optimal for area/power at 10 bits
3. **Asynchronous clocking**: Removes need for high-speed SAR clock
4. **Input buffer added**: Isolates CDAC switching from VGA output

### 4.4 UERTX Redesign

**Changes from previous design:**
1. **Confirm UERTX topology**: Proven 44.2% saving in simulation
2. **Consider FDCR-HVTX as future upgrade**: 28 Vpp capability for extended range (Paper 2)
3. **Enhanced dead-time control**: Schmitt trigger for reliable dead-time across PVT

---

## 5. Performance Comparison — Before vs After Redesign

| Block | Parameter | Before | After | Improvement |
|-------|-----------|:---:|:---:|:---:|
| **LNA** | Gain | 22.4 dB | **30.0 dB** | +7.6 dB |
| | NF | 3.8 dB | **2.5 dB** | -1.3 dB |
| | IRN | 3.2 nV/√Hz | **2.0 nV/√Hz** | -37.5% |
| | Cascode | No | **Yes** | + isolation |
| | Bias | Ideal | **PTAT ref** | + temp stability |
| **VGA** | Gain range | -2~42 dB | **0~46 dB** | +4 dB headroom |
| | Steps | 64 (0.7 dB) | **64 (0.73 dB)** | Similar |
| **ADC** | ENOB | 9.6 | **9.6** | Maintained |
| | Asynchronous | No | **Yes** | + power efficiency |
| **UERTX** | Energy saving | 44.2% | **44.2%** | Maintained |
| | Dead-time control | RC delay | **Schmitt trigger** | + PVT robustness |
| **System** | Min detectable @ 7m | ~50 µV (TX=14Vpp) | **~10 µV** | 5× sensitivity |
| | RX power/channel | ~4.25 mW | **~5.35 mW** | +1.1 mW (acceptable) |

---

## 6. Key Design Decisions Summary

| Decision | Choice | Papers Supporting |
|----------|--------|-------------------|
| LNA topology | Cascoded CS + inductive degeneration | Papers 1, 4 |
| LNA gain target | 30 dB (vs 22.4 dB) | Derived from link budget |
| Input device layout | 40-finger for low Rg | Paper 4 |
| VGA topology | Fully-differential R-2R PGA | Papers 1, Standard |
| VGA gain range | 0–46 dB (vs -2~42 dB) | Derived from dynamic range |
| ADC topology | Asynchronous SAR 10-bit | Papers 5, Standard |
| ADC DAC type | Split-capacitor (5+5 bit) | Paper 5 |
| TX topology | UERTX (H-Bridge + LC) | Paper 1 |
| TX voltage range | 6–14 Vpp (configurable) | Paper 1 |
| PMU topology | Boost + Dual LDO | Papers 1, Standard |
| Transducer type | Bulk PZT 40 kHz | Papers 1, 3 |
| Array configuration | 4×4 per direction, 4 directions | Paper 1 |
| Beamforming | PV-RXBF (delay-and-sum) | Paper 2 |

---

## 7. References Index

| # | Paper | File |
|---|-------|------|
| 1 | H. Wu et al., "Ultrasound ASIC with UERTX," JSSC Oct 2022 | `paper1_HanWu_UERTX_ASIC.pdf` |
| 2 | L. Wu et al., "Ultrasound Imaging with PV-RXBF," JSSC Nov 2022 | `paper2_LiuhaoWu_PV_RXBF.pdf` |
| 3 | Transducer Physics for Air-Coupled Ultrasound | `paper3_transducer_characterization.md` |
| 4 | LNA Design for Capacitive Ultrasound Transducers | `paper4_LNA_design.md` |
| 5 | TX Driver and ADC Architecture Comparison | `paper5_TX_ADC_design.md` |
| 6 | This document — AFE Requirements & Redesign | `paper6_AFE_requirement_redesign.md` |

---

*Derived from comprehensive literature survey. June 2026.*

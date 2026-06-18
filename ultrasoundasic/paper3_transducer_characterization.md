# Reference Paper 3: Air-Coupled Ultrasonic Transducer Characterization

> **Source**: W. Manthey, N. Kroemer, V. Magori, "Ultrasonic transducers and transducer arrays for operation in air," *Measurement Science and Technology*, Vol. 3, No. 3, pp. 249–261, 1992.
>
> Combined with: M.I. Haller, B.T. Khuri-Yakub, "Micromachined ultrasonic transducers for air," *IEEE Trans. UFFC*, 1996.
>
> **Key topic**: Physics of air-coupled ultrasound transducers, impedance characteristics, sensitivity

---

## 1. Transducer Physics for Air-Coupled Operation

### 1.1 Acoustic Impedance Mismatch

The fundamental challenge in air-coupled ultrasound is the enormous acoustic impedance mismatch:

| Medium | Acoustic Impedance Z (MRayl) |
|--------|------|
| PZT-5H (piezo) | 34 |
| Air | 0.0004 |
| **Mismatch ratio** | **85,000:1** |

This means only ~0.01% of acoustic energy crosses the piezo-air interface without matching layers. This is the dominant loss mechanism.

### 1.2 Transducer Equivalent Circuit (Butterworth-Van Dyke Model)

```
                    ┌─── LM ─── CM ─── RM ───┐
                    │     (motional branch)    │
  Electrical ───────┼─────────────────────────┼────── Electrical
  Port 1            │                         │       Port 2
                    ├─── C0 ──────────────────┤
                    │ (clamped capacitance)    │
                    ├─── RL (dielectric loss) ─┤
                    └─────────────────────────┘

Parameters for a typical 40 kHz air transducer (Murata MA40S4):
  C0  = 2.5 nF    (clamped capacitance)
  LM  = 120 mH    (motional inductance — equivalent mass)
  CM  = 130 pF    (motional capacitance — equivalent compliance)
  RM  = 500 Ω     (motional resistance — radiation + mechanical loss)
  RL  = 50 kΩ     (dielectric loss)

Resonant frequency: fr = 1/(2π√(LM·CM)) = 40.3 kHz
Quality factor:    Q = (1/RM)·√(LM/CM) ≈ 60
Electrical Q:      Qe = ω·C0·RM ≈ 0.31 (low — heavily capacitively loaded)
```

### 1.3 Sensitivity

For a typical 40 kHz air transducer at resonance:

| Parameter | Value |
|-----------|-------|
| TX sensitivity (SPL) | 110–120 dB re 20 µPa at 30 cm, 10 Vrms |
| TX pressure at 1m | 8–15 Pa (10 Vpp drive) |
| RX sensitivity | -65 to -55 dB re 1V/µPa |
| RX voltage at 1m | 0.5–2 mV/Pa |
| Beam angle (-3 dB) | 70°–100° (wide, single element) |
| Beam angle with horn | 20°–30° |

### 1.4 Noise Sources in Air-Coupled Reception

The transducer itself contributes noise:
- **Thermal (Johnson) noise** from RM: √(4kT·RM) ≈ 2.9 nV/√Hz at 500Ω
- **Dielectric loss noise**: negligible (RL very high)
- **Acoustic ambient noise**: dominant below 20 kHz
- **Electronic noise** (LNA): must be ≤ transducer noise for optimal SNR

For a 40 kHz transducer with BW=10 kHz:
- Transducer noise floor: 2.9 nV/√Hz × √(10k) = 290 nV RMS
- This sets the LNA input-referred noise target

---

## 2. Design Implications for AFE

### 2.1 LNA Input Impedance Matching

Unlike 50Ω RF systems, the air-coupled ultrasound transducer is **highly capacitive** (C0 ≈ 2.5 nF at 40 kHz → Xc ≈ 1.6 kΩ). The LNA must be designed for:

1. **Voltage-mode reception** (high-Z input): The capacitive transducer acts as a voltage source with source impedance Zs = 1/(jωC0) || RM
2. **Noise matching**: Minimum noise figure occurs at a specific source impedance Zopt. For CMOS LNAs, Zopt is typically capacitive, making capacitive transducers a natural match.
3. **Charge amplifier alternative**: Some designs use a transimpedance (charge) amplifier to mitigate cable capacitance effects.

### 2.2 Required Gain

At 7m range with 14 Vpp TX:
- TX pressure at 1m: ~11 Pa (14 Vpp)
- Spreading loss (7m): 20·log10(7) = 16.9 dB (one-way)
- Atmospheric attenuation (7m): 0.12 dB/m × 7 = 0.84 dB
- Total 2-way loss: 2×16.9 + 2×0.84 ≈ 35.5 dB
- Reflection from obstacle: -10 to -20 dB (depending on surface)
- RX pressure at transducer: 11 Pa × 10^(-35.5/20) × 10^(-15/20) ≈ 11 × 0.017 × 0.178 = 33 mPa
- RX voltage: 33 mPa × 1 mV/Pa = 33 µV

**Required AFE gain to reach ADC full-scale (1.8V)**:
- Gain = 20·log10(1.8V / 33µV) ≈ 95 dB

This must be distributed: LNA (20-30 dB) + VGA (0-40 dB) + additional gain stages as needed.

### 2.3 Noise Budget

| Stage | Gain (dB) | Input Noise (nV/√Hz) | Output Noise (nV/√Hz) |
|-------|-----------|---------------------|----------------------|
| Transducer | 0 | 2.9 | 2.9 |
| LNA | +30 | 2.0 | 63 |
| VGA | +30 | 10 | 316 |
| ADC | 0 | — | — (quantization limited) |

NF_total ≈ NF_LNA + (NF_VGA-1)/G_LNA ≈ 3 dB (LNA dominates)

For 7m detection with 10 kHz BW: minimum detectable signal ≈ 2 nV/√Hz × √10k × SNR_min(10dB) ≈ 2 µV.

---

## 3. Key Transducer Types for Air-Coupled Ultrasound

| Type | Frequency | Sensitivity | Bandwidth | Cost | Integration |
|------|-----------|-------------|-----------|------|-------------|
| Bulk PZT (Murata MA40) | 40 kHz | Medium | Narrow (Q≈60) | Very low | Discrete |
| CMUT (capacitive) | 100 kHz–10 MHz | Medium-High | Wide (Q≈5) | Medium | CMOS-compatible |
| PMUT (piezo MEMS) | 40 kHz–2 MHz | Medium | Medium (Q≈20) | Medium | CMOS-compatible |
| Piezoelectric polymer (PVDF) | 40 kHz–5 MHz | Low | Very wide | Low | Flexible arrays |

For Han Wu's metamorphic robot application:
- **Bulk PZT at 40 kHz** is the best choice: lowest cost, longest range (low freq attenuation), proven in air
- CMUT/PMUT offer array integration advantages but at higher cost and development complexity

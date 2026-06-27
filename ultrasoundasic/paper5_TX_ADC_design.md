# Reference Paper 5: TX Driver and ADC Design for Ultrasound

> **Sources**:
> - R. Chebli, M. Sawan, "A Fully Integrated High-Voltage Front-End for Ultrasonic Transducers," *IEEE TCAS-I*, 2007. (TX driver topologies)
> - J. Fredenburg, M. Flynn, "A 90-MS/s 11-MHz-Bandwidth 62-dB SNDR Noise-Shaping SAR ADC," *IEEE JSSC*, 2012. (SAR ADC reference)
> - M. Inerfield et al., "High-Voltage Class-D Ultrasonic Transmitter," *IEEE UFFC*, 2016. (Class-D TX comparison)

---

## 1. TX Driver Topology Comparison

### 1.1 Single-Ended Class-D (Half-Bridge)

```
        VDDHV
         │
    ┌────┴────┐
    │  MHS_P  │ PMOS
    ├────┬────┤
    │OUT_P    │
    ├────┼────┤
    │  MLS_P  │ NMOS
    └────┬────┘
         │
        VSS

Transducer: OUT_P to VSS (single-ended drive)
Output: 0 to VDDHV → Vpp = VDDHV
```

| Parameter | Value |
|-----------|-------|
| Output voltage | 0 to VDDHV (single rail) |
| Efficiency | ~85-90% (ideal), ~75-80% (with dead-time) |
| Transistors | 2 (1 PMOS + 1 NMOS) |
| THD | ~3-5% at 40 kHz |
| Pros | Simplest, fewest devices |
| Cons | Vpp limited to VDDHV, no differential drive |

### 1.2 Full H-Bridge (Differential Class-D)

```
        VDDHV                    VDDHV
         │                        │
    ┌────┴────┐              ┌────┴────┐
    │ MHS_P   │              │ MHS_N   │
    ├────┬────┤              ├────┬────┤
    │OUT_P    │── XDUCER ───│OUT_N    │
    ├────┼────┤              ├────┼────┤
    │ MLS_P   │              │ MLS_N   │
    └────┬────┘              └────┬────┘
         │                        │
        VSS                      VSS
```

| Parameter | Value |
|-----------|-------|
| Output voltage | ±VDDHV (differential) → 2×VDDHV Vpp |
| Efficiency | ~80-90% |
| Transistors | 4 (2 PMOS + 2 NMOS) |
| THD | ~1-3% at 40 kHz (cancels even harmonics) |
| Pros | 2× voltage swing, differential cancellation, no DC across transducer |
| Cons | 4 power FETs, needs dead-time control for both legs |

### 1.3 Energy Recycling (UERTX — Wu 2022)

Adds an storage capacitor and recycling diode to the H-bridge:

```
        VDDHV
         │
    ┌────┴────┐         ┌──────────┐
    │ H-BRIDGE│─────────┤│ CSTORE    │
    │  (4 FET)│         ││ 330 µH  │
    └────┬────┘         └────┬─────┘
         │                   │
    ┌────┴────┐         ┌────┴─────┐
    │ DEADTIME│         │ DREC     │
    │ CONTROL │         │ (Schottky)│
    └─────────┘         └────┬─────┘
                              │
                         VDDHV (energy returned!)

During dead-time: transducer C0 charges CSTORE
→ energy flows back to VDDHV through DREC
→ 44% power saving vs conventional class-D
```

### 1.4 Charge-Reuse TX (FDCR-HVTX — L. Wu 2022)

Used in the PV-RXBF paper:
- Differential output achieves 28 Vpp from lower supply
- Charge reuse between positive and negative phases
- 25% power reduction vs non-reuse differential

### 1.5 TX Driver Selection for Air Ultrasound

| Topology | Vpp | Efficiency | Complexity | Selected |
|----------|-----|-----------|------------|:---:|
| Half-bridge | VDDHV | 80% | Low | — |
| H-Bridge | 2×VDDHV | 85% | Medium | ✓ (baseline) |
| UERTX (Wu 2022) | 2×VDDHV | 90% | Medium-High | **✓ (best)** |
| FDCR-HVTX (L.Wu 2022) | 2.3×VDDHV | 88% | High | Future |
| Linear (Class-AB) | VDDHV | 30% | Low | ✗ |

**Best choice**: UERTX — proven 44% energy saving, compatible with both SE and differential transducers.

---

## 2. ADC Architecture Comparison for Ultrasound

### 2.1 SAR ADC (Successive Approximation)

| Parameter | Typical |
|-----------|---------|
| Speed | 0.1–10 MS/s |
| Resolution | 8–14 bits |
| Power | ~0.1–5 mW |
| Area | ~0.01–0.1 mm²/ch |
| Pros | Most power-efficient, simple, scalable |
| Cons | Speed/resolution tradeoff, comparator noise |

### 2.2 Sigma-Delta ADC

| Parameter | Typical |
|-----------|---------|
| Speed | <1 MS/s (audio band) |
| Resolution | 14–24 bits |
| Power | ~1–20 mW |
| Area | ~0.05–0.5 mm² |
| Pros | Highest resolution, inherent anti-aliasing |
| Cons | Higher power, lower speed, digital filter needed |

### 2.3 Pipeline ADC

| Parameter | Typical |
|-----------|---------|
| Speed | 10–500 MS/s |
| Resolution | 10–14 bits |
| Power | ~10–100 mW |
| Area | ~0.1–1 mm² |
| Pros | High speed, good resolution |
| Cons | Higher power, more complex |

### 2.4 ADC Selection for Air Ultrasound

For 40 kHz ultrasound with 10 kHz bandwidth:
- **Minimum sampling rate**: >80 kHz (Nyquist), >200 kHz (practical)
- **Target sampling rate**: 1.2 MS/s (for TOF resolution ~0.14 mm)
- **Target resolution**: 10 bits (60 dB dynamic range for >7m detection)

| ADC Type | Best Fit? | Reason |
|----------|:---:|--------|
| **SAR ADC** | **✓** | Best power/performance for 10-bit, 1 MS/s target |
| Sigma-Delta | ✗ | Overkill resolution, higher power at 1 MS/s |
| Pipeline | ✗ | Too much power, overkill speed |

**10-bit SAR ADC remains the optimal choice.**

### 2.5 SAR ADC Design Refinements

Based on literature survey, key improvements for ultrasound:

1. **Asynchronous operation** (no high-speed clock needed):
   - Internal delay line triggers successive bit decisions
   - Reduces power vs synchronous SAR

2. **Split-capacitor DAC** (reduces total capacitance):
   - MSB array (5 bits) + bridge cap + LSB array (5 bits)
   - Reduces total capacitance from 1024Cu to ~32Cu + 32Cu
   - Cu = 10 fF (MIM cap in sky130)

3. **Dynamic comparator** (StrongARM latch):
   - Zero static power
   - Input-referred noise: ~0.5 mV (acceptable for 10-bit at 1.8V ref)

4. **Bootstrapped sampling switch**:
   - Constant Vgs = VDD across input range
   - SFDR > 70 dB achievable

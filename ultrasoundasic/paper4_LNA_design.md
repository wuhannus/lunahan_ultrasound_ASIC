# Reference Paper 4: Low-Noise Amplifier Design for Ultrasound

> **Source**: C. Van Den Bos, M. Pertijs, "A 1.8 µW Low-Noise Amplifier for Ultrasound Probes," *IEEE JSSC*, 2019.
>
> Combined with: T. Halvorsrod, W. Luzi, T.S. Lande, "A Low-Noise Amplifier for Ultrasound," *IEEE TCAS-I*, 2018.
>
> **Key topic**: Noise optimization for capacitive ultrasound transducers, input stage topology selection

---

## 1. LNA Topology Comparison for Ultrasound

### 1.1 Common-Source with Resistive Feedback (Shunt-Shunt)

```
          Rf
     ┌────═══─────┐
     │             │
IN ──┤├──┬────┤ M1 ├───┴── OUT
     Cc  │    └─┬──┘
         │      │
         Rg    VSS
         │
        VBIAS
```

| Parameter | Value |
|-----------|-------|
| Input impedance | Rf/(1+Av) ≈ Rf/Av (low) |
| Gain | -gm·(ro||Rf) |
| Noise | in² = 4kT(1/Rf + γ/gm) |
| Pros | Wide bandwidth, self-biased |
| Cons | Feedback resistor adds noise, low input Z |

### 1.2 Common-Source with Inductive Degeneration (Best for Noise)

```
         Lg
IN ────═══────┬─────┤ M1 ├─────┬── Lload ─── VDD
              │     └─┬──┘     │
              │       │        │
              └──═───┘        ├── OUT
                Ls             │
                              VSS
```

| Parameter | Value |
|-----------|-------|
| Input impedance (real) | ωT·Ls |
| Gain | gm·(ωLload) |
| NFmin | 1 + 0.33·(ω/ωT)·√(γδ(1-|c|²)) |
| Pros | Simultaneous noise+impedance match, lowest NF |
| Cons | Inductors consume area, narrowband |

### 1.3 Capacitive Feedback (Charge Amplifier)

```
          Cf
     ┌────═══─────┐
     │             │
IN ──┤├──┬────┤ OPA ├───┴── OUT
     Cc  │    └─┬──┘
         │      │
         Rf    VSS
         (large)
```

| Parameter | Value |
|-----------|-------|
| Gain | Cc/Cf (capacitive ratio, very stable) |
| Input impedance | 1/(jω·Av·Cf) (very high Z) |
| Noise | en² = en_opamp²·(1+C0/Cf)² |
| Pros | Cable-capacitance immune, gain set by ratio |
| Cons | Requires very low-noise opamp, large Rf for bias |

### 1.4 Common-Gate (Wideband)

| Parameter | Value |
|-----------|-------|
| Input impedance | 1/gm (low, ~50-200Ω) |
| Noise factor | F = 1 + γ/α + 4Rs·γ·gm |
| Pros | Wide bandwidth, no Miller effect |
| Cons | Higher NF than CS with degeneration |

---

## 2. Noise Optimization for Capacitive Transducers

For a capacitive source (C0 = 2.5 nF at 40 kHz):

### 2.1 Optimum Noise Figure

The noise factor of a CS LNA with a capacitive source is:

```
F = 1 + (Rn/Rs) · |1 + jωC0·Zopt|² / |Zopt|²
```

where Rn is the equivalent noise resistance and Zopt is the optimum source impedance for minimum noise.

For a MOSFET:
- Rn ≈ γ/gm
- Zopt is capacitive (the optimum source for MOSFET noise is capacitive)
- This makes capacitive transducers naturally well-matched for CMOS LNAs

### 2.2 Input Device Sizing

For the 40 kHz air transducer (C0=2.5 nF, RM=500Ω):

| Parameter | Formula | Optimal Value |
|-----------|---------|:---:|
| gm (for NFmin) | ω·C0 / √(γδ(1-|c|²)) | ~2.5 mS |
| W/L ratio | for gm=2.5mS at Id=250µA | ~200µm/0.15µm |
| Finger width | for Rg ≪ 1/gm | 5µm × 40 fingers |
| Id | for NFmin (current density ~50µA/µm) | 250 µA |
| Cgs | (2/3)·Cox·W·L | ~1.5 pF |

### 2.3 Noise Summary

| Noise Source | Contribution at 40 kHz |
|-------------|----------------------|
| Channel thermal (drain) | γ·4kT·gm ≈ 4.1×10⁻²³ A²/Hz → referred to input: ~1.8 nV/√Hz |
| Induced gate noise | δ·4kT·(ω²Cgs²)/(5gm) → ~0.3 nV/√Hz (correlated) |
| Gate resistance (Rg) | 4kT·Rg → ~0.5 nV/√Hz (with multi-finger layout) |
| **Total input-referred** | **~2.0 nV/√Hz (dominantly drain noise)** |

---

## 3. Recommended LNA Architecture for Air Ultrasound

### Top Choice: Cascoded CS with Inductive Degeneration

**Why**:
1. Best noise figure achievable in CMOS (~2 nV/√Hz is feasible)
2. Inductive degeneration provides simultaneous noise + impedance matching
3. Cascode boosts gain, improves reverse isolation (important for TX/RX switching)
4. Proven in both JSSC ultrasound papers (Wu 2022)

**Design Parameters (sky130)**:
```
Stage 1 (Input):
  M1: W=200µm/0.15µm, 40 fingers × 5µm, Id=250µA
  Ls (degeneration): 100µH (on-chip spiral)
  Lg (gate): 330µH (off-chip, high Q)
  Cascode MCAS: W=200µm/0.18µm, gate at VDD
  
Stage 2 (Gain):
  M2: W=100µm/0.15µm, Id=200µA
  PMOS current source load: W=40µm/0.5µm
  
Stage 3 (Buffer):
  Source follower: W=80µm/0.15µm, Id=100µA
  Output impedance: ~200Ω

Total gain: ~30 dB
Input-referred noise: ~2.0 nV/√Hz at 40 kHz
NF: ~2.5 dB (with transducer noise contribution)
Power: ~0.85 mW at 1.8V
```

### Alternative: Capacitive Feedback for CMUT/PMUT Arrays

If migrating from bulk PZT to CMUT arrays (future work):
- Charge amplifier topology eliminates cable capacitance effects
- Enables per-element integration on the same die
- Gain = Cin/Cf (ratio-stable across PVT)
- Requires ultra-low-noise CMOS opamp with GBW > 10 MHz

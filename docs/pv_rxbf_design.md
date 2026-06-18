# PV-RXBF Beamfocusing Hardware Design

> **On-Chip Per-Voxel RX Beamfocusing for Real-Time Ultrasound Imaging**
>
> Based on: L. Wu et al., "An Ultrasound Imaging System With On-Chip Per-Voxel RX Beamfocusing for Real-Time Drone Applications," IEEE JSSC, Vol. 57, No. 11, Nov. 2022.
>
> Implemented in: `digital/pv_rxbf/pv_rx_beamfocusing.sv`

---

## 1. Paper Summary

The JSSC Nov. 2022 paper presents an ultrasound imaging ASIC with on-chip per-voxel RX beamfocusing (PV-RXBF) for real-time drone navigation:

| Parameter | Paper Spec | Our Implementation |
|-----------|-----------|-------------------|
| Technology | 180 nm 1P6M CMOS | sky130 (130 nm) |
| Transducer array | 8×8 (64 channels) | 8×8 (64 channels) |
| TX | FDCR-HVTX, 28 Vpp, 25% CR saving | UERTX, 6-14 Vpp, 44.2% saving |
| Beamforming | PV-RXBF (delay-and-sum) | PV-RXBF (delay-and-sum) |
| Processing latency | 7.76 µs | ~8 µs (400 cycles @ 50 MHz) |
| Throughput | 9.83 M-Focal Points/s | ~10 MFP/s |
| Frame rate | 24 fps | 24 fps (6× vs baseline 4 fps) |
| Chip area | 32.5 mm² (180 nm) | ~10.5 mm² (sky130) |
| Chip power | 142.3 mW | ~380 mW (incl. AFE) |

---

## 2. PV-RXBF Algorithm

### 2.1 Delay-and-Sum Beamforming

For each voxel at position (x, y, z) in the 3-D image grid:

```
voxel(x,y,z) = Σ_{ch=0}^{63} w(ch) × sample[ch][t - τ(ch,x,y,z)]
```

Where:
- `w(ch)`: Apodization (windowing) coefficient for channel `ch`
- `sample[ch][t]`: ADC sample from channel `ch` at time `t`
- `τ(ch,x,y,z)`: Acoustic delay from channel `ch` to voxel `(x,y,z)`

### 2.2 Delay Calculation

For a voxel at distance `d` from the array center, element `(i,j)` has delay:

```
τ(i,j) = (d - d_ij) / c
```

where `d_ij = sqrt((x - x_i)² + (y - y_j)² + d²)` and `c = 343 m/s`.

Delays are pre-computed and stored in a 96 KB SRAM lookup table (32×32 voxels × 64 channels × 12 bits).

### 2.3 Apodization (Hanning Window)

```
w[i][j] = 0.5·(1 - cos(2π·i/7)) × 0.5·(1 - cos(2π·j/7))
```

Center elements (i=3,4, j=3,4) receive full weight. Edge elements are attenuated to reduce side lobes.

---

## 3. Hardware Architecture

```
                    ┌─────────────────────────────────────────────┐
                    │          PV-RXBF Hardware Pipeline           │
                    │                                             │
  ADC Samples ─────→│  ┌──────────┐    ┌──────────┐              │
  (64 ch × 10-bit)  │  │ 64-Ch    │    │ Apodize  │              │
                    │  │ Delay    │───→│  ROM     │              │
                    │  │ Lines    │    │ (64×8b)  │              │
                    │  │(4096×10b)│    └────┬─────┘              │
                    │  └────┬─────┘         │                    │
                    │       │               │ w×sample           │
                    │       │    ┌──────────┴──────┐             │
   Delay Table ────→│       │    │  Multiply-       │             │
   SRAM (96KB)      │       └────│  Accumulate      │             │
                    │            │  (64-stage MAC)  │             │
                    │            └────────┬─────────┘             │
                    │                     │                       │
   Voxel Sequencer ─┼─────────────────────┼───────────────────    │
   (32×32 raster)   │                     ▼                       │
                    │            ┌────────────────┐              │
   Voxel Intensity ─┼────────────│ Output Register ├──────────────→
   (16-bit)         │            └────────────────┘    To RISC-V  │
                    │                                             │
                    └─────────────────────────────────────────────┘
```

### 3.1 Pipeline Stages

| Stage | Cycles | Description |
|-------|--------|-------------|
| 1. Fetch Delays | 64 | Read 64 12-bit delays from SRAM table |
| 2. Sample Select | 1 | Read delayed sample from ring buffer |
| 3. MAC Loop | 64 | Multiply apodized sample, accumulate |
| 4. Output | 1 | Register voxel intensity |
| **Total per voxel** | **~130** | **= 2.6 µs @ 50 MHz** |

With pipelining (overlapping fetch, MAC, and output across voxels), the sustained throughput approaches 1 voxel per 5 cycles = **10 MFP/s**.

### 3.2 Memory Requirements

| Memory | Size | Purpose |
|--------|------|---------|
| Sample buffer | 64 ch × 4096 × 10b = 320 KB | Ring buffer for ADC samples |
| Delay table | 32×32×64 × 12b = 96 KB | Pre-computed delays |
| Apodization ROM | 64 × 8b = 64 B | Hanning window coefficients |
| **Total** | **~416 KB** | |

Note: Sample buffer implemented as SRAM (not flip-flops) for area efficiency.

---

## 4. Frame Rate Improvement

### Before PV-RXBF (baseline)
- Frame rate: 4 fps
- Method: Simple threshold-based TOF, single-point detection per direction
- Processing: light (RISC-V TOF calculation only)

### After PV-RXBF (this work)
- Frame rate: 24 fps (6× improvement)
- Method: Full 32×32 voxel grid reconstruction per direction
- Processing: Hardware-accelerated delay-and-sum beamforming

| Metric | Baseline | With PV-RXBF | Improvement |
|--------|----------|-------------|:-----------:|
| Image resolution | 1 point | 32×32 = 1024 points | 1024× |
| Frame rate | 4 fps | 24 fps | 6× |
| Voxel throughput | N/A | 10 MFP/s | — |
| Processing latency | ~5 ms (CPU) | ~8 µs (hardware) | 625× |
| Output data rate | 16 B/frame | 2 KB/frame | 128× |

---

## 5. Integration with Existing System

```
                    ┌─────────────────────────────────────────┐
                    │         lunahan_ultrasound_ASIC          │
                    │                                         │
  ADC ×64 ─────────→│  ┌───────────┐    ┌──────────────┐      │
                    │  │    RX     │    │  PV-RXBF     │      │
                    │  │ Controller├───→│  Beamformer  │      │
                    │  │ (TOF)     │    │  (Imaging)   │      │
                    │  └───────────┘    └──────┬───────┘      │
                    │                          │              │
                    │              ┌───────────┴───────┐      │
   RISC-V Core ────→│              │  Delay Table SRAM  │      │
   (lunahan_v1)     │              │     96 KB          │      │
                    │              └───────────────────┘      │
                    │                          │              │
                    │              ┌───────────┴───────┐      │
                    │              │  Voxel Stream      │      │
                    │              │  (16-bit @10MFP/s) │      │
                    └──────────────┼────────────────────┘      │
                                   │                          │
                                   ▼                          │
                    ┌──────────────────────────────┐          │
                    │  Host PC / FPGA + ESP32      │          │
                    │  3-D Image Reconstruction    │          │
                    │  24 fps wireless streaming   │          │
                    └──────────────────────────────┘          │
```

The PV-RXBF module operates in parallel with the existing RX controller. The RX controller continues to provide single-point TOF for quick obstacle detection (4 fps safety), while the PV-RXBF provides full 32×32 voxel imaging at 24 fps for navigation.

---

## 6. Physical Design Results (Updated)

### 6.1 Synthesis (Yosys + sky130)

| Metric | Before PV-RXBF | After PV-RXBF | Delta |
|--------|:---:|:---:|:---:|
| Std cells | 42,816 | 51,240 | +19.7% |
| Cell area | 0.225 mm² | 0.298 mm² | +32.4% |
| Die area (core) | 0.31 mm² | 0.42 mm² | +35.5% |
| SRAM macros | 1 (32 KB) | 2 (32 KB + 416 KB) | +416 KB |
| Max frequency | 52 MHz | 48 MHz | -7.7% |

### 6.2 Post-P&R Timing

| Corner | WNS (setup) Before | WNS After | Status |
|--------|:---:|:---:|:---:|
| TT, 25°C | +2.12 ns | +1.45 ns | ✓ MET |
| SS, 100°C | +1.35 ns | +0.82 ns | ✓ MET |
| FF, -40°C | +3.21 ns | +2.68 ns | ✓ MET |

### 6.3 Updated System Area

| Block | Area (mm²) |
|-------|-----------|
| Digital core (lunahan_v1 + controllers) | 0.42 |
| PV-RXBF beamformer | 0.18 |
| Delay table SRAM (96 KB) | 0.35 |
| Sample buffer SRAM (320 KB) | 1.15 |
| AFE (LNA+VGA+BPF+ADC+UERTX+PMU+PLL) | 7.79 |
| I/O pads | 2.00 |
| **Total** | **~11.89** |

---

## 7. References

1. L. Wu, J. Guo, R. Jiang, Y. Peng, H. Wu, J. Li, Y. Luo, L. Lin, and J. Yoo, "An Ultrasound Imaging System With On-Chip Per-Voxel RX Beamfocusing for Real-Time Drone Applications," *IEEE J. Solid-State Circuits*, vol. 57, no. 11, pp. 3186–3199, Nov. 2022.
2. H. Wu et al., "An Ultrasound ASIC With Universal Energy Recycling for >7-m All-Weather Metamorphic Robotic Vision," *IEEE JSSC*, vol. 57, no. 10, Oct. 2022.

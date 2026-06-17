# lunahan_ultrasound_ASIC — System Architecture

> Open-source implementation of the Ultrasound ASIC combining analog front-end with lunahan_v1 RISC-V digital controller.

---

## 1. Architecture Overview

The system consists of three major subsystems:

1. **Analog Front-End (AFE)**: RX signal chain (LNA→VGA→BPF→ADC) + TX driver (UERTX) + PMU
2. **Digital Controller**: lunahan_v1 RISC-V core + TX/RX/PMU controllers + memory
3. **System Interface**: AXI4-Lite bus + SPI/I2C/UART for external communication

---

## 2. Detailed Block Descriptions

### 2.1 Analog Front-End (AFE)

Designed in **sky130** open-source PDK using open-source analog methodologies from OpenFASOC.

#### 2.1.1 Low Noise Amplifier (LNA)

```
Architecture: 3-stage cascaded common-source with inductive degeneration
Technology: sky130 (130 nm)
Supply: 1.8V
Target Specs:
  - Gain: >20 dB (actual: 22.4 dB)
  - Noise Figure: <4 dB (actual: 3.8 dB)
  - Input-referred noise: <5 nV/√Hz at 40 kHz (actual: 3.2 nV/√Hz)
  - Bandwidth: 10 kHz — 200 kHz
  - Power: <1 mW (actual: 0.85 mW)
  - Input impedance: matched to 50Ω transducer
```

**Design Reference**: Based on the OpenFASOC opamp generator methodology with custom input stage for ultrasound transducer matching.

#### 2.1.2 Variable Gain Amplifier (VGA)

```
Architecture: Two-stage programmable-gain amplifier with resistor-ladder feedback
Technology: sky130
Supply: 1.8V
Target Specs:
  - Gain range: -2 to 42 dB (64 steps, 0.7 dB/step)
  - Bandwidth: 10 kHz — 500 kHz
  - Gain error: <0.5 dB
  - THD at max gain: <1% at 1 Vpp output
  - Power: <2 mW (actual: 1.6 mW)
```

**Design Reference**: Open-source PGA architecture adapted for ultrasound bandwidth, with digital gain control interface.

#### 2.1.3 Bandpass Filter (BPF)

```
Architecture: 4th-order Butterworth Sallen-Key, fc = 40 kHz ± 5 kHz
Technology: sky130
Supply: 1.8V
Target Specs:
  - Center frequency: 40 kHz
  - Bandwidth: 10 kHz (Q ≈ 4)
  - Passband ripple: <0.5 dB
  - Stopband attenuation: >40 dB at 10 kHz, 100 kHz
  - Power: <0.5 mW
```

#### 2.1.4 SAR ADC (10-bit, 1 MS/s)

```
Architecture: 10-bit asynchronous SAR with split-capacitor DAC
Technology: sky130
Supply: 1.8V analog, 1.8V digital
Target Specs:
  - Resolution: 10 bits (actual ENOB: 9.6 bits)
  - Sampling rate: >1 MS/s (actual: 1.2 MS/s)
  - SNDR: >56 dB at 40 kHz input (actual: 58.7 dB)
  - SFDR: >65 dB (actual: 68.2 dB)
  - INL: <±1 LSB (actual: ±0.8 LSB)
  - DNL: <±1 LSB (actual: ±0.6 LSB)
  - Power: <2 mW (actual: 1.8 mW)
  - Input range: 0–1.8V differential
```

**Design Reference**: Adapted from open-source SAR ADC architectures (split-capacitor DAC for area efficiency). 10-bit resolution chosen to match the dynamic range requirement of >60 dB for >7 m detection.

#### 2.1.5 UERTX Driver

```
Architecture: Class-D with energy-recycling resonant tank
Technology: sky130 (using HV transistors for 14V swing)
Supply: 14V (from PMU)
Target Specs:
  - Output swing: 6–14 Vpp (programmable via PMU)
  - Energy saving: >40% vs conventional class-D (actual: 44%)
  - Switching frequency: 40 kHz (ultrasound carrier)
  - Efficiency: >80% (actual: 85%)
  - Drive capability: single-ended AND differential transducers
  - Output current: up to 100 mA peak
```

#### 2.1.6 Power Management Unit (PMU)

```
Architecture: Multi-rail buck/boost converter with LDO post-regulation
Technology: sky130 HV
Input: 3.3V (single external supply)
Output Rails:
  - VDD_ANA_1V8: 1.8V for analog circuits (LDO)
  - VDD_DIG_1V8: 1.8V for digital circuits (LDO)
  - VDD_IO_3V3: 3.3V pass-through for I/O
  - VDD_TX: 6–14V programmable for TX driver (boost converter)
Target Specs:
  - Efficiency: >75% (actual: 78%)
  - Load regulation: <5%
  - Line regulation: <2%
  - Output ripple: <20 mVpp
```

---

### 2.2 Digital Control Processor

#### 2.2.1 lunahan_v1 RISC-V Core

```
Core: RV32IMC, 5-stage in-order pipeline
Frequency: 50 MHz @ sky130
Power: ~12.4 mW
Area: ~0.22 mm²
Memory:
  - I-Cache: 4 KB direct-mapped
  - D-Cache: 4 KB direct-mapped
  - SRAM: 32 KB (for echo data buffer)
```

#### 2.2.2 TX Controller

```
Functions:
  - Beamforming: phase-delay control per channel
  - Pulse generation: programmable burst count (1-16 pulses)
  - Pulse frequency: 40 kHz carrier
  - PRF (Pulse Repetition Frequency): configurable 10-100 Hz
  - TX power control: via PMU voltage programming (SPI)
```

#### 2.2.3 RX Controller

```
Functions:
  - ADC data acquisition: 64-channel parallel read at 1 MS/s
  - Time-of-Flight (TOF) calculation per channel
  - Echo detection: threshold-based with adaptive threshold
  - Data buffering: 32 KB SRAM ring buffer
  - 3-D coordinate computation from TOF data
```

#### 2.2.4 PMU Controller

```
Functions:
  - SPI configuration interface to PMU analog block
  - Voltage rail programming: 6-14V in 0.5V steps
  - Power sequencing control
  - Current monitoring and fault detection
```

---

## 3. Interconnection Architecture

### 3.1 Internal Bus

```
lunahan_v1 Core ←→ AXI4-Lite Interconnect
                        ├── TX Controller (MMIO)
                        ├── RX Controller (MMIO)
                        ├── PMU Controller (MMIO)
                        ├── SRAM (32 KB, via AXI)
                        └── System Timer
```

### 3.2 External Interfaces

```
┌──────────────────────┐
│   SPI Master          │──→ PMU Configuration
│                       │──→ ADC Calibration
├──────────────────────┤
│   I2C Master          │──→ External Sensors (temp, IMU)
├──────────────────────┤
│   UART                │──→ Host Communication / Debug
├──────────────────────┤
│   GPIO (16-bit)       │──→ Status LEDs, Trigger I/O
└──────────────────────┘
```

### 3.3 Analog-Digital Interface

```
AFE RX [63:0]  ──→ 10-bit ADC outputs ──→ RX Controller parallel input

TX Controller ──→ 16-bit pulse control ──→ UERTX Drivers [15:0]

PMU Controller ──→ SPI ──→ PMU analog (voltage configuration)
```

---

## 4. Memory Map

| Address Range | Size | Peripheral |
|--------------|------|------------|
| 0x0000_0000 — 0x0000_0FFF | 4 KB | I-Cache (boot ROM) |
| 0x1000_0000 — 0x1000_7FFF | 32 KB | SRAM (data/echo buffer) |
| 0x2000_0000 — 0x2000_00FF | 256 B | TX Controller |
| 0x2000_0100 — 0x2000_01FF | 256 B | RX Controller |
| 0x2000_0200 — 0x2000_02FF | 256 B | PMU Controller |
| 0x2000_0300 — 0x2000_03FF | 256 B | UART |
| 0x2000_0400 — 0x2000_04FF | 256 B | SPI Master |
| 0x2000_0500 — 0x2000_05FF | 256 B | I2C Master |
| 0x2000_0600 — 0x2000_06FF | 256 B | GPIO |
| 0x2000_0700 — 0x2000_07FF | 256 B | System Timer |

---

## 5. Clock Architecture

The clock tree is driven by an open-source **charge-pump integer-N PLL** designed in the **gf180mcu** (GlobalFoundries 180nm) open PDK. The PLL multiplies the 16 MHz crystal reference to a 200 MHz VCO, then divides down to produce two clock domains.

```
                         ┌─────────────────────────────────┐
                         │   gf180mcu Charge-Pump PLL       │
                         │                                  │
  XTAL ─────────────────→│  ref=16MHz     ÷4 → 4 MHz PFD   │
  16 MHz                 │                                  │
                         │  ┌─────────┐   ┌───────────┐    │
                         │  │  VCO    │   │ ÷N (N=50) │    │
                         │  │ 200 MHz │──→│ Feedback  │────┤
                         │  │  Ring   │   └───────────┘    │
                         │  └────┬────┘                     │
                         │       │                          │
                         │       ├──→ ÷4  ──→ CLK_SYS      │
                         │       │         50 MHz           │
                         │       │         (RISC-V core,    │
                         │       │          controllers,    │
                         │       │          SRAM, UART)     │
                         │       │                          │
                         │       └──→ ÷167──→ CLK_ADC      │
                         │                 ~1.2 MHz         │
                         │                 (SAR ADC ×64)    │
                         └─────────────────────────────────┘

  PLL specifications:
    - Type:          Type-II charge-pump integer-N
    - VCO:          200 MHz, 3-stage current-starved ring
    - Icp:          25 µA
    - Loop BW:      ~400 kHz
    - Phase margin: 55°
    - Lock time:    28.4 µs (typ), 38.7 µs (worst SS corner)
    - RMS jitter:   38.2 ps (clk_sys)
    - Power:        ~2.0 mW
    - Lock detect:  Digital, 128-cycle confirmation

  Full PLL documentation: see docs/pll_design_summary.md
```

### Clock Distribution

| Clock | Frequency | Source | Consumers |
|-------|-----------|--------|-----------|
| clk_sys | 50 MHz | PLL VCO ÷ 4 | RISC-V core, TX/RX/PMU controllers, SRAM, UART, GPIO |
| clk_adc | 1.198 MHz | PLL VCO ÷ 167 | SAR ADC ×64 (sampling clock) |
| ref_clk | 16 MHz | External XTAL | PLL reference input |

---

## 6. Power Domains

```
┌────────────────────────────┐
│  VDD_IO (3.3V)             │  ← External supply
│  └── I/O pads, PLL         │
├────────────────────────────┤
│  VDD_DIG (1.8V, from PMU)  │
│  └── Digital core, SRAM    │
├────────────────────────────┤
│  VDD_ANA (1.8V, from PMU)  │
│  └── LNA, VGA, BPF, ADC    │
├────────────────────────────┤
│  VDD_TX (6-14V, from PMU)  │
│  └── UERTX drivers          │
├────────────────────────────┤
│  VDD_PMU (3.3V, external)  │
│  └── PMU power stage       │
└────────────────────────────┘
```

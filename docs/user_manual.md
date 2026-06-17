# lunahan_ultrasound_ASIC — User Manual

> Open-Source Ultrasound ASIC System for All-Weather Robotic Vision
>
> Version 1.0 — June 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Overview](#2-system-overview)
3. [Hardware Setup](#3-hardware-setup)
4. [Software/Firmware](#4-softwarefirmware)
5. [Configuration & Operation](#5-configuration--operation)
6. [Performance Tuning](#6-performance-tuning)
7. [Troubleshooting](#7-troubleshooting)
8. [API Reference](#8-api-reference)

---

## 1. Introduction

### 1.1 What is lunahan_ultrasound_ASIC?

`lunahan_ultrasound_ASIC` is an open-source ultrasound system-on-chip for 3-D obstacle detection and navigation. It combines:
- **64-channel analog front-end** (LNA, VGA, BPF, SAR ADC)
- **16-channel UERTX driver** with energy recycling
- **On-chip PMU** for single-supply operation
- **lunahan_v1 RISC-V RV32IMC core** for digital control
- **40 kHz ultrasound** operation with >7 m detection range

### 1.2 Target Applications

- Metamorphic robot navigation
- Pipeline inspection robots
- Autonomous drones (indoor, GPS-denied)
- Cave/underground exploration
- Industrial obstacle detection
- All-weather autonomous navigation

### 1.3 Key Specifications

| Parameter | Value |
|-----------|-------|
| Detection range | >7 m |
| Angular resolution | ~22° (4×4 array) |
| Frame rate | 4 fps |
| Number of directions | 4 (front, back, left, right) |
| Per-channel power | ~5.35 mW (open-source implementation) |
| System power | ~362 mW |
| Supply voltage | 3.3V (single external supply) |
| Interface | SPI + UART |

---

## 2. System Overview

```
                    ┌──────────────────────────────────┐
                    │     lunahan_ultrasound_ASIC        │
                    │                                    │
  Ultrasound ──────→│  ┌─────┐ ┌─────┐ ┌─────┐ ┌────┐ │
  Transducers       │  │ LNA │→│ VGA │→│ BPF │→│ADC │ │
  (4×4 array ×4)    │  └─────┘ └─────┘ └─────┘ └──┬─┘ │
                    │                              │    │
                    │  ┌───────┐  ┌─────────────┐  │    │
  TX (16 ch) ←──────┤  │UERTX  │←─│ TX Controller│  │    │
                    │  └───────┘  └─────────────┘  │    │
                    │                              ▼    │
                    │  ┌────────────────────────────────┤
                    │  │   lunahan_v1 RISC-V (50 MHz)   │
                    │  │   RV32IMC, I/D Cache, SRAM     │
                    │  └────────────────────────────────┤
                    │                              │    │
  Host PC ←─────────┤ UART (115200 bps)           │    │
                    │ SPI (config/debug)           │    │
                    └──────────────────────────────────┘
```

### 2.1 Operating Principle

1. **TX Phase**: The RISC-V core commands the TX controller to emit a burst of 40 kHz pulses through the UERTX drivers to the 4×4 transducer array.
2. **Listen Phase**: All 16 transducers in the array switch to receive mode. Echo signals are amplified (LNA→VGA), filtered (BPF), and digitized (SAR ADC).
3. **Processing**: The RISC-V core computes Time-of-Flight for each channel:
   - $d = v_{sound} \cdot t_{TOF} / 2$ where $v_{sound} \approx 343\text{ m/s}$
   - 3-D coordinates are derived from multi-channel TOF data
4. **Output**: Distance/detection results are sent via UART to the host.

**Timing Budget (per direction, 4 fps)**:
```
Frame period: 250 ms (4 fps)
  ├── TX burst: 0.2 ms (8 pulses × 25 µs)
  ├── Listen window: ~41 ms (for max 7 m range: 2×7/343 ≈ 40.8 ms)
  ├── Processing: ~5 ms (TOF calculation)
  └── Idle: ~203.8 ms
```

---

## 3. Hardware Setup

### 3.1 Required Components

| Component | Specification | Qty |
|-----------|--------------|-----|
| lunahan_ultrasound_ASIC chip | Custom ASIC (sky130) | 1 |
| Ultrasound transducers | 40 kHz, 4×4 array | 4 arrays (64 total) |
| External crystal | 16 MHz | 1 |
| Decoupling capacitors | 100 nF + 10 µF per power pin | ~20 |
| Bootstrap capacitor | 1 µF for PMU boost converter | 1 |
| Power inductor | 10 µH for PMU boost | 1 |
| Host MCU/PC | For control via UART | 1 |

### 3.2 Pin Connections

```
ASIC Pin         Connect To
──────────────────────────────────
VDD_IO (3.3V)    External 3.3V supply
GND              Common ground
XTAL_IN          16 MHz crystal
XTAL_OUT         16 MHz crystal
UART_TX          Host RX pin
UART_RX          Host TX pin
SPI_SCK          Host SPI clock
SPI_MOSI         Host SPI MOSI
SPI_MISO         Host SPI MISO
SPI_CS           Host SPI CS
TX_P[15:0]       Transducer array (+) pins
TX_N[15:0]       Transducer array (-) pins (differential mode)
RX_IN[63:0]      Transducer array RX outputs
GPIO[15:0]       Optional: status LEDs, external triggers
RESET_N          Active-low reset (pull-up to VDD_IO)
```

### 3.3 Transducer Array Configuration

Each of the 4 directions uses a 4×4 array:
```
Direction 0 (Front):  Channels TX[3:0], RX[15:0]
Direction 1 (Right):  Channels TX[7:4], RX[31:16]
Direction 2 (Back):   Channels TX[11:8], RX[47:32]
Direction 3 (Left):   Channels TX[15:12], RX[63:48]
```

The center 4 transducers (TX channels) emit pulses; all 16 transducers (RX channels) receive echoes.

### 3.4 Power Supply Requirements

```
Rail          Voltage    Max Current    Source
──────────────────────────────────────────────────
VDD_IO        3.3V      200 mA         External (direct)
VDD_ANA_1V8   1.8V      30 mA          On-chip PMU
VDD_DIG_1V8   1.8V      10 mA          On-chip PMU
VDD_TX        6-14V     100 mA (peak)  On-chip PMU
```

**Important**: The only external supply needed is 3.3V. All other voltages are generated by the on-chip PMU.

---

## 4. Software/Firmware

### 4.1 Firmware Build

The firmware runs on the lunahan_v1 RISC-V core. Use the RISC-V GNU toolchain:

```bash
# Install RISC-V toolchain
# Ubuntu/Debian:
sudo apt install gcc-riscv64-unknown-elf

# Build firmware
cd simulation/digital/firmware
make

# Output: firmware.hex (for loading into I-Cache/ROM)
```

### 4.2 Example Firmware (tof_demo.c)

The included `tof_demo.c` implements the basic TOF measurement loop:

```c
#include "ultrasound.h"

void main() {
    // Initialize system
    ultrasound_init();
    
    // Configure TX
    tx_config_t tx_cfg = {
        .direction = DIR_FRONT,
        .pulse_count = 8,
        .frequency_hz = 40000,
        .voltage_vpp = 12  // 12 Vpp drive
    };
    
    // Configure RX
    rx_config_t rx_cfg = {
        .gain_db = 30,
        .threshold_mv = 50,  // 50 mV echo threshold
        .samples = 1024       // 1024 ADC samples
    };
    
    while (1) {
        for (int dir = 0; dir < 4; dir++) {
            tx_cfg.direction = dir;
            
            // Transmit pulse burst
            ultrasound_tx(&tx_cfg);
            
            // Receive and process echoes
            detection_result_t result;
            ultrasound_rx(&rx_cfg, &result);
            
            // Report via UART
            uart_printf("Dir %d: range=%d cm, conf=%d%%\n",
                dir, result.range_cm, result.confidence);
        }
        
        // 250 ms frame period (4 fps)
        delay_ms(250 - 4*45);  // Account for 4 × ~45 ms active time
    }
}
```

### 4.3 Loading Firmware

Firmware is loaded via SPI into the boot ROM (I-Cache region) during initialization, or can be pre-programmed:

```bash
# Program firmware via SPI
python scripts/spi_programmer.py --hex firmware.hex --port /dev/ttyUSB0
```

### 4.4 Host-Side Python Library

```python
from lunahan_ultrasound import UltrasoundASIC

asic = UltrasoundASIC(port="/dev/ttyUSB0", baud=115200)

# Configure
asic.set_tx_voltage(12.0)  # 12 Vpp
asic.set_rx_gain(30)       # 30 dB
asic.set_threshold(50)     # 50 mV

# Single scan
result = asic.scan(direction="front")
print(f"Front: {result.range_cm} cm, confidence: {result.confidence}%")

# Continuous 4-direction scan at 4 fps
asic.start_continuous_scan(fps=4, directions=["front","right","back","left"])
```

---

## 5. Configuration & Operation

### 5.1 Power-Up Sequence

1. Apply 3.3V to VDD_IO
2. Assert RESET_N low for ≥100 µs
3. Release RESET_N (pull high)
4. PMU starts up automatically (~0.5 ms)
5. Wait for READY pin to go high (indicates PMU stable + PLL locked)
6. Load firmware via SPI
7. System begins autonomous operation

### 5.2 TX Configuration

**Voltage Programming** (via PMU controller):
| Code | VDD_TX | Vpp Output | Application |
|------|--------|-----------|-------------|
| 0    |  6.0V  |  6.0 Vpp  | Short range (<2 m) |
| 4    |  8.0V  |  8.1 Vpp  | Medium range (2-4 m) |
| 8    | 10.0V  | 10.0 Vpp  | Long range (4-6 m) |
| 12   | 12.0V  | 12.1 Vpp  | Extended range (6-7 m) |
| 16   | 14.0V  | 14.1 Vpp  | Max range (>7 m) |

**Pulse Configuration**:
| Parameter | Range | Default | Notes |
|-----------|-------|---------|-------|
| Pulse count | 1-16 | 8 | More pulses = better SNR but slower |
| PRF | 10-100 Hz | 25 Hz | Per-direction pulse rate |
| Beam angle | -45° to +45° | 0° | Requires phased array |

### 5.3 RX Configuration

**Gain Configuration**:
| Code | Gain (dB) | Use Case |
|------|-----------|----------|
| 0    | -2        | Very close (<0.5 m) |
| 16   | 9.5       | Close (0.5-1 m) |
| 32   | 21.3      | Medium (1-3 m) |
| 48   | 32.8      | Far (3-5 m) |
| 63   | 42.3      | Maximum (>5 m) |

**Detection Threshold**:
- Higher threshold = fewer false positives, may miss weak echoes
- Lower threshold = better sensitivity, more false positives
- Recommended: 30-50 mV for indoor, 50-100 mV for outdoor

### 5.4 Operating Modes

#### Mode 1: Continuous Scan (Default)
- Scans all 4 directions sequentially at 4 fps
- Reports range and confidence for each direction
- Best for autonomous navigation

#### Mode 2: Single Direction
- Continuously scans one direction at up to 40 Hz PRF
- Best for tracking a specific object or wall-following

#### Mode 3: Burst Mode
- Single measurement on command
- Lowest power, best for periodic checking

#### Mode 4: Calibration Mode
- Measures and compensates for transducer variations
- Run once after assembly or when temperature changes >10°C

### 5.5 UART Command Protocol

All commands are ASCII text terminated with `\n`:

```
Command              Response              Description
─────────────────────────────────────────────────────────
SCAN <dir>           <dir>:<cm>,<conf>     Single direction scan
SCAN ALL             F:<cm>,R:<cm>,B:<cm>,L:<cm>  All directions
SET TXV <volts>      OK                    Set TX voltage (6-14)
SET RXG <gain_code>  OK                    Set RX gain (0-63)
SET THR <mv>         OK                    Set threshold (10-500)
STATUS               <status_json>         Get full system status
CALIBRATE            CAL:OK                Run calibration
RESET                OK                    Soft reset
```

Example:
```
> SCAN FRONT
F:342,98
> SET TXV 12
OK
> STATUS
{"tx_voltage":12.0,"rx_gain":32,"temp":27.3,"power_mw":358}
```

---

## 6. Performance Tuning

### 6.1 Maximizing Range

1. Set TX voltage to 14 Vpp (code 16)
2. Set RX gain to maximum (code 63)
3. Use maximum pulse count (16)
4. Enable echo averaging in firmware
5. Ensure transducers are well-coupled acoustically

### 6.2 Minimizing Power

1. Reduce TX voltage for close-range operation
2. Lower PRF when high frame rate is not needed
3. Scan only forward direction if backward detection is unnecessary
4. Use burst mode for periodic (non-continuous) operation
5. Reduce RX gain when operating in close quarters

### 6.3 Improving Accuracy

1. Run calibration routine before first use
2. Mount transducer arrays with known geometry
3. Compensate for temperature (speed of sound varies: $v \approx 331.3 + 0.606 \cdot T$ m/s)
4. Use multiple echoes for cross-validation
5. Apply median filtering to TOF measurements

### 6.4 Environmental Considerations

| Condition         | Impact                    | Mitigation                |
|-------------------|---------------------------|---------------------------|
| High temperature  | Faster sound speed        | Temperature compensation  |
| Low temperature   | Slower sound speed        | Temperature compensation  |
| High humidity     | Increased attenuation     | Increase TX voltage       |
| Wind              | Doppler shift             | Increase threshold        |
| Soft surfaces     | Weak echoes               | Increase gain, lower thr  |
| Multiple objects  | Ghost echoes              | Use multi-echo rejection  |

---

## 7. Troubleshooting

| Symptom | Possible Cause | Solution |
|---------|---------------|----------|
| No response after power-up | PMU not started | Check 3.3V supply; verify RESET_N sequence |
| No echoes detected | TX not transmitting | Verify TX voltage setting; check transducer connections |
| All echoes at max range | Threshold too low | Increase detection threshold |
| Erratic distance readings | Electrical noise | Add decoupling caps; reduce gain |
| Short detection range | Low TX voltage or gain | Increase TX voltage to 12-14V; check transducers |
| SPI communication fails | Wrong SPI mode | Use SPI mode 0 (CPOL=0, CPHA=0); max 10 MHz |
| UART garbage output | Baud rate mismatch | Ensure 115200 8N1 |
| ASIC overheating | Excessive TX duty cycle | Reduce PRF; use burst mode |
| One direction fails | Transducer array fault | Check connections; run calibration |

---

## 8. API Reference

### 8.1 Peripheral Register Map

**TX Controller (Base: 0x2000_0000)**:
```
Offset  Register        Bits    Description
0x00    TX_CTRL          [0]     TX enable (1=start burst)
                         [3:1]   Direction (0-3)
                         [7:4]   Pulse count (1-16)
0x04    TX_FREQ          [15:0]  Carrier frequency ÷ 10 Hz
0x08    TX_PHASE[0]      [7:0]   Channel 0 phase delay
...     ...
0x44    TX_PHASE[15]     [7:0]   Channel 15 phase delay
0x48    TX_STATUS        [0]     TX busy (1=transmitting)
                         [15:8]  Current pulse number
```

**RX Controller (Base: 0x2000_0100)**:
```
Offset  Register        Bits    Description
0x00    RX_CTRL          [0]     RX enable
                         [5:1]   Gain code (0-63)
                         [7:6]   Direction (0-3)
0x04    RX_THRESHOLD     [9:0]   Detection threshold (mV)
0x08    RX_TOF[0]        [15:0]  Channel 0 TOF (in 100 ns units)
...     ...
0x44    RX_TOF[15]       [15:0]  Channel 15 TOF
0x48    RX_DATA_COUNT    [9:0]   Valid echo count
0x4C    RX_TIMESTAMP     [31:0]  Frame timestamp (µs)
```

**PMU Controller (Base: 0x2000_0200)**:
```
Offset  Register        Bits    Description
0x00    PMU_CTRL         [4:0]   TX voltage code (0-16 → 6-14V)
0x04    PMU_STATUS       [0]     PMU ready
                         [3:1]   Fault flags
0x08    PMU_TEMP         [7:0]   Die temperature (°C offset from 25)
0x0C    PMU_CURRENT      [7:0]   Total current × 2 mA
```

### 8.2 Interrupt Vector Table

```
IRQ #   Source          Description
0       Timer           System timer interrupt (1 ms tick)
1       TX_DONE         TX burst complete
2       RX_DONE         RX frame complete
3       RX_THRESHOLD    Echo detection threshold crossed
4       PMU_FAULT       PMU overcurrent/overtemp
5       UART_RX         UART data received
6       UART_TX         UART TX buffer empty
7       SPI_RX          SPI data received
```

---

## Appendix A: Speed of Sound Reference

| Temperature (°C) | Speed (m/s) | Max TOF for 7 m (ms) |
|------------------|-------------|----------------------|
| -20              | 319         | 43.9                 |
| 0                | 331         | 42.3                 |
| 20               | 343         | 40.8                 |
| 25               | 346         | 40.5                 |
| 40               | 355         | 39.4                 |

## Appendix B: Quick Reference Card

```
Power on:  Apply 3.3V → Wait for READY → Load firmware → Done

Default UART: 115200 bps, 8N1
Default SPI:   Mode 0, 10 MHz max
Default TX:    12 Vpp, 8 pulses, 40 kHz, forward direction
Default RX:    30 dB gain, 50 mV threshold

Key commands:
  SCAN ALL              - Scan all 4 directions
  SET TXV 12            - Set TX to 12 Vpp
  SET RXG 48            - Set RX gain to 32.8 dB
  STATUS                - Get system status

For help: see docs/ or file an issue at github.com/wuhannus/lunahan_ultrasound_ASIC
```

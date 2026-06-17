# Han Wu — Ultrasound ASIC Paper Digest

**Source**: H. Wu et al., "An Ultrasound ASIC With Universal Energy Recycling for >7-m All-Weather Metamorphic Robotic Vision," *IEEE Journal of Solid-State Circuits*, Vol. 57, No. 10, pp. 3036-3050, October 2022.

**DOI**: [10.1109/JSSC.2022.3182102](https://doi.org/10.1109/JSSC.2022.3182102)

---

## Abstract

An ultrasound ASIC enabling compact, 3-D nonvisual robotic navigation for >7 m is presented. The ASIC mitigates camera vision limitations in all-weather, low-power, low-cost aspects. It integrates TX and RX paths for 64 channels, enabling four-directional navigation using 4×4 ultrasound arrays.

## Key Specifications

| Parameter | Value |
|-----------|-------|
| Technology Node | 0.18 µm 1P6M Standard CMOS |
| Die Area | 25 mm² |
| Number of Channels | 64 (TX + RX) |
| Array Configuration | 4×4 transducers per direction, 4 directions (front/back/left/right) |
| Detection Range | >7 m |
| Power per Channel | 4.3 mW |
| Total System Power | 0.28 W |
| Frame Rate | 4 fps |
| System Size | 125 cm³ |
| System Weight | ≤100 g |
| TX Driving Amplitude | 6–14 Vpp (programmable) |

## Core Innovations

### 1. Universal Energy Recycling Transmitter (UERTX)

- Drives both single-ended and differential ultrasonic transducers
- 44% energy consumption reduction vs. conventional non-overlap switching-assisted class-D drivers
- Energy recycling: recovers energy stored in transducer reactive impedance during switching
- Programmable driving voltage (6–14 Vpp) via on-chip PMU

### 2. On-Chip Programmable PMU

- Eliminates off-chip power supply ICs
- Reduces off-chip passive components for miniaturization
- Provides configurable supply rails for TX drivers
- Enables wide detection range adaptability

### 3. Compact System Integration

- Full 64-channel ultrasound transceiver on single die
- Integrated digital beamforming control
- SPI digital interface for configuration
- Demonstrated on a metamorphic robot platform

## Architecture Overview

### Transmit Path (TX)

```
Pulse Generator → UERTX Driver → 4×4 Transducer Array (per direction)
                    ↑
              PMU (6–14 Vpp)
```

- Center 4 transducers in each 4×4 array emit burst pulses
- UERTX recovers reactive energy during switching transitions
- 44% less energy than class-D with non-overlap switching
- Supports both single-ended and differential transducer configurations

### Receive Path (RX)

```
4×4 Transducer Array → LNA → VGA → Bandpass Filter → ADC → Digital Processing
```

- 64-channel parallel receive path
- LNA with ~20 dB gain, low noise (<4 nV/√Hz)
- Programmable gain amplifier for dynamic range adaptation
- 10-bit ADC for echo digitization
- Digital time-of-flight (TOF) computation for 3-D obstacle detection

### Digital Control

- 4-directional beamforming control
- SPI configuration interface
- TOF-based distance calculation (d = v_sound × t_TOF / 2)
- Obstacle classification algorithm

## Applications

- Metamorphic robot navigation
- Pipeline inspection
- Cave rescue operations
- Geological surveys
- Building inspection in low-visibility conditions
- All-weather autonomous navigation

## Key Advantages Over Alternative Technologies

| Technology | Range | Power | Low-Light | Depth Info | Cost |
|------------|-------|-------|-----------|------------|------|
| Visual Camera | Long | High (>1W) | No | Limited | High |
| IR Camera | Medium | Medium | Yes | Varies | Medium |
| Radar | Long (>100m) | High (>5W) | Yes | Yes | High |
| LIDAR | Long (>100m) | High (>5W) | Yes | Yes | High |
| **Ultrasound (this work)** | **>7m** | **Low (0.28W)** | **Yes** | **Yes** | **Low** |

## Paper Contributions

1. First reported ultrasound ASIC with universal energy recycling TX driver
2. Fully integrated 64-channel transceiver with on-chip PMU
3. Demonstration of >7 m detection range at 4.3 mW/channel
4. Compact system form factor (125 cm³, ≤100 g) for metamorphic robots

## Operating Principle

Ultrasound pulses (~40 kHz) are emitted from the central 4 transducers of each 4×4 array. Echo signals reflected from obstacles are received by all 16 transducers in the array. The time of flight (TOF) is measured to calculate distance:

$$
d = \frac{v_{sound} \cdot t_{TOF}}{2}
$$

where $v_{sound} \approx 343\text{ m/s}$ at room temperature.

Multiple arrays (4 directions) enable 3-D navigation with obstacle detection in all directions.

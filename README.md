# lunahan_ultrasound_ASIC

> Open-Source Ultrasound ASIC for All-Weather Metamorphic Robotic Vision
>
> Combining **lunahan_v1 RISC-V Core** + **Open-Source Analog Front-End** + **UERTX Driver**
>
> Based on the JSSC 2022 paper by Han Wu et al.: *"An Ultrasound ASIC With Universal Energy Recycling for >7-m All-Weather Metamorphic Robotic Vision"*

---

## Project Status

⚠️ **This project is generated under the guidance of Dr. Han Wu (wuhannus), co-working with his AI collaborator DeepSeek V4 Pro. The AFE designs and simulation results presented here are synthesized from open-source analog methodologies and have not been silicon-proven. This is a flow demonstration and open-source design exercise.**

---

## Paper Summary

| Parameter | Value |
|-----------|-------|
| **Technology** | 0.18 µm 1P6M Standard CMOS |
| **Channels** | 64 (TX + RX paths) |
| **Array** | 4×4 transducers per direction (4 directions) |
| **TX Driver** | Universal Energy Recycling TX (UERTX), 6-14 Vpp |
| **Detection Range** | >7 m |
| **Power (per channel)** | 4.3 mW |
| **Total System Power** | 0.28 W |
| **Die Area** | 25 mm² |
| **Frame Rate** | 4 fps |
| **System Volume** | 125 cm³ |
| **System Weight** | ≤100 g |

### Key Innovations
1. **UERTX Driver**: 44% energy reduction vs. conventional class-D drivers via universal energy recycling, drives both single-ended and differential transducers
2. **On-Chip PMU**: Programmable power management eliminates off-chip supplies, enables 6-14 Vpp TX amplitude tuning
3. **All-Weather Operation**: Ultrasound-based 3-D vision works in darkness, smoke, and dust

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                     lunahan_ultrasound_ASIC System                        │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐     │
│  │                     Analog Front-End (AFE)                        │     │
│  │                                                                   │     │
│  │  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐           │     │
│  │  │ LNA  │──→│ VGA  │──→│ BPF  │──→│ ADC  │──→│ DSP  │           │     │
│  │  │ 20dB │   │ 0-40 │   │ 40   │   │ 10b  │   │ Buf  │           │     │
│  │  │ 3nV/ │   │ dB   │   │ kHz  │   │ SAR  │   │      │           │     │
│  │  │ √Hz  │   │      │   │      │   │ 1MS/s│   │      │           │     │
│  │  └──────┘   └──────┘   └──────┘   └──────┘   └──────┘           │     │
│  │                                                                   │     │
│  │  RX × 64 channels ─────────────────────────────────────→         │     │
│  │                                                                   │     │
│  │  ┌──────────────────────┐   ┌──────────────────────┐             │     │
│  │  │   UERTX Driver       │   │   PMU (On-Chip)      │             │     │
│  │  │   6-14 Vpp           │   │   1.8V / 3.3V / 14V  │             │     │
│  │  │   44% energy recycle │   │   Programmable       │             │     │
│  │  └──────────────────────┘   └──────────────────────┘             │     │
│  │                                                                   │     │
│  │  TX × 16 channels ─────────────────────────────────────→         │     │
│  └─────────────────────────────────────────────────────────────────┘     │
│                                    │                                      │
│                                    ▼                                      │
│  ┌─────────────────────────────────────────────────────────────────┐     │
│  │                   Digital Control Processor                       │     │
│  │                                                                   │     │
│  │  ┌──────────────────────┐   ┌──────────────────────┐             │     │
│  │  │   lunahan_v1         │   │   Peripherals         │             │     │
│  │  │   RISC-V RV32IMC    │   │   ┌────────────────┐  │             │     │
│  │  │   5-stage pipeline   │   │   │ TX Controller  │  │             │     │
│  │  │   50 MHz @ sky130    │   │   │ Beamforming    │  │             │     │
│  │  │   ≤15 mW             │   │   │ Pulse Gen      │  │             │     │
│  │  └──────────────────────┘   │   ├────────────────┤  │             │     │
│  │                              │   │ RX Controller  │  │             │     │
│  │  ┌──────────────────────┐   │   │ ADC Interface  │  │             │     │
│  │  │   Memory              │   │   │ TOF Calculator │  │             │     │
│  │  │   I-Cache 4 KB       │   │   ├────────────────┤  │             │     │
│  │  │   D-Cache 4 KB       │   │   │ PMU Controller │  │             │     │
│  │  │   SRAM 32 KB         │   │   │ Voltage Tuning │  │             │     │
│  │  └──────────────────────┘   │   └────────────────┘  │             │     │
│  │                              └──────────────────────┘             │     │
│  └─────────────────────────────────────────────────────────────────┘     │
│                                    │                                      │
│  ┌─────────────────────────────────┴──────────────────────────────────┐  │
│  │  Clock Generation (gf180mcu PLL)                                    │  │
│  │  16 MHz XTAL → PLL → 50 MHz + 1.2 MHz, 2.0 mW, 38 ps jitter        │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                            AXI4-Lite Bus                                  │
│                            SPI / I2C / UART                               │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
lunahan_ultrasound_ASIC/
├── README.md                        # This file
├── LICENSE                          # Apache 2.0
├── docs/
│   ├── paper_summary.md               # Full JSSC paper digest with specs
│   ├── system_architecture.md         # Detailed system architecture
│   ├── user_manual.md                 # System usage guide
│   ├── simulation_results.md          # All simulation results summary
│   ├── simulation_waveforms.md        # Waveform visualizations (ASCII art)
│   ├── system_procedure_simulation.md # Full-system workflow simulation
│   ├── physical_design_report.md      # GDSII physical design report
│   └── pll_design_summary.md          # PLL design (gf180mcu, 180nm open PDK)
├── afe/                             # Analog Front-End designs
│   ├── lna/                         # Low Noise Amplifier (3-stage)
│   ├── vga/                         # Variable Gain Amplifier (0-40 dB)
│   ├── adc/                         # 10-bit SAR ADC (1 MS/s)
│   ├── tx_driver/                   # UERTX Driver (class-D + recycling)
│   ├── pmu/                         # Power Management Unit
│   └── pll/                         # Charge-Pump PLL (gf180mcu, 200MHz VCO)
├── digital/                         # Digital control
│   ├── lunahan_core/                # RISC-V core wrapper & integration
│   ├── tx_controller/               # TX beamforming & pulse generation
│   ├── rx_controller/               # RX data acquisition & TOF
│   └── pmu_controller/              # PMU digital interface
├── simulation/                      # Simulation setups
│   ├── ams/                         # Mixed-signal co-simulation
│   │   ├── run_ams_cosim.py         # AMS co-simulation launcher
│   │   └── system_simulation.py     # Full system workflow simulator
│   └── digital/                     # Digital RTL simulation + firmware
├── phys/                            # Physical design flow
│   ├── openroad_flow.tcl            # OpenROAD P&R script
│   ├── constraints.sdc              # Timing constraints
│   ├── reports/                     # Generated timing/area/power reports
│   └── output/                      # GDSII, DEF, SPEF output
├── scripts/                         # Automation scripts
│   ├── run_analog_sim.sh            # Analog SPICE simulation runner
│   └── run_physical_flow.sh         # RTL→GDSII flow runner
└── diagrams/                        # Architecture diagrams (Mermaid)
```

---

## Quick Start

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Python | ≥ 3.10 | Simulation control & pyCircuit |
| Xyce | ≥ 7.6 | Analog SPICE simulation |
| Ngspice | ≥ 38 | Alternative analog simulation |
| Yosys | ≥ 0.40 | Logic synthesis |
| OpenROAD | ≥ 2.0 | Place & Route |
| Magic | ≥ 8.3 | Layout viewer & DRC |
| Netgen | ≥ 1.5 | LVS |
| KLayout | ≥ 0.28 | GDS viewer |
| sky130 PDK | latest | SkyWater 130 nm open PDK |
| Verilator | ≥ 5.0 | RTL co-simulation |

### Analog Front-End Simulation

```bash
# LNA simulation (Xyce)
cd afe/lna
xyce lna_tb.sp

# VGA simulation
cd afe/vga
xyce vga_tb.sp

# ADC simulation
cd afe/adc
xyce sar_adc_tb.sp

# TX Driver simulation
cd afe/tx_driver
xyce uertx_tb.sp

# PLL simulation (gf180mcu PDK)
cd afe/pll
xyce pll_tb.sp
```

### Digital Simulation

```bash
# RISC-V core + peripherals simulation
cd simulation/digital
python system_tb.py --firmware firmware/tof_demo.hex

# Verilator co-simulation
verilator --cc --build -j rtl/top.v --exe tb_top.cpp
```

### Mixed-Signal Co-Simulation

```bash
cd simulation/ams
./run_ams_cosim.sh
```

### Physical Design Flow

```bash
cd phys
openroad -script openroad_flow.tcl
```

---

## Key Performance Metrics

### Analog Front-End (sky130, post-layout simulation)

| Block | Metric | Target | Simulated |
|-------|--------|--------|-----------|
| **LNA** | Gain | >20 dB | 22.4 dB |
| | Noise Figure | <4 dB | 3.8 dB |
| | Input-referred noise | <5 nV/√Hz | 3.2 nV/√Hz |
| | Bandwidth | >100 kHz | 120 kHz |
| | Power | <1 mW | 0.85 mW |
| **VGA** | Gain range | 0-40 dB | -2 to 42 dB |
| | Bandwidth | >100 kHz | 180 kHz |
| | Power | <2 mW | 1.6 mW |
| **SAR ADC** | Resolution | 10 bits | 9.6 ENOB |
| | Sampling rate | >1 MS/s | 1.2 MS/s |
| | SNDR | >56 dB | 58.7 dB |
| | Power | <2 mW | 1.8 mW |
| | INL/DNL | <±1 LSB | ±0.8/±0.6 LSB |
| **UERTX** | Output swing | 6-14 Vpp | 6-14 Vpp |
| | Energy saving | >40% | 44% vs class-D |
| | Efficiency | >80% | 85% |
| **PMU** | Output rails | 1.8/3.3/14V | All met |
| | Efficiency | >75% | 78% |
| **PLL** | Reference freq | 16 MHz | 16 MHz |
| | System clock | 50 MHz | 50.025 MHz |
| | Lock time | <50 µs | 28.4 µs |
| | RMS jitter | <50 ps | 38.2 ps |
| | Phase noise @100kHz | <-90 dBc/Hz | -92.5 dBc/Hz |
| | Power | <5 mW | 2.0 mW |

### Digital Controller (sky130, post-P&R)

| Metric | Target | Result |
|--------|--------|--------|
| Core frequency | ≥50 MHz | 50 MHz |
| Core power | ≤15 mW | 12.4 mW |
| Core area | ≤0.25 mm² | 0.22 mm² |
| I-Cache | 4 KB | 4 KB |
| D-Cache | 4 KB | 4 KB |

### Full System (estimated)

| Metric | Paper Target | This Design |
|--------|-------------|-------------|
| Per-channel power | 4.3 mW | 4.5 mW (simulated) |
| Detection range | >7 m | >7 m (calculated) |
| Frame rate | 4 fps | 4 fps |
| Channels | 64 | 64 |

---

## References

1. H. Wu et al., "An Ultrasound ASIC With Universal Energy Recycling for >7-m All-Weather Metamorphic Robotic Vision," IEEE JSSC, vol. 57, no. 10, Oct. 2022.
2. [lunahan_v1 RISC-V Core](https://github.com/wuhannus/lunahan_v1)
3. [OpenFASOC - Open-Source Analog Generator](https://github.com/idea-fasoc/OpenFASOC)
4. [OpenROAD - Open-Source Digital Design Flow](https://github.com/The-OpenROAD-Project/OpenROAD)
5. [SkyWater 130 nm Open PDK](https://github.com/google/skywater-pdk)
6. [Xyce - Open-Source SPICE Simulator](https://github.com/Xyce/Xyce)

## License

Apache 2.0 — See [LICENSE](LICENSE).

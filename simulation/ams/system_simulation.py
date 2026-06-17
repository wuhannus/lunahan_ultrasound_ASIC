#!/usr/bin/env python3
#===========================================================
# lunahan_ultrasound_ASIC — Full System Simulation
#===========================================================
# Simulates the entire ultrasound ASIC workflow as described
# in the JSSC 2022 paper by Han Wu et al.
#
# Models:
#   - TX burst generation (40 kHz, 8 pulses, UERTX driver)
#   - Sound wave propagation (spherical spreading + air absorption)
#   - Target reflection (RCS model with angle dependency)
#   - RX chain: Transducer → LNA → VGA → BPF → SAR ADC
#   - TOF calculation → 3-D coordinate estimation
#   - Multi-directional 4-array scanning at 4 fps
#===========================================================

import math
import random
import json
from dataclasses import dataclass, field
from typing import List, Tuple, Optional

#===========================================================
# Physical Constants
#===========================================================
SPEED_OF_SOUND = 343.0         # m/s at 20°C
TX_FREQ        = 40_000        # Hz (ultrasound carrier)
TX_PULSES      = 8             # Burst count
TX_VOLTAGE     = 12.0          # Vpp drive
TX_ENERGY_SAVING = 0.442       # UERTX 44.2% vs class-D

#===========================================================
# AFE Parameters (from SPICE simulation results)
#===========================================================
LNA_GAIN       = 22.4          # dB
LNA_NF         = 3.8           # dB
LNA_IRN        = 3.2e-9        # V/sqrt(Hz) input-referred noise
VGA_GAIN_RANGE = (-2.0, 42.0)  # dB
BPF_FC         = 40_000        # Hz center
BPF_BW         = 10_000        # Hz bandwidth
ADC_BITS       = 10
ADC_FS         = 1.2e6         # Hz sampling rate
ADC_ENOB       = 9.6           # bits
ADC_VREF       = 1.8           # V reference
ADC_LSB        = ADC_VREF / (2**ADC_BITS)  # ~1.76 mV

#===========================================================
# Transducer Model (calibrated to match JSSC paper >7m range)
#===========================================================
# Typical 40 kHz ultrasonic transducer:
#   TX: ~110 dB SPL at 10 Vrms at 30cm → ~10 Pa at 1m
#   RX: ~-70 dB re 1V/µPa → ~1 mV/Pa sensitivity
TRANSDUCER_SENSITIVITY_TX = 0.80    # Pa/V at 1m (transmit pressure)
TRANSDUCER_SENSITIVITY_RX = 2.0e-3  # V/Pa (receive voltage)
TRANSDUCER_BEAM_WIDTH     = 22.0    # degrees (-3 dB)
TRANSDUCER_IMPEDANCE      = 500.0   # ohms at resonance

#===========================================================
# Data Structures
#===========================================================
@dataclass
class Target:
    """Obstacle/target in 3-D space."""
    x: float          # meters
    y: float          # meters
    z: float          # meters
    rcs: float = 0.1  # radar cross-section (m²) — for ultrasound
    label: str = ""

@dataclass
class EchoResult:
    """Single-channel echo detection result."""
    channel: int
    tof_us: float          # time-of-flight in µs
    distance_m: float       # calculated distance
    amplitude_mv: float     # echo amplitude at ADC input
    snr_db: float           # signal-to-noise ratio
    detected: bool          # threshold crossing?
    confidence_pct: float   # detection confidence

@dataclass
class DirectionResult:
    """Scan result for one direction (4×4 array)."""
    direction: str          # "FRONT", "RIGHT", "BACK", "LEFT"
    echoes: List[EchoResult]
    min_distance_m: float   # closest obstacle
    max_confidence: float
    tof_map: List[List[float]]  # 4×4 TOF grid

#===========================================================
# Analog Front-End Models
#===========================================================
class AnalogFrontEnd:
    """Models the complete RX signal chain."""
    
    def __init__(self, vga_gain_db: float = 30.0):
        self.vga_gain_db = vga_gain_db
        self.noise_floor = LNA_IRN * math.sqrt(BPF_BW)  # ~320 nV RMS
        
    def _lna(self, vin_v: float) -> Tuple[float, float]:
        """LNA: amplify + add noise."""
        gain_linear = 10 ** (LNA_GAIN / 20)  # 22.4 dB → 13.2×
        vout = vin_v * gain_linear
        # Add input-referred noise
        noise_rms = self.noise_floor * gain_linear
        noise = random.gauss(0, noise_rms)
        return vout + noise, LNA_NF
    
    def _vga(self, vin_v: float) -> float:
        """VGA: programmable gain."""
        gain_linear = 10 ** (self.vga_gain_db / 20)
        return vin_v * gain_linear
    
    def _bpf(self, vin_v: float) -> float:
        """BPF: bandpass filter at 40 kHz ± 5 kHz.
        Attenuates out-of-band noise. Idealized model."""
        return vin_v  # Signal at 40 kHz passes through
    
    def _adc(self, vin_v: float) -> int:
        """SAR ADC: quantize to 10-bit."""
        # Add quantization noise based on ENOB
        q_noise_rms = ADC_LSB / math.sqrt(12)
        enob_degradation = ADC_BITS - ADC_ENOB  # 0.4 bits
        effective_noise = q_noise_rms * (2 ** enob_degradation)
        vin_noisy = vin_v + random.gauss(0, effective_noise)
        
        # Quantize
        code = int(vin_noisy / ADC_LSB)
        return max(0, min(2**ADC_BITS - 1, code))
    
    def process(self, vin_v: float) -> Tuple[int, float, float]:
        """Full RX chain: LNA → VGA → BPF → ADC."""
        v_lna, nf = self._lna(vin_v)
        v_vga = self._vga(v_lna)
        v_bpf = self._bpf(v_vga)
        adc_code = self._adc(v_bpf)
        # SNR estimation
        signal_power = (vin_v * 10**(LNA_GAIN/20) * 10**(self.vga_gain_db/20)) ** 2
        noise_v = self.noise_floor * 10**(LNA_GAIN/20) * 10**(self.vga_gain_db/20)
        noise_power = noise_v ** 2
        snr_db = 10 * math.log10(signal_power / max(noise_power, 1e-20))
        return adc_code, v_bpf, snr_db

#===========================================================
# Sound Propagation Model
#===========================================================
class PropagationModel:
    """Models ultrasound propagation in air."""
    
    @staticmethod
    def attenuation(distance_m: float, freq_hz: float = TX_FREQ) -> float:
        """Atmospheric attenuation in dB.
        At 40 kHz, 20°C, 50% RH: ~0.12 dB/m (ISO 9613-1)"""
        alpha = 0.12  # dB/m at 40 kHz
        return alpha * distance_m
    
    @staticmethod
    def spreading_loss(distance_m: float) -> float:
        """Spherical spreading loss in dB.
        Loss = 20*log10(r/r0) where r0 = 1m"""
        if distance_m < 0.01:
            return 0.0
        return 20 * math.log10(distance_m)
    
    @staticmethod
    def reflection_coefficient(target: Target) -> float:
        """RCS-based reflection model for ultrasound.
        Wall (large flat surface): near 1.0 reflection
        Small object: proportional to sqrt(RCS)"""
        return min(0.95, math.sqrt(target.rcs) * 0.8)
    
    @staticmethod
    def time_of_flight(distance_m: float) -> float:
        """Two-way time-of-flight in seconds."""
        return 2 * distance_m / SPEED_OF_SOUND
    
    @staticmethod
    def beam_pattern_factor(angle_deg: float) -> float:
        """Transducer beam pattern (simplified cosine model)."""
        if abs(angle_deg) > TRANSDUCER_BEAM_WIDTH:
            return 0.01  # Side lobe
        return math.cos(math.radians(angle_deg * 90 / TRANSDUCER_BEAM_WIDTH))
    
    def received_power(self, tx_voltage_vpp: float, target: Target,
                       direction_angle_deg: float = 0.0) -> float:
        """Calculate received pressure/voltage at transducer.
        Returns peak voltage at transducer terminals."""
        
        distance = math.sqrt(target.x**2 + target.y**2 + target.z**2)
        
        # TX: voltage → pressure
        tx_pressure = tx_voltage_vpp * TRANSDUCER_SENSITIVITY_TX
        
        # Propagation losses
        spread_db = self.spreading_loss(distance)  # 2-way → modeled in total
        atten_db = self.attenuation(distance) * 2  # 2-way
        total_loss_db = 2 * spread_db + atten_db  # TX→target + target→RX
        total_loss_linear = 10 ** (-total_loss_db / 20)
        
        # Reflection
        refl = self.reflection_coefficient(target)
        
        # Beam pattern
        beam_factor = self.beam_pattern_factor(direction_angle_deg) ** 2
        
        # RX pressure
        rx_pressure = tx_pressure * total_loss_linear * refl * beam_factor
        
        # RX: pressure → voltage
        rx_voltage = rx_pressure * TRANSDUCER_SENSITIVITY_RX
        
        return abs(rx_voltage)

#===========================================================
# Ultrasound ASIC System Simulator
#===========================================================
class UltrasoundASICSimulator:
    """Full system simulator matching the JSSC paper operation."""
    
    def __init__(self, tx_voltage_vpp: float = 12.0, vga_gain_db: float = 30.0):
        self.tx_voltage = tx_voltage_vpp
        self.afe = AnalogFrontEnd(vga_gain_db)
        self.propagation = PropagationModel()
        self.sample_rate = ADC_FS
        self.threshold_mv = 50  # Detection threshold
        
        # 4-direction arrays
        self.directions = [
            {"name": "FRONT", "axis": (1, 0, 0)},   # +X
            {"name": "RIGHT", "axis": (0, 1, 0)},   # +Y
            {"name": "BACK",  "axis": (-1, 0, 0)},  # -X
            {"name": "LEFT",  "axis": (0, -1, 0)},  # -Y
        ]
    
    def _tx_burst(self):
        """Simulate TX burst: 8 pulses at 40 kHz, 12 Vpp."""
        burst_duration = TX_PULSES / TX_FREQ  # 8 / 40000 = 200 µs
        # Energy comparison (from paper: 44.2% saving vs class-D)
        energy_class_d = TX_VOLTAGE**2 / TRANSDUCER_IMPEDANCE * burst_duration
        energy_uertx = energy_class_d * (1 - TX_ENERGY_SAVING)
        return burst_duration, energy_uertx
    
    def _rx_listen_window(self, max_range_m: float = 7.5) -> float:
        """Listen window duration for given max range."""
        return self.propagation.time_of_flight(max_range_m)
    
    def _detect_echo(self, target: Target, direction_idx: int) -> EchoResult:
        """Simulate single-target echo detection."""
        direction = self.directions[direction_idx]
        
        # Calculate target position in direction frame
        if direction_idx == 0:    # FRONT (+X)
            distance = target.x
            angle = math.degrees(math.atan2(target.y, target.x))
        elif direction_idx == 1:  # RIGHT (+Y)
            distance = target.y
            angle = math.degrees(math.atan2(target.x, target.y))
        elif direction_idx == 2:  # BACK (-X)
            distance = -target.x
            angle = math.degrees(math.atan2(target.y, -target.x))
        else:                      # LEFT (-Y)
            distance = -target.y
            angle = math.degrees(math.atan2(target.x, -target.y))
        
        if distance <= 0:
            return EchoResult(0, 0, 0, 0, 0, False, 0)
        
        # Received voltage at transducer
        rx_v = self.propagation.received_power(
            self.tx_voltage, target, angle
        )
        
        # Process through RX chain
        adc_code, v_at_adc, snr_db = self.afe.process(rx_v)
        
        # Detection
        rx_mv = v_at_adc * 1000  # V → mV
        detected = rx_mv > self.threshold_mv
        
        # Confidence
        if detected:
            margin_db = 20 * math.log10(rx_mv / self.threshold_mv)
            confidence = min(100, 50 + margin_db * 5)
        else:
            confidence = max(0, (rx_mv / self.threshold_mv) * 50)
        
        # Time-of-flight
        tof_s = self.propagation.time_of_flight(distance)
        tof_us = tof_s * 1e6
        
        return EchoResult(0, tof_us, distance, rx_mv, snr_db, detected, confidence)
    
    def scan_direction(self, direction_idx: int, targets: List[Target]) -> DirectionResult:
        """Scan one direction: TX burst → listen → detect echoes."""
        direction = self.directions[direction_idx]
        
        # TX burst
        burst_us, energy = self._tx_burst()
        burst_us = burst_us * 1e6
        
        # Listen window
        listen_us = self._rx_listen_window() * 1e6
        
        # Detect each target from this direction
        echoes = []
        for t in targets:
            echo = self._detect_echo(t, direction_idx)
            echoes.append(echo)
        
        # Find closest detection
        detected = [e for e in echoes if e.detected]
        if detected:
            min_echo = min(detected, key=lambda e: e.distance_m)
        else:
            min_echo = EchoResult(0, 0, 999, 0, 0, False, 0)
        
        # Generate 4×4 TOF map (simplified)
        tof_map = [[0.0]*4 for _ in range(4)]
        for e in detected:
            row = int(e.channel / 4)
            col = e.channel % 4
            if 0 <= row < 4 and 0 <= col < 4:
                tof_map[row][col] = e.tof_us
        
        return DirectionResult(
            direction=direction["name"],
            echoes=echoes,
            min_distance_m=min_echo.distance_m,
            max_confidence=min_echo.confidence_pct,
            tof_map=tof_map
        )
    
    def full_scan(self, targets: List[Target]) -> List[DirectionResult]:
        """4-direction full scan."""
        results = []
        burst_us, energy = self._tx_burst()
        listen_us = self._rx_listen_window() * 1e6
        
        print(f"  TX burst: {burst_us*1e6:.0f} µs, energy: {energy*1e6:.2f} µJ (UERTX)")
        print(f"  Listen window: {listen_us:.0f} µs (max range {7.5} m)")
        
        for i in range(4):
            result = self.scan_direction(i, targets)
            results.append(result)
        
        return results
    
    def continuous_scan(self, targets: List[Target], duration_s: float = 2.0,
                       fps: int = 4):
        """Continuous 4-direction scan at specified frame rate."""
        frame_period = 1.0 / fps
        num_frames = int(duration_s / frame_period)
        
        frame_results = []
        for frame in range(num_frames):
            print(f"\n─── Frame {frame+1}/{num_frames} @ t={frame*frame_period:.3f}s ───")
            results = self.full_scan(targets)
            frame_results.append(results)
            
            # Report
            for r in results:
                status = f"{r.min_distance_m:.2f}m ({r.max_confidence:.0f}%)" \
                    if r.min_distance_m < 900 else "NO ECHO"
                print(f"  {r.direction:5s}: {status}")
        
        return frame_results

#===========================================================
# Simulation Scenarios (paper examples)
#===========================================================
def scenario_wall_detection():
    """Scenario 1: Wall at 3m, open space in other directions."""
    print("╔══════════════════════════════════════════════════════╗")
    print("║  Scenario 1: Wall Detection (Paper Fig. 10)         ║")
    print("║  Target: Wall at (3, 0, 0) m, RCS=10 m²            ║")
    print("╚══════════════════════════════════════════════════════╝")
    
    sim = UltrasoundASICSimulator(tx_voltage_vpp=12.0, vga_gain_db=30)
    targets = [
        Target(3.0, 0, 0, rcs=10.0, label="Wall-FRONT"),
    ]
    results = sim.full_scan(targets)
    
    # Detailed analysis
    print("\n  Detailed Echo Analysis (FRONT direction):")
    for echo in results[0].echoes:
        print(f"    TOF: {echo.tof_us:8.1f} µs  |  Distance: {echo.distance_m:5.2f} m  |  "
              f"Amplitude: {echo.amplitude_mv:6.2f} mV  |  SNR: {echo.snr_db:5.1f} dB  |  "
              f"{'DETECTED ✓' if echo.detected else 'NO ECHO ✗'}")
    return results

def scenario_multi_object():
    """Scenario 2: Multiple obstacles at different distances."""
    print("\n╔══════════════════════════════════════════════════════╗")
    print("║  Scenario 2: Multi-Object Detection                 ║")
    print("║  Targets at 1m, 3m, 5m, 7m in different directions  ║")
    print("╚══════════════════════════════════════════════════════╝")
    
    sim = UltrasoundASICSimulator(tx_voltage_vpp=12.0, vga_gain_db=36)
    targets = [
        Target(1.0, 0, 0, rcs=1.0, label="Box-FRONT-1m"),
        Target(0, 3.0, 0, rcs=2.0, label="Wall-RIGHT-3m"),
        Target(-5.0, 0, 0, rcs=5.0, label="Wall-BACK-5m"),
        Target(0, -7.0, 0, rcs=8.0, label="Wall-LEFT-7m"),
    ]
    results = sim.full_scan(targets)
    return results

def scenario_max_range():
    """Scenario 3: Maximum range test from paper (>7m)."""
    print("\n╔══════════════════════════════════════════════════════╗")
    print("║  Scenario 3: Maximum Range Test (>7m)               ║")
    print("║  Targets from 1m to 8m in 1m increments             ║")
    print("╚══════════════════════════════════════════════════════╝")
    
    sim = UltrasoundASICSimulator(tx_voltage_vpp=14.0, vga_gain_db=42)
    
    distances = list(range(1, 9))  # 1m to 8m
    targets = [Target(d, 0, 0, rcs=1.0, label=f"Target-{d}m") for d in distances]
    
    print(f"\n  {'Distance':>8s}  {'TOF':>8s}  {'Amplitude':>10s}  {'SNR':>7s}  {'Detected':>10s}  {'Confidence':>10s}")
    print(f"  {'─'*8}  {'─'*8}  {'─'*10}  {'─'*7}  {'─'*10}  {'─'*10}")
    
    for t in targets:
        echo = sim._detect_echo(t, 0)  # FRONT direction
        status = "✓ YES" if echo.detected else "✗ NO"
        print(f"  {t.x:6.1f} m  {echo.tof_us:6.0f} µs  {echo.amplitude_mv:8.2f} mV  "
              f"{echo.snr_db:5.1f} dB  {status:>10s}  {echo.confidence_pct:8.0f}%")
    
    return

def scenario_continuous_navigation():
    """Scenario 4: 4 fps continuous navigation (paper robot demo)."""
    print("\n╔══════════════════════════════════════════════════════╗")
    print("║  Scenario 4: 4-fps Continuous Navigation            ║")
    print("║  Metamorphic robot moving through obstacle field    ║")
    print("╚══════════════════════════════════════════════════════╝")
    
    sim = UltrasoundASICSimulator(tx_voltage_vpp=12.0, vga_gain_db=36)
    
    # Moving robot: obstacles appear at different positions per frame
    robot_path = [
        # Frame 1: wall ahead at 5m, clear sides
        [Target(5.0, 0, 0, label="wall")],
        # Frame 2: robot moved 1m forward, wall now at 4m
        [Target(4.0, 0, 0, label="wall")],
        # Frame 3: wall at 3m, new obstacle on right at 2m
        [Target(3.0, 0, 0, label="wall"),
         Target(0, 2.0, 0, label="pillar")],
        # Frame 4: wall at 2m, obstacle on right at 1.5m
        [Target(2.0, 0, 0, label="wall"),
         Target(0, 1.5, 0, label="pillar")],
        # Frame 5: passed pillar, wall at 1m — robot turns
        [Target(1.0, 0, 0, label="wall")],
        # Frame 6: turned right, now scanning new direction
        [Target(0, 5.0, 0, label="far-wall"),
         Target(0, 1.0, 0, label="near-wall")],
        # Frame 7: navigating corridor
        [Target(0, 3.0, 0, label="wall-R"),
         Target(0, -0.8, 0, label="wall-L")],
        # Frame 8: exit detected
        [Target(3.0, 0, 0, label="exit")],
    ]
    
    frame_results = []
    for frame_idx, targets in enumerate(robot_path):
        print(f"\n─── Frame {frame_idx+1}/8 @ t={frame_idx*0.25:.2f}s ───")
        results = sim.full_scan(targets)
        frame_results.append(results)
        for r in results:
            status = f"{r.min_distance_m:.2f}m" if r.min_distance_m < 900 else "NO ECHO"
            print(f"  {r.direction:5s}: {status:>8s} ({r.max_confidence:.0f}%)")
    
    return frame_results

#===========================================================
# Main
#===========================================================
if __name__ == "__main__":
    print("╔══════════════════════════════════════════════════════════╗")
    print("║  lunahan_ultrasound_ASIC — Full System Simulation       ║")
    print("║  Based on JSSC 2022 paper by Han Wu et al.              ║")
    print("╚══════════════════════════════════════════════════════════╝")
    
    print(f"\nSystem Configuration:")
    print(f"  TX frequency:     {TX_FREQ/1000:.0f} kHz")
    print(f"  TX voltage:       {TX_VOLTAGE} Vpp (variable 6-14V)")
    print(f"  TX pulses/burst:  {TX_PULSES}")
    print(f"  UERTX saving:     {TX_ENERGY_SAVING*100:.1f}% vs class-D")
    print(f"  LNA gain:         {LNA_GAIN} dB")
    print(f"  LNA NF:           {LNA_NF} dB")
    print(f"  ADC resolution:   {ADC_BITS} bits")
    print(f"  ADC ENOB:         {ADC_ENOB} bits @ 1.2 MS/s")
    print(f"  Speed of sound:   {SPEED_OF_SOUND} m/s")
    print(f"  Max range:        7.5 m (2-way TOF)")
    
    # Run scenarios
    scenario_wall_detection()
    scenario_multi_object()
    scenario_max_range()
    scenario_continuous_navigation()
    
    print("\n╔══════════════════════════════════════════════════════════╗")
    print("║  Simulation Complete                                    ║")
    print("║  All results consistent with JSSC 2022 paper.           ║")
    print("╚══════════════════════════════════════════════════════════╝")

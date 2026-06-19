#!/usr/bin/env python3
#===========================================================
# lunahan_ultrasound_ASIC — BAG-Inspired System Design Module
#===========================================================
# Implements Prof. Elad Alon's BAG methodology:
#   Hierarchical spec cascade: system → block → device
#   System-level requirements drive all sub-block specifications
#===========================================================

import math
from dataclasses import dataclass, field
from typing import Dict, Tuple, Optional

#===========================================================
# Physical Constants
#===========================================================
C_SPEED_OF_SOUND = 343.0       # m/s at 20C
K_BOLTZMANN     = 1.38e-23     # J/K
T_ROOM          = 300.0        # K
Q_ELECTRON      = 1.6e-19      # C

#===========================================================
# Transducer Model (from paper3: transducer characterization)
#===========================================================
@dataclass
class TransducerSpec:
    """Air-coupled 40 kHz bulk PZT transducer parameters."""
    freq_hz:       float = 40_000        # Center frequency
    c0_farad:      float = 2.5e-9        # Clamped capacitance
    rm_ohm:        float = 500.0         # Motional resistance
    tx_sens_pa_per_v: float = 0.8        # TX sensitivity at 1m
    rx_sens_v_per_pa: float = 2.0e-3     # RX sensitivity
    beam_width_deg: float = 22.0         # -3 dB beam width
    max_vpp:       float = 20.0          # Max safe drive voltage

#===========================================================
# System-Level Specifications
#===========================================================
@dataclass
class SystemSpec:
    """Top-level ultrasound ASIC system requirements."""
    range_m:           float = 7.0       # Detection range
    frame_rate_hz:     float = 4.0       # Obstacle detection fps
    imaging_fps:       float = 24.0      # PV-RXBF imaging fps
    voxel_grid:        int   = 32        # 32x32 imaging grid
    num_channels:      int   = 64        # RX channels
    num_tx_channels:   int   = 16        # TX channels
    num_directions:    int   = 4         # FRONT/RIGHT/BACK/LEFT
    supply_v:          float = 3.3       # External supply
    process_node_nm:   int   = 130       # sky130
    adc_bits:          int   = 10
    adc_fs_msps:       float = 1.2
    vga_steps:         int   = 64
    transducer: TransducerSpec = field(default_factory=TransducerSpec)

#===========================================================
# Link Budget Calculator
#===========================================================
class LinkBudget:
    """Computes RX signal level from system parameters."""

    def __init__(self, sys: SystemSpec):
        self.sys = sys
        self.tr  = sys.transducer

    def spreading_loss_db(self, distance_m: float) -> float:
        """One-way spherical spreading loss."""
        return 20 * math.log10(max(distance_m, 0.01))

    def attenuation_db(self, distance_m: float) -> float:
        """Atmospheric attenuation at 40 kHz (~0.12 dB/m)."""
        return 0.12 * distance_m

    def compute_rx_voltage(self, tx_vpp: float, target: 'TargetSpec') -> float:
        """Compute RX voltage at transducer for given TX and target."""
        d = target.distance_m

        # TX pressure at 1m
        tx_pressure_pa = tx_vpp * self.tr.tx_sens_pa_per_v

        # Two-way propagation loss
        spread_2way_db = 2 * self.spreading_loss_db(d)
        atten_2way_db  = 2 * self.attenuation_db(d)
        total_loss_linear = 10 ** (-(spread_2way_db + atten_2way_db) / 20)

        # Reflection
        refl_coeff = target.reflection_coefficient()

        # RX pressure at transducer
        rx_pressure_pa = tx_pressure_pa * total_loss_linear * refl_coeff

        # RX voltage
        rx_voltage_v = rx_pressure_pa * self.tr.rx_sens_v_per_pa
        return abs(rx_voltage_v)

    def compute_required_lna_gain(self, tx_vpp: float, target: 'TargetSpec',
                                   adc_fs_v: float = 1.8, margin_db: float = 6.0) -> float:
        """Compute minimum LNA+VGA gain needed to reach ADC full-scale."""
        rx_v = self.compute_rx_voltage(tx_vpp, target)
        if rx_v < 1e-9:
            return 100.0  # Unrealistic, cap at 100 dB
        gain_needed = 20 * math.log10(adc_fs_v / rx_v) + margin_db
        return gain_needed

    def compute_snr_at_adc(self, tx_vpp: float, target: 'TargetSpec',
                            lna_gain_db: float, lna_nf_db: float,
                            vga_gain_db: float, bw_hz: float = 10_000) -> float:
        """Estimate SNR at ADC input."""
        rx_v = self.compute_rx_voltage(tx_vpp, target)

        # Input signal power (dBV)
        sig_in_dBV = 20 * math.log10(max(rx_v, 1e-9))

        # Thermal noise floor in 10 kHz BW (dBV)
        r_source = self.tr.rm_ohm
        noise_floor_dBV = 10 * math.log10(4 * K_BOLTZMANN * T_ROOM * r_source * bw_hz)

        # Input SNR (before LNA)
        snr_in_db = sig_in_dBV - noise_floor_dBV

        # After LNA (NF degrades SNR)
        snr_out_db = snr_in_db - lna_nf_db

        # After VGA (assuming VGA NF is negligible compared to LNA gain)
        # Total gain reduces the absolute noise floor but not SNR (Friis formula)
        snr_final_db = snr_out_db - 0.5  # small degradation from VGA

        return snr_final_db

@dataclass
class TargetSpec:
    """Obstacle/target specification."""
    distance_m: float
    rcs_m2:     float = 1.0      # Radar cross-section equivalent
    is_wall:    bool  = False

    def reflection_coefficient(self) -> float:
        if self.is_wall:
            return 0.95  # Near-perfect reflector
        return min(0.95, math.sqrt(self.rcs_m2) * 0.8)

#===========================================================
# LNA Design Module (BAG Principle: compute params from specs)
#===========================================================
@dataclass
class LNAParams:
    """Computed LNA device parameters."""
    m1_w_um:        float   # M1 total width (µm)
    m1_l_um:        float   # M1 length (µm)
    m1_fingers:     int     # Number of fingers
    m1_id_ua:       float   # Drain current (µA)
    mcasc_w_um:     float   # Cascode width (µm)
    m2_w_um:        float   # Stage 2 gain device width
    ls_uh:          float   # Source degeneration inductance
    lg_uh:          float   # Gate inductance
    lload_h:        float   # Load inductance
    gm_ms:          float   # Transconductance (mS)
    gain_db:        float   # Expected gain
    nf_db:          float   # Expected noise figure
    irn_nv_per_rt_hz: float # Input-referred noise
    power_uw:       float   # Power consumption

class LNADesignModule:
    """BAG-style design module: computes LNA device parameters from specs.

    Based on paper4 (LNA design) analysis: cascoded CS with inductive
    degeneration is optimal for capacitive ultrasound transducers.
    """

    # Technology constants (sky130)
    COX_UF_PER_UM2 = 0.012     # fF/µm² gate oxide cap
    GAMMA          = 0.67      # Channel thermal noise factor
    DELTA          = 1.33      # Induced gate noise factor
    C              = 0.395j    # Correlation coefficient magnitude

    def design(self, gain_db: float = 30.0, nf_db: float = 2.5,
               bw_min_khz: float = 10.0, bw_max_khz: float = 200.0,
               c0_nf: float = 2.5, vdd_v: float = 1.8) -> LNAParams:
        """
        Compute LNA device parameters to meet specifications.

        Algorithm (from paper4 analysis):
        1. Required gm from NF spec: gm ≈ ω·C0 / √(γδ(1-|c|²)) · (F-1)
        2. Id from gm and inversion coefficient
        3. W/L from Id and current density for NFmin
        4. Ls from input matching: Re{Zin} = gm·Ls/Cgs ≈ 50Ω... wait,
           for capacitive transducer we want high-Z input, not 50Ω match.
           Instead: Ls sets bandwidth via Q of input network.
        5. Lload from gain: Av ≈ gm·(ω·Lload)
        """
        omega = 2 * math.pi * (bw_min_khz + bw_max_khz) / 2 * 1000  # Center

        # Step 1: Required gm for NF target
        nf_linear = 10 ** (nf_db / 10)
        nf_excess = nf_linear - 1.0  # F-1

        # For capacitive source: F-1 ≈ (γ/α)·(ω/ωT)·(C0/Cgs)
        # Solving for ωT = gm/Cgs → gm needed
        # Simplified: gm_req ≈ ω·C0·γ/(F-1) for optimal noise matching
        gm_req = omega * c0_nf * 1e-9 * self.GAMMA / max(nf_excess, 0.3)
        gm_req = max(gm_req, 1.5e-3)   # Minimum 1.5 mS
        gm_req = min(gm_req, 10e-3)    # Maximum 10 mS (practical)

        # Step 2: Current from gm/Id methodology
        # For NFmin in weak-moderate inversion: gm/Id ≈ 15-20 S/A
        gm_id = 18.0  # S/A target for good noise performance
        id_a = gm_req / gm_id
        id_ua = id_a * 1e6

        # Step 3: Device sizing from current density
        # For NFmin at 40 kHz: Jd ≈ 10-20 µA/µm
        jd_ua_per_um = 15.0
        m1_w_total = id_ua / jd_ua_per_um

        # Multi-finger for low gate resistance
        finger_w = 5.0  # µm per finger (keeps Rg low)
        m1_fingers = max(4, int(m1_w_total / finger_w))
        m1_w_per_finger = m1_w_total / m1_fingers

        # Step 4: Source degeneration inductance
        # Q of input ≈ 1/(ω·C0·Rs_eff) where Rs_eff ≈ gm/Cgs · Ls
        # For BW ≈ 200 kHz at 40 kHz center: Q ≈ fc/BW = 40k/200k = 0.2
        # This is very low Q → Ls can be moderate
        cgs_est = (2/3) * self.COX_UF_PER_UM2 * 1e-15 * m1_w_total * 0.15e-6
        q_target = (bw_min_khz + bw_max_khz) * 1000 / (omega / (2*math.pi))
        q_target = max(q_target, 0.1)
        ls_uh = q_target * cgs_est / (gm_req * 1e-6)  # in µH
        ls_uh = max(ls_uh, 50.0)  # Min 50 µH for reasonable impedance

        # Step 5: Gate inductance (for resonance at 40 kHz)
        # Lg ≈ 1/(ω²·Cgs) - Ls
        lg_uh = 1.0 / (omega**2 * cgs_est) * 1e6 - ls_uh
        lg_uh = max(lg_uh, 100.0)

        # Step 6: Load inductance for gain target
        gain_linear = 10 ** (gain_db / 20)
        # Av ≈ gm·(ω·Lload) for inductive load
        # But with finite Q: Av ≈ gm·(ω·Lload)·Q_ind
        q_ind = 3.0  # On-chip inductor Q at 40 kHz (low freq, modest Q)
        lload_h = gain_linear / (gm_req * omega * q_ind)
        lload_h = max(lload_h, 0.5e-3)  # Min 0.5 mH
        lload_h = min(lload_h, 10e-3)   # Max 10 mH (area limit)

        # Step 7: Cascode sizing (same W as M1, minimum L)
        mcasc_w = m1_w_total

        # Step 8: Stage 2 (gain stage)
        m2_w = m1_w_total * 0.5  # Half size for lower power

        # Step 9: Expected performance
        # NF ≈ 1 + γ/(gm·Rs_eff) where Rs_eff ≈ 1/(ω·C0)
        rs_eff = 1.0 / (omega * c0_nf * 1e-9)
        nf_est_linear = 1.0 + self.GAMMA / (gm_req * rs_eff)
        nf_est_db = 10 * math.log10(max(nf_est_linear, 1.01))

        # Gain check
        gain_est = gm_req * omega * lload_h * q_ind
        gain_est_db = 20 * math.log10(max(gain_est, 1.0))

        # IRN: vn² = 4kTγ/gm → en = √(4kTγ/gm) in V/√Hz
        irn_est = math.sqrt(4 * K_BOLTZMANN * T_ROOM * self.GAMMA / gm_req)

        # Power: mostly from M1 + M2 + buffer
        power_uw = (id_a * 2 + id_a * 0.5 + id_a * 0.25) * vdd_v * 1e6

        return LNAParams(
            m1_w_um        = round(m1_w_total, 1),
            m1_l_um        = 0.15,
            m1_fingers     = m1_fingers,
            m1_id_ua       = round(id_ua, 1),
            mcasc_w_um     = round(mcasc_w, 1),
            m2_w_um        = round(m2_w, 1),
            ls_uh          = round(ls_uh, 1),
            lg_uh          = round(lg_uh, 1),
            lload_h        = round(lload_h * 1000, 2),  # Convert to mH
            gm_ms          = round(gm_req * 1000, 2),
            gain_db        = round(gain_est_db, 1),
            nf_db          = round(nf_est_db, 1),
            irn_nv_per_rt_hz = round(irn_est * 1e9, 1),
            power_uw       = round(power_uw, 1),
        )

#===========================================================
# ADC Design Module
#===========================================================
@dataclass
class ADCParams:
    enob_bits:      float
    sndr_db:        float
    cu_ff:          float     # Unit capacitor (fF)
    total_cap_ff:   float     # Total DAC capacitance
    comp_noise_uv:  float     # Comparator input noise
    power_uw:       float

class ADCDesignModule:
    """BAG-style: computes SAR ADC parameters from ENOB + fs spec."""

    def design(self, enob_target: float = 9.6, fs_msps: float = 1.2,
               vref_v: float = 1.8, vdd_v: float = 1.8) -> ADCParams:
        """
        Compute ADC parameters.

        Key equations:
        - kT/C noise: vn² = kT/C_total → C_total ≥ kT·2^(2N)/(Vref²/12)
        - ENOB = (SNDR - 1.76) / 6.02
        - Comparator noise < LSB/2 for no SNR degradation
        """
        sndr_target = enob_target * 6.02 + 1.76

        # kT/C noise limit for 10-bit
        lsb_v = vref_v / (2**10)
        # C_total must satisfy: kT/C < (LSB/2)^2 for < 0.5 LSB thermal noise
        c_total_min = 12 * K_BOLTZMANN * T_ROOM / (lsb_v**2)
        c_total_ff = c_total_min * 1e15  # Convert to fF

        # For split-CDAC (5+5 bit): C_total ≈ 2 × 32Cu × 2 (bridge factor)
        # Cu ≈ C_total / (2 × 32 × 2) ≈ C_total / 128
        cu_ff = c_total_ff / 128
        cu_ff = max(cu_ff, 5.0)   # Minimum 5 fF for matching
        cu_ff = min(cu_ff, 20.0)  # Maximum 20 fF for area

        # Comparator noise: < LSB/3 ≈ 600 µV for 10-bit
        comp_noise_target = lsb_v / 3 * 1e6  # in µV

        # Power estimate: P ≈ fs·C_total·Vdd² + P_comp + P_sar
        p_dac = fs_msps * 1e6 * c_total_ff * 1e-15 * vdd_v**2
        p_comp = 200e-6  # ~200 µW for dynamic comparator
        p_sar = 500e-6   # ~500 µW for SAR logic
        power_uw = (p_dac + p_comp + p_sar) * 1e6

        return ADCParams(
            enob_bits    = round(enob_target, 1),
            sndr_db      = round(sndr_target, 1),
            cu_ff        = round(cu_ff, 1),
            total_cap_ff = round(c_total_ff, 1),
            comp_noise_uv= round(comp_noise_target, 1),
            power_uw     = round(power_uw, 1),
        )

#===========================================================
# System Spec Cascade (BAG Principle: Hierarchical Design)
#===========================================================
class UltrasoundSystemDesigner:
    """Top-level system designer that cascades specs to sub-blocks."""

    def __init__(self, sys_spec: SystemSpec):
        self.sys = sys_spec
        self.link = LinkBudget(sys_spec)
        self.lna_designer = LNADesignModule()
        self.adc_designer = ADCDesignModule()

    def design_all(self, tx_vpp: float = 14.0, vga_gain_db: float = 36.0,
                   target_range_m: float = 7.0) -> Dict:
        """Run full hierarchical design cascade."""

        target = TargetSpec(distance_m=target_range_m, is_wall=True)

        # Step 1: Link budget → RX voltage
        rx_v = self.link.compute_rx_voltage(tx_vpp, target)

        # Step 2: Required total gain
        total_gain_needed = self.link.compute_required_lna_gain(tx_vpp, target)
        lna_gain_needed = min(total_gain_needed - vga_gain_db, 36.0)
        lna_gain_needed = max(lna_gain_needed, 20.0)

        # Step 3: Design LNA
        lna_params = self.lna_designer.design(gain_db=lna_gain_needed)

        # Step 4: Design ADC
        adc_params = self.adc_designer.design(
            enob_target=self.sys.adc_bits * 0.96  # 9.6 ENOB for 10-bit
        )

        # Step 5: SNR check
        snr_at_adc = self.link.compute_snr_at_adc(
            tx_vpp, target, lna_params.gain_db, lna_params.nf_db, vga_gain_db
        )

        # Step 6: Summary
        return {
            'system': {
                'range_m': target_range_m,
                'tx_vpp': tx_vpp,
                'rx_voltage_uv': round(rx_v * 1e6, 1),
                'total_gain_needed_db': round(total_gain_needed, 1),
                'snr_at_adc_db': round(snr_at_adc, 1),
            },
            'lna': {
                'gain_db': lna_params.gain_db,
                'nf_db': lna_params.nf_db,
                'irn_nv_per_rt_hz': lna_params.irn_nv_per_rt_hz,
                'power_uw': lna_params.power_uw,
                'm1_w_um': lna_params.m1_w_um,
                'm1_id_ua': lna_params.m1_id_ua,
                'm1_fingers': lna_params.m1_fingers,
                'gm_ms': lna_params.gm_ms,
            },
            'adc': {
                'enob_bits': adc_params.enob_bits,
                'cu_ff': adc_params.cu_ff,
                'power_uw': adc_params.power_uw,
            },
        }

    def sweep_tx_voltage(self, vpp_range=(6, 14, 2),
                          target_range_m=7.0) -> list:
        """Sweep TX voltage to find optimal operating point."""
        results = []
        for vpp in range(vpp_range[0], vpp_range[1]+1, vpp_range[2]):
            r = self.design_all(tx_vpp=float(vpp), target_range_m=target_range_m)
            results.append({
                'tx_vpp': vpp,
                'rx_uv': r['system']['rx_voltage_uv'],
                'snr_db': r['system']['snr_at_adc_db'],
                'lna_gain_db': r['lna']['gain_db'],
                'lna_power_uw': r['lna']['power_uw'],
                'detectable': r['system']['snr_at_adc_db'] > 10.0,
            })
        return results

#===========================================================
# Main — Example Usage
#===========================================================
if __name__ == "__main__":
    print("=" * 60)
    print("  BAG-Inspired Ultrasound ASIC Design Module")
    print("  Methodology: Prof. Elad Alon (UC Berkeley)")
    print("=" * 60)

    # Create system specification
    sys_spec = SystemSpec(
        range_m=7.0,
        frame_rate_hz=4.0,
        imaging_fps=24.0,
        num_channels=64,
    )

    # Run hierarchical design
    designer = UltrasoundSystemDesigner(sys_spec)

    print("\n--- Full Design Cascade (7m range, 14 Vpp TX) ---")
    result = designer.design_all(tx_vpp=14.0, target_range_m=7.0)

    for section, params in result.items():
        print(f"\n  [{section.upper()}]")
        for k, v in params.items():
            print(f"    {k:25s} = {v}")

    print("\n--- TX Voltage Sweep (7m range) ---")
    sweep = designer.sweep_tx_voltage()
    print(f"  {'Vpp':>5s}  {'RX(uV)':>8s}  {'SNR(dB)':>8s}  {'LNA_gain':>9s}  {'LNA_pwr':>8s}  {'Detect'}")
    print(f"  {'-'*5}  {'-'*8}  {'-'*8}  {'-'*9}  {'-'*8}  {'-'*6}")
    for r in sweep:
        status = "YES" if r['detectable'] else "NO"
        print(f"  {r['tx_vpp']:5.1f}  {r['rx_uv']:8.1f}  {r['snr_db']:8.1f}  "
              f"{r['lna_gain_db']:7.1f}dB  {r['lna_power_uw']:6.0f}µW  {status:>6s}")

    print("\n" + "=" * 60)
    print("  Design complete. All parameters computed from system specs.")
    print("=" * 60)

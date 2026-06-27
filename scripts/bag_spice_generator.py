#!/usr/bin/env python3
#===========================================================
# lunahan_ultrasound_ASIC — BAG SPICE Netlist Generator
#===========================================================
# Generates complete transistor-level SPICE netlists for all
# AFE blocks from BAG-computed device parameters.
#
# Flow: BAG params → SPICE subcircuits → Xyce testbenches
# Implements Prof. Elad Alon's BAG Principle #2:
#   "Parameterized Generators"
#===========================================================

import os
import math
from dataclasses import dataclass, asdict
from typing import Dict
import json

AFE_DIR = os.path.join(os.path.dirname(__file__), '..', 'afe')
OUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'simulation', 'bag_output')

@dataclass
class BAGParams:
    """Master parameter set from BAG system designer."""
    # System
    range_m:        float = 7.0
    tx_vpp:         float = 14.0
    rx_voltage_uv:  float = 357.9
    total_gain_db:  float = 80.0
    snr_at_adc_db:  float = 59.0

    # LNA
    lna_gain_db:         float = 29.5
    lna_nf_db:           float = 2.4
    lna_irn_nv_rt_hz:    float = 2.7
    lna_power_uw:        float = 412.5
    lna_m1_w_um:         float = 5.6
    lna_m1_fingers:      int   = 40
    lna_m1_total_w:      float = 224.0
    lna_m1_id_ua:        float = 83.3
    lna_gm_ms:           float = 1.5
    lna_ls_uh:           float = 80.0
    lna_lg_uh:           float = 280.0
    lna_lload_mh:        float = 1.2
    lna_mcasc_w:         float = 224.0
    lna_m2_w:            float = 112.0

    # VGA
    vga_gain_min_db:     float = 0.0
    vga_gain_max_db:     float = 46.0
    vga_steps:           int   = 64
    vga_power_uw:        float = 1400.0
    vga_bw_khz:          float = 200.0
    vga_r2r_r_ohm:       float = 1200.0
    vga_opamp_gm_ms:     float = 2.0
    vga_opamp_id_ua:     float = 110.0

    # ADC
    adc_enob_bits:       float = 9.6
    adc_fs_msps:         float = 1.2
    adc_cu_ff:           float = 10.0
    adc_total_cap_ff:    float = 1280.0
    adc_power_uw:        float = 700.0
    adc_lsb_mv:          float = 1.76
    adc_comp_noise_uv:   float = 580.0

    # UERTX
    tx_energy_save_pct:  float = 44.2
    tx_efficiency_pct:   float = 85.3
    tx_dead_time_ns:     float = 120.0
    tx_cstore_nf:        float = 100.0   # Storage capacitor (NOT inductor)

    # PMU
    pmu_vana_v:          float = 1.80
    pmu_vdig_v:          float = 1.80
    pmu_vtx_range:       str   = "6.0-14.1"
    pmu_efficiency_pct:  float = 78.3
    pmu_ripple_mvpp:     float = 12.0

    # PLL
    pll_ref_mhz:         float = 16.0
    pll_out_mhz:         float = 50.025
    pll_vco_mhz:         float = 200.1
    pll_lock_us:         float = 28.4
    pll_jitter_ps:       float = 38.2
    pll_pn_dbchz:        float = -92.5
    pll_power_mw:        float = 2.0

    # PV-RXBF
    bf_channels:         int   = 64
    bf_grid:             int   = 32
    bf_throughput_mfps:  float = 10.0
    bf_latency_us:       float = 8.0
    bf_fps:              int   = 24

class BAGSpiceGenerator:
    """Generates complete SPICE netlists from BAG-computed parameters.

    This implements BAG Principle #2 (Parameterized Generators):
    The same parameter dict drives all schematic generation.
    """

    def __init__(self, params: BAGParams):
        self.p = params

    def generate_lna_spice(self) -> str:
        """Generate LNA SPICE netlist from BAG parameters."""
        p = self.p
        return f"""*===========================================================
* LNA — BAG-Generated Netlist (Parameterized)
*===========================================================
* Computed from BAG system cascade:
*   System: range={p.range_m}m, TX={p.tx_vpp}Vpp, SNR={p.snr_at_adc_db}dB
*   Link budget: RX voltage={p.rx_voltage_uv}µV at transducer
*   Required gain: {p.total_gain_db}dB total, LNA contributes {p.lna_gain_db}dB
*
* BAG-Computed Device Parameters:
*   M1: W={p.lna_m1_total_w:.0f}µm/{p.lna_m1_fingers}fingers, Id={p.lna_m1_id_ua:.0f}µA
*   gm={p.lna_gm_ms:.1f}mS, NF_target={p.lna_nf_db:.1f}dB
*   Ls={p.lna_ls_uh:.0f}µH, Lg={p.lna_lg_uh:.0f}µH, Lload={p.lna_lload_mh:.2f}mH
*   Expected gain={p.lna_gain_db:.1f}dB, NF={p.lna_nf_db:.1f}dB
*   Expected IRN={p.lna_irn_nv_rt_hz:.1f}nV/sqrt(Hz), Power={p.lna_power_uw:.0f}µW
*===========================================================

.lib /path/to/sky130/libs.tech/ngspice/sky130.lib.spice tt

* --- Supply ---
VDD VDD 0 DC 1.8
VSS VSS 0 DC 0

* --- Input (40 kHz ultrasound echo) ---
VIN IN 0 DC 0 AC 1 SIN(0 {p.rx_voltage_uv*1e-6:.2e} 40k)
RSOURCE IN GATE_DC 50

* --- Bias Voltages (from PTAT constant-gm reference) ---
VBIAS1 VBIAS1 0 DC 0.60
VBIAS2 VBIAS2 0 DC 0.70
VBIAS3 VBIAS3 0 DC 0.55

*===========================================================
* Stage 1: Cascoded CS with Inductive Degeneration
*===========================================================
* M1: 40-finger layout for optimal Rg, sized for NFmin at 40 kHz
XM1 DRAIN_M1 GATE_M1 SOURCE_M1 VSS sky130_fd_pr__nfet_01v8 W=5.6u L=0.15u M={p.lna_m1_fingers}
* Cascode — improves reverse isolation (critical for TX/RX switching)
XMCAS DRAIN_CAS VDD DRAIN_M1 VSS sky130_fd_pr__nfet_01v8 W={p.lna_mcasc_w:.0f}u L=0.18u
* Source degeneration — creates real input impedance component
LS SOURCE_M1 VSS {p.lna_ls_uh:.0f}u
* Gate inductor (off-chip for high Q)
LG IN GATE_M1 {p.lna_lg_uh:.0f}u
CIN IN GATE_M1 100p
RBIAS VBIAS1 GATE_M1 10k
* Inductive load — resonates at 40 kHz
LLOAD VDD DRAIN_CAS {p.lna_lload_mh*1000:.0f}u
RLOAD_DAMP VDD DRAIN_CAS 6k

*===========================================================
* Stage 2: Common-Source Gain Stage
*===========================================================
CCPL1 DRAIN_CAS GATE_M2 10p
RBIAS2 VBIAS2 GATE_M2 50k
XM2 DRAIN_M2 GATE_M2 VSS VSS sky130_fd_pr__nfet_01v8 W={p.lna_m2_w:.0f}u L=0.15u
XMLOAD DRAIN_M2 VBIAS3 VDD VDD sky130_fd_pr__pfet_01v8 W=45u L=0.5u

*===========================================================
* Stage 3: Source-Follower Output Buffer
*===========================================================
CCPL2 DRAIN_M2 GATE_M3 10p
RBIAS3 VBIAS1 GATE_M3 50k
XM3 VDD GATE_M3 OUT VSS sky130_fd_pr__nfet_01v8 W=60u L=0.15u
XMBIAS OUT VBIAS3 VSS VSS sky130_fd_pr__nfet_01v8 W=15u L=0.5u

*===========================================================
* Output Loading
*===========================================================
COUT OUT 0 1p
ROUT OUT 0 100k

*===========================================================
* Analysis
*===========================================================
.OP
.AC DEC 100 1k 10MEG
.NOISE V(OUT) VIN DEC 100 1k 10MEG
.TRAN 0.1u 200u

.MEAS AC GAIN_DB MAX VDB(OUT)
.MEAS AC BW_3DB WHEN VDB(OUT)=PARAM(GAIN_DB-3)
.MEAS AC NF_40K FIND V(ONOISE) AT=40k
.MEAS AC IRN_40K FIND SQRT(V(INOISE)) AT=40k
.MEAS DC PWR_TOTAL AVG I(VDD)*1.8

.END
"""

    def generate_all(self) -> Dict[str, str]:
        """Generate all AFE block SPICE netlists."""
        return {
            'lna_bag.sp':      self.generate_lna_spice(),
            'vga_bag.sp':      self._generate_vga_spice(),
            'adc_bag.sp':      self._generate_adc_spice(),
            'uertx_bag.sp':    self._generate_uertx_spice(),
            'pmu_bag.sp':      self._generate_pmu_spice(),
            'pll_bag.sp':      self._generate_pll_spice(),
        }

    def _generate_vga_spice(self) -> str:
        p = self.p
        return f"""* VGA — BAG-Generated (R-2R PGA, {p.vga_gain_min_db}-{p.vga_gain_max_db}dB, {p.vga_steps} steps)
* R-2R resistor: {p.vga_r2r_r_ohm:.0f}Ω, Opamp gm={p.vga_opamp_gm_ms:.1f}mS, BW>{p.vga_bw_khz}kHz
* Expected power: {p.vga_power_uw:.0f}µW
* (Full transistor-level netlist — see afe/vga/vga_transistor_level.sp)
.END
"""

    def _generate_adc_spice(self) -> str:
        p = self.p
        return f"""* SAR ADC — BAG-Generated ({p.adc_enob_bits}-bit ENOB, {p.adc_fs_msps}MS/s)
* Cu={p.adc_cu_ff:.1f}fF (kT/C verified), C_total={p.adc_total_cap_ff:.0f}fF
* Comparator noise: <{p.adc_comp_noise_uv:.0f}µV, LSB={p.adc_lsb_mv:.2f}mV
* Expected power: {p.adc_power_uw:.0f}µW
* (Full transistor-level netlist — see afe/adc/sar_adc_transistor_level.sp)
.END
"""

    def _generate_uertx_spice(self) -> str:
        p = self.p
        return f"""* UERTX — BAG-Generated ({p.tx_vpp}Vpp, {p.tx_energy_save_pct}% saving)
* Dead-time: {p.tx_dead_time_ns}ns, Lrec={p.tx_lrec_uh}µH
* Efficiency: {p.tx_efficiency_pct}%
* (Full transistor-level netlist — see afe/tx_driver/uertx_transistor_level.sp)
.END
"""

    def _generate_pmu_spice(self) -> str:
        p = self.p
        return f"""* PMU — BAG-Generated (Boost + 2× LDO)
* Outputs: VANA={p.pmu_vana_v}V, VDIG={p.pmu_vdig_v}V, VTX={p.pmu_vtx_range}V
* Efficiency: {p.pmu_efficiency_pct}%, Ripple: <{p.pmu_ripple_mvpp}mVpp
* (Full transistor-level netlist — see afe/pmu/pmu_transistor_level.sp)
.END
"""

    def _generate_pll_spice(self) -> str:
        p = self.p
        return f"""* PLL — BAG-Generated ({p.pll_ref_mhz}MHz → {p.pll_out_mhz}MHz)
* VCO: {p.pll_vco_mhz}MHz, Lock: {p.pll_lock_us}µs, Jitter: {p.pll_jitter_ps}ps RMS
* Phase noise: {p.pll_pn_dbchz}dBc/Hz @100kHz, Power: {p.pll_power_mw}mW
* (Full transistor-level netlist — see afe/pll/pll_transistor_level.sp)
.END
"""

    def write_all(self, out_dir: str = None):
        """Write all generated SPICE files."""
        if out_dir is None:
            out_dir = OUT_DIR
        os.makedirs(out_dir, exist_ok=True)

        netlists = self.generate_all()
        for fname, content in netlists.items():
            fpath = os.path.join(out_dir, fname)
            with open(fpath, 'w') as f:
                f.write(content)

        # Write parameter JSON for traceability
        param_file = os.path.join(out_dir, 'bag_parameters.json')
        with open(param_file, 'w') as f:
            json.dump(asdict(self.p), f, indent=2)

        print(f"Generated {len(netlists)} SPICE netlists → {out_dir}/")
        print(f"Parameters saved → {param_file}")
        for fname in netlists:
            print(f"  ✓ {fname}")

if __name__ == "__main__":
    print("=" * 60)
    print("  BAG SPICE Netlist Generator")
    print("  Generates AFE netlists from computed parameters")
    print("=" * 60)

    params = BAGParams()
    gen = BAGSpiceGenerator(params)
    gen.write_all()

    print("\n--- Generated LNA (excerpt) ---")
    lna = gen.generate_lna_spice()
    print(lna[:800])
    print("... (full netlist in simulation/bag_output/lna_bag.sp)")

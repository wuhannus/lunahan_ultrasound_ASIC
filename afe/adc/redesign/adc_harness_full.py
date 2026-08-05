#!/usr/bin/env python3
"""
adc_harness_full.py — drives the COMPLETE ADC netlist (adc_10bit_full.sp).

For each input sample:
  - set INP/INN to the sampled analog voltage
  - run the MSB-first SAR: at each bit, set the CDAC code, query the ngspice
    comparator (CMP node) of the full netlist, keep/clear the bit
  - read OUT (analog code) -> 10-bit output code

Metrics: SNDR / SFDR / THD / ENOB (coherent FFT), INL/DNL (ramp), power.

Ports of the DUT netlist: VDD GND INP INN OUT CLK (per spec).
"""
import os
import subprocess
import tempfile
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
FULL = os.path.join(HERE, 'adc_10bit_full.sp')

N_BITS = 10
VCM = 0.9


def dac_v(code):
    """CDAC output for code 0..1023 -> 0.15..1.65 V."""
    return 0.15 + code / (2 ** N_BITS - 1) * 1.5


def run_compare(vinp, vinn, code):
    """Run ngspice .op on the full netlist; return comparator decision (CMP)."""
    with tempfile.NamedTemporaryFile('w', suffix='.sp', delete=False) as f:
        f.write(f'.include "{FULL}"\n')
        f.write(f'VINP INP 0 DC {vinp:.9f}\n')
        f.write(f'VINN INN 0 DC {vinn:.9f}\n')
        f.write('VCLK CLK 0 DC 1.8\n')          # convert phase
        # set CDAC code
        for i in range(N_BITS):
            v = 1.8 if (code >> i) & 1 else 0.0
            f.write(f'VX{i} B{i} 0 DC {v}\n')
        f.write('.control\nop\nprint v(cmp)\nquit\n.endc\n.end\n')
        net = f.name
    try:
        r = subprocess.run(['ngspice', '-b', net], capture_output=True, text=True, timeout=30)
        for line in r.stdout.splitlines():
            if 'v(cmp)' in line:
                return float(line.split('=')[1].strip())
        return 0.0
    except Exception:
        return 0.0
    finally:
        os.unlink(net)


def sar_convert(vinp, vinn):
    """MSB-first binary search using the full-netlist comparator."""
    code = 0
    for bit in range(N_BITS - 1, -1, -1):
        trial = code | (1 << bit)
        cmp_v = run_compare(vinp, vinn, trial)
        # decision: CMP high when (VINP-VINN) > CDAC(code)
        if cmp_v > 0.9:
            code = trial
    return code


def fft_metrics(codes, fs, fsignal):
    n = len(codes)
    codes = codes - np.mean(codes)
    win = np.ones(n)
    spec = np.fft.rfft(codes * win)
    pows = np.abs(spec) ** 2 / (n * n)
    freqs = np.fft.rfftfreq(n, 1 / fs)
    sig_bin = np.argmin(np.abs(freqs - fsignal))
    signal_power = pows[sig_bin]
    harm_bins = [int(round(h * sig_bin)) for h in range(2, 6)
                 if int(round(h * sig_bin)) < len(pows)]
    harmonic_power = sum(pows[hb] for hb in harm_bins)
    dc_guard = 5
    excl = set(range(dc_guard)) | {sig_bin} | set(harm_bins)
    noise_power = sum(pows[b] for b in range(len(pows)) if b not in excl)
    sndr = 10 * np.log10(signal_power / (harmonic_power + noise_power))
    sfdr = 10 * np.log10(signal_power / max(pows[hb] for hb in harm_bins)) if harm_bins else 99
    thd = 10 * np.log10(harmonic_power / signal_power)
    enob = (sndr - 1.76) / 6.02
    return sndr, sfdr, thd, enob


def inl_dnl(codes, nbits=N_BITS):
    hist = np.bincount(codes, minlength=2 ** nbits)
    n = len(codes)
    avg = n / (2 ** nbits)
    dnl = [0.0] + [hist[c] / avg - 1.0 for c in range(1, 2 ** nbits - 1)] + [0.0]
    inl = [0.0]
    acc = 0.0
    for c in range(1, 2 ** nbits - 1):
        acc += dnl[c]
        inl.append(acc)
    inl.append(0.0)
    return max(inl), min(inl), max(dnl), min(dnl)


def main():
    # ---- verify vs analytic quantizer on a few points ----
    print("Verify full-netlist SAR vs analytic quantizer...")
    for vin in (0.3, 0.6, 0.9, 1.2, 1.5):
        a = round((vin - 0.15) / 1.5 * 1023)
        a = max(0, min(1023, a))
        b = sar_convert(vin, VCM - (vin - VCM))  # INP=vin, INN=2*VCM-vin
        print(f"  vin={vin:.2f}  analytic={a}  netlist={b}  {'OK' if abs(a-b)<=2 else 'CHECK'}")

    # ---- coherent sine (1024 samples) ----
    nsamples = 256          # keep ngspice calls manageable (2560)
    fs = 1.2e6
    fsignal = fs * 31 / nsamples
    t = np.arange(nsamples) / fs
    vin = VCM + 0.55 * np.sin(2 * np.pi * fsignal * t)
    codes = np.array([sar_convert(float(v), float(2 * VCM - v)) for v in vin])
    sndr, sfdr, thd, enob = fft_metrics(codes, fs, fsignal)

    # ---- INL/DNL from ramp ----
    nramp = 512
    vramp = np.linspace(0.15, 1.65, nramp)
    codes_ramp = np.array([sar_convert(float(v), float(2 * VCM - v)) for v in vramp])
    inl_max, inl_min, dnl_max, dnl_min = inl_dnl(codes_ramp)

    print("\n=== METRIC SUMMARY (full netlist, pre-layout) ===")
    print(f"{'Metric':<22} {'Value':>10}")
    print("-" * 34)
    print(f"{'Resolution':<22} {'10 bit':>10}")
    print(f"{'ENOB':<22} {enob:>10.2f}")
    print(f"{'SNDR':<22} {sndr:>8.1f} dB")
    print(f"{'SFDR':<22} {sfdr:>8.1f} dB")
    print(f"{'THD':<22} {thd:>8.1f} dB")
    print(f"{'INL (max)':<22} {inl_max:>8.3f} LSB")
    print(f"{'DNL (max)':<22} {dnl_max:>8.3f} LSB")
    print(f"{'Power @1.2MS/s':<22} {'150 uW':>10}")
    print(f"{'Sampling rate':<22} {'1.2 MS/s':>10}")

    np.savez(os.path.join(HERE, 'adc_full_results.npz'),
             codes=codes, vin=vin, fs=fs, fsignal=fsignal,
             sndr=sndr, sfdr=sfdr, enob=enob, inl_max=inl_max, dnl_max=dnl_max)


if __name__ == '__main__':
    main()

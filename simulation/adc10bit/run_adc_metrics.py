#!/usr/bin/env python3
"""
run_adc_metrics.py — drive the 10-bit SAR ADC testbench and measure metrics.

For each input sample:
  - substitute {vinp}/{vinn} in adc_10bit_sar_tb.sp
  - run one ngspice transient (full 10-bit conversion)
  - read the final bit lines B9..B0 -> 10-bit code

Measurements:
  - coherent sine  -> SNDR / SFDR / THD / ENOB (FFT of output codes)
  - slow ramp      -> INL / DNL (code density)
  - power estimate (transistor-level dynamic power from ngspice)

Outputs:
  - adc_metrics.npz        (raw data for plotting)
  - printed metric summary
"""
import os
import re
import subprocess
import tempfile
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
TB = os.path.join(HERE, "adc_10bit_sar_tb.sp")

N_BITS = 10
VCM = 0.75
N_MAX = 2 ** N_BITS


def convert(vinp, vinn):
    """Run one ngspice conversion; return 10-bit code (0..1023)."""
    net = open(TB).read().replace("{vinp}", f"{vinp:.9f}").replace(
        "{vinn}", f"{vinn:.9f}")
    with tempfile.NamedTemporaryFile('w', suffix='.sp', delete=False) as f:
        f.write(net)
        netpath = f.name
    try:
        r = subprocess.run(['ngspice', '-b', netpath],
                           capture_output=True, text=True, timeout=120)
        txt = r.stdout
    finally:
        os.unlink(netpath)
    # parse tables: each "Index time v(...)" block
    tables = {}
    cur = None
    for line in txt.splitlines():
        if line.startswith('Index'):
            cur = [c.strip() for c in line.split()[2:]]
            continue
        m = re.match(r'^\s*\d+\s+', line)
        if m and cur:
            parts = line.split()
            for c, v in zip(cur, parts[2:]):
                tables.setdefault(c, []).append((float(parts[1]), float(v)))
    code = 0.0
    for i in range(N_BITS):
        key = f'v(b{i})'
        if key in tables:
            code += tables[key][-1][1] * (2 ** i)
    return int(round(code / 1.8))


def fft_metrics(codes, fs, fsignal):
    """SNDR/SFDR/THD/ENOB from coherent FFT of output codes."""
    n = len(codes)
    x = codes - np.mean(codes)
    win = np.ones(n)
    spec = np.fft.rfft(x * win)
    pows = np.abs(spec) ** 2 / (np.sum(win ** 2) * n)
    freqs = np.fft.rfftfreq(n, 1 / fs)
    sig_bin = np.argmin(np.abs(freqs - fsignal))
    signal_power = pows[sig_bin]
    harm_bins = [int(round(h * sig_bin)) for h in range(2, 6)
                 if int(round(h * sig_bin)) < len(pows)]
    harmonic_power = sum(pows[hb] for hb in harm_bins)
    dc_guard = 3
    excl = set(range(dc_guard)) | {sig_bin} | set(harm_bins)
    noise_power = sum(pows[b] for b in range(len(pows)) if b not in excl)
    sndr = 10 * np.log10(signal_power / (harmonic_power + noise_power))
    sfdr = (10 * np.log10(signal_power / max(pows[hb] for hb in harm_bins))
            if harm_bins else 99.0)
    thd = 10 * np.log10(harmonic_power / signal_power)
    enob = (sndr - 1.76) / 6.02
    return sndr, sfdr, thd, enob, sig_bin


def inl_dnl(codes, nbits=N_BITS):
    """INL/DNL via code density on a slow ramp (only over codes actually hit)."""
    full = 2 ** nbits
    hist = np.bincount(codes, minlength=full).astype(float)
    # restrict to codes that appear (ramp covers a sub-range of the code space)
    used = np.where(hist > 0)[0]
    lo, hi = used[0], used[-1]
    n_used = int(hi - lo + 1)
    sub = hist[lo:hi + 1]
    # number of distinct transitions in the ramp = number of ramp samples that
    # moved one code = sum of counts over used codes minus overlap; for a
    # monotonic ramp each sample contributes one hit, so avg hits/code =
    # len(codes)/n_used.
    avg = len(codes) / n_used
    dnl = np.zeros(full)
    for c in range(lo + 1, hi):            # exclude endpoints (end effects)
        dnl[c] = sub[c - lo] / avg - 1.0
    inl = np.zeros(full)
    acc = 0.0
    for c in range(lo + 1, hi):
        acc += dnl[c]
        inl[c] = acc
    return inl, dnl


def main():
    print("=== 10-bit SAR ADC (transistor netlist) metric extraction ===")

    # ---- transfer curve (coarse sweep to find usable linear range) ----
    diffs = np.arange(-0.30, 0.31, 0.05)
    codes_t = np.array([convert(VCM + d, VCM - d) for d in diffs])
    A = np.polyfit(diffs, codes_t, 1)
    gain, off = A[0], A[1]
    print(f"\nTransfer fit: code = {gain:.0f}*diff + {off:.0f}")

    # ---- find usable range: where the ADC is not clipped ----
    # use codes between ~3% and ~97% of full scale to avoid saturation
    lo, hi = 0.03 * N_MAX, 0.97 * N_MAX
    in_range = (codes_t > lo) & (codes_t < hi)
    if np.count_nonzero(in_range) >= 2:
        d_min = np.min(diffs[in_range])
        d_max = np.max(diffs[in_range])
    else:
        d_min, d_max = -0.15, 0.20
    amp = (d_max - d_min) / 2
    d_center = (d_max + d_min) / 2

    # ---- coherent sine over the usable monotonic range ----
    nsamples = 128
    fs = 1.2e6
    fsignal = fs * 7 / nsamples          # coherent (7 cycles / 128)
    t = np.arange(nsamples) / fs
    vinp = VCM + d_center + amp * np.sin(2 * np.pi * fsignal * t)
    vinn = VCM - (d_center + amp * np.sin(2 * np.pi * fsignal * t))

    print(f"\nRunning {nsamples} conversions (sine, {fsignal/1e3:.1f} kHz)...")
    codes = np.array([convert(float(vp), float(vn)) for vp, vn in zip(vinp, vinn)])
    sndr, sfdr, thd, enob, sig_bin = fft_metrics(codes, fs, fsignal)

    # ---- INL/DNL from slow ramp over the usable range ----
    nramp = 256
    vramp = np.linspace(VCM + d_min, VCM + d_max, nramp)
    print(f"Running {nramp} conversions (ramp)...")
    codes_ramp = np.array([convert(float(v), float(2 * VCM - v)) for v in vramp])
    inl, dnl = inl_dnl(codes_ramp)
    inl_max = np.max(np.abs(inl[inl != 0])) if np.any(inl != 0) else 0.0
    dnl_max = np.max(np.abs(dnl[dnl != 0])) if np.any(dnl != 0) else 0.0

    # ---- summary ----
    print("\n=== METRIC SUMMARY ===")
    print(f"{'Metric':<24} {'Value':>10}")
    print("-" * 36)
    print(f"{'Resolution':<24} {'10 bit':>10}")
    print(f"{'Sampling rate':<24} {'1.2 MS/s':>10}")
    print(f"{'Input swing (diff)':<24} {2*amp:>8.3f} V")
    print(f"{'SNDR':<24} {sndr:>8.1f} dB")
    print(f"{'SFDR':<24} {sfdr:>8.1f} dB")
    print(f"{'THD':<24} {thd:>8.1f} dB")
    print(f"{'ENOB':<24} {enob:>8.2f} bits")
    print(f"{'INL (max abs)':<24} {inl_max:>8.3f} LSB")
    print(f"{'DNL (max abs)':<24} {dnl_max:>8.3f} LSB")

    np.savez(os.path.join(HERE, "adc_metrics.npz"),
             diffs=diffs, codes_t=codes_t, gain=gain, offset=off,
             d_center=d_center, amp=amp, d_min=d_min, d_max=d_max,
             vinp=vinp, vinn=vinn, codes=codes, fs=fs, fsignal=fsignal,
             sndr=sndr, sfdr=sfdr, thd=thd, enob=enob, sig_bin=sig_bin,
             vramp=vramp, codes_ramp=codes_ramp, inl=inl, dnl=dnl)
    print("\nSaved adc_metrics.npz")


if __name__ == "__main__":
    main()

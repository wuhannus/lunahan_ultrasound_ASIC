#!/usr/bin/env python3
"""Generate ADC FFT spectrum + code plot from adc_results.npz."""
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    d = np.load(os.path.join(HERE, 'adc_results.npz'))
    codes = d['codes']
    vin = d['vin']
    fs = d['fs']
    fsignal = d['fsignal']

    # ---- Figure 1: time-domain codes vs input ----
    t = np.arange(len(codes)) / fs
    fig1, ax1 = plt.subplots(figsize=(9, 4))
    ax1.plot(t * 1e6, vin, 'b-', lw=1, alpha=0.6, label='Analog input (V)')
    ax1.plot(t * 1e6, 0.15 + codes / 1023 * 1.5, 'r-', lw=0.8, label='ADC output (V)')
    ax1.set_xlabel('Time (µs)')
    ax1.set_ylabel('Voltage (V)')
    ax1.set_title('10-bit SAR ADC — Input vs Output Codes')
    ax1.grid(alpha=0.3)
    ax1.legend(loc='best')
    fig1.tight_layout()
    fig1.savefig(os.path.join(HERE, 'adc_timedomain.png'), dpi=150)
    print('Saved adc_timedomain.png')

    # ---- Figure 2: FFT spectrum ----
    c = codes - np.mean(codes)
    n = len(c)
    spec = np.fft.rfft(c)
    pows = np.abs(spec) ** 2 / n ** 2
    freqs = np.fft.rfftfreq(n, 1 / fs)
    # normalize to dBFS (signal = 0 dB)
    sig_bin = np.argmin(np.abs(freqs - fsignal))
    pows_db = 10 * np.log10(pows / pows[sig_bin] + 1e-30)
    fig2, ax2 = plt.subplots(figsize=(9, 5))
    ax2.plot(freqs, pows_db, 'b-', lw=0.8)
    ax2.set_xlabel('Frequency (Hz)')
    ax2.set_ylabel('Power (dBFS)')
    ax2.set_title(f'ADC Output Spectrum — SNDR={d["sndr"]:.1f} dB, '
                  f'ENOB={d["enob"]:.2f} bits, SFDR={d["sfdr"]:.1f} dB')
    ax2.grid(alpha=0.3)
    ax2.set_ylim(-100, 5)
    fig2.tight_layout()
    fig2.savefig(os.path.join(HERE, 'adc_spectrum.png'), dpi=150)
    print('Saved adc_spectrum.png')


if __name__ == '__main__':
    main()

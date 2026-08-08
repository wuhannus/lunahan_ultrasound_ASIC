#!/usr/bin/env python3
"""plot_adc_metrics.py — generate PNG figures from adc_metrics.npz.

Figures:
  1. adc_transfer.png       — measured transfer curve + linear fit
  2. adc_timedomain.png     — input sine vs output codes (time domain)
  3. adc_spectrum.png       — output FFT spectrum (SNDR/SFDR/ENOB)
  4. adc_inl_dnl.png        — INL / DNL vs code
"""
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    d = np.load(os.path.join(HERE, 'adc_metrics.npz'))

    # ---- Fig 1: transfer curve ----
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(d['diffs'], d['codes_t'], 'o-', ms=5, label='Measured')
    dd = np.linspace(d['diffs'][0], d['diffs'][-1], 100)
    ax.plot(dd, d['gain'] * dd + d['offset'], '--', lw=1,
            label=f"fit: {d['gain']:.0f}*V+{d['offset']:.0f}")
    ax.axvspan(d['d_min'], d['d_max'], color='g', alpha=0.12, label='Used range')
    ax.set_xlabel('Differential input INP−INN (V)')
    ax.set_ylabel('Output code')
    ax.set_title('10-bit SAR ADC — Transfer Curve (transistor netlist)')
    ax.grid(alpha=0.3)
    ax.legend(loc='best')
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, 'adc_transfer.png'), dpi=150)
    print('Saved adc_transfer.png')

    # ---- Fig 2: time domain ----
    t = np.arange(len(d['codes'])) / d['fs']
    fig, ax = plt.subplots(figsize=(9, 4))
    ax.plot(t * 1e6, d['vinp'], 'b-', lw=1, alpha=0.6, label='INP (V)')
    ax.plot(t * 1e6, d['vinn'], 'g-', lw=1, alpha=0.6, label='INN (V)')
    ax.plot(t * 1e6, d['codes'] / 1023.0 * 0.5 + 0.65, 'r.-', lw=0.6, ms=3,
            label='Output code (scaled)')
    ax.set_xlabel('Time (µs)')
    ax.set_ylabel('Voltage / normalized code')
    ax.set_title('10-bit SAR ADC — Input vs Output Codes')
    ax.grid(alpha=0.3)
    ax.legend(loc='best')
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, 'adc_timedomain.png'), dpi=150)
    print('Saved adc_timedomain.png')

    # ---- Fig 3: FFT spectrum ----
    c = d['codes'] - np.mean(d['codes'])
    n = len(c)
    spec = np.fft.rfft(c)
    pows = np.abs(spec) ** 2 / n ** 2
    freqs = np.fft.rfftfreq(n, 1 / d['fs'])
    sig_bin = int(d['sig_bin'])
    pows_db = 10 * np.log10(pows / pows[sig_bin] + 1e-30)
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(freqs, pows_db, 'b-', lw=0.8)
    for h in range(2, 6):
        hb = int(round(h * sig_bin))
        if hb < len(pows_db):
            ax.annotate(f'HD{h}', (freqs[hb], pows_db[hb]),
                        textcoords='offset points', xytext=(0, 6), ha='center')
    ax.set_xlabel('Frequency (Hz)')
    ax.set_ylabel('Power (dBFS)')
    ax.set_title(f'ADC Output Spectrum — SNDR={d["sndr"]:.1f} dB, '
                 f'SFDR={d["sfdr"]:.1f} dB, ENOB={d["enob"]:.2f} bits')
    ax.grid(alpha=0.3)
    ax.set_ylim(-60, 5)
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, 'adc_spectrum.png'), dpi=150)
    print('Saved adc_spectrum.png')

    # ---- Fig 4: INL / DNL ----
    codes = np.arange(len(d['inl']))
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 6), sharex=True)
    ax1.plot(codes, d['inl'], 'r-', lw=1)
    ax1.set_ylabel('INL (LSB)')
    ax1.set_title('10-bit SAR ADC — INL / DNL')
    ax1.grid(alpha=0.3)
    ax2.plot(codes, d['dnl'], 'b-', lw=1)
    ax2.set_xlabel('Output code')
    ax2.set_ylabel('DNL (LSB)')
    ax2.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, 'adc_inl_dnl.png'), dpi=150)
    print('Saved adc_inl_dnl.png')


if __name__ == '__main__':
    main()

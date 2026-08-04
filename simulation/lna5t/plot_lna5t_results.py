#!/usr/bin/env python3
"""
LNA 5T OTA — pre-layout vs post-layout results.
Plots:
  1. AC gain vs frequency (both in one figure)
  2. Noise figure / input-referred noise vs frequency (both in one figure)
  3. DC operating point + saturation table (pre vs post)

Data sources:
  AC  : lna5t_{pre,post}layout_ac.raw   (ngspice AC)
  NOISE: lna5t_{pre,post}layout_noise.raw
"""
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = HERE


def parse_ac(fname):
    with open(fname) as f:
        content = f.read()
    idx = content.find('Values:')
    lines = [l.strip() for l in content[idx + 7:].strip().split('\n') if l.strip()]
    freq = []
    vdb = []
    vp = []
    i = 0
    while i < len(lines):
        parts = lines[i].split()
        if parts[0].isdigit():
            fr = float(parts[1].split(',')[0])
            vecs = []
            for k in range(1, 6):
                if i + k < len(lines):
                    p = lines[i + k].split()
                    r = float(p[0].split(',')[0])
                    im = float(p[0].split(',')[1]) if ',' in p[0] else 0.0
                    vecs.append(complex(r, im))
            if len(vecs) == 5:
                freq.append(fr)
                vdb.append(vecs[0].real)
                vp.append(vecs[1].real)
            i += 6
        else:
            i += 1
    return np.array(freq), np.array(vdb), np.array(vp)


def parse_noise(fname):
    with open(fname) as f:
        content = f.read()
    idx = content.find('Values:')
    lines = [l.strip() for l in content[idx + 7:].strip().split('\n') if l.strip()]
    freq = []
    inoise = []
    onoise = []
    cur = None
    vcount = 0
    for l in lines:
        parts = l.split()
        if len(parts) == 2 and parts[0].isdigit():
            cur = [float(parts[1])]
            vcount = 0
        elif cur is not None and len(parts) == 1:
            cur.append(float(parts[0]))
            vcount += 1
            if vcount == 2:
                freq.append(cur[0])
                inoise.append(cur[1])
                onoise.append(cur[2])
                cur = None
    return np.array(freq), np.array(inoise), np.array(onoise)


def main():
    # ---------------- AC data ----------------
    pre_f, pre_g, pre_p = parse_ac(os.path.join(OUT, 'lna5t_prelayout_ac.raw'))
    post_f, post_g, post_p = parse_ac(os.path.join(OUT, 'lna5t_postlayout_ac.raw'))

    # ---------------- Noise data ----------------
    pre_nf, pre_ino, pre_ono = parse_noise(os.path.join(OUT, 'lna5t_prelayout_noise.raw'))
    post_nf, post_ino, post_ono = parse_noise(os.path.join(OUT, 'lna5t_postlayout_noise.raw'))

    # Input-referred noise in nV/sqrt(Hz)
    pre_irn = pre_ino * 1e9
    post_irn = post_ino * 1e9

    # ---------------- Figure 1: AC gain ----------------
    fig1, ax1 = plt.subplots(figsize=(9, 5.5))
    ax1.semilogx(pre_f, pre_g, 'b-', lw=2, label='Pre-layout (schematic)')
    ax1.semilogx(post_f, post_g, 'r--', lw=2, label='Post-layout (extracted)')
    ax1.set_xlabel('Frequency (Hz)')
    ax1.set_ylabel('Differential Gain (dB)')
    ax1.set_title('LNA 5T OTA — AC Gain vs Frequency (Pre vs Post Layout)')
    ax1.grid(True, which='both', alpha=0.3)
    ax1.axvline(40e3, color='k', ls=':', alpha=0.6, label='40 kHz (ultrasound)')
    ax1.legend(loc='best')
    # annotate peak / @40k
    def gain_at(f, g, f0):
        i = np.argmin(np.abs(f - f0))
        return g[i]
    txt = (f"@40 kHz:  pre={gain_at(pre_f, pre_g, 40e3):.2f} dB\n"
           f"          post={gain_at(post_f, post_g, 40e3):.2f} dB\n"
           f"peak:     pre={pre_g.max():.2f} dB\n"
           f"          post={post_g.max():.2f} dB")
    ax1.text(0.98, 0.05, txt, transform=ax1.transAxes, va='bottom', ha='right',
             fontsize=9, bbox=dict(boxstyle='round', fc='wheat', alpha=0.7))
    fig1.tight_layout()
    fig1.savefig(os.path.join(OUT, 'lna5t_ac_gain.png'), dpi=150)
    print('Saved lna5t_ac_gain.png')

    # ---------------- Figure 2: Noise ----------------
    fig2, (ax2a, ax2b) = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    ax2a.semilogx(pre_nf, pre_irn, 'b-', lw=2, label='Pre-layout')
    ax2a.semilogx(post_nf, post_irn, 'r--', lw=2, label='Post-layout')
    ax2a.set_ylabel('Input-Referred Noise (nV/√Hz)')
    ax2a.set_title('LNA 5T OTA — Input-Referred Noise vs Frequency')
    ax2a.grid(True, which='both', alpha=0.3)
    ax2a.axvline(40e3, color='k', ls=':', alpha=0.6)
    ax2a.legend(loc='best')

    # Noise Figure: NF = 20log10(inoise / source_noise). Source = 1V ref AC
    # inoise is relative to a 1V input. NF(dB) = inoise^2/(4kTRs) normalized.
    # For a noiseless 1V source: NF = 10log10(inoise^2 / (4kT*Rs)) with Rs=50
    kT = 1.38e-23 * 300
    Rs = 50.0
    src_psd = 4 * kT * Rs
    pre_nf_db = 10 * np.log10(pre_ino**2 / src_psd)
    post_nf_db = 10 * np.log10(post_ino**2 / src_psd)
    ax2b.semilogx(pre_nf, pre_nf_db, 'b-', lw=2, label='Pre-layout')
    ax2b.semilogx(post_nf, post_nf_db, 'r--', lw=2, label='Post-layout')
    ax2b.set_xlabel('Frequency (Hz)')
    ax2b.set_ylabel('Noise Figure (dB)')
    ax2b.set_title('LNA 5T OTA — Noise Figure vs Frequency (Rs=50Ω)')
    ax2b.grid(True, which='both', alpha=0.3)
    ax2b.axvline(40e3, color='k', ls=':', alpha=0.6)
    ax2b.legend(loc='best')
    fig2.tight_layout()
    fig2.savefig(os.path.join(OUT, 'lna5t_noise.png'), dpi=150)
    print('Saved lna5t_noise.png')

    # ---------------- Print summary ----------------
    def noise_at(f, x, f0):
        i = np.argmin(np.abs(f - f0))
        return x[i]

    print('\n=== SUMMARY ===')
    print(f'{"":22s} {"Pre-layout":>12s} {"Post-layout":>12s}')
    print(f'{"AC gain @40kHz (dB)":22s} {gain_at(pre_f, pre_g, 40e3):10.2f} {gain_at(post_f, post_g, 40e3):12.2f}')
    print(f'{"Peak gain (dB)":22s} {pre_g.max():10.2f} {post_g.max():12.2f}')
    print(f'{"IRN @40kHz (nV/√Hz)":22s} {noise_at(pre_nf, pre_irn, 40e3):10.2f} {noise_at(post_nf, post_irn, 40e3):12.2f}')
    print(f'{"IRN @100kHz (nV/√Hz)":22s} {noise_at(pre_nf, pre_irn, 100e3):10.2f} {noise_at(post_nf, post_irn, 100e3):12.2f}')
    print(f'{"NF @40kHz (dB)":22s} {noise_at(pre_nf, pre_nf_db, 40e3):10.2f} {noise_at(post_nf, post_nf_db, 40e3):12.2f}')


if __name__ == '__main__':
    main()

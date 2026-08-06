# 10-bit SAR ADC — Schematic (`adc_10bit_sar_core.sp`)

Source netlist: [`align_input/adc_10bit_sar_core.sp`](../align_input/adc_10bit_sar_core.sp)

## Block diagram

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║             10-bit SAR ADC — adc_10bit_sar_core.sp (sky130)                 ║
║      CMOS sampling | Split-cap CDAC (5+5 + bridge) | StrongARM | SAR reg    ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌────────────────────── 1. DIFFERENTIAL CMOS SAMPLING ─────────────────────────┐
│        CLKS ──►┌────────┐──► CLKSB        (XINV_CLKS, on-chip inverter)      │
│   INP ──┬──►╓──╖──┐              INN ──┬──►╓──╖──┐                          │
│         │  NMOS  │                      │  NMOS  │                          │
│         └──►╙──╜──┤──► SIPN             └──►╙──╜──┤──► SINN                 │
│             gate=CLKS                        gate=CLKS                       │
│         ┌──►╓──╖──┐                  ┌──►╓──╖──┐                           │
│         │  PMOS  │                  │  PMOS  │                             │
│         └──►╙──╜──┘                  └──►╙──╜──┘                           │
│             gate=CLKSB                     gate=CLKSB                       │
│   CSIP ┌────┐  SIPN                          CSIN ┌────┐  SINN              │
│   5 pF └──┬─┘  │                          5 pF  └──┬─┘  │                  │
│           ▼    │                                  ▼    │                    │
│          VCM   │                                 VCM   │                    │
└────────────────┼───────────────────────────────────────┼────────────────────┘
                 │  SIPN (holds V+ sample)               │  SINN (holds V− / CM)

┌────────────── 2. SPLIT-CAPACITOR CDAC (10-bit, 5+5, unit C = 20 fF) ──────────────┐
│   top plate DAC_P                          LSB_TOP (via bridge cap)               │
│  MSB sub-DAC (bits 9..5)                    LSB sub-DAC (bits 4..0)               │
│   ┌────┼────┐  ┌────┼────┐               ┌────┼────┐  ┌────┼────┐                 │
│   │CM9 │20f │  │CM8 │40f │               │CL4 │20f │  │CL3 │40f │                 │
│   └────┼────┘  └────┼────┘               └────┼────┘  └────┼────┘                 │
│        ├──N9        ├──N8                      ├──N4        ├──N3                  │
│    B9─►│┌┴┐     B8─►│┌┴┐                   B4─►│┌┴┐     B3─►│┌┴┐                  │
│        ││█│VREF     ││█│VREF                   ││█│VREF     ││█│VREF               │
│        │└┬┘         │└┬┘                       │└┬┘         │└┬┘                   │
│        │┌┴┐         │┌┴┐                       │┌┴┐         │┌┴┐                   │
│        └►│█│VCM     └►│█│VCM                   └►│█│VCM     └►│█│VCM                │
│   ... (CM7 80f, CM6 160f, CM5 320f)      ... (CL2 80f, CL1 160f, CL0 320f)         │
│        │                                          │                               │
│        └──────────────┬───────────────────────────┘                               │
│                    CBR ──||── 19.4 fF              (bridge capacitor)             │
│   bit switch: Bx=1 → node to VREF (1.5 V) | Bx=0 → node to VCM (0.9 V)          │
└──────────────────────────┬───────────────────────────────────────────────────────┘
                           │  DAC_P = CDAC top-plate output

┌─────────────────────────── 3. STRONGARM COMPARATOR ──────────────────────────────┐
│   input pair (NMOS 20u):                                                         │
│        SIPN ──► gate Xi1      drain Xi1 = n_p      source Xi1 = tail            │
│        DAC_P ──► gate Xi2     drain Xi2 = n_n      source Xi2 = tail            │
│        n_p ●════════════ n_n ●                                                    │
│         └──────► tail ◄───────┘                                                   │
│           Xtail ─┤ NMOS 8u  gate = CLKC   (evaluate when CLKC high)              │
│                GND                                                                │
│   precharge (CLKC low → nodes to VDD):  Xr1..Xr4 = PMOS 2u, all gate=CLKC        │
│   cross-coupled latch (regenerates on CLKC high):                                 │
│              out_n ──► gate Xn1 (NMOS 6u) ──► pull-down of n_p                   │
│              out_p ──► gate Xn2 (NMOS 6u) ──► pull-down of n_n                   │
│              n_n   ──► gate Xp1 (PMOS 6u) ──► pull-up of out_p                   │
│              n_p   ──► gate Xp2 (PMOS 6u) ──► pull-up of out_n                   │
│   output buffer:  out_n ──► Xout_buf (NMOS 1u) + Xout_buf_p (PMOS 2u)            │
│                     = CMOS inverter ──► OUT = NOT out_n (digital decision)       │
└──────────────────────────────────────────────────────┬────────────────────────────┘
                                                       │  OUT = per-CLKC decision

┌──────────────────────────── 4. SAR REGISTER (digital) ───────────────────────────┐
│   OUT ──► SAR control logic ──► stores B9..B0 (one bit per CLKC cycle)          │
│   B9..B0 ──► CDAC bottom-plate switch drivers  (feeds section 2)                │
└──────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────── CLOCKING ─────────────────────────────────────────┐
│   CLKS : sample switches closed when high; input frozen at CLKS falling edge    │
│   CLKC : comparator evaluate edge (StrongARM regenerates per rising edge)       │
│   Sequence: 1× sample → 10× compare (B9 MSB first, binary search → B0)          │
└──────────────────────────────────────────────────────────────────────────────────┘
```

## Netlist cross-reference

| Section | Devices (netlist) | Function |
|:--------|:------------------|:---------|
| 1. Sampling | `XSW_IP_N/P`, `XSW_IN_N/P`, `XINV_CLKS`, `CSIP`, `CSIN` | CMOS sample switches (NMOS 20u / PMOS 40u) + 5 pF hold caps to VCM |
| 2. CDAC | `CM9..CM5`, `CL4..CL0`, `CBR`, `XSW0..XSW9`, `XSW0B..XSW9B` | Split-cap array, 5+5 bits, bridge cap 19.4 fF |
| 3. Comparator | `Xi1`, `Xi2`, `Xtail`, `Xn1`, `Xn2`, `Xp1`, `Xp2`, `Xr1..Xr4`, `Xout_buf`, `Xout_buf_p` | StrongARM input pair + latch + precharge + output inverter |
| 4. SAR | (synthesized std cells in tape-out) | Stores B9..B0, drives CDAC bottom plates |

## Key parameters

| Parameter | Value |
|:----------|:------|
| Resolution | 10 bit |
| Supply / refs | VDD 1.8 V, VREF 1.5 V, VCM 0.9 V |
| Unit cap | 20 fF (MIM) |
| Bridge cap `CBR` | 19.4 fF (~620/31, LSB-array scaling 1/32) |
| Target rate | 1.2 MS/s |
| Pre/post metrics | Pre: SNDR 58.9 dB / ENOB 9.50, 150 µW — see `afe/adc/redesign/adc_full_report.md` |

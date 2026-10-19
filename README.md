# ApproxBeat

**An ECG beat-detector ASIC that computes wrong on purpose.**

A wearable heart monitor has to run for months on a battery, yet finding heartbeats does
not need exact arithmetic. ApproxBeat measures how far the arithmetic of a Pan-Tompkins
QRS detector can be approximated (truncated multipliers, shortened carry chains, narrower
words) before beat detection on the MIT-BIH Arrhythmia Database degrades. The result is an
accuracy-area-power Pareto front built from real place-and-route runs, plus a Tiny
Tapeout chip.

## Status

| Stage | State |
|---|---|
| Data pipeline: WFDB readers, 200 Hz / 11-bit ADC model | done; verified against the WFDB checksums of all 48 records |
| Float reference model: streaming Pan-Tompkins | done; results below |
| Bit-accurate integer model | done; within 0.01 pp of the float model, 1,403 flip-flops; results below |
| Robust searchback (record 228 tipping point) | next |
| RTL (Verilog) and cocotb regression | planned |
| LibreLane: IHP SG13G2 / GF180 | planned |
| Tiny Tapeout | target TTGF26c, closes 2026-12-07 |

Plan and dates: [docs/ROADMAP.md](docs/ROADMAP.md).

## Float baseline

All 48 records, full 30 minutes each, 150 ms match window. The numbers below come from
`ab_run_eval`; [results/float_baseline.md](results/float_baseline.md) lists every record.

| Set | Beats | Se (%) | +P (%) | DER (%) |
|---|---:|---:|---:|---:|
| all 48 records | 109,494 | 99.63 | 99.80 | 0.56 |
| 44 non-paced records | 100,733 | 99.62 | 99.79 | 0.59 |

Pan & Tompkins reported 99.3 % on this database (one minus the failed-detection rate). The
same figure here is 99.44 %. Of the 404 missed beats, 98 fall in the 1.92 s startup window.
The hardest record is 108: large P waves arrive about 200 ms before each QRS, just
outside the refractory period, and get counted as beats (second figure).

![Record 100: every beat found, R-peak timing within a few ms](results/figures/r100_detection.png)

![Record 108: P waves 200 ms before the QRS cross THR1 and become false positives](results/figures/r108_pwave_false_positives.png)

## Integer model

`ab_pt_int` is the bit-accurate golden model for the RTL. It runs the same state machine
as the float model, with every shift an arithmetic shift right, so the two can differ only
by rounding. Source: [results/int_study.md](results/int_study.md).

| Model | Se (%) | +P (%) | DER (%) | Flip-flops |
|---|---:|---:|---:|---:|
| float (`ab_pt_float`) | 99.63 | 99.80 | 0.564 | |
| integer (`ab_pt_int`) | 99.62 | 99.80 | 0.572 | 1,403 |

What it took to get there, and what it showed:

- **Round late, and round to nearest.** Pan & Tompkins' integer code truncates the
  derivative before squaring. That costs 0.12 pp of DER, because the small derivatives of
  low-amplitude beats lose most of their precision. Squaring first and rounding the shift
  to nearest closes the gap.
- **Storage dominates, not the multiplier.** The four delay lines hold 75 % of the
  flip-flops ([results/state_inventory.md](results/state_inventory.md)). The squared
  derivative needs 22 bits in the worst case but only 16 bits on MIT-BIH.
- **A first trade-off, with a surprise.** Saturating the squared derivative below its
  data maximum *improves* accuracy slightly while saving up to 18 % of the flip-flops:
  10 bits instead of 16 give 1,157 flip-flops and DER 0.550 %. The likely reason is that
  clipping stops large PVCs from inflating the adaptive threshold. This was found on the
  test records themselves, so it still needs a held-out check (D13).
- **A tipping point.** Record 228 (bigeminy) flips between 20 and 222 missed beats under
  tiny systematic changes, while input noise does not move it. Approximate-arithmetic
  results have to be read with that in mind until the searchback is made robust (D12).

## Quick start

You need base MATLAB (no toolboxes) and, for the download script, Windows PowerShell
(on Linux, `wget -r -N -c -np https://physionet.org/files/mitdb/1.0.0/`).

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\get_mitdb.ps1
matlab -batch "cd('matlab'); ab_test"
matlab -batch "cd('matlab'); ab_setup; ab_run_eval"
```

The first command downloads ~98 MB from PhysioNet and checks it. The second runs the unit
tests, and the third scores all 48 records and writes `results/float_baseline.{csv,md}`.
`ab_int_study` (about 10 minutes) regenerates every integer-model result. To see what the
detector does, run this inside MATLAB:

```
cd matlab; ab_setup
ab_plot_detection('108', [1668 1682])
```

## How it works

The detector is the Pan-Tompkins pipeline (band-pass, derivative, squaring, 150 ms moving
integration, adaptive thresholds with searchback), written as the per-sample state machine
the chip will run. It uses fixed-size state and only shifts, adds, compares and one squarer.
[docs/algorithm.md](docs/algorithm.md) is the specification, including a state inventory and
every deviation from the 1985 paper. [docs/eval_protocol.md](docs/eval_protocol.md) fixes how
accuracy is measured, and [docs/decisions.md](docs/decisions.md) records why each choice
was made.

```
matlab/
  io/      WFDB header, signal and annotation readers, resampler, record loader
  model/   ab_params (every constant), ab_pt_filters, ab_pt_decide, ab_pt_detect,
           ab_pt_float / ab_pt_int, ab_int_widths (word lengths), ab_state_inventory
  eval/    beat matching, scoring (ab_run_eval), integer study, range study, plots
  tests/   unit tests, run by ab_test
scripts/   get_mitdb.ps1: download and SHA-256 check
docs/      algorithm spec, evaluation protocol, decision log, roadmap
results/   written by scripts, never edited by hand
data/      MIT-BIH, not committed
```

## Data and references

MIT-BIH Arrhythmia Database v1.0.0, PhysioNet, Open Data Commons Attribution License v1.0.

- J. Pan and W. J. Tompkins, "A real-time QRS detection algorithm," *IEEE Trans. Biomed.
  Eng.*, vol. BME-32, no. 3, pp. 230-236, 1985.
- G. B. Moody and R. G. Mark, "The impact of the MIT-BIH Arrhythmia Database," *IEEE Eng.
  Med. Biol. Mag.*, vol. 20, no. 3, pp. 45-50, 2001.
- A. L. Goldberger et al., "PhysioBank, PhysioToolkit, and PhysioNet," *Circulation*,
  vol. 101, no. 23, pp. e215-e220, 2000.
- ANSI/AAMI EC57, *Testing and reporting performance results of cardiac rhythm and ST
  segment measurement algorithms*.

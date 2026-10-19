# Algorithm: streaming Pan-Tompkins detector (v1)

The code is the source of truth: `matlab/model/ab_params.m`, `ab_pt_filters.m`,
`ab_pt_decide.m` and `ab_int_widths.m`. This page explains it. If the two disagree, fix
this page.

The model is written as the hardware will run it: one sample in, one state update, with
fixed-size state and only shifts, adds, compares and one squarer. One code path serves two
arithmetics. With `p.arith = 'float'` every shift divides exactly; this is the reference,
`ab_pt_float`. With `'int'` every shift is an arithmetic shift right; this is the
bit-accurate golden model for the RTL, `ab_pt_int`. Because both run the same code, any
difference between them comes from rounding alone.

## Signal chain (fs = 200 Hz)

| Stage | Operation | Gain | Delay (samples) |
|---|---|---|---|
| input | `x[n] = adc[n] - 1024` (11-bit ADC, zero at code 1024) | 1 | 0 |
| low-pass | `y[n] = 2y[n-1] - y[n-2] + x[n] - 2x[n-6] + x[n-12]`, `lp = y >> 5` | 36/32 at DC | 5 |
| high-pass | `S[n] = S[n-1] + lp[n] - lp[n-32]`, `hp[n] = lp[n-16] - (S >> 5)` | 0 at DC, 1 in the pass band | 16 |
| derivative | `der[n] = 2hp[n] + hp[n-1] - hp[n-3] - 2hp[n-4]` | | 2 |
| squarer | `sq[n] = (der^2 + 32) >> 6`, saturated at 16 bits (the only multiplier) | | 0 |
| integrator | `M[n] = M[n-1] + sq[n] - sq[n-30]` (150 ms) | | 14.5 |

The low-pass and high-pass together form the 5-15 Hz QRS band-pass. In the model the
low-pass runs as its equivalent FIR `[1 2 3 4 5 6 5 4 3 2 1]` and the running sums as
moving-sum FIRs. These give the same integers, and `test_int` checks the
equivalence against a register-level implementation with wrap-around arithmetic. The
MWI is a sum, not a mean: every decision compares MWI values with each other, so the
1/30 scaling would change nothing.

### Integer rounding rules

- **Scale late, round once.** The derivative's 1/8 from the paper is applied after the
  squarer, as part of `>> 6`. Rounding the small derivative of a low-amplitude beat before
  squaring gives a large relative error (D9).
- **Round to nearest where errors accumulate.** The MWI sums 30 squared samples, so
  truncation would bias it by -15 LSB. Adding half an LSB (`+ 32`) before the shift
  removes that bias (D10).
- **Clip MSBs before dropping LSBs.** `sq` saturates at 16 bits, the widest value it
  reaches on MIT-BIH, so nothing clips there, while the analytic worst case is 22 bits
  (D11). Clipping a few more MSBs costs no accuracy, and dropping LSBs costs it quickly
  unless MSBs are clipped too (D13, `results/int_study.md` section 4).
- **Accumulators never overflow.** Every running sum and recursive register has its
  analytic worst-case width (`ab_int_widths`), so approximations happen only at memoryless
  points (the `sq` shift and saturation), and the vectorised model stays exact.

## Decision logic (once per sample)

1. **Peak detector.** Track the running maximum of `mwi`. It becomes a *peak* when `mwi`
   falls below half of it, or when 200 ms pass without a new maximum. Then follow `mwi`
   down to the next valley. Each peak also carries the largest `sq` (its *slope*) and the
   position of the largest `|hp|` (its *R peak*), both taken since the previous peak.
2. **Startup.** The first 128 samples (0.64 s) are ignored while the filters settle. The
   next 256 samples (1.28 s) are the learning window: it keeps `max(mwi)` and the running
   mean (a sum of `mwi >> 8`), then sets `SPKI = (max >> 2) + (max >> 4)` and
   `NPKI = mean >> 1`.
3. **Classification.** A peak within 200 ms of the last QRS is ignored. Any other peak is
   a **QRS** if it is above `THR1` and is not a T wave. A T wave is a peak within 360 ms
   of the last QRS whose slope is less than half of that QRS's slope (`sq < last_sq >> 2`).
   Every other peak is a **noise peak**. A QRS updates `SPKI += (peak - SPKI) >> 3`, a
   noise peak updates `NPKI += (peak - NPKI) >> 3`, and then
   `THR1 = NPKI + ((SPKI - NPKI) >> 2)` and `THR2 = THR1 >> 1`.
4. **Searchback.** The largest noise peak above `THR2` since the last QRS, T waves excluded,
   is kept as a candidate. If no QRS arrives for `RR + RR>>1 + RR>>3 + RR>>5` samples
   (1.656 x the RR average), the candidate becomes a QRS and `SPKI += (peak - SPKI) >> 2`.
5. **Output.** Each QRS updates the RR average, kept with three fraction bits:
   `acc += rr - (acc >> 3)`, `RR = acc >> 3`. The reported beat time is the R-peak position
   minus the 21-sample band-pass delay.

Event positions are **age counters** (samples since the event), 11 bits wide and
saturating at 2047 (10.2 s). Distances between events are differences of ages, for
example `dt = age(last QRS) - age(peak)`. Nothing in the logic needs an absolute time.

## Constants

| Constant | Value | Hardware form | Pan & Tompkins 1985 |
|---|---|---|---|
| refractory period | 40 samples | counter compare | 200 ms |
| T-wave window | 72 samples | counter compare | 360 ms |
| peak confirmation | `mwi < max >> 1` or 40 samples | shift, compare, counter | "signal changes direction" |
| SPKI / NPKI update | `+= (peak - level) >> 3` | shift, add | 0.125 / 0.875 |
| searchback SPKI update | `+= (peak - SPKI) >> 2` | shift, add | 0.25 / 0.75 |
| THR1, THR2 | `NPKI + (SPKI - NPKI) >> 2`, `THR1 >> 1` | shift, add | same |
| T-wave slope test | `sq < last_sq >> 2` | shift, compare | slope < 1/2 |
| RR missed limit | 1.65625 x RR | `rr + rr>>1 + rr>>3 + rr>>5` | 1.66 |
| RR average | `acc += rr - acc >> 3` | shift, add | mean of the last 8 (two averages) |
| SPKI / NPKI init | 0.3125 x max, mean / 2 | `max>>2 + max>>4`, `sum>>1` | 2 s learning phase |

## Deviations from Pan & Tompkins (1985)

| # | Here | Paper | Why |
|---|---|---|---|
| 1 | high-pass = all-pass minus 32-point moving average | the printed transfer function has non-zero DC gain | follows Tompkins' reference C code, the intended filter |
| 2 | input resampled 360 -> 200 Hz | tapes digitised at 200 Hz | keeps the published coefficients (D1) |
| 3 | peak = MWI maximum confirmed at half height or after 200 ms | change of direction | ripple-proof (D4) |
| 4 | fiducial = largest \|band-pass\|, minus 21 samples | integration waveform | the MWI peak wanders on a plateau (D3) |
| 5 | one threshold set (MWI) | two sets (MWI and band-pass) | half the threshold hardware; revisit if accuracy demands |
| 6 | one RR average (EMA, 1/8), no irregular-rhythm threshold halving | RR AVERAGE1/2 with 92-116 % limits | one register instead of 16 words |
| 7 | 0.64 s blanking + 1.28 s learning | 2 s learning | power-of-two window, `sum >> 8` |
| 8 | derivative's 1/8 after the squarer, rounded to nearest, `sq` saturated | `der >> 3`, then square (C code) | precision for small beats, no MWI bias (D9-D11) |

## State inventory

[`results/state_inventory.md`](../results/state_inventory.md) lists every register with its
word length, generated by `ab_inventory_report` from the parameters. The four delay lines
(78 stored samples: 12 + 32 + 4 + 30) dominate the flip-flop count, and the MWI line's word
length (that of `sq`) is the biggest single knob. See
[`results/int_study.md`](../results/int_study.md), section 4.

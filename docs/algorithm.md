# Algorithm: streaming Pan-Tompkins detector (float reference, v1)

The code is the source of truth: `matlab/model/ab_params.m`, `ab_pt_filters.m` and
`ab_pt_decide.m`. This page explains it. If the two disagree, fix this page.

The model is written as the hardware will run it: one sample in, one state update, with
fixed-size state and only shifts, adds, compares and one squarer. The float and integer
models differ only in rounding, which isolates the effect of the arithmetic.

## Signal chain (fs = 200 Hz)

| Stage | Operation | Gain | Delay (samples) |
|---|---|---|---|
| input | `x[n] = adc[n] - 1024` (11-bit ADC, zero at code 1024) | 1 | 0 |
| low-pass | `y[n] = 2y[n-1] - y[n-2] + x[n] - 2x[n-6] + x[n-12]`, `lp = y / 32` | 36/32 at DC | 5 |
| high-pass | `hp[n] = lp[n-16] - (lp[n] + ... + lp[n-31]) / 32` | 0 at DC, 1 in the pass band | 16 |
| derivative | `der[n] = (2hp[n] + hp[n-1] - hp[n-3] - 2hp[n-4]) / 8` | | 2 |
| squarer | `sq[n] = der[n]^2` (the only multiplier) | | 0 |
| integrator | `mwi[n] = sq[n] + sq[n-1] + ... + sq[n-29]` (150 ms) | | 14.5 |

The low-pass and high-pass together form the 5-15 Hz QRS band-pass. In the model the
low-pass runs as its equivalent FIR `[1 2 3 4 5 6 5 4 3 2 1]`, which gives the same
numbers. The MWI is a sum, not a mean: every decision compares MWI values with each other,
so the 1/30 scaling would change nothing.

## Decision logic (once per sample)

1. **Peak detector.** Track the running maximum of `mwi`. It becomes a *peak* when `mwi`
   falls below half of it, or when 200 ms pass without a new maximum. Then follow `mwi`
   down to the next valley. Each peak also carries the largest `sq` (its *slope*) and the
   position of the largest `|hp|` (its *R peak*), both taken since the previous peak.
2. **Startup.** The first 128 samples (0.64 s) are ignored while the filters settle. The
   next 256 samples (1.28 s) are the learning window, after which
   `SPKI = 0.3125 * max(mwi)` and `NPKI = mean(mwi) / 2`.
3. **Classification.** A peak within 200 ms of the last QRS is ignored. Any other peak is
   a **QRS** if it is above `THR1` and is not a T wave. A T wave is a peak within 360 ms
   of the last QRS whose slope is less than half of that QRS's slope (`sq < last_sq / 4`).
   Every other peak is a **noise peak**. A QRS updates `SPKI += (peak - SPKI)/8`, a noise
   peak updates `NPKI += (peak - NPKI)/8`, and then `THR1 = NPKI + (SPKI - NPKI)/4` and
   `THR2 = THR1/2`.
4. **Searchback.** The largest noise peak above `THR2` since the last QRS, T waves excluded,
   is kept as a candidate. If no QRS arrives for 1.65625 x the RR average, the candidate
   becomes a QRS and `SPKI += (peak - SPKI)/4`.
5. **Output.** Each QRS updates the RR average, `RR += (rr - RR)/8`. The reported beat time
   is the R-peak position minus the 21-sample band-pass delay.

## Constants

| Constant | Value | Hardware form | Pan & Tompkins 1985 |
|---|---|---|---|
| refractory period | 40 samples | counter compare | 200 ms |
| T-wave window | 72 samples | counter compare | 360 ms |
| peak confirmation | `mwi < max/2` or 40 samples | shift, compare, counter | "signal changes direction" |
| SPKI / NPKI update | `+= (peak - level)/8` | shift, add | 0.125 / 0.875 |
| searchback SPKI update | `+= (peak - SPKI)/4` | shift, add | 0.25 / 0.75 |
| THR1, THR2 | `NPKI + (SPKI - NPKI)/4`, `THR1/2` | shift, add | same |
| T-wave slope test | `sq < last_sq/4` | shift, compare | slope < 1/2 |
| RR missed limit | 1.65625 x RR | `rr + rr>>1 + rr>>3 + rr>>5` | 1.66 |
| RR average | `+= (rr - RR)/8` | shift, add | mean of the last 8 (two averages) |
| SPKI / NPKI init | 0.3125 x max, mean / 2 | `x>>2 + x>>4`, `sum>>9` | 2 s learning phase |

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

## State inventory

Word lengths are left open until the week-2 integer model fixes them.

| Block | Stored samples | Scalar registers |
|---|---|---|
| low-pass | `x[n-1..n-12]`: 12 | `y[n-1]`, `y[n-2]` |
| high-pass | `lp[n-1..n-32]`: 32 | running sum |
| derivative | `hp[n-1..n-4]`: 4 | |
| integrator | `sq[n-1..n-30]`: 30 | running sum |
| peak detector | | rising flag, running max and its age, segment max `sq`, segment max `\|hp\|` and its age |
| levels | | `SPKI`, `NPKI`, `THR1` (`THR2` is a wire) |
| startup | | sample counter (to 384), learning max, learning sum |
| QRS history | | age of last QRS, last slope, RR average |
| searchback | | valid flag, value, age, slope, R-peak age |
| **total** | **78 words** | about 20 registers |

The 78 stored words dominate the area. See `ROADMAP.md`, "Settle these in week 2".

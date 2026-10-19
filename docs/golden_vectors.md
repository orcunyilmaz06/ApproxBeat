# Golden vectors and the RTL contract

The RTL is correct when it reproduces the integer model (`ab_pt_int`) bit for bit: every
stage, every sample, all 48 records. The golden vectors are that model's output, written
by `ab_write_golden`. This page fixes their format and what the RTL has to match.

## Sets

| Set | Where | Contents | Size | Committed |
|---|---|---|---|---|
| full | `data/golden/` | all 48 MIT-BIH records | ~410 MB | no; regenerate with `ab_write_golden` (~20 s) |
| smoke | `tb/vectors/` | `r100_20s` (first 20 s of record 100), `r210_30s` (first 30 s of record 210: searchback, T-wave and refractory decisions), `stress` (40 s of `ab_synthetic('stress')`, whose full-scale burst saturates `sq`) | ~450 KB | yes, for CI without MIT-BIH |

Every stream `<name>` has three files and the set has one `manifest.json`. The manifest
lists the column names, the word lengths, every parameter and the stream sizes; the full
set's manifest also records the git commit of the model. `test_golden` fails when the
committed smoke vectors no longer match the model, so regenerate them with
`ab_write_golden('smoke')` after any model change.

## Files

All files are NumPy `.npy`, int32, little-endian, C order, so in Python
`numpy.load('100_samples.npy')` returns an `(N, 6)` array. MATLAB reads them with
`ab_npy_read`. Sample indices are 0-based.

**`<name>_samples.npy`, N x 6, one row per input sample `n = 0 .. N-1`**

| Column | Signal | Type |
|---|---|---|
| `adu` | input ADC code | unsigned 11 bit |
| `lp` | low-pass output | signed 12 bit |
| `hp` | band-pass output | signed 13 bit |
| `der` | derivative | signed 15 bit |
| `sq` | `(der^2 + 32) >> 6`, saturated | unsigned 16 bit |
| `mwi` | moving-window integral | unsigned 21 bit |

`adu` is the stream the RTL must be fed: the recording followed by 1 s of its last code
(`ab_pt_stream`). Word lengths are those of `ab_int_widths` for the current parameters;
see `manifest.json`.

**`<name>_beats.npy`, B x 7, one row per QRS decision, in order**

| Column | Meaning |
|---|---|
| `n` | sample whose processing declared the QRS |
| `r_age` | samples from the R peak (largest \|hp\|) to `n`; the R peak of the ADC input is `n - r_age - 21` |
| `kind` | 1 above threshold, 2 searchback |
| `spk`, `npk`, `thr1`, `rr_lim` | SPKI, NPKI, THR1 and the RR-missed limit after the decision |

**`<name>_peaks.npy`, P x 9, one row per classified MWI peak**

| Column | Meaning |
|---|---|
| `index` | sample of the MWI maximum (`n - age`) |
| `value` | MWI value of the peak |
| `class` | 0 refractory, 1 QRS, 2 noise, 3 T wave, 4 noise peak later taken by searchback |
| `thr1_used` | THR1 the peak was compared with |
| `n`, `age` | sample at which the peak was confirmed and classified, and its age then |
| `spk`, `npk`, `thr1` | levels after the classification |

## What the RTL must reproduce

The core takes one sample per `in_valid` strobe and may spend a fixed number of clock
cycles on it. The planned ports are `clk`, `rst_n`, `in_valid`, `in_adu[10:0]`,
`beat_valid`, `beat_kind`, `beat_r_age[10:0]`.

1. **Reset.** After `rst_n`, every register is 0, except the RR average accumulator,
   which is `8 * rr_init` = 1600, and the RR limit, which is 331. The first sample after
   reset is `n = 0`.
2. **Datapath.** Once the core has processed sample `n`, its `lp`, `hp`, `der`, `sq` and
   `mwi` registers hold row `n` of `samples`.
3. **Beats.** Processing sample `n` produces exactly one `beat_valid` pulse if `beats` has
   a row with that `n`, and none otherwise. `beat_kind` must be 0 for kind 1 and 1 for
   kind 2, and `beat_r_age` must equal `r_age`. The testbench compares the whole beat
   sequence.
4. **Decision state.** At every peak and beat row, the internal SPKI, NPKI, THR1 and
   RR limit equal the logged values. Testbenches read them through the design hierarchy
   to find the first mismatch. They are not outputs.
5. **Order inside a sample** (`ab_pt_decide`): age counters increment and saturate at
   2047, then the peak detector, then startup or learning, then classification, then
   searchback, then QRS bookkeeping.

Any single difference fails the run. "Close" does not count.

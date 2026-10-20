<!---
This file is used to generate the Tiny Tapeout datasheet.
-->

## How it works

ApproxBeat detects heartbeats (QRS complexes) in an ECG sampled at 200 Hz with 11-bit
samples. It is a streaming Pan-Tompkins detector: a low-pass, high-pass, derivative,
squarer and 150 ms moving-window integrator, followed by adaptive thresholds with
searchback for missed beats and T-wave rejection. Every gain is a shift, and every
register has an analytically bounded word length.

The RTL is bit-exact to an integer model of the algorithm. On all 48 records of the
MIT-BIH Arrhythmia Database, that model finds 99.68 % of the beats with 99.78 % positive
predictivity. Source, evaluation and design decisions: the project repository (README,
`docs/decisions.md`).

The host hands the chip one sample at a time with a four-phase handshake, so the clock
can be anything from a few kHz to the design's maximum. 10 MHz is nominal. A sample
takes 4 to 13 clock cycles to process, plus the handshake.

| Pin | Direction | Function |
|---|---|---|
| `ui[7:0]` | in | ADC sample, bits 7..0 (11-bit code, 1024 = 0 mV) |
| `uio[2:0]` | in | ADC sample, bits 10..8 |
| `uio[3]` | in | REQ: a new sample is on the inputs |
| `uio[4]` | in | PAGE: selects the byte on `uo[7:0]` |
| `uio[5]` | out | KIND: the beat was found by searchback (0: above threshold) |
| `uio[6]` | out | BEAT: a beat was declared on this sample |
| `uio[7]` | out | ACK: the results of this sample are ready |
| `uo[7:0]` | out | PAGE 0: R-peak age, bits 7..0. PAGE 1: `{0, 0, class[1:0], PEAK, age[10:8]}` |

**Handshake.**

1. The host puts the sample on `ui[7:0]` and `uio[2:0]`, then raises REQ.
2. The chip processes the sample, latches the results and raises ACK.
3. The host reads BEAT, KIND and both pages of `uo`, then drops REQ.
4. The chip drops ACK, and the next sample may follow.

The sample must stay stable from REQ until ACK. The results hold until the next ACK.

**Outputs.**

- **R-peak age.** The number of samples from the beat's R peak to the current sample,
  measured in the band-pass signal. The R peak in the input signal is 21 samples earlier
  still. The age is 0 when BEAT is 0.
- **PEAK.** Set when an MWI peak was classified on this sample. Its class is 0
  (refractory), 1 (QRS), 2 (noise) or 3 (T wave).
- **Startup.** After reset, the detector learns its thresholds for 384 samples (1.92 s)
  and declares no beats in that time.

## How to test

From the demo board's microcontroller, stream an ECG at 200 samples per second, or as
fast as the handshake allows, for a recorded one. For each sample `code` (0..2047),
counted from `n = 0` after reset:

```
set ui_in = code & 0xFF, uio_in = (code >> 8) | REQ
wait for ACK
beat, kind = BEAT, KIND
age_lo = uo_out                       # PAGE 0
set uio_in = (code >> 8) | REQ | PAGE
age_hi, peak, cls = uo_out & 7, (uo_out >> 3) & 1, (uo_out >> 4) & 3
set uio_in = code >> 8                # drop REQ and PAGE
wait for ACK to drop
if beat: R peak at sample n - (age_hi << 8 | age_lo) - 21
```

`test/test.py` does exactly this in simulation. It runs the repository's smoke vectors,
20 s of MIT-BIH record 100, 30 s of record 210 and a synthetic stress signal, and checks
every beat and peak against the integer model.

## External hardware

None. The samples can come from the demo board's microcontroller, for example from a
recorded ECG. A live source needs an ECG front end and an 11-bit ADC at 200 Hz.

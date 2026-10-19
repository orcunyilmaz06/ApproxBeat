# Decision log

One entry per algorithm or protocol decision: what was decided, why, and the measured
effect where there is one. Newest at the bottom.

## 2026-10-19: D1. Run the detector at 200 Hz on resampled MIT-BIH

Pan & Tompkins designed their integer filters for 200 Hz. They digitised the MIT-BIH tapes
at that rate, while PhysioNet distributes them at 360 Hz. Resampling to 200 Hz keeps the
published coefficients unchanged and makes every delay line 44 % shorter than a 360 Hz
redesign would, which matters for a Tiny Tapeout tile. The resampler (`ab_resample`) is
linear-phase, so reference annotations map by time and need no shift.

## 2026-10-19: D2. Base MATLAB only

This machine has no Signal Processing Toolbox, and reviewers may not either. The WFDB
readers, the resampler and the filters are therefore written in base MATLAB, and the
readers are verified against the WFDB checksums of all 48 records (`test_io`).

## 2026-10-19: D3. R-peak fiducial from the band-pass output, not the MWI peak

The first version reported the MWI peak minus the nominal chain delay (37.5 samples). On a
synthetic ECG its timing error reached 77 ms, because a narrow QRS gives the 150 ms
integration window a flat top and the maximum lands anywhere on that plateau. The detector
now reports the largest |band-pass| sample between consecutive MWI peaks, minus the 21-sample
band-pass delay. The synthetic test then stays under 40 ms. On MIT-BIH, see the
timing-error column of `results/float_baseline.md`. Hardware cost: one magnitude
comparator, one register and one age counter.

## 2026-10-19: D4. MWI peak detector with hysteresis

A peak is the running MWI maximum, confirmed once the MWI falls below half of it or 200 ms
pass without a new maximum. The paper's rule ("the signal changes direction") also fires
on small ripples, for instance where the derivative crosses zero at the R peak. Each such
ripple would split a QRS into two peaks and cut short the slope measurement used by the
T-wave test.

## 2026-10-19: D5. Scoring follows EC57 practice, startup included

Ventricular flutter and fibrillation episodes are excluded from beat-by-beat scoring, as
EC57 does. The detector's learning window is **not** excluded: its 2-3 beats per record count
as misses (`docs/eval_protocol.md`). Scoring from the start of the record is the stricter
choice and is closer to how a wearable is used.

## 2026-10-19: D6. MLII lead

The MLII lead is used where a record has one, which is every record except 102 and 104
(V5). Record 114 stores MLII as its second signal, so the lead is chosen by name, not
by position.

## 2026-10-19: D7. Record 108 left as a known failure, not tuned

The float baseline's worst record is 108, with 43 FN and 98 FP (`results/float_baseline.md`).
Its large P waves arrive about 200 ms before each QRS, just outside the refractory period,
and cross THR1 (`results/figures/r108_pwave_false_positives.png`). A "larger peak within
N ms wins" rule would fix this record, but N would have to sit between the PR interval
here and the RR interval of ventricular tachycardia elsewhere in the database. That is
tuning on the test set, so the rule is not added. Any later fix must improve the gross
statistics without per-record parameters.

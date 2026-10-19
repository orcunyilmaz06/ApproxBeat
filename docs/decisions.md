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

## 2026-10-19: D8. One decision engine for float and integer arithmetic

The decision logic is written register by register: event positions are saturating
11-bit age counters, and every gain is a list of shifts. `p.arith` chooses whether a shift
divides exactly (`'float'`) or rounds down (`'int'`). Rewriting the float model into this
form left TP, FN and FP unchanged on all 48 records, as checked against the committed
baseline. Any float/integer difference therefore comes from rounding.

## 2026-10-19: D9. The derivative's 1/8 moves behind the squarer

Tompkins' C code shifts the derivative right by 3 and then squares it. In integer
arithmetic that truncates the small derivatives of low-amplitude beats. Here the squarer
sees the full derivative and the combined scaling is one `>> 6` after it. In
`results/int_study.md` section 2, DER drops from 0.693 % (configuration A) to 0.572 % (B,
rounded). Cost: the squarer grows from 12 x 12 to 15 x 15 bits. No delay line grows,
because the derivative is not stored.

## 2026-10-19: D10. Round to nearest at the squarer shift

Truncation lowers every `sq` by half an LSB on average, and the MWI sums 30 of them, a
-15 LSB bias that hurts small beats the most. Adding half an LSB before the shift costs
one constant adder. Truncated, configuration B gives DER 0.593 % and 48 FN in record 228;
rounded, it gives 0.572 % and 20 FN, the same as the float model (`int_study.md`,
sections 2 and 4a). With rounding, the decision logic's own rounding no longer changes
record 228 (last column of section 2).

## 2026-10-19: D11. Saturate the squared derivative at 16 bits

The analytic worst case of `sq` is 22 bits, but the widest value on MIT-BIH needs 16
(`results/range_study.md`). Saturating at 16 bits clips nothing on MIT-BIH. It shrinks
the MWI line from 660 to 480 flip-flops and the MWI and decision registers from 27 to
21 bits. The integer baseline has 1,403 flip-flops, 75 % of them in the four delay lines
(`results/state_inventory.md`).

## 2026-10-19: D12. Record 228 sits at a tipping point

Record 228 has long runs of bigeminy, where large PVCs alternate with small normal beats.
The PVCs dominate SPKI, so the normal beats are found only by searchback. Once a few are
missed, the RR average locks onto the PVC-to-PVC interval, the searchback fires too late,
and THR2 rises above the normal beats. That state absorbs: the detector stays in it.

Evidence (`results/int_study.md`):
- Across the rounding variants of section 2, the record's FN count ranges from 20 to 222.
- Configurations C and D-rounded keep more bits than the baseline yet give 55. Closer
  arithmetic does not predict the outcome.
- Zero-mean input dither of +/-1 LSB moves no record by more than 5 (section 3). The
  record is pushed over by systematic bias, not by noise.

Consequences:
- Protocol item 8 (`eval_protocol.md`).
- The searchback needs a robustness fix before the approximate-arithmetic study, or the
  study will mostly measure which side of this tipping point each variant lands on.

## 2026-10-19: D13. Clipping MSBs of the squared derivative helps (finding, not adopted)

In the word-length grid (`results/int_study.md`, section 4b), saturating `sq` 4 bits below
its MIT-BIH maximum (12 bits) lowers DER from 0.572 % to 0.553 % and FN in 228 from 20 to
10. Combined with dropping 1-2 LSBs, DER stays at 0.548-0.550 % with 1,198-1,157
flip-flops, 15-18 % fewer than the baseline. Clipping 6 MSBs goes too far: noise peaks
become as large as QRS complexes, and +P falls to about 98 %.

The likely mechanism: saturation compresses the MWI's dynamic range, so large PVCs no
longer dominate SPKI. That is the failure behind D12.

The finding is not adopted as the baseline, because the grid was evaluated on the same
records it would be judged on. It is the leading candidate for the v1 tape-out if area is
tight. Confirm it on a held-out split first, such as the AAMI DS1/DS2 record split: choose
on DS1, report on DS2.

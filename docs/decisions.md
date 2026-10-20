# Decision log

One entry per algorithm or protocol decision: what was decided, why, and the measured
effect where there is one. Newest at the bottom. Each entry cites the results files as
they were when it was written, and git history keeps those versions: D1-D7 at commit
3a535a3, D8-D13 at 60b857a. Later changes are added as updates under the entry.

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

*Update after D14.* With the outlier-clipped SPKI, configuration A is no worse than B:
DER 0.513 % against 0.544 % on all 48 records (`int_study.md`, section 2). This is not a
DS1 choice. B's measured advantage had come through the record-228 tipping point, not
through the precision gain itself. B stays the baseline as the high-precision reference
for the approximation study. A, with its 12-bit squarer instead of 15 bits, is the first
approximate-multiplier candidate.

## 2026-10-19: D10. Round to nearest at the squarer shift

Truncation lowers every `sq` by half an LSB on average, and the MWI sums 30 of them, a
-15 LSB bias that hurts small beats the most. Adding half an LSB before the shift costs
one constant adder. Truncated, configuration B gives DER 0.593 % and 48 FN in record 228;
rounded, it gives 0.572 % and 20 FN, the same as the float model (`int_study.md`,
sections 2 and 4a). With rounding, the decision logic's own rounding no longer changes
record 228 (last column of section 2).

*Update after D14.* Truncated and rounded now give 0.545 % and 0.544 %, so the bias no
longer shows in the gross statistics. Rounding stays in the baseline because it keeps
the reference unbiased. When many LSBs are dropped, truncation is even better: with 6
dropped, it gives 0.737 % against 0.959 % rounded (section 4a). The likely reason is that
truncation zeroes small noise, acting as a dead zone. That makes it an approximation
worth testing in its own right.

## 2026-10-19: D11. Saturate the squared derivative at 16 bits

The analytic worst case of `sq` is 22 bits, but the widest value on MIT-BIH needs 16
(`results/range_study.md`). Saturating at 16 bits clips nothing on MIT-BIH. It shrinks
the MWI line from 660 to 480 flip-flops and the MWI and decision registers from 27 to
21 bits. The integer baseline has 1,403 flip-flops, 75 % of them in the four delay lines
(`results/state_inventory.md`).

*Update (D15).* The inventory now also counts the RR missed limit, which the model stores
too, and the RTL's sequencing registers: 1,542 flip-flops in all, 68 % of them in the delay
lines.

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

*Update after D14.* With the outlier-clipped SPKI, clipping MSBs no longer improves
accuracy much: DER is 0.535 % against 0.544 % with 4 clipped bits. That fits the idea that
both act through the same mechanism. Clipping stays free, though. With 4 MSBs clipped and
4 LSBs dropped, `sq` fits in 8 bits, the design needs 1,075 flip-flops (-23 %), and DER is
0.542 % (`int_study.md`, section 4b; all 48 records, not yet a DS1 choice). Clipping 6 MSBs
still costs +P, which falls to about 97.9 %.

## 2026-10-19: D14. Outlier-clipped signal level (SPKI)

**Rule.** A QRS peak enters the SPKI update clipped to 1.25 x SPKI:

    SPKI += (min(peak, SPKI + SPKI >> 2) - SPKI) >> 3

One large beat can now raise SPKI by at most 3 %. Small beats still pull it down at full
speed. Hardware cost: a shift, an adder and a min, with no new register.

**Why.** D12's absorbing state starts when large PVCs pull SPKI up in big steps. With
the paper's update, a single PVC 30 times the size of the normal beats raises SPKI by
almost four times the normal-beat level. Bounding the step keeps the threshold in reach
of the small beats as long as the detector is tracking them. The same bound protects
against one huge artifact counted as a QRS.

**Choice.** Made on DS1 alone, with a rule fixed in advance: lowest DS1 DER, ties within
0.01 pp go to the weaker clip. The candidates were no clip, 2 x, 1.5 x and 1.25 x, and
1.25 x won (`results/searchback_study.md`). The float model on the held-out DS2:

- DER falls from 0.430 % to 0.412 %. Se rises from 99.71 to 99.76 %, +P drops from 99.85
  to 99.82 %.
- Record 228, which is in DS2, falls from 20 to 3 FN.

**Robustness.** Across the six rounding configurations of the integer model, record
228's FN count spread falls from 20-216 to 3-3, and the spread of the gross DER from
0.175 pp to 0.034 pp. The tipping point of D12 is gone, so arithmetic variants can now be
compared on their own merit.

**Limitation.** The clip bounds the step size. It does not repair a wrong start: a
record that begins in such bigeminy gets its SPKI from a PVC in the learning window, and
the small beats stay lost (`test_detector`, comment in
`test_bigeminy_with_small_normal_beats`). A fix would need a way to lower SPKI without a
QRS, for example a slow decay. That is left for later.

## 2026-10-20: D15. RTL architecture, first version

**Filter chain** (`src/ab_filters.v`). It computes every stage of a sample in the clock
cycle that brings it. The delay lines are packed shift registers. The design is written
for correctness first, and area comes later.

**Decision logic** (`src/ab_decide.v`). A four-phase state machine runs once per sample:
PEAK, CLASS, SEARCH, BOOK. This keeps the model's order inside a sample, including
same-sample effects such as a searchback that fires on a candidate taken one phase
earlier. A sample takes 6 clock cycles, while the ADC delivers one every 5 ms. The phases
cost registers that the model does not have: an input latch, the classified peak, the
phase and flags, and the event outputs. Together they come to 127 flip-flops, and
`ab_state_inventory` now counts them, giving 1,542 flip-flops in total.

**Area-phase candidates.**
- Drop the input latch (49 flip-flops), since the filter outputs are already stable until
  `done`.
- Merge PEAK into CLASS (54).
- Share one adder across the phases.
- Then the word lengths of D13.

**Verification.** Smoke vectors on every change, and all 48 records end to end
(`results/rtl_filters.md`, `results/rtl_core.md`).

## 2026-10-20: D16. Generic synthesis: the flip-flops reconcile, and logic is the other half

Yosys 0.33 on generic gates (`flow/synth`, `results/synth_core.md`) gives `ab_core` 1,516
flip-flops and 7,057 logic cells. The flip-flops reconcile with the 1,542 declared
register bits, which are what `ab_state_inventory` counts:

- **-24.** `y1` and `y2` of the low-pass are `lp` shifted left by 5 plus 5 LSBs, so their
  upper 12 bits equal the first two slots of `lp_line`. Yosys merges them. An RTL that
  keeps only the 5 LSBs of `y1` and `y2` would make this explicit.
- **-4.** `last_slope` and `sb_slope` are only ever read shifted right by 2, so their two
  LSBs go.
- **+2.** The FSM pass re-encodes the decision phases one-hot, with 5 flip-flops instead
  of 3.

The inventory is therefore accurate to 1.7 %.

The logic is not small. 4,434 of the 7,057 cells are in the decision logic, where every
phase has its own adders and comparators, and the level update alone exists six times.
The filter chain, squarer included, has 2,622.

Area plan, with D15:
- Share one level-update unit across the phases.
- Drop the input latch.
- Merge PEAK into CLASS.
- Then measure on a real PDK with LibreLane.

## 2026-10-20: D17. Area step 1: one shared adder, no input latch

Measured by generic synthesis (`flow/synth`). The reports are at commits e320531 and
cdd8653, and `results/synth_core.md` holds the last row.

| RTL | `ab_decide` logic cells | `ab_decide` flip-flops | design logic cells | design flip-flops |
|---|---:|---:|---:|---:|
| four phases, own adders (e320531) | 4,434 | 419 | 7,057 | 1,516 |
| one shared adder (cdd8653) | 2,795 | 441 | 5,400 | 1,538 |
| plus no input latch | 2,789 | 392 | 5,401 | 1,489 |

**Shared adder.** Every sum of the decision logic now runs through one 23-bit
adder/subtractor: the level and threshold updates, the clip, the learning sum and the
initial levels, in 11 states. A carry-in turns subtraction into the same addition, so
only one adder is built. Each sum takes one cycle, so a sample takes 4 to 14 cycles
instead of 6, still far inside the 5 ms between samples.
Comparators keep their own logic, because they need no sum bits and sharing them would
cost more in multiplexers than it saves. The decision logic shrinks by 37 % and gains a
23-bit result register.

**No input latch.** `mwi`, `sq` and `hp` stay stable from `in_valid` until `done`: in
the core they are register outputs of `ab_filters`, and the next sample comes after
`done`. Copying them is unnecessary, which saves 49 flip-flops. `ab_state_inventory`
follows the RTL and now counts 1,517 flip-flops for the baseline instead of 1,542. The
word-length grid of `results/int_study.md` shifts by the same amount; its accuracy
figures are unchanged.

**Noise.** The same RTL always synthesizes to the same counts. But `ab_filters`, whose
RTL did not change, gave 2,622, 2,604 and 2,611 logic cells in the three rows: its logic
count moves by about 1 % when `ab_decide` changes. Logic differences below that are
noise. Flip-flop counts are exact.

**Verified.** `ab_decide` is bit-exact on the smoke vectors and on records 203 and 228.
The core is bit-exact end to end on all 48 records: 276,457 peak and 109,794 beat
events, the same table as before the area step (`results/rtl_core.md`). That run used
the new `full-parallel` target, which splits the 48 records over 6 simulators and takes
13 minutes instead of about 55.

## 2026-10-20: D18. Area step 2: the classified peak needs no copy

Before this step, PEAK advanced the peak detector and copied a confirmed peak into four
registers: `c_val`, `c_age`, `c_slope` and `c_r_age`, 54 bits in all. CLS then
classified it one cycle later. Now the peak detector and the segment maxima advance
last, in BOOK. No step in between reads their new values, so until BOOK their registers
still hold the confirmed peak. The classification reads them directly, in the PEAK
cycle. The four registers become wires, the CLS state goes away, and a confirmed peak
takes one cycle less, so a sample now takes 4 to 13 cycles.

Measured by generic synthesis (`flow/synth`, `results/synth_core.md`):

| RTL | `ab_decide` logic cells | `ab_decide` flip-flops | design logic cells | design flip-flops |
|---|---:|---:|---:|---:|
| D17 (6f29b60) | 2,789 | 392 | 5,401 | 1,489 |
| classification in PEAK, first version | 3,013 | 338 | 5,618 | 1,435 |
| the same, flat candidate update | 2,836 | 338 | 5,441 | 1,435 |

**The first version cost logic.** It saved the 54 flip-flops but added 224 logic cells.
The searchback-candidate update sat at the bottom of the classification's if-else
chain and overrode the age increments of `sb_age` and `sb_r_age`. Yosys built an
11-bit multiplexer for every level of that chain: six more `$mux_11` before mapping and
139 more multiplexer cells after it. ABC did not fold them. One flat condition
(`cand_now`) gives each register a single choice, and the multiplexer count returns to
D17's.

**Net.** The design has 54 fewer flip-flops (-3.6 %) and 40 more logic cells (+0.7 %).
In the decision logic the logic cells are 1.7 % above D17, a little more than the
noise. The classification now reads the incremented RR age and peak age, where it used
to read registers. A flip-flop with reset and enable costs several gates of area, so
the step is a net gain, but only LibreLane on a real PDK can size it.

**Inventory.** `ab_state_inventory` drops its classified-peak row and counts 1,463
flip-flops, which equals the declared RTL register bits. The word-length grid of
`results/int_study.md` moves by the same 54. Its accuracy figures are unchanged, and
the 8-bit `sq` variant of D13 needs 1,127 flip-flops (-23 %).

**Verified.** Bit-exact on the smoke vectors (decide, core) and end to end on all 48
records: 276,457 peak and 109,794 beat events, the same table as before
(`results/rtl_core.md`, `full-parallel`, 15 minutes).

## 2026-10-20: D19. Word length of `sq`, chosen on DS1: not confirmed on DS2

D13 found that `sq` could be stored in far fewer bits than 16, but it had judged that on
all 48 records. This step made the choice by protocol item 9 (`ab_wordlength_study`,
`results/wordlength_study.md`). The candidates drop e = 0-6 LSBs and clip c = 0-6 MSBs
of the exact design (integer model, rounding on). The rule was written in the script
header before the run:

- **Acceptable:** on DS1, DER at most 0.02 pp above the exact design, with Se and +P
  each at most 0.02 pp below it.
- **Chosen:** the acceptable candidate with the fewest flip-flops.
- **Confirmed:** only if the chosen candidate meets the same tolerance on DS2.

**Result.** The rule chose 5 LSBs dropped and 5 MSBs clipped: `sq` in 6 bits, 1,043
flip-flops instead of 1,463 (-29 %). On DS1 it looked better than the exact design, with
DER 0.678 % against 0.719 %. On DS2 it is worse, 0.668 % against 0.422 %, so it fails
the confirmation. Most of the difference is record 222, where false positives rise from
13 to 122. Record 210 also misses 8 more beats. **Not adopted: the design keeps `sq` at
16 bits.**

**What the grid shows.** Dropping 5 or more LSBs raises DS2 DER to 0.65 % or more in
every row, while DS1 barely moves. The records that expose it are all in DS2. With up to
4 LSBs dropped and up to 5 MSBs clipped, the DS2 DER stays within the tolerance.
Clipping 6 MSBs fails on both sets, as D13 found.

**Lesson.** "Fewest flip-flops within tolerance" picks the edge of the region that is
acceptable on DS1, where one unseen record can push it over. A rule with a margin
would have been safer, for example one that also requires the neighbouring grid points
to be acceptable. Writing such a rule now, after looking at DS2, would not give a
held-out result, so no other candidate is adopted on this evidence.

**What stays.** The RTL takes the word length as parameters: `SQ_SHIFT` and `SQ_BITS`
of `ab_core`, with the MWI and level widths derived from them. The defaults are the
exact design, and they are bit-exact against its golden vectors. Variants for the
accuracy-area front can now be synthesized without editing the RTL, and `flow/synth`
prints the parameters it used. Only the defaults are verified so far. A variant counts
as correct only once it passes against golden vectors generated with its own
parameters.

**Verified (defaults).** The parametric RTL is bit-exact on the smoke vectors (filters,
decide, core) and on all 48 records. The filter chain matches at every stage of all
17,342,976 samples, in 6 minutes on 6 simulators (`results/rtl_filters.md`). The core
matches end to end: 276,457 peak and 109,794 beat events (`results/rtl_core.md`).
Synthesis gives the same 1,435 flip-flops. The filter chain maps to 2,513 logic cells
instead of 2,604, because the squarer is now written generically for any `SQ_SHIFT`
(`results/synth_core.md`).

# Evaluation protocol (frozen)

`ab_run_eval` produces every accuracy number in this project, under exactly this protocol.
Changing the protocol requires an entry in `decisions.md`.

1. **Database.** MIT-BIH Arrhythmia Database v1.0.0 (PhysioNet): all 48 records, each the
   full 30 minutes. Files are verified by SHA-256 when downloaded and by the WFDB checksums
   on every load.
2. **Input.** The MLII lead of each record (V5 in records 102 and 104, which have no MLII),
   resampled from 360 Hz to 200 Hz with a linear-phase windowed-sinc filter (`ab_resample`),
   then rounded and clipped to 11-bit ADC codes. This models a 200 Hz, 11-bit ADC in front
   of the chip.
3. **Reference beats.** Every annotation that WFDB counts as a QRS complex (`isqrs`):
   `N L R a V F J A S E j / Q B ? ! e n f r`.
4. **Exclusions.** Reference beats and detections inside ventricular flutter / fibrillation
   episodes (from `[` to `]`) are not scored, because ANSI/AAMI EC57 scores VF detection
   separately. In MIT-BIH this removes the 472 flutter waves of record 207, leaving
   109,494 scored beats. Nothing else is excluded. In particular, the detector's 1.92 s
   learning window at the start of each record is scored, so beats there count as missed.
5. **Matching.** A detection matches a reference beat if it lies within +/-150 ms of it,
   one-to-one (`ab_match_beats`).
6. **Metrics.** TP, FN and FP per record; gross statistics summed over records:
   Se = TP/(TP+FN), +P = TP/(TP+FP), F1 = 2TP/(2TP+FP+FN), DER = (FP+FN)/(TP+FN).
   They are reported for all 48 records and for the 44 non-paced records (102, 104, 107
   and 217 are paced).
7. **One parameter set.** `ab_params` applies to every record. Nothing is tuned per record.
8. **Comparing variants** (float against integer, or approximate designs). Report the gross
   statistics of both and list every record whose FN or FP changed. Before D14, record 228
   sat at a tipping point of the searchback (D12), and a swing there alone was not evidence
   of an arithmetic effect. Input dither of +/-1 LSB sets the noise floor for gross
   differences (`results/int_study.md`, section 3).
9. **Design set and held-out set.** Any choice between algorithm variants or parameter
   values is made on DS1 alone, by a rule written down before the run. The result is
   then reported on DS2 and on all 48 records. DS1 and DS2 are the standard 22 + 22 split
   of the non-paced records (de Chazal et al., IEEE TBME 51(7), 2004), listed in
   `ab_records`. Results from before this rule (D1-D13) were chosen on all records and
   are labelled as such.

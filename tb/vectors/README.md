# Smoke vectors

Golden vectors of the integer model for two short streams, committed so that CI can run
the RTL testbench without downloading MIT-BIH. Written by
`matlab -batch "cd('matlab'); ab_setup; ab_write_golden('smoke')"`, and kept in sync with
the model by `test_golden`. Format: [`docs/golden_vectors.md`](../../docs/golden_vectors.md).

- `r100_20s`: the first 20 s of MIT-BIH record 100, clean sinus rhythm.
- `r210_30s`: the first 30 s of MIT-BIH record 210, which includes searchback, T-wave and
  refractory decisions, so every path of the decision logic is exercised.

  Both are lead MLII, resampled to 200 Hz. Source: Moody GB, Mark RG, MIT-BIH Arrhythmia
  Database v1.0.0, PhysioNet, Open Data Commons Attribution License v1.0.
- `stress`: 40 s of `ab_synthetic('stress')`, ECG-like pulses with a full-scale
  square-wave burst that drives every stage to its largest values.

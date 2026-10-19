function tests = test_detector
%TEST_DETECTOR  End-to-end check of the float detector on a synthetic ECG.
tests = functiontests(localfunctions);
end

function test_synthetic_ecg(tc)
p = ab_params();
fs = p.fs;
rng(7);
n = (0:60 * fs - 1)' / fs;
tq = 0.4 + cumsum(0.8 + 0.08 * randn(80, 1));
tq = tq(tq < 59);
ecg = 0.3 * sin(2 * pi * 0.2 * n) + 0.01 * randn(size(n));       % baseline wander + noise, mV
g = @(t0, w) exp(-0.5 * ((n - t0) / w).^2);
for t = tq'
    ecg = ecg + 0.1 * g(t - 0.16, 0.02) + g(t, 0.012) - 0.2 * g(t + 0.03, 0.01) ...
              + 0.3 * g(t + 0.26, 0.045);                          % P, R, S, T
end
det = ab_pt_float(round(p.adc_zero + 200 * ecg), p);

% score from the middle of the first RR interval after the learning phase
k = find(tq > (p.blank + p.learn) / fs + 0.3, 1);
t0 = (tq(k - 1) + tq(k)) / 2;
t_det = det.sample / fs;
m = ab_match_beats(tq(tq > t0), t_det(t_det > t0), 0.15);
tc.verifyEqual([m.fn m.fp], [0 0]);
tc.verifyLessThan(max(abs(m.err)), 0.04);
end

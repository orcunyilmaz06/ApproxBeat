function tests = test_detector
%TEST_DETECTOR  End-to-end checks of the float detector on synthetic ECGs.
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
m = score(tq, det.sample / fs, p);
tc.verifyEqual([m.fn m.fp], [0 0]);
tc.verifyLessThan(max(abs(m.err)), 0.04);
end

function test_bigeminy_with_small_normal_beats(tc)
% 20 s of small normal beats, then bigeminy: large, wide PVCs with about 30 times the
% MWI energy alternate with the normal beats. With the outlier-clipped SPKI update
% (D14) every beat is found. With the paper's unclipped update, the PVCs lift THR2
% above the normal beats and those are lost. (A record that starts in such bigeminy
% defeats both: the learning window then sets SPKI from a PVC, see D14.)
p = ab_params();
fs = p.fs;
rs = RandStream('mt19937ar', 'Seed', 11);
n = (0:90 * fs - 1)' / fs;
tq = []; tv = []; t = 0.6;
while t < 20
    tq(end+1) = t; tv(end+1) = false;          %#ok<AGROW> normal rhythm
    t = t + 0.8;
end
while t < 88
    tq(end+1) = t; tv(end+1) = false;          %#ok<AGROW> normal beat
    t = t + 0.55;
    tq(end+1) = t; tv(end+1) = true;           %#ok<AGROW> PVC
    t = t + 1.05;                              % compensatory pause
end
ecg = 0.2 * sin(2 * pi * 0.25 * n) + 0.01 * randn(rs, size(n));
g = @(t0, w) exp(-0.5 * ((n - t0) / w).^2);
for k = 1:numel(tq)
    if tv(k)
        ecg = ecg + 2.8 * g(tq(k), 0.020) - 0.5 * g(tq(k) + 0.30, 0.06);   % wide PVC, inverted T
    else
        ecg = ecg + 0.4 * g(tq(k), 0.012) + 0.15 * g(tq(k) + 0.25, 0.045);
    end
end
adu = min(max(round(p.adc_zero + 200 * ecg), 0), 2^p.adc_bits - 1);
m = score(tq', ab_pt_float(adu, p).sample / fs, p);
tc.verifyEqual([m.fn m.fp], [0 0]);
q = p; q.spk_clip_shifts = [];
tc.verifyGreaterThan(score(tq', ab_pt_float(adu, q).sample / fs, q).fn, 10);
end

function m = score(tq, t_det, p)
% score from the middle of the first RR interval after the learning phase
k = find(tq > (p.blank + p.learn) / p.fs + 0.3, 1);
t0 = (tq(k - 1) + tq(k)) / 2;
m = ab_match_beats(tq(tq > t0), t_det(t_det > t0), 0.15);
end

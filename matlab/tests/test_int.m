function tests = test_int
%TEST_INT  The bit-accurate integer model: word lengths, register-level equivalence, detection.
tests = functiontests(localfunctions);
end

function test_widths_hold_under_stress(tc)
% Full-scale noise and square waves drive every stage hard; ab_pt_filters asserts that
% each integer signal stays inside the analytic range of ab_int_widths.
p = ab_params(); p.arith = 'int'; p.sq_bits = inf;   % analytic widths, no saturation
rs = RandStream('mt19937ar', 'Seed', 3);
top = 2^p.adc_bits - 1;
sq_wave = @(period, n) top * (mod(0:n-1, period) < period / 2)';
adu = [randi(rs, [0 top], 4000, 1); sq_wave(12, 2000); sq_wave(24, 2000); sq_wave(64, 2000); ...
       repmat([0; top], 1000, 1)];
s = ab_pt_filters(adu, p);
w = ab_int_widths(p);
tc.verifyLessThanOrEqual(max(s.sq), w.sq.hi);
tc.verifyGreaterThan(max(abs(s.lp_acc)), 0.9 * w.lp_acc.hi);   % the LP bound is reached
end

function test_register_level_equivalence(tc)
% A register-level datapath (recursive filters, registers of the analytic widths,
% two's-complement wrap-around) gives exactly the vectorised integer filter chain.
p = ab_params(); p.arith = 'int';
adu = stress_signal(20000);
s = ab_pt_filters(adu, p);
r = stream_filters(adu, p);
for f = {'lp', 'hp', 'der', 'sq', 'mwi'}
    tc.verifyEqual(r.(f{1}), s.(f{1}), [f{1} ' differs from the register-level model']);
end
end

function test_int_detects_synthetic_ecg(tc)
p = ab_params();
[adu, tq] = synthetic_ecg(p);
det = ab_pt_int(adu, p);
k = find(tq > (p.blank + p.learn) / p.fs + 0.3, 1);
t0 = (tq(k - 1) + tq(k)) / 2;
t_det = det.sample / p.fs;
m = ab_match_beats(tq(tq > t0), t_det(t_det > t0), 0.15);
tc.verifyEqual([m.fn m.fp], [0 0]);
end

function test_float_model_is_scale_free(tc)
% Moving the derivative's 1/8 behind the squarer (D9) rescales every MWI value by the
% same factor, so the float model must give exactly the same detections.
p = ab_params();
adu = synthetic_ecg(p);
a = p; a.der_shift = 3; a.sq_shift = 0;
b = p; b.der_shift = 0; b.sq_shift = 6;
tc.verifyEqual(ab_pt_float(adu, a).sample, ab_pt_float(adu, b).sample);
end

% ---------------------------------------------------------------------------

function r = stream_filters(adu, p)
% One sample per step, as the RTL: the low-pass in its recursive form
% y[n] = 2y[n-1] - y[n-2] + x[n] - 2x[n-6] + x[n-12], running sums for the high-pass and MWI.
w = ab_int_widths(p);
N = numel(adu);
xd = zeros(1, 12); y1 = 0; y2 = 0;              % x[n-1..n-12], y[n-1], y[n-2]
lpd = zeros(1, p.hp_len); hsum = 0;             % lp[n-1..n-32], running sum
hpd = zeros(1, 4);                              % hp[n-1..n-4]
sqd = zeros(1, p.mwi_len); msum = 0;            % sq[n-1..n-30], running sum
[r.lp, r.hp, r.der, r.sq, r.mwi] = deal(zeros(N, 1));
for n = 1:N
    x  = adu(n) - p.adc_zero;
    y  = wrap(2 * y1 - y2 + x - 2 * xd(6) + xd(12), w.lp_acc.bits);
    xd = [x, xd(1:end-1)]; y2 = y1; y1 = y;
    lp = floor(y / 2^p.lp_shift);
    hsum = wrap(hsum + lp - lpd(end), w.hp_acc.bits);
    hp = wrap(lpd(p.hp_len / 2) - floor(hsum / 2^p.hp_shift), w.hp.bits);
    lpd = [lp, lpd(1:end-1)];
    der = floor(wrap(2 * hp + hpd(1) - hpd(3) - 2 * hpd(4), w.der_acc.bits) / 2^p.der_shift);
    hpd = [hp, hpd(1:end-1)];
    sq = min(floor((der^2 + p.sq_round * 2^(p.sq_shift - 1)) / 2^p.sq_shift), 2^p.sq_bits - 1);
    msum = mod(msum + sq - sqd(end), 2^w.mwi.bits);
    sqd = [sq, sqd(1:end-1)];
    r.lp(n) = lp; r.hp(n) = hp; r.der(n) = der; r.sq(n) = sq; r.mwi(n) = msum;
end
end

function v = wrap(v, bits)
v = mod(v + 2^(bits - 1), 2^bits) - 2^(bits - 1);
end

function adu = stress_signal(n)
% ECG-like pulses, baseline wander, noise and a few full-scale bursts.
rs = RandStream('mt19937ar', 'Seed', 5);
t = (0:n-1)' / 200;
v = 1024 + 300 * sin(2 * pi * 0.3 * t) + 8 * randn(rs, n, 1);
v = v + 600 * exp(-0.5 * ((mod(t, 0.8) - 0.4) / 0.012).^2);
v(5001:5400) = 2047 * (mod(0:399, 12) < 6);
adu = min(max(round(v), 0), 2047);
end

function [adu, tq] = synthetic_ecg(p)
fs = p.fs;
rs = RandStream('mt19937ar', 'Seed', 7);
n = (0:60 * fs - 1)' / fs;
tq = 0.4 + cumsum(0.8 + 0.08 * randn(rs, 80, 1));
tq = tq(tq < 59);
ecg = 0.3 * sin(2 * pi * 0.2 * n) + 0.01 * randn(rs, size(n));
g = @(t0, w) exp(-0.5 * ((n - t0) / w).^2);
for t = tq'
    ecg = ecg + 0.1 * g(t - 0.16, 0.02) + g(t, 0.012) - 0.2 * g(t + 0.03, 0.01) ...
              + 0.3 * g(t + 0.26, 0.045);
end
adu = round(p.adc_zero + 200 * ecg);
end

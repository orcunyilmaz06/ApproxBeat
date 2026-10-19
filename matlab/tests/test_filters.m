function tests = test_filters
%TEST_FILTERS  Responses and delays of the Pan-Tompkins filter chain, and the resampler.
tests = functiontests(localfunctions);
end

function test_lowpass_impulse(tc)
p = ab_params();
s = ab_pt_filters(p.adc_zero + [32; zeros(39, 1)], p);
tc.verifyEqual(s.lp', [1 2 3 4 5 6 5 4 3 2 1, zeros(1, 29)]);   % triangle centred on delay 5
end

function test_highpass_removes_dc(tc)
p = ab_params();
s = ab_pt_filters(p.adc_zero + 100 * ones(200, 1), p);
tc.verifyEqual(s.lp(end), 100 * 36 / 32);                        % LP DC gain 36 / 2^5
tc.verifyEqual(s.hp(60:end), zeros(141, 1));                     % settled after 11 + 31 samples
end

function test_bandpass_delay(tc)
% A narrow symmetric pulse at sample k0 peaks in the band-pass output p.r_delay samples later.
p = ab_params();
k0 = 300;
n = (0:599)';
s = ab_pt_filters(p.adc_zero + round(400 * exp(-0.5 * ((n - k0) / 2).^2)), p);
[~, imax] = max(abs(s.hp));
tc.verifyEqual((imax - 1) - k0, p.r_delay);
end

function test_resample_sine(tc)
x = 500 * sin(2 * pi * 10 * (0:3599)' / 360);
y = ab_resample(x, 5, 9);
tc.verifyEqual(numel(y), 2000);
e = y - 500 * sin(2 * pi * 10 * (0:1999)' / 200);
tc.verifyLessThan(max(abs(e(20:end-20))), 0.5);
end

function [samples, peaks, beats] = ab_golden_vectors(adu, p)
%AB_GOLDEN_VECTORS  Golden vectors of the integer model for one input stream.
%   [samples, peaks, beats] = AB_GOLDEN_VECTORS(adu, p) runs ab_pt_int's datapath on
%   ab_pt_stream(adu, p), the exact stream the RTL is fed, and returns
%   samples [N x 6] - adu, lp, hp, der, sq, mwi for every sample n = 0 .. N-1
%   peaks   [P x 9] - index, value, class, thr1_used, n, age, spk, npk, thr1
%   beats   [B x 7] - n, r_age, kind, spk, npk, thr1, rr_lim
%   Column meanings: ab_pt_decide and docs/golden_vectors.md.
if nargin < 2, p = ab_params(); end
p.arith = 'int';
x = ab_pt_stream(adu, p);
s = ab_pt_filters(x, p);
det = ab_pt_decide(s, p);
samples = [x, s.lp, s.hp, s.der, s.sq, s.mwi];
peaks = det.peaks;
beats = det.events;
end

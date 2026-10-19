function [det, s] = ab_pt_detect(adu, p)
%AB_PT_DETECT  Pan-Tompkins QRS detector: filter chain followed by decision logic.
%   det = AB_PT_DETECT(adu, p) detects QRS complexes in ADC codes adu (fs = p.fs)
%   using the arithmetic in p.arith ('float' or 'int'); see ab_pt_float, ab_pt_int.
%   det.sample - 0-based sample index of each detected R peak
%   det.kind   - 1 above threshold, 2 found by searchback
%   det.peaks  - all MWI peaks seen by the decision logic (see ab_pt_decide)
%   [det, s] = AB_PT_DETECT(...) also returns the filter-chain signals (ab_pt_filters).
n   = numel(adu);
adu = [adu(:); repmat(adu(end), p.fs, 1)];   % 1 s flush so the last beat completes
s   = ab_pt_filters(adu, p);
det = ab_pt_decide(s, p);
keep = det.sample >= 0 & det.sample < n;
det.sample = det.sample(keep);
det.kind   = det.kind(keep);
if nargout > 1
    s = structfun(@(v) v(1:n), s, 'UniformOutput', false);
end
end

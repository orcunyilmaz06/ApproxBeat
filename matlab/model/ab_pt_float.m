function [det, s] = ab_pt_float(adu, p)
%AB_PT_FLOAT  Pan-Tompkins QRS detector, double-precision reference model.
%   det = AB_PT_FLOAT(adu, p) detects QRS complexes in ADC codes adu (fs = p.fs).
%   det.sample - 0-based sample index of each detected R peak
%   det.kind   - 1 above threshold, 2 found by searchback
%   det.peaks  - all MWI peaks seen by the decision logic (see ab_pt_decide)
%   [det, s] = AB_PT_FLOAT(...) also returns the filter-chain signals (ab_pt_filters).
%
%   The filters are linear and causal, so filter() computes exactly what the
%   streaming datapath computes; the decision logic is the per-sample state
%   machine the RTL implements.
if nargin < 2, p = ab_params(); end
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

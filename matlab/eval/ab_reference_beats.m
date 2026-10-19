function [t, sym, excl] = ab_reference_beats(ann, fs)
%AB_REFERENCE_BEATS  Reference beat times and scoring exclusions from WFDB annotations.
%   [t, sym, excl] = AB_REFERENCE_BEATS(ann, fs)
%   t    - times (s) of all QRS annotations (ab_beat_codes)
%   sym  - their WFDB symbols (char column)
%   excl - K-by-2 [start end] times (s) of ventricular flutter/fibrillation
%          episodes ('[' .. ']'), which are not scored beat by beat (EC57)
[isbeat, symbol] = ab_beat_codes();
code = ann.type;
b = false(size(code));
ok = code >= 0 & code <= 49;
b(ok) = isbeat(code(ok) + 1);
t   = ann.sample(b) / fs;
sym = symbol(code(b) + 1).';

on  = ann.sample(code == 32);
off = ann.sample(code == 33);
ev  = sortrows([on, ones(size(on)); off, -ones(size(off))], 1);
excl = zeros(0, 2);
start = NaN;
for k = 1:size(ev, 1)
    if ev(k, 2) > 0 && isnan(start)
        start = ev(k, 1);
    elseif ev(k, 2) < 0
        if isnan(start), start = 0; end      % episode already running at record start
        excl(end+1, :) = [start, ev(k, 1)]; %#ok<AGROW>
        start = NaN;
    end
end
if ~isnan(start), excl(end+1, :) = [start, inf]; end
excl = excl / fs;
end

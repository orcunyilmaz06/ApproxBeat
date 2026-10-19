function S = ab_smoke_streams()
%AB_SMOKE_STREAMS  The short input streams of the committed smoke vector set.
%   S.r100_20s - the first 20 s of record 100: clean sinus rhythm
%   S.r210_30s - the first 30 s of record 210: searchback, T-wave and refractory
%                decisions, so every path of the decision logic is exercised
%   S.stress   - 40 s of ab_synthetic('stress'): a full-scale burst saturates sq
%   The MIT-BIH streams need data/mitdb.
r = ab_load_record('100');
S.r100_20s = r.adu(1:4000);
r = ab_load_record('210');
S.r210_30s = r.adu(1:6000);
S.stress = ab_synthetic('stress', 8000);
end

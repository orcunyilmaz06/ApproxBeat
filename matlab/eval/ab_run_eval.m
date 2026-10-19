function S = ab_run_eval(varargin)
%AB_RUN_EVAL  Score a QRS detector on the MIT-BIH Arrhythmia Database.
%   S = AB_RUN_EVAL() scores the float model (ab_pt_float with ab_params) on all
%   48 records as specified in docs/eval_protocol.md, prints per-record and gross
%   statistics, and writes results/<tag>.csv and results/<tag>.md.
%
%   Name-value options:
%     'model'    detector handle @(adu, p) -> det   (default @ab_pt_float)
%     'params'   parameter struct                   (default ab_params())
%     'tag'      results file stem                  (default 'float_baseline')
%     'records'  cell array of record names         (default ab_records())
%     'save'     write the results files            (default true)
%     'verbose'  print the per-record table         (default true)
%
%   S.table - one row per record;  S.gross - gross statistics (all / non-paced)
%   S.missed{k}, S.false{k} - times (s) of the false negatives / false positives
%   S.detections{k} - every detection of record k (0-based samples at p.fs)
ip = inputParser;
ip.addParameter('model', @ab_pt_float, @(f) isa(f, 'function_handle'));
ip.addParameter('params', ab_params(), @isstruct);
ip.addParameter('tag', 'float_baseline', @(s) ischar(s) || isstring(s));
ip.addParameter('records', ab_records(), @iscellstr);
ip.addParameter('save', true, @islogical);
ip.addParameter('verbose', true, @islogical);
ip.parse(varargin{:});
o = ip.Results;
if o.verbose, say = @fprintf; else, say = @(varargin) []; end
o.tag = char(o.tag);
p = o.params;
tol = 0.150;                                     % EC57 match window (s)
[~, paced] = ab_records();

rec = o.records(:);
nr = numel(rec);
[lead, missed, false_det, detections] = deal(cell(nr, 1));
[beats, tp, fn, fp, fn_learn, sb, vf_excluded, err_ms, err_sd_ms] = deal(zeros(nr, 1));
t_learn = (p.blank + p.learn) / p.fs;             % detector is still learning before this

say('%-5s %-5s %6s %6s %5s %5s %7s %7s %13s %4s\n', ...
    'rec', 'lead', 'beats', 'TP', 'FN', 'FP', 'Se%', '+P%', 'err ms', 'SB');
t0 = tic;
for k = 1:nr
    r = ab_load_record(rec{k}, p.fs);
    det = o.model(r.adu, p);
    [t_ref, ~, excl] = ab_reference_beats(r.ann, r.fs_orig);
    t_det  = sort(det.sample / p.fs);
    in_ref = in_intervals(t_ref, excl);
    in_det = in_intervals(t_det, excl);
    t_ref_s = sort(t_ref(~in_ref));
    t_det_s = t_det(~in_det);
    m = ab_match_beats(t_ref_s, t_det_s, tol);

    detections{k} = det.sample;
    missed{k} = t_ref_s(~m.ref_hit);
    false_det{k} = t_det_s(~m.det_hit);
    lead{k}  = r.lead;
    beats(k) = nnz(~in_ref);
    tp(k) = m.tp; fn(k) = m.fn; fp(k) = m.fp;
    fn_learn(k) = nnz(missed{k} < t_learn);
    err_ms(k) = 1000 * mean(m.err);
    err_sd_ms(k) = 1000 * std(m.err);
    sb(k) = nnz(det.kind(~in_det) == 2);
    vf_excluded(k) = nnz(in_ref);
    say('%-5s %-5s %6d %6d %5d %5d %7.2f %7.2f %6.1f +-%5.1f %4d\n', rec{k}, lead{k}, ...
        beats(k), tp(k), fn(k), fp(k), 100 * tp(k) / (tp(k) + fn(k)), ...
        100 * tp(k) / (tp(k) + fp(k)), err_ms(k), err_sd_ms(k), sb(k));
end
secs = toc(t0);

se_pct = 100 * tp ./ (tp + fn);
ppv_pct = 100 * tp ./ (tp + fp);
T = table(rec, lead, beats, tp, fn, fp, se_pct, ppv_pct, err_ms, err_sd_ms, sb, fn_learn, ...
          vf_excluded, 'VariableNames', {'record', 'lead', 'beats', 'tp', 'fn', 'fp', 'se_pct', ...
          'ppv_pct', 'err_mean_ms', 'err_sd_ms', 'searchback', 'fn_learning', 'vf_excluded'});
not_paced = ~ismember(rec, paced);
G = [gross_row(sprintf('all %d records', nr), T, true(nr, 1));
     gross_row(sprintf('%d non-paced records', nnz(not_paced)), T, not_paced)];

say('\n%-22s %7s %6s %5s %5s %7s %7s %7s %7s\n', 'set', 'beats', 'TP', 'FN', 'FP', ...
    'Se%', '+P%', 'F1%', 'DER%');
for k = 1:height(G)
    say('%-22s %7d %6d %5d %5d %7.2f %7.2f %7.2f %7.2f\n', G.set(k), G.beats(k), ...
        G.tp(k), G.fn(k), G.fp(k), G.se_pct(k), G.ppv_pct(k), G.f1_pct(k), G.der_pct(k));
end
[~, worst] = sort((T.fn + T.fp) ./ T.beats, 'descend');
say('worst records (FN+FP): %s\n', strjoin(compose('%s (%d+%d)', ...
    string(T.record(worst(1:min(6, nr)))), T.fn(worst(1:min(6, nr))), T.fp(worst(1:min(6, nr)))), ', '));
say('%d records in %.1f s\n', nr, secs);

if o.save
    P = ab_paths();
    if ~isfolder(P.results), mkdir(P.results); end
    writetable(T, fullfile(P.results, [o.tag '.csv']));
    write_markdown(fullfile(P.results, [o.tag '.md']), o, p, T, G, secs);
    say('wrote results/%s.csv and results/%s.md\n', o.tag, o.tag);
end
S.table = T;
S.gross = G;
S.params = p;
S.missed = missed;
S.false = false_det;
S.detections = detections;
end

function in = in_intervals(t, iv)
in = false(size(t));
for k = 1:size(iv, 1)
    in = in | (t >= iv(k, 1) & t <= iv(k, 2));
end
end

function g = gross_row(name, T, mask)
tp = sum(T.tp(mask)); fn = sum(T.fn(mask)); fp = sum(T.fp(mask));
g = table(string(name), nnz(mask), tp + fn, tp, fn, fp, 100 * tp / (tp + fn), ...
          100 * tp / (tp + fp), 100 * 2 * tp / (2 * tp + fp + fn), 100 * (fp + fn) / (tp + fn), ...
          'VariableNames', {'set', 'records', 'beats', 'tp', 'fn', 'fp', 'se_pct', 'ppv_pct', ...
                            'f1_pct', 'der_pct'});
end

function write_markdown(file, o, p, T, G, secs)
pm = char(177);
fid = fopen(file, 'w', 'n', 'UTF-8');
closer = onCleanup(@() fclose(fid));
fprintf(fid, '# %s: MIT-BIH Arrhythmia Database\n\n', o.tag);
fprintf(fid, ['Generated by `ab_run_eval(''tag'', ''%s'')` on %s, MATLAB %s, model `%s`, %.0f s. ' ...
              'Do not edit by hand.\n\n'], o.tag, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm')), ...
        version('-release'), func2str(o.model), secs);
fprintf(fid, ['Protocol ([docs/eval_protocol.md](../docs/eval_protocol.md)): MLII lead (V5 in 102 and 104) ' ...
              'resampled to %d Hz, every WFDB beat annotation, 150 ms match window, ventricular ' ...
              'flutter/fibrillation episodes excluded, full 30 min records.\n\n'], p.fs);
fprintf(fid, '| Set | Beats | TP | FN | FP | Se (%%) | +P (%%) | F1 (%%) | DER (%%) |\n');
fprintf(fid, '|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for k = 1:height(G)
    fprintf(fid, '| %s | %d | %d | %d | %d | %.2f | %.2f | %.2f | %.2f |\n', G.set(k), G.beats(k), ...
            G.tp(k), G.fn(k), G.fp(k), G.se_pct(k), G.ppv_pct(k), G.f1_pct(k), G.der_pct(k));
end
fprintf(fid, '\nSe = TP/(TP+FN), +P = TP/(TP+FP), DER = (FP+FN)/beats; gross statistics (summed over records).\n');
fprintf(fid, ['%d of the %d false negatives fall in the %.2f s startup window (blanking + learning) ' ...
              'at the start of each record.\n'], sum(T.fn_learning), sum(T.fn), (p.blank + p.learn) / p.fs);

fprintf(fid, '\n## Parameters\n\n```\n');
f = fieldnames(p);
for k = 1:numel(f)
    v = p.(f{k});
    if ischar(v), s = v; else, s = num2str(v, 6); end
    fprintf(fid, '%-11s = %s\n', f{k}, s);
end
fprintf(fid, '```\n\n## Per record\n\n');
fprintf(fid, '| Record | Lead | Beats | TP | FN | FP | Se (%%) | +P (%%) | Timing error (ms) | Searchback |\n');
fprintf(fid, '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|\n');
for k = 1:height(T)
    fprintf(fid, '| %s | %s | %d | %d | %d | %d | %.2f | %.2f | %.1f %s %.1f | %d |\n', T.record{k}, ...
            T.lead{k}, T.beats(k), T.tp(k), T.fn(k), T.fp(k), T.se_pct(k), T.ppv_pct(k), ...
            T.err_mean_ms(k), pm, T.err_sd_ms(k), T.searchback(k));
end
fprintf(fid, '\nTiming error: detection minus reference R-peak time over matched beats (mean %s SD).\n', pm);
if any(T.vf_excluded)
    fprintf(fid, 'Beats inside VF/VFL episodes, not scored: %s.\n', strjoin(compose('%s: %d', ...
            string(T.record(T.vf_excluded > 0)), T.vf_excluded(T.vf_excluded > 0)), ', '));
end
end

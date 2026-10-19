function M = ab_write_golden(set)
%AB_WRITE_GOLDEN  Write the golden vectors of the integer model for the RTL testbench.
%   AB_WRITE_GOLDEN() or AB_WRITE_GOLDEN('full') writes <rec>_samples.npy,
%   <rec>_peaks.npy and <rec>_beats.npy for all 48 records to data/golden (about
%   420 MB, not committed), with a manifest.json that records the model version.
%   AB_WRITE_GOLDEN('smoke') writes the small set committed for CI to tb/vectors: the
%   streams of ab_smoke_streams.
%   Format and the RTL contract: docs/golden_vectors.md.
if nargin < 1, set = 'full'; end
P = ab_paths();
p = ab_params();
p.arith = 'int';
switch set
    case 'full'
        out = fullfile(P.root, 'data', 'golden');
        names = ab_records();
        source = @(name) load_adu(name, p);
        stamp = true;
    case 'smoke'
        out = fullfile(P.root, 'tb', 'vectors');
        S = ab_smoke_streams();
        names = fieldnames(S)';
        source = @(name) S.(name);
        stamp = false;                     % deterministic: git already versions these files
    otherwise
        error('ab:golden', 'unknown set ''%s'' (full or smoke)', set);
end
if ~isfolder(out), mkdir(out); end

streams = struct('name', {}, 'samples', {}, 'peaks', {}, 'beats', {});
for k = 1:numel(names)
    [samples, peaks, beats] = ab_golden_vectors(source(names{k}), p);
    ab_npy_write(fullfile(out, [names{k} '_samples.npy']), samples);
    ab_npy_write(fullfile(out, [names{k} '_peaks.npy']), peaks);
    ab_npy_write(fullfile(out, [names{k} '_beats.npy']), beats);
    streams(k) = struct('name', names{k}, 'samples', size(samples, 1), ...
                        'peaks', size(peaks, 1), 'beats', size(beats, 1));
end

M.format = 'ApproxBeat golden vectors, version 1 (docs/golden_vectors.md)';
M.model = 'ab_pt_int';
if stamp
    M.generated = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
    M.git_commit = git_version();
end
M.columns.samples = {'adu', 'lp', 'hp', 'der', 'sq', 'mwi'};
M.columns.peaks = {'index', 'value', 'class', 'thr1_used', 'n', 'age', 'spk', 'npk', 'thr1'};
M.columns.beats = {'n', 'r_age', 'kind', 'spk', 'npk', 'thr1', 'rr_lim'};
w = ab_int_widths(p);
for f = {'lp', 'hp', 'der', 'sq', 'mwi'}
    M.word_lengths.(f{1}) = struct('bits', w.(f{1}).bits, 'signed', w.(f{1}).signed);
end
M.params = p;
M.streams = streams;
fid = fopen(fullfile(out, 'manifest.json'), 'w', 'n', 'UTF-8');
closer = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', jsonencode(M, 'PrettyPrint', true));
fprintf('wrote %d streams to %s\n', numel(streams), out);
end

function adu = load_adu(name, p)
r = ab_load_record(name, p.fs);
adu = r.adu;
end

function v = git_version()
[st, h] = system('git rev-parse --short HEAD');
if st ~= 0, v = 'unknown'; return; end
v = strtrim(h);
[~, d] = system('git status --porcelain --untracked-files=no');
if ~isempty(strtrim(d)), v = [v '-dirty']; end
end

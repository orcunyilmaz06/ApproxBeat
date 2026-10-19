function tests = test_golden
%TEST_GOLDEN  Golden-vector format, consistency with the model, and freshness of tb/vectors.
tests = functiontests(localfunctions);
end

function test_npy_round_trip(tc)
rs = RandStream('mt19937ar', 'Seed', 2);
A = randi(rs, [-2^31 + 1, 2^31 - 1], 37, 5);
f = [tempname '.npy'];
cleaner = onCleanup(@() delete(f));
ab_npy_write(f, A);
tc.verifyEqual(ab_npy_read(f), A);
fid = fopen(f, 'r'); head = fread(fid, 128, 'uint8=>char')'; fclose(fid);
tc.verifyEqual(mod(find(head == newline, 1), 64), 0);      % data starts on a 64-byte boundary
end

function test_npy_empty_and_column(tc)
f = [tempname '.npy'];
cleaner = onCleanup(@() delete(f));
ab_npy_write(f, zeros(0, 7));
tc.verifyEqual(size(ab_npy_read(f)), [0 7]);
ab_npy_write(f, (1:9)');
tc.verifyEqual(ab_npy_read(f), (1:9)');
end

function test_vectors_agree_with_model(tc)
% The beat events reproduce ab_pt_int's detections, and the peak log is self-consistent.
p = ab_params();
adu = ab_synthetic('stress', 12000);
[samples, peaks, beats] = ab_golden_vectors(adu, p);
tc.verifyEqual(samples(:, 1), ab_pt_stream(adu, p));
det = ab_pt_int(adu, p);
r = beats(:, 1) - beats(:, 2) - p.r_delay;                 % R-peak samples
tc.verifyEqual(r(r >= 0 & r < numel(adu)), det.sample);
tc.verifyEqual(peaks(:, 1), peaks(:, 5) - peaks(:, 6));    % index = n - age
tc.verifyTrue(all(diff(beats(:, 1)) > 0));
tc.verifyTrue(all(samples(:) == round(samples(:))));
end

function test_smoke_vectors_current(tc)
% tb/vectors must match what the model computes now: regenerate with ab_write_golden('smoke').
P = ab_paths();
tc.assumeTrue(isfile(fullfile(P.mitdb, '100.dat')), 'MIT-BIH not downloaded');
tc.assumeTrue(isfile(fullfile(P.root, 'tb', 'vectors', 'manifest.json')), 'no smoke vectors yet');
S = ab_smoke_streams();
p = ab_params();
for name = fieldnames(S)'
    [samples, peaks, beats] = ab_golden_vectors(S.(name{1}), p);
    stem = fullfile(P.root, 'tb', 'vectors', name{1});
    msg = sprintf('tb/vectors/%s is stale: run ab_write_golden(''smoke'')', name{1});
    tc.verifyEqual(ab_npy_read([stem '_samples.npy']), samples, msg);
    tc.verifyEqual(ab_npy_read([stem '_peaks.npy']), peaks, msg);
    tc.verifyEqual(ab_npy_read([stem '_beats.npy']), beats, msg);
end
end

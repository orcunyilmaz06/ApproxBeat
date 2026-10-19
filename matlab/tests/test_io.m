function tests = test_io
%TEST_IO  WFDB readers against the checksums and known contents of MIT-BIH.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
P = ab_paths();
tc.TestData.dir = P.mitdb;
tc.assumeTrue(isfile(fullfile(P.mitdb, '234.atr')), ...
              'MIT-BIH not downloaded: run scripts/get_mitdb.ps1');
end

function test_signal_checksums_all_records(tc)
recs = ab_records();
for k = 1:numel(recs)
    hdr = ab_read_header(fullfile(tc.TestData.dir, [recs{k} '.hea']));
    tc.verifyEqual([hdr.fs hdr.nsig hdr.nsamp], [360 2 650000], recs{k});
    x = ab_read_212(fullfile(tc.TestData.dir, hdr.sig(1).file), hdr.nsig, hdr.nsamp);
    for s = 1:hdr.nsig
        tc.verifyEqual(x(1, s), hdr.sig(s).initval, sprintf('%s signal %d: first sample', recs{k}, s));
        tc.verifyEqual(ab_checksum16(x(:, s)), hdr.sig(s).checksum, ...
                       sprintf('%s signal %d: checksum', recs{k}, s));
    end
end
end

function test_record_100_annotations(tc)
ann = ab_read_annotations(fullfile(tc.TestData.dir, '100.atr'));
[isbeat, symbol] = ab_beat_codes();
tc.verifyEqual(ann.sample(1:5)', [18 77 370 662 946]);
tc.verifyEqual(symbol(ann.type(1:2) + 1), '+N');
tc.verifyEqual(ann.aux{1}, '(N');
beats = ann.type(isbeat(ann.type + 1));
% MIT-BIH directory, record 100: 2239 normal, 33 APC, 1 PVC
tc.verifyEqual([numel(beats) nnz(beats == 1) nnz(beats == 8) nnz(beats == 5)], [2273 2239 33 1]);
end

function test_annotations_all_records(tc)
recs = ab_records();
isbeat = ab_beat_codes();
for k = 1:numel(recs)
    ann = ab_read_annotations(fullfile(tc.TestData.dir, [recs{k} '.atr']));
    tc.verifyTrue(all(diff(ann.sample) >= 0), [recs{k} ': annotations out of order']);
    tc.verifyTrue(ann.sample(1) >= 0 && ann.sample(end) < 650000, [recs{k} ': annotation outside the record']);
    tc.verifyGreaterThan(nnz(isbeat(ann.type + 1)), 1000, [recs{k} ': too few beats']);
end
end

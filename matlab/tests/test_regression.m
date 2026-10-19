function tests = test_regression
%TEST_REGRESSION  The committed results files still match what the code computes.
%   Fails when a model change was made without regenerating results/ (CLAUDE.md, rule 2).
%   Record 228 is included on purpose: its outcome flips on the smallest change.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
P = ab_paths();
tc.assumeTrue(isfile(fullfile(P.mitdb, '234.atr')), 'MIT-BIH not downloaded: run scripts/get_mitdb.ps1');
tc.TestData.P = P;
end

function test_float_results_current(tc)
check(tc, @ab_pt_float, 'float_baseline.csv');
end

function test_int_results_current(tc)
check(tc, @ab_pt_int, 'int_baseline.csv');
end

function check(tc, model, file)
recs = {'100', '108', '228'};
ref = readtable(fullfile(tc.TestData.P.results, file));
S = ab_run_eval('model', model, 'records', recs, 'save', false, 'verbose', false);
for k = 1:numel(recs)
    row = ref(string(ref.record) == recs{k}, :);
    tc.verifyEqual([S.table.tp(k) S.table.fn(k) S.table.fp(k)], [row.tp row.fn row.fp], ...
                   sprintf('%s, record %s: regenerate results with ab_int_study', file, recs{k}));
end
end

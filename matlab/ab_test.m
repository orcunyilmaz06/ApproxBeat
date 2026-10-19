function varargout = ab_test()
%AB_TEST  Run all ApproxBeat unit tests; errors if any test fails (for matlab -batch).
%   Tests that need the MIT-BIH data are skipped (Incomplete) until it is downloaded.
%   results = AB_TEST() also returns the TestResult array.
here = fileparts(mfilename('fullpath'));
ab_setup();
results = runtests(fullfile(here, 'tests'));
fprintf('%d passed, %d failed, %d skipped\n', nnz([results.Passed]), nnz([results.Failed]), ...
        nnz([results.Incomplete]));
assert(~any([results.Failed]), 'ab:test', '%d test(s) failed', nnz([results.Failed]));
if nargout, varargout{1} = results; end
end

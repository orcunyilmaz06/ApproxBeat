function tests = test_match
%TEST_MATCH  Beat matching rules of ab_match_beats.
tests = functiontests(localfunctions);
end

function test_perfect(tc)
t = (1:10)';
m = ab_match_beats(t, t + 0.01, 0.15);
tc.verifyEqual([m.tp m.fn m.fp], [10 0 0]);
tc.verifyEqual(m.err, 0.01 * ones(10, 1), 'AbsTol', 1e-12);
end

function test_tolerance(tc)
m = ab_match_beats([1; 2; 3], [1.14; 2.16; 2.9], 0.15);
tc.verifyEqual([m.tp m.fn m.fp], [2 1 1]);
end

function test_missed_and_extra(tc)
m = ab_match_beats([1; 2; 3; 4], [1.0; 1.5; 3.05; 4.0; 5.0], 0.15);
tc.verifyEqual([m.tp m.fn m.fp], [3 1 2]);
tc.verifyEqual(m.ref_hit', [true false true true]);
end

function test_prefers_closer_detection(tc)
m = ab_match_beats(1.0, [0.9; 1.01], 0.15);
tc.verifyEqual([m.tp m.fn m.fp], [1 0 1]);
tc.verifyEqual(m.err, 0.01, 'AbsTol', 1e-12);
end

function test_empty(tc)
m = ab_match_beats(zeros(0, 1), [1; 2], 0.15);
tc.verifyEqual([m.tp m.fn m.fp], [0 0 2]);
m = ab_match_beats([1; 2], zeros(0, 1), 0.15);
tc.verifyEqual([m.tp m.fn m.fp], [0 2 0]);
end

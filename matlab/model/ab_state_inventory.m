function T = ab_state_inventory(p)
%AB_STATE_INVENTORY  Every register of the detector with its word length (flip-flop count).
%   T = AB_STATE_INVENTORY(p) lists the state of the integer datapath and decision
%   logic for parameter set p: block, register, words, bits per word and total bits.
%   Word lengths come from ab_int_widths(p), so T tracks the approximation knobs.
%   Structure as in docs/algorithm.md: the low-pass in Pan & Tompkins' recursive form,
%   running sums for the high-pass and the MWI, age counters for event positions. The
%   'RTL sequencing' rows are what the sequenced RTL adds on top of the model's state
%   (rtl/ab_decide.v, rtl/ab_core.v): phase and flags, the result register of the
%   shared adder (D17), and the event outputs. The classified peak needs no copy, since
%   the peak detector holds it until the end of the sample (D18). The total is
%   the declared register bits of rtl/ab_core.v (results/synth_core.md).
w  = ab_int_widths(p);
a  = p.age_bits;
m  = w.mwi.bits;
s  = w.sq.bits;
rows = {
    'low-pass',      'x delay line x[n-1..n-12]',        12,              w.x.bits
    'low-pass',      'y[n-1], y[n-2]',                   2,               w.lp_acc.bits
    'high-pass',     'lp delay line lp[n-1..n-32]',      p.hp_len,        w.lp.bits
    'high-pass',     'running sum',                      1,               w.hp_acc.bits
    'derivative',    'hp delay line hp[n-1..n-4]',       4,               w.hp.bits
    'integrator',    'sq delay line sq[n-1..n-30]',      p.mwi_len,       s
    'integrator',    'running sum (MWI)',                1,               m
    'peak detector', 'rising flag',                      1,               1
    'peak detector', 'running max',                      1,               m
    'peak detector', 'age of running max',               1,               nbits(p.pk_timeout)
    'peak detector', 'segment max sq (slope)',           1,               s
    'peak detector', 'segment max |hp| and its age',     1,               w.ahp.bits + a
    'levels',        'SPKI, NPKI, THR1',                 3,               m
    'startup',       'sample counter',                   1,               nbits(p.blank + p.learn)
    'startup',       'learning max, learning sum',       2,               m
    'QRS history',   'QRS flag, age of last QRS',        1,               1 + a
    'QRS history',   'slope of last QRS',                1,               s
    'QRS history',   'RR average (3 fraction bits)',     1,               a + 3
    'QRS history',   'RR missed limit',                  1,               a + 1
    'searchback',    'valid flag, value',                1,               1 + m
    'searchback',    'age, R-peak age',                  2,               a
    'searchback',    'slope',                            1,               s
    'RTL sequencing','phase (4), result, searchback and filter-done flags', 1, 8
    'RTL sequencing','shared adder result',              1,               m + 2
    'RTL sequencing','event outputs (done, peak, class, beat, kind, R-peak age)', 1, 6 + a
    };
T = cell2table(rows, 'VariableNames', {'block', 'register', 'words', 'bits'});
T.total = T.words .* T.bits;
end

function b = nbits(maxval)
b = ceil(log2(maxval + 1));
end

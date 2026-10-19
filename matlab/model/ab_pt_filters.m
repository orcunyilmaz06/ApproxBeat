function s = ab_pt_filters(adu, p)
%AB_PT_FILTERS  Pan-Tompkins filter chain, in float or bit-accurate integer arithmetic.
%   s = AB_PT_FILTERS(adu, p) filters ADC codes adu (fs = p.fs). All coefficients
%   are integers and all scalings powers of two. With p.arith = 'float' the
%   scalings divide exactly; with 'int' they round down, as an arithmetic shift
%   right in the RTL does, and every signal is checked against ab_int_widths.
%
%   signal     operation                                          delay (samples)
%   s.x        adu - ADC zero                                      0
%   s.lp_acc   (1 - z^-6)^2 / (1 - z^-1)^2 applied to x             5
%   s.lp       lp_acc >> lp_shift
%   s.hp_acc   sum of the last hp_len lp
%   s.hp       lp[n - hp_len/2] - (hp_acc >> hp_shift)              16
%   s.der_acc  2 hp[n] + hp[n-1] - hp[n-3] - 2 hp[n-4]              2
%   s.der      der_acc >> der_shift
%   s.sq       der^2 >> sq_shift (rounded if sq_round), saturated    0
%   s.mwi      sum of the last mwi_len sq                           (mwi_len - 1)/2
%
%   Each stage is a causal LTI filter followed by a memoryless rounding step, so
%   filter() gives exactly the samples the streaming datapath produces (the
%   recursive forms in docs/algorithm.md compute the same integers).
is_int = strcmp(p.arith, 'int');
s.x       = double(adu(:)) - p.adc_zero;
s.lp_acc  = filter(conv(ones(1, 6), ones(1, 6)), 1, s.x);
s.lp      = shr(s.lp_acc, p.lp_shift, is_int);
d         = p.hp_len / 2;
s.hp_acc  = filter(ones(1, p.hp_len), 1, s.lp);
s.hp      = [zeros(d, 1); s.lp(1:end-d)] - shr(s.hp_acc, p.hp_shift, is_int);
s.der_acc = filter([2 1 0 -1 -2], 1, s.hp);
s.der     = shr(s.der_acc, p.der_shift, is_int);
half      = is_int * p.sq_round * (p.sq_shift > 0) * 2^(p.sq_shift - 1);   % round to nearest
s.sq      = min(shr(s.der .^ 2 + half, p.sq_shift, is_int), 2^p.sq_bits - 1);
s.mwi     = filter(ones(1, p.mwi_len), 1, s.sq);

if is_int
    w = ab_int_widths(p);
    for f = {'x', 'lp_acc', 'lp', 'hp_acc', 'hp', 'der_acc', 'der', 'sq', 'mwi'}
        v = s.(f{1});
        assert(all(v >= w.(f{1}).lo & v <= w.(f{1}).hi & v == round(v)), 'ab:int', ...
               '%s leaves its integer range [%d, %d]', f{1}, w.(f{1}).lo, w.(f{1}).hi);
    end
end
end

function y = shr(x, k, is_int)
y = x / 2^k;
if is_int, y = floor(y); end
end

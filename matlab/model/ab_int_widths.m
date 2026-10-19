function w = ab_int_widths(p)
%AB_INT_WIDTHS  Worst-case range and word length of every integer datapath signal.
%   w = AB_INT_WIDTHS(p) returns, for each signal of the integer filter chain
%   (x, lp_acc, lp, hp_acc, hp, der_acc, der, sq, mwi, ahp = |hp|), a struct with
%   fields lo, hi, bits and signed. The ranges bound every input in the ADC
%   range, so a register of that many bits can never overflow, and the
%   integer model checks that every computed sample lies inside them.
x  = rng_(-2^(p.adc_bits - 1), 2^(p.adc_bits - 1) - 1);
w.x       = x;
w.lp_acc  = fir_(conv(ones(1, 6), ones(1, 6)), x);
w.lp      = shr_(w.lp_acc, p.lp_shift);
w.hp_acc  = fir_(ones(1, p.hp_len), w.lp);
h         = shr_(w.hp_acc, p.hp_shift);
w.hp      = rng_(w.lp.lo - h.hi, w.lp.hi - h.lo);    % lp[n-16] - sum/32
w.der_acc = fir_([2 1 0 -1 -2], w.hp);
w.der     = shr_(w.der_acc, p.der_shift);
half      = p.sq_round * (p.sq_shift > 0) * 2^(p.sq_shift - 1);
sq_hi     = floor((max(w.der.lo^2, w.der.hi^2) + half) / 2^p.sq_shift);
sq_hi     = min(sq_hi, 2^p.sq_bits - 1);
w.sq      = urng_(sq_hi);
w.mwi     = urng_(p.mwi_len * sq_hi);
w.ahp     = urng_(max(-w.hp.lo, w.hp.hi));
end

function r = fir_(h, u)
hi = sum(h(h > 0)) * u.hi + sum(h(h < 0)) * u.lo;
lo = sum(h(h > 0)) * u.lo + sum(h(h < 0)) * u.hi;
r = rng_(lo, hi);
end

function r = shr_(u, k)
r = rng_(floor(u.lo / 2^k), floor(u.hi / 2^k));
end

function r = rng_(lo, hi)
b = 1;
while lo < -2^(b - 1) || hi > 2^(b - 1) - 1, b = b + 1; end
r = struct('lo', lo, 'hi', hi, 'bits', b, 'signed', true);
end

function r = urng_(hi)
b = 1;
while hi > 2^b - 1, b = b + 1; end
r = struct('lo', 0, 'hi', hi, 'bits', b, 'signed', false);
end

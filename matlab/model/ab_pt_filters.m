function s = ab_pt_filters(adu, p)
%AB_PT_FILTERS  Pan-Tompkins filter chain in double precision.
%   s = AB_PT_FILTERS(adu, p) filters ADC codes adu (fs = p.fs). All coefficients
%   are integers and all scalings powers of two, so the result is what an integer
%   datapath with unlimited word length would compute.
%
%   signal  operation                                         delay (samples)
%   s.x     adu - ADC zero                                     0
%   s.lp    (1 - z^-6)^2 / (1 - z^-1)^2, / 2^lp_shift           5
%   s.hp    lp[n-16] - (sum of last 32 lp) / 2^hp_shift         16
%   s.der   (2 hp[n] + hp[n-1] - hp[n-3] - 2 hp[n-4]) / 8       2
%   s.sq    der^2                                              0
%   s.mwi   sum of the last mwi_len sq                         (mwi_len - 1)/2
s.x   = double(adu(:)) - p.adc_zero;
s.lp  = filter(conv(ones(1, 6), ones(1, 6)), 1, s.x) / 2^p.lp_shift;
d     = p.hp_len / 2;
s.hp  = [zeros(d, 1); s.lp(1:end-d)] - filter(ones(1, p.hp_len), 1, s.lp) / 2^p.hp_shift;
s.der = filter([2 1 0 -1 -2], 1, s.hp) / 2^p.der_shift;
s.sq  = s.der .^ 2;
s.mwi = filter(ones(1, p.mwi_len), 1, s.sq);
end

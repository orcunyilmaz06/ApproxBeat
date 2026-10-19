function [det, s] = ab_pt_int(adu, p)
%AB_PT_INT  Pan-Tompkins QRS detector, bit-accurate integer model (the RTL's golden model).
%   [det, s] = AB_PT_INT(adu, p) is ab_pt_detect with p.arith = 'int': every shift
%   is an arithmetic shift right and every signal stays inside the word lengths of
%   ab_int_widths. The RTL must reproduce s and det.sample sample for sample.
if nargin < 2, p = ab_params(); end
p.arith = 'int';
[det, s] = ab_pt_detect(adu, p);
end

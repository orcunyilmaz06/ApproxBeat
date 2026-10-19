function [det, s] = ab_pt_float(adu, p)
%AB_PT_FLOAT  Pan-Tompkins QRS detector, double-precision reference model.
%   [det, s] = AB_PT_FLOAT(adu, p) is ab_pt_detect with p.arith = 'float': every
%   shift divides exactly, so this is the integer datapath with unlimited
%   precision. It is the reference that ab_pt_int is measured against.
if nargin < 2, p = ab_params(); end
p.arith = 'float';
[det, s] = ab_pt_detect(adu, p);
end

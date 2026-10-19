function y = ab_resample(x, p, q)
%AB_RESAMPLE  Rational sample-rate change by p/q with a windowed-sinc anti-alias filter.
%   y = AB_RESAMPLE(x, p, q) for a vector x; y(m+1) is the signal at input time m*q/p.
%   Base-MATLAB stand-in for resample() (no Signal Processing Toolbox needed):
%   linear phase, delay compensated, ends extended with the edge values.
x = x(:);
g = gcd(p, q); p = p / g; q = q / g;
half = 10 * max(p, q);                         % filter half-length in upsampled samples
k  = (-half:half).';
fc = 1 / max(p, q);                            % cutoff relative to the upsampled Nyquist rate
h  = sinc_(fc * k) .* (0.42 + 0.5 * cos(pi * k / half) + 0.08 * cos(2 * pi * k / half));
h  = p * h / sum(h);                           % DC gain p restores the zero-stuffed amplitude
L  = q * ceil((half / p + 1) / q);             % edge padding: a multiple of q input samples
xe = [repmat(x(1), L, 1); x; repmat(x(end), L, 1)];
xu = zeros(p * numel(xe), 1);
xu(1:p:end) = xe;
yu = conv(xu, h);
yu = yu(half + 1 : half + numel(xu));          % undo the filter delay
y  = yu(1:q:end);
y  = y(L * p / q + (1:ceil(numel(x) * p / q)));
end

function s = sinc_(t)
s = ones(size(t));
nz = t ~= 0;
s(nz) = sin(pi * t(nz)) ./ (pi * t(nz));
end

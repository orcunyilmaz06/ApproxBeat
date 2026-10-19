function adu = ab_synthetic(kind, n)
%AB_SYNTHETIC  Deterministic synthetic ADC streams (200 Hz, 11 bits) for tests and smoke vectors.
%   adu = AB_SYNTHETIC('stress', n), n >= 5400: ECG-like pulses every 0.8 s on 0.3 Hz
%   baseline wander with noise, plus a 2 s full-scale square-wave burst at samples
%   5001-5400. The burst drives every stage to its largest values, so it exercises
%   the word lengths and the saturation of sq.
switch kind
    case 'stress'
        assert(n >= 5400, 'ab:synthetic', 'the stress stream needs at least 5400 samples');
        rs = RandStream('mt19937ar', 'Seed', 5);
        t = (0:n-1)' / 200;
        v = 1024 + 300 * sin(2 * pi * 0.3 * t) + 8 * randn(rs, n, 1);
        v = v + 600 * exp(-0.5 * ((mod(t, 0.8) - 0.4) / 0.012).^2);
        v(5001:5400) = 2047 * (mod(0:399, 12) < 6);
        adu = min(max(round(v), 0), 2047);
    otherwise
        error('ab:synthetic', 'unknown stream ''%s''', kind);
end
end

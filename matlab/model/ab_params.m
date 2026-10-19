function p = ab_params()
%AB_PARAMS  Constants of the streaming Pan-Tompkins detector (fs = 200 Hz).
%   Every time constant is an integer number of samples and every gain is a
%   power of two or a short sum of powers of two, so the integer model and the
%   RTL implement them with counters, adders and shifts. See docs/algorithm.md.

p.fs        = 200;        % Hz; Pan & Tompkins' integer filter coefficients assume 200 Hz
p.adc_bits  = 11;         % MIT-BIH ADC resolution
p.adc_zero  = 1024;       % ADC code of 0 mV

% Arithmetic. 'float' divides exactly (the reference); 'int' turns every shift
% into an arithmetic shift right (floor), exactly as the RTL. Same code, so the
% two differ by rounding alone. Word lengths: ab_int_widths.
p.arith     = 'float';

% Filter chain (Pan & Tompkins 1985; output scaling as in Tompkins' reference C code)
p.lp_shift  = 5;          % low-pass (1 - z^-6)^2 / (1 - z^-1)^2, DC gain 36, then /32
p.hp_len    = 32;         % high-pass x[n-16] - (moving sum of 32) / 32
p.hp_shift  = 5;
p.der_shift = 0;          % derivative 2x[n] + x[n-1] - x[n-3] - 2x[n-4]. Its 1/8 is
p.sq_shift  = 6;          % applied after squaring, as >> 6, because rounding the small
                          % derivative of a low-amplitude beat before squaring gives a
                          % large relative error (D9). sq_shift is also the
                          % approximation knob for the MWI word length.
p.sq_round  = true;       % int: add half an LSB before the sq shift. Truncation would bias
                          % every sq by -0.5 LSB, and the MWI sums 30 of them (D10)
p.sq_bits   = 16;         % saturate the stored der^2 at 16 bits: the widest value on
                          % MIT-BIH, so nothing clips there (D11; inf = never saturate)
p.mwi_len   = 30;         % moving-window integrator, 150 ms. A sum, not a mean:
                          % every decision compares MWI values with each other

% Delay from an R peak at the ADC input to its peak in the band-pass output hp
% (LP 5 + HP 16). The MWI peak is no good as a fiducial: a narrow QRS gives the
% 150 ms window a flat top, so its maximum wanders by up to ~75 ms.
p.r_delay   = 21;

% Decision logic
p.pk_timeout = 40;        % an MWI maximum not exceeded for 200 ms is a peak
p.blank      = 128;       % startup: ignore the filter transient (0.64 s)
p.learn      = 256;       % learning window after blanking (1.28 s), a power of two
p.refractory = 40;        % 200 ms: no second QRS
p.twave_win  = 72;        % 360 ms: T-wave slope test window
p.rr_init    = 200;       % initial RR average (1 s)
p.rr_mode    = 'ema';     % 'ema': RR += (rr - RR)/8 (one register)
                          % 'mean8': mean of the last 8 RR intervals (as in the paper)
p.age_bits   = 11;        % event positions are saturating age counters (2047 = 10.2 s)

% Gains, all applied as shifts:
%   peak levels    SPKI, NPKI += (peak - level) >> k_pk          (paper: 0.125 / 0.875)
%   searchback     SPKI += (peak - SPKI) >> k_sb                  (paper: 0.25 / 0.75)
%   thresholds     THR1 = NPKI + (SPKI - NPKI) >> k_thr, THR2 = THR1 >> 1
%   missed beat    no QRS for sum(RR >> rr_missed_shifts) = 1.656 RR   (paper: 1.66 RR)
%   initial levels SPKI = sum(max >> spk_init_shifts) = 0.3125 max (common choice: 1/3)
%                  NPKI = mean >> npk_init_shift      = mean / 2   (common choice: 1/2)
%   outlier clip   a QRS peak enters SPKI clipped to SPKI + SPKI >> 2 = 1.25 SPKI, so
%                  one large beat raises SPKI by at most 3 %; chosen on DS1 (D14;
%                  [] = no clip, as in the paper)
p.k_pk             = 3;
p.spk_clip_shifts  = [0 2];
p.k_sb             = 2;
p.k_thr            = 2;
p.rr_missed_shifts = [0 1 3 5];
p.spk_init_shifts  = [2 4];
p.npk_init_shift   = 1;
end

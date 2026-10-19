function det = ab_pt_decide(s, p)
%AB_PT_DECIDE  Pan-Tompkins decision logic as a per-sample state machine.
%   det = AB_PT_DECIDE(s, p) finds QRS complexes from the filter-chain signals
%   s.mwi (moving-window integral), s.sq (squared derivative) and s.hp
%   (band-pass output) of ab_pt_filters.
%
%   Per sample:
%   1. Peak detector: track the running MWI maximum; it becomes a peak when the
%      MWI falls below half of it or p.pk_timeout samples pass without a new
%      maximum. Each peak carries its slope (largest sq) and its R-peak position
%      (largest |hp|), both taken since the previous peak.
%   2. Startup: the first p.blank samples are ignored, the next p.learn samples
%      initialise the signal and noise peak levels SPKI and NPKI.
%   3. Every peak outside the 200 ms refractory period is a QRS if it is above
%      THR1 and not a T wave (a peak within 360 ms of the last QRS with less than
%      half of its slope); otherwise it is a noise peak. With p.spk_clip_shifts
%      set, a QRS peak enters SPKI clipped to a multiple of SPKI.
%   4. Searchback: when no QRS was found for 1.656 x the RR average, the largest
%      noise peak above THR2 since the last QRS becomes the missed QRS.
%   Pan & Tompkins, IEEE TBME 32(3):230-236, 1985. Deviations: docs/algorithm.md.
%
%   The code is laid out register by register, as the RTL will be: event
%   positions are saturating age counters (samples since the event) and every
%   gain is a shift. With p.arith = 'int' a shift rounds down; with 'float' it
%   divides exactly. Both modes run this same code.
%
%   det.sample - 0-based R-peak estimate: position of the largest |hp| - p.r_delay
%   det.kind   - 1 threshold detection, 2 searchback detection
%   det.peaks  - every classified MWI peak: [0-based MWI index, value, class, THR1],
%                class 0 refractory, 1 QRS, 2 noise, 3 T wave, 4 taken by searchback;
%                THR1 is the threshold the peak was compared with

is_int  = strcmp(p.arith, 'int');
mwi = s.mwi; sq = s.sq; ahp = abs(s.hp);
N       = numel(mwi);
n0      = p.blank + p.learn;                 % last learning sample (1-based)
k_learn = log2(p.learn);
assert(k_learn == round(k_learn), 'ab:params', 'p.learn must be a power of two');
age_max = 2^p.age_bits - 1;
use_ema = strcmp(p.rr_mode, 'ema');

% peak detector
rising = false; pk_max = 0; pk_age = 0;      % running MWI maximum and its age
seg_sq = 0; seg_hp = 0; seg_hp_age = 0;      % largest sq / |hp| since the last peak
c_val = 0; c_age = 0; c_slope = 0; c_r_age = 0;
% levels and startup
spk = 0; npk = 0; thr1 = inf; thr2 = inf;
learn_max = 0; learn_sum = 0;
% QRS history
have_qrs = false; qrs_age = 0; last_slope = 0;
rr_acc = 8 * p.rr_init;                      % RR average with three fraction bits
rr_buf = repmat(p.rr_init, 1, 8); rr_ptr = 1;
rr_lim = rr_limit(p.rr_init, p, is_int);
% searchback candidate
sb_valid = false; sb_val = 0; sb_age = 0; sb_slope = 0; sb_r_age = 0; sb_row = 0;
f_age = 0; f_slope = 0; f_r_age = 0;

qrs   = zeros(ceil(N / p.refractory) + 1, 2); nq = 0;
peaks = zeros(ceil(N / 2), 4);              np = 0;

for n = 1:N
    % age counters: samples since each event, as of this sample
    pk_age     = min(pk_age + 1, age_max);
    seg_hp_age = min(seg_hp_age + 1, age_max);
    qrs_age    = min(qrs_age + 1, age_max);
    sb_age     = min(sb_age + 1, age_max);
    sb_r_age   = min(sb_r_age + 1, age_max);

    % 1. peak detector
    v = mwi(n);
    is_pk = false;
    if rising
        half = pk_max / 2;
        if is_int, half = floor(half); end
        if v > pk_max
            pk_max = v; pk_age = 0;
        elseif v < half || pk_age >= p.pk_timeout
            is_pk = true;
            c_val = pk_max; c_age = pk_age; c_slope = seg_sq; c_r_age = seg_hp_age;
            rising = false; pk_max = v;
            seg_sq = 0; seg_hp = 0;
        end
    elseif v > pk_max
        rising = true; pk_max = v; pk_age = 0;
    else
        pk_max = v;                           % follow the MWI down to the next valley
    end
    if sq(n) > seg_sq, seg_sq = sq(n); end
    if ahp(n) > seg_hp, seg_hp = ahp(n); seg_hp_age = 0; end

    % 2. startup
    if n <= p.blank
        continue
    elseif n <= n0
        if v > learn_max, learn_max = v; end
        learn_sum = learn_sum + shr(v, k_learn, is_int);     % running mean
        if n == n0
            spk = 0;
            for k = p.spk_init_shifts, spk = spk + shr(learn_max, k, is_int); end
            npk = shr(learn_sum, p.npk_init_shift, is_int);
            [thr1, thr2] = thresholds(spk, npk, p, is_int);
            qrs_age = 0;                      % the searchback timer starts here
        end
        continue
    end

    % 3. classify the peak
    found = 0;
    if is_pk
        np  = np + 1;
        cls = 0;
        thr_used = thr1;
        if have_qrs, dt = qrs_age - c_age; else, dt = inf; end
        if dt > p.refractory
            twave = dt < p.twave_win && c_slope < shr(last_slope, 2, is_int);   % slope < 1/2
            if c_val > thr1 && ~twave
                cls = 1;
                pk_in = c_val;
                if ~isempty(p.spk_clip_shifts)            % bounded step for large beats
                    lim = 0;
                    for k = p.spk_clip_shifts, lim = lim + shr(spk, k, is_int); end
                    pk_in = min(pk_in, lim);
                end
                spk = spk + shr(pk_in - spk, p.k_pk, is_int);
                found = 1; f_age = c_age; f_slope = c_slope; f_r_age = c_r_age;
            else
                cls = 2 + twave;
                npk = npk + shr(c_val - npk, p.k_pk, is_int);
                if ~twave && c_val > thr2 && (~sb_valid || c_val > sb_val)
                    sb_valid = true; sb_val = c_val; sb_age = c_age;
                    sb_slope = c_slope; sb_r_age = c_r_age; sb_row = np;
                end
            end
            [thr1, thr2] = thresholds(spk, npk, p, is_int);
        end
        peaks(np, :) = [n - c_age - 1, c_val, cls, thr_used];
    end

    % 4. searchback
    if ~found && sb_valid && qrs_age > rr_lim
        spk = spk + shr(sb_val - spk, p.k_sb, is_int);
        [thr1, thr2] = thresholds(spk, npk, p, is_int);
        peaks(sb_row, 3) = 4;
        found = 2; f_age = sb_age; f_slope = sb_slope; f_r_age = sb_r_age;
    end

    % QRS bookkeeping: RR average, last QRS, clear the searchback candidate
    if found
        if have_qrs
            rr = qrs_age - f_age;
            if use_ema
                rr_acc = rr_acc + rr - shr(rr_acc, 3, is_int);
                rr_avg = shr(rr_acc, 3, is_int);
            else
                rr_buf(rr_ptr) = rr;
                rr_ptr = mod(rr_ptr, 8) + 1;
                rr_avg = shr(sum(rr_buf), 3, is_int);
            end
            rr_lim = rr_limit(rr_avg, p, is_int);
        end
        have_qrs = true; qrs_age = f_age; last_slope = f_slope;
        sb_valid = false;
        nq = nq + 1;
        qrs(nq, :) = [n - f_r_age, found];
    end
end

det.sample = qrs(1:nq, 1) - 1 - p.r_delay;
det.kind   = qrs(1:nq, 2);
det.peaks  = peaks(1:np, :);
end

function y = shr(x, k, is_int)
y = x / 2^k;
if is_int, y = floor(y); end
end

function [thr1, thr2] = thresholds(spk, npk, p, is_int)
thr1 = npk + shr(spk - npk, p.k_thr, is_int);
thr2 = shr(thr1, 1, is_int);
end

function lim = rr_limit(rr, p, is_int)
lim = 0;
for k = p.rr_missed_shifts, lim = lim + shr(rr, k, is_int); end
end

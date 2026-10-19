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
%      half of its slope); otherwise it is a noise peak.
%   4. Searchback: when no QRS was found for p.rr_missed x the RR average, the
%      largest noise peak above THR2 since the last QRS becomes the missed QRS.
%   Pan & Tompkins, IEEE TBME 32(3):230-236, 1985. Deviations: docs/algorithm.md.
%
%   det.sample - 0-based R-peak estimate: index of the largest |hp| - p.r_delay
%   det.kind   - 1 threshold detection, 2 searchback detection
%   det.peaks  - every classified MWI peak: [0-based MWI index, value, class, THR1],
%                class 0 refractory, 1 QRS, 2 noise, 3 T wave, 4 taken by searchback;
%                THR1 is the threshold the peak was compared with

mwi = s.mwi; sq = s.sq; ahp = abs(s.hp);
N  = numel(mwi);
n0 = p.blank + p.learn;                      % last learning sample (1-based)
use_ema = strcmp(p.rr_mode, 'ema');
k_pk = 2^p.k_pk; k_sb = 2^p.k_sb; k_thr = 2^p.k_thr;

% peak detector
rising = false;                              % tracking a maximum (else following the MWI down)
pk_max = 0; pk_at = 0;                       % running maximum and its index
seg_sq = 0; seg_hp = 0; seg_hp_at = 1;       % largest sq / |hp| since the previous peak
pk_loc = 0; pk_val = 0; pk_slope = 0; pk_r = 0;
% decision state
spk = 0; npk = 0; thr1 = inf; thr2 = inf;
learn_max = 0; learn_sum = 0;
last_qrs = -inf; last_slope = 0;             % MWI index and slope of the last QRS
rr_avg = p.rr_init; rr_buf = repmat(p.rr_init, 1, 8); rr_ptr = 1;
sb_val = 0; sb_loc = 0; sb_slope = 0; sb_r = 0; sb_row = 0;   % searchback candidate
f_loc = 0; f_slope = 0; f_r = 0;

qrs   = zeros(ceil(N / p.refractory) + 1, 2); nq = 0;
peaks = zeros(ceil(N / 2), 4);              np = 0;

for n = 2:N
    % 1. peak detector
    v = mwi(n);
    is_pk = false;
    if rising
        if v > pk_max
            pk_max = v; pk_at = n;
        elseif v < pk_max / 2 || n - pk_at >= p.pk_timeout
            is_pk = true;
            pk_loc = pk_at; pk_val = pk_max; pk_slope = seg_sq; pk_r = seg_hp_at;
            seg_sq = 0; seg_hp = 0;
            rising = false; pk_max = v;
        end
    elseif v > pk_max
        rising = true; pk_max = v; pk_at = n;
    else
        pk_max = v;                           % follow the MWI down to the next valley
    end
    seg_sq = max(seg_sq, sq(n));
    if ahp(n) > seg_hp, seg_hp = ahp(n); seg_hp_at = n; end

    % 2. startup
    if n <= p.blank
        continue
    elseif n <= n0
        learn_max = max(learn_max, v);
        learn_sum = learn_sum + v;
        if n == n0
            spk  = p.spk_init * learn_max;
            npk  = p.npk_init * learn_sum / p.learn;
            thr1 = npk + (spk - npk) / k_thr;
            thr2 = thr1 / 2;
        end
        continue
    end

    % 3. classify the peak
    found = 0;
    if is_pk
        np  = np + 1;
        cls = 0;
        thr_used = thr1;
        dt  = pk_loc - last_qrs;
        if dt > p.refractory
            twave = dt < p.twave_win && pk_slope < last_slope / 4;   % slope below 1/2
            if pk_val > thr1 && ~twave
                cls = 1;
                spk = spk + (pk_val - spk) / k_pk;
                found = 1; f_loc = pk_loc; f_slope = pk_slope; f_r = pk_r;
            else
                cls = 2 + twave;
                npk = npk + (pk_val - npk) / k_pk;
                if ~twave && pk_val > thr2 && pk_val > sb_val
                    sb_val = pk_val; sb_loc = pk_loc; sb_slope = pk_slope; sb_r = pk_r; sb_row = np;
                end
            end
            thr1 = npk + (spk - npk) / k_thr;
            thr2 = thr1 / 2;
        end
        peaks(np, :) = [pk_loc, pk_val, cls, thr_used];
    end

    % 4. searchback
    if ~found && sb_val > 0 && n - max(last_qrs, n0) > p.rr_missed * rr_avg
        spk  = spk + (sb_val - spk) / k_sb;
        thr1 = npk + (spk - npk) / k_thr;
        thr2 = thr1 / 2;
        peaks(sb_row, 3) = 4;
        found = 2; f_loc = sb_loc; f_slope = sb_slope; f_r = sb_r;
    end

    % QRS bookkeeping: RR average, last QRS, clear the searchback candidate
    if found
        if last_qrs > -inf
            rr = f_loc - last_qrs;
            if use_ema
                rr_avg = rr_avg + (rr - rr_avg) / 8;
            else
                rr_buf(rr_ptr) = rr;
                rr_ptr = mod(rr_ptr, 8) + 1;
                rr_avg = sum(rr_buf) / 8;
            end
        end
        last_qrs = f_loc; last_slope = f_slope;
        sb_val = 0;
        nq = nq + 1;
        qrs(nq, :) = [f_r, found];
    end
end

det.sample = qrs(1:nq, 1) - 1 - p.r_delay;
det.kind   = qrs(1:nq, 2);
det.peaks  = peaks(1:np, :);
det.peaks(:, 1) = det.peaks(:, 1) - 1;
end

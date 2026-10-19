function fig = ab_plot_detection(rec, t_span, varargin)
%AB_PLOT_DETECTION  Show what the detector did in a time window of a record.
%   AB_PLOT_DETECTION('108', [100 110]) plots record 108 from 100 s to 110 s:
%   (1) the ECG with reference beats (symbol on top), detections, misses (red x)
%       and false detections (red o),
%   (2) the band-pass output,
%   (3) the MWI with every classified peak and the threshold THR1 it met.
%   Options: 'params' (default ab_params()), 'file' (save as an image, figure hidden).
ip = inputParser;
ip.addParameter('params', ab_params(), @isstruct);
ip.addParameter('file', '', @(s) ischar(s) || isstring(s));
ip.parse(varargin{:});
p = ip.Results.params;
file = char(ip.Results.file);

r = ab_load_record(rec, p.fs);
[det, s] = ab_pt_float(r.adu, p);
[t_ref, sym] = ab_reference_beats(r.ann, r.fs_orig);
t_det = det.sample / p.fs;
m = ab_match_beats(t_ref, t_det, 0.150);          % inputs are already time-sorted
t = (0:numel(r.adu) - 1)' / p.fs;
w = t >= t_span(1) & t <= t_span(2);
in = @(tt) tt >= t_span(1) & tt <= t_span(2);

vis = 'on';
if ~isempty(file), vis = 'off'; end
fig = figure('Color', 'w', 'Position', [80 80 1200 760], 'Visible', vis);
tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, sprintf('Record %s (%s), %g-%g s', rec, r.lead, t_span(1), t_span(2)));

ax1 = nexttile(tl);
ecg = (r.adu - r.adczero) / r.gain;
plot(ax1, t(w), ecg(w), 'k');
hold(ax1, 'on');
[lo, hi] = bounds(ecg(w));
top = hi + 0.15 * (hi - lo);
k = in(t_ref);
plot(ax1, t_ref(k & m.ref_hit), top * ones(nnz(k & m.ref_hit), 1), 'v', 'Color', [0 0.5 0], 'MarkerFaceColor', [0 0.5 0]);
plot(ax1, t_ref(k & ~m.ref_hit), top * ones(nnz(k & ~m.ref_hit), 1), 'rx', 'MarkerSize', 12, 'LineWidth', 2);
text(ax1, t_ref(k), (top + 0.08 * (hi - lo)) * ones(nnz(k), 1), cellstr(sym(k)), ...
     'HorizontalAlignment', 'center', 'FontSize', 8);
kd = in(t_det);
yd = interp1(t, ecg, t_det(kd));
plot(ax1, t_det(kd & m.det_hit), yd(m.det_hit(kd)), 'bo');
plot(ax1, t_det(kd & ~m.det_hit), yd(~m.det_hit(kd)), 'ro', 'MarkerSize', 10, 'LineWidth', 2);
ylabel(ax1, 'ECG (mV)');
grid(ax1, 'on');

ax2 = nexttile(tl);
plot(ax2, t(w), s.hp(w), 'Color', [0.2 0.3 0.7]);
ylabel(ax2, 'band-pass (adu)');
grid(ax2, 'on');

ax3 = nexttile(tl);
plot(ax3, t(w), s.mwi(w), 'k', 'DisplayName', 'MWI');
hold(ax3, 'on');
pk = det.peaks;
tp = pk(:, 1) / p.fs;
kp = in(tp);
stairs(ax3, tp(kp), pk(kp, 4), 'Color', [0.85 0.4 0], 'LineWidth', 1, 'DisplayName', 'THR1');
style = {'.', [0.6 0.6 0.6], 'refractory'; 'o', [0 0.5 0], 'QRS'; 'o', [0.6 0.6 0.6], 'noise'; ...
         '^', [0.5 0 0.5], 'T wave'; 'd', [0.9 0.1 0.1], 'searchback'};
for c = 0:4
    kk = kp & pk(:, 3) == c;
    if any(kk)
        plot(ax3, tp(kk), pk(kk, 2), style{c + 1, 1}, 'Color', style{c + 1, 2}, 'MarkerSize', 7, ...
             'LineWidth', 1.2, 'DisplayName', style{c + 1, 3});
    end
end
legend(ax3, 'Location', 'northeastoutside', 'FontSize', 8);
ylabel(ax3, 'MWI');
xlabel(ax3, 'time (s)');
grid(ax3, 'on');
linkaxes([ax1 ax2 ax3], 'x');
xlim(ax1, t_span);

if ~isempty(file)
    exportgraphics(fig, file, 'Resolution', 110);
    close(fig);
end
end

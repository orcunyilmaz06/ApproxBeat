function ab_make_figures()
%AB_MAKE_FIGURES  Regenerate the figures in results/figures that the README shows.
P = ab_paths();
out = fullfile(P.results, 'figures');
if ~isfolder(out), mkdir(out); end
ab_plot_detection('100', [600 610], 'file', fullfile(out, 'r100_detection.png'));
ab_plot_detection('108', [1668 1682], 'file', fullfile(out, 'r108_pwave_false_positives.png'));
fprintf('wrote %s\n', out);
end

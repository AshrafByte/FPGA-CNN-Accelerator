% sweep_charts.m - charts of the kernel-size sweep (experiments/sweep/results.csv)
%
% Three MAC architectures and the auto-selecting system, K = 1, no ReLU, 32x32, 160 MHz,
% N = 2..17. Builds that did not fit or were not continued are left out of the curves and
% shown in the status map.
%
% Outputs (docs/report/figures/charts/):
%   sweep_resources.png   LUT, FF, DSP, LUT + 50 DSP + 100 BRAM
%   sweep_performance.png total and dynamic power, Fmax, FoM
%   sweep_fom_ratio.png   FoM relative to the best architecture at each N
%   sweep_status.png      which builds ran, did not fit or were not continued
%   sweep_results.csv     copy of the sweep table for the report
%   sweep_winners.csv     best architecture per N and the system's choice
%
% usage (repository root):  matlab -batch "run('docs/report/scripts/sweep_charts.m')"

here = fileparts(mfilename('fullpath'));
repo = fullfile(here, '..', '..', '..');
out  = fullfile(repo, 'docs', 'report', 'figures', 'charts');
src  = fullfile(repo, 'experiments', 'sweep', 'results.csv');

opts = detectImportOptions(src, 'TextType', 'string');
num = {'mac_sel', 'n', 'lut', 'lutram', 'ff', 'dsp', 'bram', 'resource_points', 'wns_ns', ...
       'fmax_mhz', 'power_mw', 'dynamic_mw', 'static_mw', 'fom', 'max_dsp'};
opts = setvartype(opts, num, 'double');
opts = setvartype(opts, {'design', 'status', 'tag', 'note'}, 'string');
T = readtable(src, opts);
copyfile(src, fullfile(out, 'sweep_results.csv'));

arch   = ["conv_single_chain", "conv_row_chain", "conv_tree"];
label  = ["single DSP cascade", "row DSP chains", "multiplier array + tree"];
colour = [0.12 0.23 0.37; 0.72 0.58 0.04; 0.72 0.33 0.31];
marker = ['o', 's', '^'];
Nall   = 2:17;

% ---- resources ---------------------------------------------------------------------------
f = figure('Visible', 'off', 'Position', [0 0 1400 900]);
tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
panel(nexttile(tl), T, 'lut', 'LUTs', true, arch, label, colour, marker);
title('(a) LUTs');
panel(nexttile(tl), T, 'ff', 'flip-flops', true, arch, label, colour, marker);
title('(b) flip-flops (skew registers grow as N^4 / N^3)');
ax = nexttile(tl); panel(ax, T, 'dsp', 'DSP48E1', false, arch, label, colour, marker, [0 235]);
yline(ax, 220, 'k--', '220 DSPs in the xc7z020', 'LabelHorizontalAlignment', 'right', 'HandleVisibility', 'off');
legend(ax, 'Location', 'east');
yline(ax, 60, ':', '60-slice DSP column', 'Color', [0.4 0.4 0.4], 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
title('(c) DSP slices (tree beyond 220: multipliers in LUTs)');
panel(nexttile(tl), T, 'resource_points', 'LUT + 50 DSP + 100 BRAM', true, arch, label, colour, marker);
title('(d) FoM resource points');
exportgraphics(f, fullfile(out, 'sweep_resources.png'), 'Resolution', 200);

% ---- power, Fmax, FoM -------------------------------------------------------------------------
f = figure('Visible', 'off', 'Position', [0 0 1400 900]);
tl = tiledlayout(f, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
panel(nexttile(tl), T, 'power_mw', 'total on-chip power (mW)', false, arch, label, colour, marker);
title('(a) total power, random image and kernel (SAIF)');
panel(nexttile(tl), T, 'dynamic_mw', 'dynamic power (mW)', true, arch, label, colour, marker);
title('(b) dynamic power');
ax = nexttile(tl); panel(ax, T, 'fmax_mhz', 'Fmax (MHz)', false, arch, label, colour, marker, 150);
yline(ax, 160, 'k--', '160 MHz constraint', 'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
title('(c) Fmax = 1 / (6.25 ns - WNS)'); legend(ax, 'Location', 'northeast');
ax = nexttile(tl); panel(ax, T, 'fom', 'FoM (1 / (W \cdot points))', true, arch, label, colour, marker);
legend(ax, 'Location', 'northeast');
title('(d) Figure of Merit');
exportgraphics(f, fullfile(out, 'sweep_performance.png'), 'Resolution', 200);

% ---- FoM relative to the best architecture at each N -------------------------------------------
best = nan(size(Nall)); winner = strings(size(Nall)); sysd = strings(size(Nall)); ratio = nan(size(Nall));
f = figure('Visible', 'off', 'Position', [0 0 1100 470]); ax = axes(f); hold(ax, 'on');
bands(ax, [0 105]);
for i = 1:numel(Nall)
    rows = T(T.n == Nall(i) & T.status == "ok" & T.design ~= "system", :);
    if isempty(rows), continue; end
    [best(i), j] = max(rows.fom); winner(i) = rows.design(j);
    s = T(T.n == Nall(i) & T.design == "system", :);
    if ~isempty(s), sysd(i) = s.note(1); ratio(i) = s.fom(1) / best(i); end
end
for a = 1:3
    rows = T(T.design == arch(a) & T.status == "ok", :);
    r = rows.fom' ./ best(rows.n' - 1);
    plot(ax, rows.n, 100 * r, ['-' marker(a)], 'Color', colour(a, :), 'LineWidth', 1.6, ...
         'MarkerFaceColor', colour(a, :), 'DisplayName', label(a));
end
plot(ax, Nall, 100 * ratio, 'kp', 'MarkerSize', 12, 'LineWidth', 1.2, 'DisplayName', 'system (auto selection)');
xlim(ax, [1.5 17.5]); xticks(ax, Nall); ylim(ax, [0 105]);
xlabel(ax, 'kernel size N'); ylabel(ax, 'FoM / best FoM at this N (%)');
title(ax, 'FoM of each architecture relative to the best one at the same kernel size');
legend(ax, 'Location', 'southwest'); grid(ax, 'on'); box(ax, 'on');
exportgraphics(f, fullfile(out, 'sweep_fom_ratio.png'), 'Resolution', 200);
W = table(Nall', winner', best', sysd', ratio', 'VariableNames', {'n', 'best_design', 'best_fom', 'system_is', 'system_over_best'});
writetable(W, fullfile(out, 'sweep_winners.csv'));
disp(W)

% ---- status map -----------------------------------------------------------------------------------
codes = ["ok", "not_run", "failed", "not_continued"];
cmap  = [0.80 0.91 0.80; 0.93 0.87 0.87; 0.95 0.70 0.70; 0.92 0.92 0.92];
M = nan(3, numel(Nall));
for a = 1:3
    for i = 1:numel(Nall)
        r = T(T.design == arch(a) & T.n == Nall(i), :);
        if ~isempty(r), M(a, i) = find(codes == r.status(1)); end
    end
end
f = figure('Visible', 'off', 'Position', [0 0 1200 300]); ax = axes(f);
image(ax, M); colormap(ax, cmap); clim(ax, [0.5 4.5]);
txt = ["built", "no fit", "failed", "stopped"];
for a = 1:3
    for i = 1:numel(Nall)
        if ~isnan(M(a, i))
            text(ax, i, a, txt(M(a, i)), 'HorizontalAlignment', 'center', 'FontSize', 8);
        end
    end
end
xticks(ax, 1:numel(Nall)); xticklabels(ax, string(Nall)); yticks(ax, 1:3); yticklabels(ax, label);
xlabel(ax, 'kernel size N'); title(ax, 'Sweep builds (xc7z020, 160 MHz)');
exportgraphics(f, fullfile(out, 'sweep_status.png'), 'Resolution', 200);

function panel(ax, T, metric, ylab, logy, arch, label, colour, marker, extra)
% extra: reference values (limit lines) that must stay inside the y range
if nargin < 10, extra = []; end
hold(ax, 'on');
vals = extra(:);
for a = 1:3
    rows = T(T.design == arch(a) & T.status == "ok", :);
    plot(ax, rows.n, rows.(metric), ['-' marker(a)], 'Color', colour(a, :), 'LineWidth', 1.6, ...
         'MarkerFaceColor', colour(a, :), 'MarkerSize', 5, 'DisplayName', label(a));
    vals = [vals; rows.(metric)]; %#ok<AGROW>
end
s = T(T.design == "system" & T.status == "ok", :);
plot(ax, s.n, s.(metric), 'ko', 'MarkerSize', 10, 'LineWidth', 1.3, 'DisplayName', 'system (auto selection)');
vals = vals(isfinite(vals));
if logy
    set(ax, 'YScale', 'log');
    yl = [min(vals) / 1.6, max(vals) * 1.6];
else
    pad = 0.08 * (max(vals) - min(vals));
    yl = [max(0, min(vals) - pad), max(vals) + pad];
end
ylim(ax, yl);
bands(ax, yl);
xlim(ax, [1.5 17.5]); xticks(ax, 2:17); xlabel(ax, 'kernel size N'); ylabel(ax, ylab);
grid(ax, 'on'); box(ax, 'on'); ax.Layer = 'top'; legend(ax, 'Location', 'northwest');
end

function bands(ax, yl)
% the system's selection for one kernel: single chain N <= 3, row chains 4..8, tree 9+
p = [patch(ax, [1.5 3.5 3.5 1.5], yl([1 1 2 2]), [0.90 0.93 0.97], 'EdgeColor', 'none', 'HandleVisibility', 'off'), ...
     patch(ax, [3.5 8.5 8.5 3.5], yl([1 1 2 2]), [0.99 0.97 0.88], 'EdgeColor', 'none', 'HandleVisibility', 'off'), ...
     patch(ax, [8.5 17.5 17.5 8.5], yl([1 1 2 2]), [0.99 0.93 0.93], 'EdgeColor', 'none', 'HandleVisibility', 'off')];
uistack(p, 'bottom');
end

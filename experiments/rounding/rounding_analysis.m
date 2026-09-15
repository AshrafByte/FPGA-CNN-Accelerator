% rounding_analysis.m - rounding and saturation of the 20-to-16-bit output stage
%
% Compares truncation, round half up (conv_system) and round half to even (the earlier
% design) on the 3x3 datapath (DROP = 4):
%   1. exhaustively over every accumulator value a 3x3 window of 8-bit data can reach,
%   2. on real convolutions: the inspection image, a random image and a smooth image through
%      the preset kernels of sw/conv_lab,
% and computes the saturation headroom of the 16-bit output for kernel sizes 2..17 with
% DROP = ceil(log2 N^2) (conv_system) against a fixed DROP of 4.
%
% Outputs (docs/report/figures/charts/):
%   rounding_error.png  saturation_headroom.png  rounding_stats.csv  rounding_kernels.csv
%
% usage (repository root):  matlab -batch "run('experiments/rounding/rounding_analysis.m')"

here  = fileparts(mfilename('fullpath'));
repo  = fullfile(here, '..', '..');
out   = fullfile(repo, 'docs', 'report', 'figures', 'charts');
if ~exist(out, 'dir'), mkdir(out); end

DROP = 4;  S = 2^DROP;
methods = {'truncation', 'round half up', 'round half to even'};
colours = [0.55 0.55 0.55; 0.12 0.23 0.37; 0.72 0.33 0.31];

% ---- 1. exhaustive: every reachable 3x3 accumulator value --------------------------------
xmin = 9 * 255 * -128;  xmax = 9 * 255 * 127;           % -293760 .. 291465
x = (xmin:xmax)';
Y = rounders(x, DROP);
E = Y - x / S;                                          % error in output LSBs
bias = mean(E, 1);  rmse = sqrt(mean(E.^2, 1));  maxe = max(abs(E), [], 1);
ties = mean(mod(x, S) == S/2);
stats = table(string(methods)', bias', rmse', maxe', repmat(ties, 3, 1), ...
    'VariableNames', {'method', 'bias_lsb', 'rms_error_lsb', 'max_abs_error_lsb', 'tie_fraction'});
writetable(stats, fullfile(out, 'rounding_stats.csv'));
disp(stats)

% ---- 2. real convolutions -----------------------------------------------------------------
K = struct( ...
    'name', {'sobel_x', 'sobel_y', 'laplacian_8', 'gaussian_blur', 'box_blur', 'sharpen', 'emboss', 'scharr_x'}, ...
    'w', {[1 0 -1; 2 0 -2; 1 0 -1], [1 2 1; 0 0 0; -1 -2 -1], [-1 -1 -1; -1 8 -1; -1 -1 -1], ...
          [1 2 1; 2 4 2; 1 2 1], ones(3), [0 -16 0; -16 80 -16; 0 -16 0], ...
          [-16 -16 0; -16 16 16; 0 16 16], [3 0 -3; 10 0 -10; 3 0 -3]});
img = double(imread(fullfile(repo, 'docs', 'report', 'figures', 'inputs', 'inspection_plate.png')));
if size(img, 3) > 1, img = mean(img, 3); end
rng(2026);
[cc, rr] = meshgrid(0:127, 0:127);
images = {round(img), randi([0 255], 128), round(120 + 100 * sin(cc / 20) .* cos(rr / 27))};
kname = strings(0); tieF = []; bUp = []; bEven = []; bTr = []; diffF = [];
for k = 1:numel(K)
    acc = [];
    for i = 1:numel(images)
        a = conv2(images{i}, rot90(K(k).w, 2), 'valid');  % valid cross-correlation
        acc = [acc; a(:)]; %#ok<AGROW>
    end
    Yk = rounders(acc, DROP);
    Ek = Yk - acc / S;
    kname(end+1) = K(k).name; %#ok<SAGROW>
    tieF(end+1) = mean(mod(acc, S) == S/2); %#ok<SAGROW>
    bTr(end+1) = mean(Ek(:, 1)); bUp(end+1) = mean(Ek(:, 2)); bEven(end+1) = mean(Ek(:, 3)); %#ok<SAGROW>
    diffF(end+1) = mean(Yk(:, 2) ~= Yk(:, 3)); %#ok<SAGROW>
end
kt = table(kname', tieF', bTr', bUp', bEven', diffF', 'VariableNames', ...
    {'kernel', 'tie_fraction', 'bias_truncation', 'bias_half_up', 'bias_half_even', 'outputs_differing'});
writetable(kt, fullfile(out, 'rounding_kernels.csv'));
disp(kt)

% ---- figure: rounding ----------------------------------------------------------------------
f = figure('Visible', 'off', 'Position', [0 0 1500 430]);
tl = tiledlayout(f, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

ax = nexttile(tl); hold(ax, 'on');
xs = (-40:40)';
Ys = rounders(xs, DROP);
plot(ax, xs, xs / S, 'k--', 'LineWidth', 1, 'DisplayName', 'exact x / 16');
for m = 1:3
    stairs(ax, xs, Ys(:, m) + (m - 2) * 0.04, 'LineWidth', 1.5, 'Color', colours(m, :), 'DisplayName', methods{m});
end
xline(ax, [-24 -8 8 24], ':', 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off');
title(ax, '(a) transfer near zero (ties at \pm8, \pm24, \pm40)'); xlabel(ax, 'accumulator x'); ylabel(ax, 'output y');
legend(ax, 'Location', 'northwest'); grid(ax, 'on'); box(ax, 'on');

ax = nexttile(tl);
b = bar(ax, categorical({'bias', 'RMS error', 'max |error|'}), [bias; rmse; maxe]);
for m = 1:3, b(m).FaceColor = colours(m, :); end
title(ax, '(b) every reachable 3\times3 sum'); ylabel(ax, 'error (output LSB)');
ylim(ax, [-0.6 1.05]);
legend(ax, methods, 'Location', 'northoutside', 'Orientation', 'horizontal'); grid(ax, 'on');

ax = nexttile(tl);
b = bar(ax, categorical(kname, kname), [bUp; bEven]');
b(1).FaceColor = colours(2, :); b(2).FaceColor = colours(3, :);
ax.TickLabelInterpreter = 'none';
ylim(ax, [-0.005 0.045]);
yyaxis(ax, 'right'); plot(ax, 1:numel(kname), 100 * tieF, 'o-', 'Color', [0.18 0.52 0.35], 'LineWidth', 1.3);
ylabel(ax, 'exact ties (% of outputs)'); ax.YAxis(2).Color = [0.18 0.52 0.35]; ylim(ax, [0 9]);
yyaxis(ax, 'left'); ylabel(ax, 'bias (output LSB)');
title(ax, '(c) real convolutions (3 images \times 8 kernels)');
legend(ax, {'round half up', 'round half to even', 'exact ties'}, 'Location', 'northoutside', ...
       'Orientation', 'horizontal'); grid(ax, 'on');
exportgraphics(f, fullfile(out, 'rounding_error.png'), 'Resolution', 220);

% ---- 3. saturation headroom vs kernel size ----------------------------------------------------
N = (2:17)';
Dours = ceil(log2(N.^2));
posOurs = floor((255 * 127 * N.^2 + 2.^(Dours - 1)) ./ 2.^Dours);
negOurs = floor((-255 * 128 * N.^2 + 2.^(Dours - 1)) ./ 2.^Dours);
posFix = floor((255 * 127 * N.^2 + 8) / 16);
negFix = floor((-255 * 128 * N.^2 + 8) / 16);
f = figure('Visible', 'off', 'Position', [0 0 1000 430]); ax = axes(f); hold(ax, 'on');
kilo = 1000;                                              % plotted in thousands
rectangle(ax, 'Position', [1.5 32.767 16 80], 'FaceColor', [0.99 0.9 0.9], 'EdgeColor', 'none');
rectangle(ax, 'Position', [1.5 -112.768 16 80], 'FaceColor', [0.99 0.9 0.9], 'EdgeColor', 'none');
plot(ax, N, posOurs / kilo, 'o-', 'Color', colours(2, :), 'LineWidth', 1.6, 'DisplayName', 'max, DROP = \lceillog_2N^2\rceil (conv\_system)');
plot(ax, N, negOurs / kilo, 's-', 'Color', colours(2, :), 'LineWidth', 1.6, 'DisplayName', 'min, DROP = \lceillog_2N^2\rceil');
plot(ax, N, posFix / kilo, 'o--', 'Color', colours(3, :), 'LineWidth', 1.4, 'DisplayName', 'max, fixed DROP = 4');
plot(ax, N, negFix / kilo, 's--', 'Color', colours(3, :), 'LineWidth', 1.4, 'DisplayName', 'min, fixed DROP = 4');
yline(ax, [32.767 -32.768], 'k-', {'+32767', '-32768'}, 'LineWidth', 1, 'HandleVisibility', 'off');
ylim(ax, [-110 110]); xlim(ax, [1.5 17.5]); xticks(ax, 2:17); ax.Layer = 'top';
xlabel(ax, 'kernel size N'); ylabel(ax, 'reachable output feature (thousands)');
title(ax, 'Reachable 16-bit output with 8-bit pixels and weights (shaded: saturation needed)');
legend(ax, 'Location', 'eastoutside'); grid(ax, 'on'); box(ax, 'on');
exportgraphics(f, fullfile(out, 'saturation_headroom.png'), 'Resolution', 220);
sat = table(N, Dours, posOurs, negOurs, posFix, negFix);
writetable(sat, fullfile(out, 'saturation_headroom.csv'));
fprintf('fixed DROP=4 first overflows at N = %d\n', N(find(posFix > 32767 | negFix < -32768, 1)));

function Y = rounders(x, drop)
% columns: truncation, round half up, round half to even (x integer, output of x / 2^drop)
s = 2^drop;
q = floor(x / s);
r = x - q * s;
Y = [q, floor((x + s/2) / s), q + (r > s/2) + ((r == s/2) & (mod(q, 2) == 1))];
end

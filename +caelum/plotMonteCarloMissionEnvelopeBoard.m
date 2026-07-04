function fig = plotMonteCarloMissionEnvelopeBoard(envelope, sensitivity, cfg)
%PLOTMONTECARLOMISSIONENVELOPEBOARD Plot Monte Carlo mission envelope evidence.
arguments
    envelope table
    sensitivity table
    cfg struct = caelum.defaultConfig()
end

if isempty(envelope) || height(envelope) < 1
    error('caelum:plotMonteCarloMissionEnvelopeBoard:EmptyEnvelope', ...
        'Monte Carlo envelope audit table must contain at least one row.');
end

required = [ ...
    "runIndex", ...
    "success", ...
    "truth_peak_altitude_m", ...
    "logged_peak_altitude_m", ...
    "replay_peak_altitude_m", ...
    "est3d_peak_z_m", ...
    "peak_altitude_error_m", ...
    "peak_altitude_abs_error_m", ...
    "rmse_h_m", ...
    "rmse_pz_m", ...
    "gpsAcceptanceRate", ...
    "windError_mps", ...
    "data_loss_fraction", ...
    "composite_error_score", ...
    "envelope_code", ...
    "envelope_label", ...
    "envelope_rationale"];
missing = setdiff(required, string(envelope.Properties.VariableNames), 'stable');
if ~isempty(missing)
    error('caelum:plotMonteCarloMissionEnvelopeBoard:MissingEnvelopeFields', ...
        'Monte Carlo envelope audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

theme = localTheme();
fig = figure('Name', 'Caelum Monte Carlo Mission Envelope / Sensitivity Board', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.06 0.92 0.86]);

tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, 'Monte Carlo Mission Envelope / Sensitivity Board');
hTitle.Color = theme.textColor;

axEnvelope = nexttile(tl, 1, [1 2]);
localPlotPeakEnvelope(axEnvelope, envelope, cfg, theme);

axError = nexttile(tl, 3);
localPlotPeakError(axError, envelope, theme);

axMetrics = nexttile(tl, 4);
localPlotOutcomeMetrics(axMetrics, envelope, theme);

axSensitivity = nexttile(tl, 5);
localPlotSensitivity(axSensitivity, sensitivity, theme);

axClass = nexttile(tl, 6);
localPlotClassifications(axClass, envelope);

axSummary = nexttile(tl, 7, [1 2]);
localPlotSummary(axSummary, envelope, sensitivity);

localApplyStyle(fig, theme);
end

function localPlotPeakEnvelope(ax, envelope, cfg, theme)
hold(ax, 'on');
x = envelope.runIndex;
plot(ax, x, envelope.truth_peak_altitude_m, '-o', ...
    'LineWidth', 1.2, ...
    'MarkerSize', 4, ...
    'DisplayName', 'truth peak altitude');
plot(ax, x, envelope.logged_peak_altitude_m, '--o', ...
    'LineWidth', 1.0, ...
    'MarkerSize', 4, ...
    'DisplayName', 'logged KF peak');
plot(ax, x, envelope.replay_peak_altitude_m, ':s', ...
    'LineWidth', 1.0, ...
    'MarkerSize', 4, ...
    'DisplayName', 'MATLAB replay peak');
plot(ax, x, envelope.est3d_peak_z_m, '-.^', ...
    'LineWidth', 1.0, ...
    'MarkerSize', 4, ...
    'DisplayName', '3D EKF peak z');

target_m = localMissionTarget(cfg);
if isfinite(target_m)
    localPlotTargetReference(ax, x, envelope, target_m, theme);
end

xlabel(ax, 'run index');
ylabel(ax, 'peak altitude [m]');
title(ax, 'Peak Altitude Envelope');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotTargetReference(ax, x, envelope, target_m, theme)
values = [ ...
    envelope.truth_peak_altitude_m; ...
    envelope.logged_peak_altitude_m; ...
    envelope.replay_peak_altitude_m; ...
    envelope.est3d_peak_z_m];
values = values(isfinite(values));
if isempty(values)
    return;
end

span = max(values) - min(values);
if span <= eps
    span = max(abs(values(1)), 1);
end
low = min(values) - 0.25 * span;
high = max(values) + 0.25 * span;
if target_m >= low && target_m <= high
    yline(ax, target_m, '--', 'Color', theme.targetColor, ...
        'LineWidth', 1.1, ...
        'DisplayName', 'IREC target');
else
    text(ax, max(x), max(values), sprintf('IREC target %.0f m outside plot scale', target_m), ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', ...
        'Color', theme.targetColor, ...
        'Interpreter', 'none');
end
end

function localPlotPeakError(ax, envelope, theme)
hold(ax, 'on');
success = envelope.success;
bar(ax, envelope.runIndex(success), envelope.peak_altitude_error_m(success), ...
    'FaceColor', theme.primaryColor, ...
    'EdgeColor', theme.primaryColor, ...
    'DisplayName', 'successful run');
failed = ~success;
if any(failed)
    bar(ax, envelope.runIndex(failed), zeros(nnz(failed), 1), ...
        'FaceColor', theme.invalidColor, ...
        'EdgeColor', theme.invalidColor, ...
        'DisplayName', 'failed run');
end

warn = localFiniteMedian(envelope.peak_altitude_abs_error_m) * 2;
if isfinite(warn) && warn > 0
    yline(ax, warn, ':', 'Color', theme.warnColor, 'DisplayName', '2x median |error|');
    yline(ax, -warn, ':', 'Color', theme.warnColor, 'HandleVisibility', 'off');
end

xlabel(ax, 'run index');
ylabel(ax, 'logged peak - truth [m]');
title(ax, 'Peak Altitude Error');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotOutcomeMetrics(ax, envelope, theme)
hold(ax, 'on');
yyaxis(ax, 'left');
plot(ax, envelope.runIndex, envelope.rmse_h_m, '-o', ...
    'LineWidth', 1.0, ...
    'MarkerSize', 4, ...
    'DisplayName', 'logged h RMSE');
plot(ax, envelope.runIndex, envelope.rmse_pz_m, '--s', ...
    'LineWidth', 1.0, ...
    'MarkerSize', 4, ...
    'DisplayName', '3D p_z RMSE');
plot(ax, envelope.runIndex, envelope.windError_mps, ':^', ...
    'LineWidth', 1.0, ...
    'MarkerSize', 4, ...
    'DisplayName', 'wind error');
plot(ax, envelope.runIndex, envelope.composite_error_score, '-.', ...
    'Color', theme.warnColor, ...
    'LineWidth', 1.0, ...
    'DisplayName', 'composite score');
ylabel(ax, 'm, m/s, or normalized score');

yyaxis(ax, 'right');
plot(ax, envelope.runIndex, envelope.gpsAcceptanceRate, ...
    'Color', theme.gpsColor, ...
    'LineStyle', '-', ...
    'LineWidth', 1.1, ...
    'DisplayName', 'GPS acceptance');
ylim(ax, [0 1]);
ylabel(ax, 'GPS acceptance');

xlabel(ax, 'run index');
title(ax, 'Estimator / 3D / Wind Outcomes');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotSensitivity(ax, sensitivity, theme)
if isempty(sensitivity) || height(sensitivity) < 1
    localShowUnavailable(ax, "Sensitivity table unavailable.");
    title(ax, 'Sensitivity Correlation');
    return;
end

inputNames = localSensitivityInputNames();
outputNames = localSensitivityOutputNames();
matrix = nan(numel(outputNames), numel(inputNames));

for k = 1:height(sensitivity)
    i = find(inputNames == sensitivity.input_name(k), 1, 'first');
    j = find(outputNames == sensitivity.output_name(k), 1, 'first');
    if ~isempty(i) && ~isempty(j)
        matrix(j, i) = sensitivity.correlation(k);
    end
end

imagesc(ax, matrix, [-1 1]);
colormap(ax, localDivergingMap());
cb = colorbar(ax);
cb.Color = theme.textColor;
cb.Label.String = 'Pearson r';
cb.Label.Color = theme.textColor;
set(ax, ...
    'XTick', 1:numel(inputNames), ...
    'XTickLabel', localPrettyNames(inputNames), ...
    'YTick', 1:numel(outputNames), ...
    'YTickLabel', localPrettyNames(outputNames));
xtickangle(ax, 35);
title(ax, 'Input Sensitivity vs. Mission Outcomes');
end

function localPlotClassifications(ax, envelope)
stairs(ax, envelope.runIndex, envelope.envelope_code, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'mission envelope label');
yticks(ax, 1:9);
yticklabels(ax, localClassificationTickLabels());
ylim(ax, [0.5 9.5]);
xlabel(ax, 'run index');
title(ax, 'Audit Classification');
grid(ax, 'on');
end

function localPlotSummary(ax, envelope, sensitivity)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

successful = envelope.success;
lines = strings(0, 1);
lines(end+1) = "Mission Envelope Summary";
lines(end+1) = sprintf('Runs: %d | successful: %d | success rate: %.3f', ...
    height(envelope), nnz(successful), mean(double(successful), 'omitnan'));
lines(end+1) = sprintf('Peak-altitude |error| mean / p95 / max: %.3f / %.3f / %.3f m', ...
    mean(envelope.peak_altitude_abs_error_m(successful), 'omitnan'), ...
    localPercentile(envelope.peak_altitude_abs_error_m(successful), 95), ...
    max(envelope.peak_altitude_abs_error_m(successful), [], 'omitnan'));
lines(end+1) = sprintf('Estimator RMSE h mean: %.3f m | 3D p_z mean: %.3f m | wind error mean: %.3f m/s', ...
    mean(envelope.rmse_h_m(successful), 'omitnan'), ...
    mean(envelope.rmse_pz_m(successful), 'omitnan'), ...
    mean(envelope.windError_mps(successful), 'omitnan'));
lines(end+1) = sprintf('GPS acceptance mean: %.3f | data-loss mean: %.3f', ...
    mean(envelope.gpsAcceptanceRate(successful), 'omitnan'), ...
    mean(envelope.data_loss_fraction(successful), 'omitnan'));

labels = unique(envelope.envelope_label, 'stable');
labelCounts = strings(numel(labels), 1);
for k = 1:numel(labels)
    labelCounts(k) = sprintf('%s=%d', labels(k), nnz(envelope.envelope_label == labels(k)));
end
lines(end+1) = "Envelope labels: " + strjoin(labelCounts, "; ");

topText = localTopSensitivityText(sensitivity);
if topText ~= ""
    lines(end+1) = "Top sensitivities: " + topText;
end

idx = find(envelope.envelope_label ~= "", 1, 'last');
if ~isempty(idx)
    lines(end+1) = "Final label: " + envelope.envelope_label(idx);
    lines(end+1) = "Final rationale: " + envelope.envelope_rationale(idx);
end

text(ax, 0.02, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none');
end

function textOut = localTopSensitivityText(sensitivity)
textOut = "";
if isempty(sensitivity) || height(sensitivity) < 1
    return;
end

valid = isfinite(sensitivity.abs_correlation);
idx = find(valid, min(3, nnz(valid)), 'first');
if isempty(idx)
    return;
end

parts = strings(numel(idx), 1);
for k = 1:numel(idx)
    row = idx(k);
    parts(k) = sprintf('%s -> %s r=%.2f', ...
        char(localPrettyName(sensitivity.input_name(row))), ...
        char(localPrettyName(sensitivity.output_name(row))), ...
        sensitivity.correlation(row));
end
textOut = strjoin(parts, "; ");
end

function labels = localClassificationTickLabels()
labels = { ...
    'run failed', ...
    'metric incomplete', ...
    'peak error high', ...
    'estimator RMSE high', ...
    '3D RMSE high', ...
    'wind error high', ...
    'GPS acceptance low', ...
    'data loss high', ...
    'nominal'};
end

function target_m = localMissionTarget(cfg)
target_m = NaN;
if isstruct(cfg) && isfield(cfg, 'mission') && isstruct(cfg.mission) && ...
        isfield(cfg.mission, 'targetApogee_m')
    target_m = cfg.mission.targetApogee_m;
end
end

function names = localSensitivityInputNames()
names = [ ...
    "boostAccel_mps2", ...
    "boostDuration_s", ...
    "dragCoeff", ...
    "baroAltNoise_m", ...
    "accelNoise_mps2", ...
    "gyroNoise_rps", ...
    "gpsRateHz", ...
    "wind_speed_mps", ...
    "timingJitterStd_s", ...
    "nanFraction", ...
    "dropoutFraction"];
end

function names = localSensitivityOutputNames()
names = [ ...
    "truth_peak_altitude_m", ...
    "peak_altitude_abs_error_m", ...
    "rmse_h_m", ...
    "rmse_pz_m", ...
    "windError_mps", ...
    "gpsAcceptanceRate", ...
    "detected_apogee_time_error_s"];
end

function labels = localPrettyNames(names)
labels = cell(numel(names), 1);
for k = 1:numel(names)
    labels{k} = char(localPrettyName(names(k)));
end
end

function label = localPrettyName(name)
switch string(name)
    case "boostAccel_mps2"
        label = "boost accel";
    case "boostDuration_s"
        label = "boost dur";
    case "dragCoeff"
        label = "drag";
    case "baroAltNoise_m"
        label = "baro noise";
    case "accelNoise_mps2"
        label = "accel noise";
    case "gyroNoise_rps"
        label = "gyro noise";
    case "gpsRateHz"
        label = "GPS rate";
    case "wind_speed_mps"
        label = "wind speed";
    case "timingJitterStd_s"
        label = "jitter";
    case "nanFraction"
        label = "NaN frac";
    case "dropoutFraction"
        label = "dropout";
    case "truth_peak_altitude_m"
        label = "truth peak";
    case "peak_altitude_abs_error_m"
        label = "|peak err|";
    case "rmse_h_m"
        label = "h RMSE";
    case "rmse_pz_m"
        label = "p_z RMSE";
    case "windError_mps"
        label = "wind err";
    case "gpsAcceptanceRate"
        label = "GPS accept";
    case "detected_apogee_time_error_s"
        label = "apogee time err";
    otherwise
        label = string(name);
end
end

function medianValue = localFiniteMedian(values)
values = sort(values(isfinite(values)));
if isempty(values)
    medianValue = NaN;
elseif mod(numel(values), 2) == 1
    medianValue = values((numel(values) + 1) / 2);
else
    lo = values(numel(values) / 2);
    hi = values(numel(values) / 2 + 1);
    medianValue = 0.5 * (lo + hi);
end
end

function value = localPercentile(values, percent)
values = sort(values(isfinite(values)));
if isempty(values)
    value = NaN;
    return;
end

percent = min(max(percent, 0), 100);
if numel(values) == 1
    value = values(1);
    return;
end

position = 1 + (numel(values) - 1) * percent / 100;
lo = floor(position);
hi = ceil(position);
if lo == hi
    value = values(lo);
else
    alpha = position - lo;
    value = (1 - alpha) * values(lo) + alpha * values(hi);
end
end

function cmap = localDivergingMap()
n = 256;
t = linspace(0, 1, n).';
low = [0.15 0.32 0.78];
mid = [0.12 0.12 0.12];
high = [0.88 0.32 0.18];
cmap = zeros(n, 3);
for k = 1:n
    if t(k) <= 0.5
        a = t(k) / 0.5;
        cmap(k, :) = (1 - a) * low + a * mid;
    else
        a = (t(k) - 0.5) / 0.5;
        cmap(k, :) = (1 - a) * mid + a * high;
    end
end
end

function localShowUnavailable(ax, message)
cla(ax);
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end

function theme = localTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.primaryColor = [0.18 0.49 0.85];
theme.gpsColor = [0.88 0.88 0.36];
theme.warnColor = [0.95 0.62 0.22];
theme.invalidColor = [0.80 0.22 0.20];
theme.targetColor = [0.24 0.78 0.42];
end

function localApplyStyle(fig, theme)
axesHandles = findall(fig, 'Type', 'axes');
for k = 1:numel(axesHandles)
    ax = axesHandles(k);
    set(ax, ...
        'Color', theme.axesColor, ...
        'XColor', theme.textColor, ...
        'YColor', theme.textColor, ...
        'ZColor', theme.textColor, ...
        'GridColor', theme.gridColor, ...
        'MinorGridColor', theme.gridColor);
end

textHandles = findall(fig, 'Type', 'text');
for k = 1:numel(textHandles)
    set(textHandles(k), 'Color', theme.textColor);
end

legendHandles = findall(fig, 'Type', 'legend');
for k = 1:numel(legendHandles)
    try
        set(legendHandles(k), ...
            'Color', theme.axesColor, ...
            'TextColor', theme.textColor, ...
            'EdgeColor', theme.panelEdgeColor);
    catch
    end
end
end

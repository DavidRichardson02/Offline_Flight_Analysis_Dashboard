function fig = plotReplayContractDiffViewer(sampleAudit, fieldSummary)
%PLOTREPLAYCONTRACTDIFFVIEWER Plot firmware-vs-MATLAB replay contract diffs.
arguments
    sampleAudit table
    fieldSummary table
end

if isempty(sampleAudit) || height(sampleAudit) < 1
    error('caelum:plotReplayContractDiffViewer:EmptyAudit', ...
        'Replay contract sample audit table must contain at least one row.');
end

requiredAudit = [ ...
    "t", ...
    "logged_h_m", ...
    "replay_h_m", ...
    "delta_h_m", ...
    "logged_v_mps", ...
    "replay_v_mps", ...
    "delta_v_mps", ...
    "delta_a_vertical_mps2", ...
    "delta_sigma_h_m", ...
    "delta_sigma_v_mps", ...
    "replay_baro_used", ...
    "replay_baro_rejected", ...
    "contract_code", ...
    "contract_label", ...
    "contract_rationale"];
missingAudit = setdiff(requiredAudit, string(sampleAudit.Properties.VariableNames), 'stable');
if ~isempty(missingAudit)
    error('caelum:plotReplayContractDiffViewer:MissingAuditFields', ...
        'Replay contract sample audit is missing required fields: %s', ...
        strjoin(cellstr(missingAudit), ', '));
end

requiredSummary = [ ...
    "contract_field", ...
    "logged_field", ...
    "replay_field", ...
    "samples_compared", ...
    "match_rate", ...
    "max_abs_diff", ...
    "mean_abs_diff", ...
    "rmse_diff", ...
    "pass", ...
    "notes"];
missingSummary = setdiff(requiredSummary, string(fieldSummary.Properties.VariableNames), 'stable');
if ~isempty(missingSummary)
    error('caelum:plotReplayContractDiffViewer:MissingSummaryFields', ...
        'Replay contract field summary is missing required fields: %s', ...
        strjoin(cellstr(missingSummary), ', '));
end

theme = localTheme();
fig = figure('Name', 'Caelum Firmware-vs-MATLAB Replay Contract Diff Viewer', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.06 0.92 0.86]);

tl = tiledlayout(fig, 5, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, 'Firmware-vs-MATLAB Replay Contract Diff Viewer');
hTitle.Color = theme.textColor;

axState = nexttile(tl, 1, [1 2]);
localPlotStateOverlay(axState, sampleAudit);

axStateDelta = nexttile(tl, 3);
localPlotStateDelta(axStateDelta, sampleAudit, theme);

axInputCov = nexttile(tl, 4);
localPlotInputCovarianceDelta(axInputCov, sampleAudit, theme);

axField = nexttile(tl, 5);
localPlotFieldSummary(axField, fieldSummary, theme);

axCoverage = nexttile(tl, 6);
localPlotCoverage(axCoverage, fieldSummary, theme);

axUpdate = nexttile(tl, 7);
localPlotUpdateEvidence(axUpdate, sampleAudit);

axClass = nexttile(tl, 8);
localPlotClassification(axClass, sampleAudit);

axSummary = nexttile(tl, 9, [1 2]);
localPlotSummary(axSummary, sampleAudit, fieldSummary);

localApplyStyle(fig, theme);
end

function localPlotStateOverlay(ax, audit)
hold(ax, 'on');
yyaxis(ax, 'left');
plot(ax, audit.t, audit.logged_h_m, 'LineWidth', 1.1, 'DisplayName', 'logged firmware h');
plot(ax, audit.t, audit.replay_h_m, '--', 'LineWidth', 1.1, 'DisplayName', 'MATLAB replay h');
ylabel(ax, 'altitude [m]');

yyaxis(ax, 'right');
plot(ax, audit.t, audit.logged_v_mps, ':', 'LineWidth', 1.0, 'DisplayName', 'logged firmware v');
plot(ax, audit.t, audit.replay_v_mps, '-.', 'LineWidth', 1.0, 'DisplayName', 'MATLAB replay v');
ylabel(ax, 'velocity [m/s]');

xlabel(ax, 't [s]');
title(ax, 'Logged Firmware State vs. MATLAB Replay');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotStateDelta(ax, audit, theme)
hold(ax, 'on');
yyaxis(ax, 'left');
plot(ax, audit.t, audit.delta_h_m, 'LineWidth', 1.1, 'DisplayName', 'h delta');
ylabel(ax, 'altitude delta [m]');

yyaxis(ax, 'right');
plot(ax, audit.t, audit.delta_v_mps, '--', 'LineWidth', 1.1, 'DisplayName', 'v delta');
ylabel(ax, 'velocity delta [m/s]');

if any(audit.state_delta_high)
    yyaxis(ax, 'left');
    high = audit.state_delta_high & isfinite(audit.delta_h_m);
    plot(ax, audit.t(high), audit.delta_h_m(high), '.', ...
        'Color', theme.warnColor, ...
        'MarkerSize', 8, ...
        'DisplayName', 'state delta high');
end

xlabel(ax, 't [s]');
title(ax, 'State Delta');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotInputCovarianceDelta(ax, audit, theme)
hold(ax, 'on');
plot(ax, audit.t, audit.delta_a_vertical_mps2, ...
    'LineWidth', 1.0, ...
    'DisplayName', 'a vertical delta');
plot(ax, audit.t, audit.delta_sigma_h_m, '--', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'sigma h delta');
plot(ax, audit.t, audit.delta_sigma_v_mps, ':', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'sigma v delta');
if any(audit.input_delta_high)
    high = audit.input_delta_high & isfinite(audit.delta_a_vertical_mps2);
    plot(ax, audit.t(high), audit.delta_a_vertical_mps2(high), '.', ...
        'Color', theme.warnColor, ...
        'MarkerSize', 8, ...
        'DisplayName', 'input delta high');
end
xlabel(ax, 't [s]');
ylabel(ax, 'delta');
title(ax, 'Input / Covariance Delta');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotFieldSummary(ax, summary, theme)
if isempty(summary)
    localShowUnavailable(ax, "Field summary unavailable.");
    title(ax, 'Field Max Absolute Diff');
    return;
end

labels = string(summary.contract_field);
values = summary.max_abs_diff;
values(~isfinite(values)) = 0;
colors = repmat(theme.primaryColor, height(summary), 1);
colors(~summary.pass, :) = repmat(theme.invalidColor, nnz(~summary.pass), 1);

b = barh(ax, values);
b.FaceColor = 'flat';
b.CData = colors;
yticks(ax, 1:height(summary));
yticklabels(ax, cellstr(labels));
xlabel(ax, 'max abs diff');
title(ax, 'Field Contract Diffs');
grid(ax, 'on');
end

function localPlotCoverage(ax, summary, theme)
if isempty(summary)
    localShowUnavailable(ax, "Coverage summary unavailable.");
    title(ax, 'Coverage / Match Rate');
    return;
end

x = 1:height(summary);
hold(ax, 'on');
bar(ax, x - 0.25, summary.finite_fraction_logged, 0.25, ...
    'FaceColor', theme.primaryColor, ...
    'DisplayName', 'logged finite');
bar(ax, x, summary.finite_fraction_replay, 0.25, ...
    'FaceColor', theme.secondaryColor, ...
    'DisplayName', 'replay finite');
bar(ax, x + 0.25, summary.match_rate, 0.25, ...
    'FaceColor', theme.acceptColor, ...
    'DisplayName', 'match rate');
ylim(ax, [0 1.05]);
xticks(ax, x);
xticklabels(ax, cellstr(summary.contract_field));
xtickangle(ax, 35);
ylabel(ax, 'fraction');
title(ax, 'Coverage / Match Rate');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotUpdateEvidence(ax, audit)
hold(ax, 'on');
stairs(ax, audit.t, double(audit.replay_baro_used), ...
    'LineWidth', 1.1, ...
    'DisplayName', 'replay baro used');
stairs(ax, audit.t, 0.8 .* double(audit.replay_baro_rejected), '--', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'replay baro rejected');
if ismember("est_updated", string(audit.Properties.VariableNames))
    stairs(ax, audit.t, 0.6 .* double(audit.est_updated), ':', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'logged est updated');
end
if ismember("sample_gap", string(audit.Properties.VariableNames))
    stairs(ax, audit.t, -0.4 .* double(audit.sample_gap), '-.', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'sample gap');
end
ylim(ax, [-0.5 1.1]);
xlabel(ax, 't [s]');
ylabel(ax, 'flag');
title(ax, 'Update / Timebase Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotClassification(ax, audit)
stairs(ax, audit.t, audit.contract_code, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'contract label');
yticks(ax, 1:10);
yticklabels(ax, localClassificationTickLabels());
ylim(ax, [0.5 10.5]);
xlabel(ax, 't [s]');
title(ax, 'Contract Classification');
grid(ax, 'on');
end

function localPlotSummary(ax, audit, summary)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

lines = strings(0, 1);
lines(end+1) = "Replay Contract Diff Summary";
lines(end+1) = sprintf('Rows: %d | duration: %.3f s', height(audit), localDuration(audit.t));
lines(end+1) = sprintf('Aligned samples: %d / %d | max nearest replay dt: %.6g s', ...
    nnz(audit.time_aligned), height(audit), max(abs(audit.nearest_replay_dt_s), [], 'omitnan'));
lines(end+1) = sprintf('State delta RMSE: h=%.3f m, v=%.3f m/s', ...
    localRmse(audit.delta_h_m), localRmse(audit.delta_v_mps));
lines(end+1) = sprintf('Input delta max: %.6g m/s^2 | sigma delta max h/v: %.6g / %.6g', ...
    max(abs(audit.delta_a_vertical_mps2), [], 'omitnan'), ...
    max(abs(audit.delta_sigma_h_m), [], 'omitnan'), ...
    max(abs(audit.delta_sigma_v_mps), [], 'omitnan'));
lines(end+1) = sprintf('Field comparisons passing: %d / %d', nnz(summary.pass), height(summary));

labels = unique(audit.contract_label, 'stable');
labelCounts = strings(numel(labels), 1);
for k = 1:numel(labels)
    labelCounts(k) = sprintf('%s=%d', char(labels(k)), nnz(audit.contract_label == labels(k)));
end
lines(end+1) = "Contract labels: " + strjoin(labelCounts, "; ");

topDiff = localTopDiffText(summary);
if topDiff ~= ""
    lines(end+1) = "Largest field diffs: " + topDiff;
end

idx = find(audit.contract_label ~= "", 1, 'last');
if ~isempty(idx)
    lines(end+1) = "Final label: " + audit.contract_label(idx);
    lines(end+1) = "Final rationale: " + audit.contract_rationale(idx);
end

text(ax, 0.02, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none');
end

function labels = localClassificationTickLabels()
labels = { ...
    'logged incomplete', ...
    'replay incomplete', ...
    'timebase mismatch', ...
    'sample gap', ...
    'input delta', ...
    'state delta', ...
    'covariance delta', ...
    'firmware warning', ...
    'baro rejected', ...
    'contract nominal'};
end

function textOut = localTopDiffText(summary)
textOut = "";
if isempty(summary)
    return;
end
values = summary.max_abs_diff;
values(~isfinite(values)) = -Inf;
[~, order] = sort(values, 'descend');
order = order(values(order) > -Inf);
if isempty(order)
    return;
end
order = order(1:min(3, numel(order)));
parts = strings(numel(order), 1);
for k = 1:numel(order)
    idx = order(k);
    parts(k) = sprintf('%s=%.4g', char(summary.contract_field(idx)), summary.max_abs_diff(idx));
end
textOut = strjoin(parts, "; ");
end

function duration = localDuration(t)
t = t(isfinite(t));
if isempty(t)
    duration = NaN;
else
    duration = max(t) - min(t);
end
end

function value = localRmse(x)
x = x(isfinite(x));
if isempty(x)
    value = NaN;
else
    value = sqrt(mean(x.^2, 'omitnan'));
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
theme.secondaryColor = [0.88 0.53 0.17];
theme.acceptColor = [0.20 0.70 0.42];
theme.warnColor = [0.95 0.62 0.22];
theme.invalidColor = [0.80 0.22 0.20];
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

function fig = plotTelemetryFreshnessHeatmap(audit)
%PLOTTELEMETRYFRESHNESSHEATMAP Plot source freshness and provenance states.
arguments
    audit table
end

if isempty(audit) || height(audit) < 1
    error('caelum:plotTelemetryFreshnessHeatmap:EmptyAudit', ...
        'Telemetry freshness audit table must contain at least one row.');
end

required = ["sample_index","t","source","source_label","status_code","status_label"];
missing = setdiff(required, string(audit.Properties.VariableNames));
if ~isempty(missing)
    error('caelum:plotTelemetryFreshnessHeatmap:MissingAuditFields', ...
        'Telemetry freshness audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

theme = localTheme();
fig = figure('Name', 'Caelum Telemetry Freshness Heatmap', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.08 0.92 0.82]);

tl = tiledlayout(fig, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, 'Telemetry Freshness / Source Provenance Heatmap');
hTitle.Color = theme.textColor;

axHeat = nexttile(tl, 1, [2 2]);
localPlotStatusHeatmap(axHeat, audit);

axUpdate = nexttile(tl, 5);
localPlotUpdateFractions(axUpdate, audit);

axSummary = nexttile(tl, 6);
localPlotSummary(axSummary, audit);

localApplyStyle(fig, theme);
end

function localPlotStatusHeatmap(ax, audit)
[matrix, sourceLabels, t] = localStatusMatrix(audit);
imagesc(ax, t, 1:numel(sourceLabels), matrix);
set(ax, 'YDir', 'normal');
yticks(ax, 1:numel(sourceLabels));
yticklabels(ax, cellstr(sourceLabels));
colormap(ax, localStatusColormap());
caxis(ax, [0 5]);
cb = colorbar(ax);
cb.Ticks = 0:5;
cb.TickLabels = {'missing','invalid','stale','valid held','valid updated','warning'};
xlabel(ax, 't [s]');
title(ax, 'Source Status by Sample');
grid(ax, 'on');
end

function localPlotUpdateFractions(ax, audit)
sources = unique(string(audit.source_label), 'stable');
updatedFraction = nan(numel(sources), 1);
invalidFraction = nan(numel(sources), 1);
staleFraction = nan(numel(sources), 1);

for k = 1:numel(sources)
    mask = string(audit.source_label) == sources(k);
    status = audit.status_code(mask);
    updatedFraction(k) = mean(status == 4 | status == 5, 'omitnan');
    invalidFraction(k) = mean(status == 1, 'omitnan');
    staleFraction(k) = mean(status == 2, 'omitnan');
end

bar(ax, categorical(sources, sources, 'Ordinal', true), ...
    [updatedFraction invalidFraction staleFraction], 'stacked');
ylabel(ax, 'fraction');
ylim(ax, [0 1]);
title(ax, 'Updated / Invalid / Stale Fractions');
legend(ax, {'updated/warn','invalid','stale'}, 'Location', 'best');
grid(ax, 'on');
end

function localPlotSummary(ax, audit)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

statusLabels = unique(audit.status_label, 'stable');
parts = strings(numel(statusLabels), 1);
for k = 1:numel(statusLabels)
    parts(k) = statusLabels(k) + "=" + string(nnz(audit.status_label == statusLabels(k)));
end

sampleCount = numel(unique(audit.sample_index));
sourceCount = numel(unique(audit.source));
latestAge = localFirstFinite(audit.report_latest_age_s);
snapshotStale = any(logical(audit.report_snapshot_stale));

lines = strings(0, 1);
lines(end+1) = "Freshness Summary";
lines(end+1) = sprintf('Samples: %d | sources: %d', sampleCount, sourceCount);
lines(end+1) = "Status counts: " + strjoin(parts, "; ");
lines(end+1) = sprintf('Accepted rows: %.0f', localFirstFinite(audit.report_accepted_rows));
lines(end+1) = sprintf('Dropped malformed/non-numeric/nonmonotonic/capacity: %.0f / %.0f / %.0f / %.0f', ...
    localFirstFinite(audit.report_dropped_malformed_rows), ...
    localFirstFinite(audit.report_dropped_non_numeric_rows), ...
    localFirstFinite(audit.report_dropped_nonmonotonic_rows), ...
    localFirstFinite(audit.report_dropped_capacity_rows));
if isfinite(latestAge)
    lines(end+1) = sprintf('Latest host age: %.3f s | snapshot stale: %d', latestAge, snapshotStale);
else
    lines(end+1) = sprintf('Snapshot stale: %d', snapshotStale);
end

text(ax, 0.02, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none');
end

function [matrix, sourceLabels, t] = localStatusMatrix(audit)
sampleIndex = unique(audit.sample_index, 'stable');
sourceNames = unique(string(audit.source), 'stable');
sourceLabels = strings(numel(sourceNames), 1);
matrix = nan(numel(sourceNames), numel(sampleIndex));
t = nan(1, numel(sampleIndex));

for j = 1:numel(sampleIndex)
    sampleMask = audit.sample_index == sampleIndex(j);
    sampleRows = audit(sampleMask, :);
    if ~isempty(sampleRows)
        t(j) = sampleRows.t(1);
    end
end

for i = 1:numel(sourceNames)
    sourceMask = string(audit.source) == sourceNames(i);
    sourceRows = audit(sourceMask, :);
    if ~isempty(sourceRows)
        sourceLabels(i) = string(sourceRows.source_label(1));
    else
        sourceLabels(i) = sourceNames(i);
    end
    for j = 1:numel(sampleIndex)
        rowMask = sourceMask & audit.sample_index == sampleIndex(j);
        idx = find(rowMask, 1, 'first');
        if ~isempty(idx)
            matrix(i, j) = audit.status_code(idx);
        end
    end
end
end

function cmap = localStatusColormap()
cmap = [ ...
    0.16 0.16 0.16; ...
    0.75 0.18 0.18; ...
    0.95 0.66 0.18; ...
    0.25 0.40 0.70; ...
    0.20 0.68 0.38; ...
    0.80 0.20 0.82];
end

function value = localFirstFinite(values)
idx = find(isfinite(values), 1, 'first');
if isempty(idx)
    value = NaN;
else
    value = values(idx);
end
end

function theme = localTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
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

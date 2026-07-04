function audit = plotCompactTelemetryFreshness(ax, T, options)
%PLOTCOMPACTTELEMETRYFRESHNESS Plot a compact source freshness strip.
%
% This axes-level view intentionally reuses buildTelemetryFreshnessAudit so
% offline dashboard and live serial evidence share the same classification
% semantics as the standalone validation heatmap.
arguments
    ax
    T table
    options.Report struct = struct()
    options.MaxAge_ms (1,1) double = 500
    options.RecentWindow_s (1,1) double = Inf
    options.MaxSamples (1,1) double {mustBeInteger,mustBePositive} = 600
    options.CursorTime (1,1) double = NaN
    options.Title (1,1) string = "Telemetry Freshness"
    options.ShowColorbar (1,1) logical = false
end

cla(ax);
if isempty(T) || height(T) < 1
    audit = table();
    localShowMessage(ax, "Telemetry freshness unavailable");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

Tview = localSelectView(T, options.RecentWindow_s, options.MaxSamples);
audit = caelum.buildTelemetryFreshnessAudit(Tview, ...
    Report=options.Report, ...
    MaxAge_ms=options.MaxAge_ms);

if isempty(audit)
    localShowMessage(ax, "Telemetry freshness unavailable");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

[statusMatrix, sourceLabels, x] = localStatusMatrix(audit);
if all(~isfinite(x))
    x = 1:size(statusMatrix, 2);
    xLabel = "sample";
else
    xLabel = "t [s]";
end

imagesc(ax, x, 1:numel(sourceLabels), statusMatrix);
set(ax, 'YDir', 'normal');
yticks(ax, 1:numel(sourceLabels));
yticklabels(ax, cellstr(sourceLabels));
colormap(ax, localStatusColormap());
caxis(ax, [0 5]);
if options.ShowColorbar
    cb = colorbar(ax);
    cb.Ticks = 0:5;
    cb.TickLabels = {'missing','invalid','stale','held','updated','warning'};
    try
        cb.Color = [0.92 0.92 0.92];
    catch
    end
end
grid(ax, 'on');
xlabel(ax, xLabel);
title(ax, {char(options.Title), char(localLatestSummary(audit))}, 'Interpreter', 'none');

if isfinite(options.CursorTime) && any(isfinite(x))
    hold(ax, 'on');
    xline(ax, options.CursorTime, '--', 'Color', [0.86 0.86 0.86], 'LineWidth', 0.8);
end
end

function Tview = localSelectView(T, recentWindow_s, maxSamples)
Tview = T;
vars = string(T.Properties.VariableNames);

if isfinite(recentWindow_s) && recentWindow_s > 0 && ismember("t", vars) && any(isfinite(T.t))
    latestTime = localLastFinite(T.t);
    if isfinite(latestTime)
        keep = T.t >= latestTime - recentWindow_s;
        if any(keep)
            Tview = T(keep, :);
        end
    end
end

if height(Tview) > maxSamples
    idx = unique(round(linspace(1, height(Tview), maxSamples))).';
    Tview = Tview(idx, :);
end
end

function [matrix, sourceLabels, x] = localStatusMatrix(audit)
sampleIndex = unique(audit.sample_index, 'stable');
sourceNames = unique(string(audit.source), 'stable');
sourceLabels = strings(numel(sourceNames), 1);
matrix = nan(numel(sourceNames), numel(sampleIndex));
x = nan(1, numel(sampleIndex));

for j = 1:numel(sampleIndex)
    sampleMask = audit.sample_index == sampleIndex(j);
    sampleRows = audit(sampleMask, :);
    if ~isempty(sampleRows)
        x(j) = sampleRows.t(1);
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

function textOut = localLatestSummary(audit)
latestSample = max(audit.sample_index);
latestRows = audit(audit.sample_index == latestSample, :);
invalidCount = nnz(latestRows.status_label == "invalid");
staleCount = nnz(latestRows.status_label == "stale");
missingCount = nnz(latestRows.status_label == "missing");
warningCount = nnz(latestRows.status_label == "warning_active");

textOut = sprintf('latest invalid=%d | stale=%d | missing=%d | warning=%d', ...
    invalidCount, staleCount, missingCount, warningCount);
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

function value = localLastFinite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
end

function localShowMessage(ax, message)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end

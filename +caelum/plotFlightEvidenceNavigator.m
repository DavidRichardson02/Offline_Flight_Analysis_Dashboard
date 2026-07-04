function fig = plotFlightEvidenceNavigator(eventIndex, T, events, cfg, options)
%PLOTFLIGHTEVIDENCENAVIGATOR Plot shared mission evidence events.
arguments
    eventIndex table
    T table = table()
    events struct = struct()
    cfg struct = caelum.defaultConfig()
    options.Title (1,1) string = "Cross-Linked Flight Evidence Navigator"
    options.MaxSummaryEvents (1,1) double {mustBeInteger,mustBePositive} = 10
    options.TimeBins (1,1) double {mustBeInteger,mustBePositive} = 24
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

localValidateEventIndex(eventIndex);

theme = localTheme();
fig = figure('Name', 'Caelum Flight Evidence Navigator', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.07 0.92 0.84]);

tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, options.Title);
hTitle.Color = theme.textColor;

axTimeline = nexttile(tl, 1, [2 2]);
localPlotTimeline(axTimeline, eventIndex, T, events);

axSource = nexttile(tl, 5);
localPlotSourceCounts(axSource, eventIndex);

axSeverity = nexttile(tl, 6);
localPlotSeverityBins(axSeverity, eventIndex, T, options.TimeBins);

axSummary = nexttile(tl, 7, [1 2]);
localPlotSummary(axSummary, eventIndex, T, events, options.MaxSummaryEvents);

localApplyStyle(fig, theme);
end

function localValidateEventIndex(eventIndex)
required = ["t_start","t_end","t_mid","event_type","severity","source_view","label","rationale","confidence","field_names"];
missing = setdiff(required, string(eventIndex.Properties.VariableNames), 'stable');
if ~isempty(missing)
    error('caelum:plotFlightEvidenceNavigator:MissingEventIndexFields', ...
        'Event index is missing required fields: %s', strjoin(cellstr(missing), ', '));
end
end

function localPlotTimeline(ax, eventIndex, T, events)
cla(ax);
hold(ax, 'on');
if isempty(eventIndex)
    localShowUnavailable(ax, "No flight evidence events were indexed.");
    return;
end

sourceNames = localOrderedSources(eventIndex);
for k = 1:height(eventIndex)
    tStart = eventIndex.t_start(k);
    tEnd = eventIndex.t_end(k);
    if ~isfinite(tStart) && ~isfinite(tEnd)
        continue;
    elseif ~isfinite(tStart)
        tStart = tEnd;
    elseif ~isfinite(tEnd)
        tEnd = tStart;
    end

    y = find(sourceNames == string(eventIndex.source_view(k)), 1, 'first');
    if isempty(y)
        continue;
    end
    color = localSeverityColor(eventIndex.severity(k));
    if abs(tEnd - tStart) > 1.0e-9
        patch(ax, [tStart tEnd tEnd tStart], [y-0.36 y-0.36 y+0.36 y+0.36], color, ...
            'FaceAlpha', 0.82, 'EdgeColor', color, 'LineWidth', 0.5, ...
            'HandleVisibility', 'off');
    else
        plot(ax, tStart, y, 'o', ...
            'MarkerFaceColor', color, 'MarkerEdgeColor', [0.92 0.92 0.92], ...
            'MarkerSize', 5, 'HandleVisibility', 'off');
    end
end

localPlotMissionLines(ax, events);
yticks(ax, 1:numel(sourceNames));
yticklabels(ax, cellstr(localDisplaySourceNames(sourceNames)));
ylim(ax, [0.4 numel(sourceNames)+0.6]);
xlim(ax, localTimeLimits(eventIndex, T));
xlabel(ax, 't [s]');
title(ax, 'Shared Mission Evidence Timeline');
grid(ax, 'on');
box(ax, 'on');
localSeverityLegend(ax);
end

function sourceNames = localOrderedSources(eventIndex)
preferred = ["mission","phase_state_machine","policy_decision","estimator_trust", ...
    "replay_contract","telemetry_freshness:Barometer","telemetry_freshness:IMU", ...
    "telemetry_freshness:Aux accel","telemetry_freshness:Attitude", ...
    "telemetry_freshness:Vertical accel","telemetry_freshness:Estimator", ...
    "telemetry_freshness:Phase diag","telemetry_freshness:Policy", ...
    "telemetry_freshness:Warning mask","attitude_gravity","trajectory_wind"];
sourceNames = strings(0, 1);
actual = unique(string(eventIndex.source_view), 'stable');
for k = 1:numel(preferred)
    if any(actual == preferred(k))
        sourceNames(end+1, 1) = preferred(k); %#ok<AGROW>
    end
end
for k = 1:numel(actual)
    if ~any(sourceNames == actual(k))
        sourceNames(end+1, 1) = actual(k); %#ok<AGROW>
    end
end
end

function names = localDisplaySourceNames(sourceNames)
names = replace(sourceNames, "_", " ");
names = replace(names, "telemetry freshness:", "fresh: ");
names = replace(names, "phase state machine", "phase");
names = replace(names, "policy decision", "policy");
names = replace(names, "estimator trust", "estimator");
names = replace(names, "replay contract", "replay diff");
names = replace(names, "attitude gravity", "att/gravity");
names = replace(names, "trajectory wind", "3D/wind");
end

function localPlotMissionLines(ax, events)
items = [ ...
    "launchTime_s", "Launch"; ...
    "burnoutTime_s", "Burnout"; ...
    "apogeeTime_s", "Apogee"; ...
    "landingTime_s", "Landing"];
yl = ylim(ax);
for k = 1:size(items, 1)
    fieldName = char(items(k, 1));
    if isstruct(events) && isfield(events, fieldName) && isfinite(events.(fieldName))
        xline(ax, events.(fieldName), ':', items(k, 2), ...
            'Color', [0.75 0.75 0.75], ...
            'LabelOrientation', 'horizontal', ...
            'LabelVerticalAlignment', 'bottom', ...
            'HandleVisibility', 'off');
    end
end
ylim(ax, yl);
end

function localSeverityLegend(ax)
labels = ["info","notice","missing","warning","critical"];
handles = gobjects(numel(labels), 1);
for k = 1:numel(labels)
    handles(k) = plot(ax, NaN, NaN, 's', ...
        'MarkerFaceColor', localSeverityColor(labels(k)), ...
        'MarkerEdgeColor', [0.9 0.9 0.9], ...
        'DisplayName', labels(k));
end
legend(ax, handles, cellstr(labels), 'Location', 'eastoutside');
end

function localPlotSourceCounts(ax, eventIndex)
cla(ax);
if isempty(eventIndex)
    localShowUnavailable(ax, "No source counts.");
    return;
end
sources = unique(string(eventIndex.source_view), 'stable');
counts = zeros(numel(sources), 1);
for k = 1:numel(sources)
    counts(k) = nnz(string(eventIndex.source_view) == sources(k));
end
[counts, order] = sort(counts, 'descend');
sources = sources(order);
barh(ax, categorical(localDisplaySourceNames(sources), localDisplaySourceNames(sources), 'Ordinal', true), counts, ...
    'FaceColor', [0.25 0.55 0.85]);
xlabel(ax, 'events');
title(ax, 'Event Count by Source');
grid(ax, 'on');
end

function localPlotSeverityBins(ax, eventIndex, T, binCount)
cla(ax);
if isempty(eventIndex)
    localShowUnavailable(ax, "No severity bins.");
    return;
end
limits = localTimeLimits(eventIndex, T);
if ~all(isfinite(limits)) || limits(2) <= limits(1)
    localShowUnavailable(ax, "Time limits unavailable.");
    return;
end

edges = linspace(limits(1), limits(2), max(2, binCount + 1));
centers = 0.5 * (edges(1:end-1) + edges(2:end));
severities = ["info","notice","missing","warning","critical"];
counts = zeros(numel(centers), numel(severities));
for s = 1:numel(severities)
    mask = string(eventIndex.severity) == severities(s) & isfinite(eventIndex.t_mid);
    counts(:, s) = histcounts(eventIndex.t_mid(mask), edges).';
end
bar(ax, centers, counts, 'stacked', 'BarWidth', 1.0);
colors = zeros(numel(severities), 3);
for s = 1:numel(severities)
    colors(s, :) = localSeverityColor(severities(s));
end
series = findobj(ax, 'Type', 'Bar');
for k = 1:min(numel(series), size(colors, 1))
    series(k).FaceColor = colors(size(colors, 1) - k + 1, :);
end
xlim(ax, limits);
xlabel(ax, 't [s]');
ylabel(ax, 'events');
title(ax, 'Severity Density by Time');
legend(ax, cellstr(severities), 'Location', 'best');
grid(ax, 'on');
end

function localPlotSummary(ax, eventIndex, T, events, maxEvents)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

lines = strings(0, 1);
lines(end+1) = "Evidence Navigator Summary";
lines(end+1) = sprintf('Rows: %d | sources: %d | event types: %d', ...
    height(eventIndex), numel(unique(string(eventIndex.source_view))), ...
    numel(unique(string(eventIndex.event_type))));

if istable(T) && ~isempty(T) && ismember("t", string(T.Properties.VariableNames))
    lines(end+1) = sprintf('Log duration: %.3f s | samples: %d', ...
        max(T.t, [], 'omitnan') - min(T.t, [], 'omitnan'), height(T));
end

if isstruct(events) && isfield(events, 'launchTime_s') && isfield(events, 'apogeeTime_s')
    lines(end+1) = sprintf('Launch/apogee/landing: %.3f / %.3f / %.3f s', ...
        localStructNumber(events, "launchTime_s"), ...
        localStructNumber(events, "apogeeTime_s"), ...
        localStructNumber(events, "landingTime_s"));
end

severityLabels = ["critical","warning","missing","notice","info"];
parts = strings(0, 1);
for k = 1:numel(severityLabels)
    count = nnz(string(eventIndex.severity) == severityLabels(k));
    if count > 0
        parts(end+1) = severityLabels(k) + "=" + string(count); %#ok<AGROW>
    end
end
if ~isempty(parts)
    lines(end+1) = "Severity counts: " + strjoin(parts, "; ");
end

important = localImportantEvents(eventIndex, maxEvents);
if ~isempty(important)
    lines(end+1) = "";
    lines(end+1) = "Top evidence intervals:";
    for k = 1:height(important)
        lines(end+1) = sprintf('%.3f-%.3f s | %s | %s | %s', ...
            important.t_start(k), important.t_end(k), ...
            char(important.severity(k)), char(important.source_view(k)), char(important.label(k))); %#ok<AGROW>
    end
end

text(ax, 0.015, 0.97, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none');
end

function important = localImportantEvents(eventIndex, maxEvents)
important = eventIndex;
if isempty(important)
    return;
end
rank = localSeverityRank(important.severity);
[~, order] = sortrows([-rank -important.t_mid]);
important = important(order, :);
important = important(1:min(maxEvents, height(important)), :);
end

function value = localStructNumber(s, fieldName)
name = char(fieldName);
if isfield(s, name) && isfinite(s.(name))
    value = s.(name);
else
    value = NaN;
end
end

function limits = localTimeLimits(eventIndex, T)
values = [eventIndex.t_start; eventIndex.t_end; eventIndex.t_mid];
if istable(T) && ~isempty(T) && ismember("t", string(T.Properties.VariableNames))
    values = [values; double(T.t(:))]; %#ok<AGROW>
end
values = values(isfinite(values));
if isempty(values)
    limits = [0 1];
else
    limits = [min(values) max(values)];
    if limits(2) <= limits(1)
        limits = limits + [-0.5 0.5];
    else
        pad = 0.02 * diff(limits);
        limits = limits + [-pad pad];
    end
end
end

function rank = localSeverityRank(severity)
severity = string(severity(:));
rank = zeros(numel(severity), 1);
for k = 1:numel(severity)
    switch severity(k)
        case "critical"
            rank(k) = 5;
        case "warning"
            rank(k) = 4;
        case "missing"
            rank(k) = 3;
        case "notice"
            rank(k) = 2;
        otherwise
            rank(k) = 1;
    end
end
end

function color = localSeverityColor(severity)
switch string(severity)
    case "critical"
        color = [0.82 0.20 0.18];
    case "warning"
        color = [0.94 0.58 0.18];
    case "missing"
        color = [0.35 0.35 0.35];
    case "notice"
        color = [0.25 0.55 0.85];
    otherwise
        color = [0.24 0.68 0.42];
end
end

function localShowUnavailable(ax, message)
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

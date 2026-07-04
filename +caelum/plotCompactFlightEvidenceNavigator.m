function eventIndex = plotCompactFlightEvidenceNavigator(ax, T, events, replay, cfg, options)
%PLOTCOMPACTFLIGHTEVIDENCENAVIGATOR Axes-level shared evidence navigator strip.
%
% The compact strip reuses buildFlightEvidenceIndex so the integrated
% dashboard summarizes the same forensic evidence as the standalone navigator.
arguments
    ax (1,1) matlab.graphics.axis.Axes
    T table
    events struct = struct()
    replay = table()
    cfg struct = caelum.defaultConfig()
    options.EventIndex table = table()
    options.Attitude table = table()
    options.Est3D table = table()
    options.MaxTimeBins (1,1) double {mustBeInteger,mustBePositive} = 180
    options.Title (1,1) string = "Flight Evidence Navigator"
    options.IncludeNominal (1,1) logical = false
end

cla(ax);
eventIndex = table();

if isempty(T) || height(T) < 1
    localShowUnavailable(ax, "Flight evidence navigator unavailable.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

try
    if ~isempty(options.EventIndex)
        eventIndex = options.EventIndex;
    else
        eventIndex = caelum.buildFlightEvidenceIndex(T, events, replay, cfg, ...
            Attitude=options.Attitude, ...
            Est3D=options.Est3D, ...
            IncludeNominal=options.IncludeNominal);
    end
catch ME
    localShowUnavailable(ax, "Flight evidence navigator unavailable: " + string(ME.message));
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

if isempty(eventIndex)
    localShowUnavailable(ax, "No flight evidence events were indexed.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

[status, centers, groupLabels] = localBuildStatusMatrix(eventIndex, T, options.MaxTimeBins);
if isempty(status) || isempty(centers)
    localShowUnavailable(ax, "Flight evidence timebase unavailable.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

imagesc(ax, centers, 1:numel(groupLabels), status);
set(ax, 'YDir', 'normal');
yticks(ax, 1:numel(groupLabels));
yticklabels(ax, cellstr(groupLabels));
colormap(ax, localSeverityColormap());
caxis(ax, [0 5]);
xlabel(ax, 't [s]');
title(ax, localTitleText(options.Title, eventIndex), 'Interpreter', 'none');
grid(ax, 'on');
box(ax, 'on');
localPlotMissionLines(ax, events);
end

function [status, centers, groupLabels] = localBuildStatusMatrix(eventIndex, T, maxTimeBins)
limits = localTimeLimits(eventIndex, T);
if ~all(isfinite(limits)) || limits(2) <= limits(1)
    status = [];
    centers = [];
    groupLabels = strings(0, 1);
    return;
end

groupIds = ["mission","phase","policy","estimator","replay","freshness","attitude","trajectory"];
groupLabels = ["mission","phase","policy","estimator","replay","freshness","att/gravity","3D/wind"].';
edges = linspace(limits(1), limits(2), max(2, maxTimeBins + 1));
centers = 0.5 * (edges(1:end-1) + edges(2:end));
status = zeros(numel(groupIds), numel(centers));

for k = 1:height(eventIndex)
    group = localSourceGroup(eventIndex.source_view(k));
    row = find(groupIds == group, 1, 'first');
    if isempty(row)
        continue;
    end

    tStart = eventIndex.t_start(k);
    tEnd = eventIndex.t_end(k);
    tMid = eventIndex.t_mid(k);
    if ~isfinite(tStart) && ~isfinite(tEnd) && ~isfinite(tMid)
        continue;
    end
    if ~isfinite(tStart)
        tStart = tMid;
    end
    if ~isfinite(tEnd)
        tEnd = tStart;
    end
    if ~isfinite(tMid)
        tMid = 0.5 * (tStart + tEnd);
    end

    lo = min(tStart, tEnd);
    hi = max(tStart, tEnd);
    if abs(hi - lo) <= 1.0e-9
        [~, cols] = min(abs(centers - tMid));
    else
        cols = find(centers >= lo & centers <= hi);
        if isempty(cols)
            [~, cols] = min(abs(centers - tMid));
        end
    end

    status(row, cols) = max(status(row, cols), localSeverityCode(eventIndex.severity(k)));
end
end

function group = localSourceGroup(sourceView)
sourceView = string(sourceView);
if sourceView == "mission"
    group = "mission";
elseif sourceView == "phase_state_machine"
    group = "phase";
elseif sourceView == "policy_decision"
    group = "policy";
elseif sourceView == "estimator_trust"
    group = "estimator";
elseif sourceView == "replay_contract"
    group = "replay";
elseif startsWith(sourceView, "telemetry_freshness")
    group = "freshness";
elseif sourceView == "attitude_gravity"
    group = "attitude";
elseif sourceView == "trajectory_wind"
    group = "trajectory";
else
    group = "";
end
end

function value = localSeverityCode(severity)
switch string(severity)
    case "critical"
        value = 5;
    case "warning"
        value = 4;
    case "missing"
        value = 3;
    case "notice"
        value = 2;
    case "info"
        value = 1;
    otherwise
        value = 1;
end
end

function titleText = localTitleText(baseTitle, eventIndex)
latestCounts = localLatestSeverityCounts(eventIndex);
important = localMostImportantEvent(eventIndex);
if isempty(important)
    importantText = "current: none";
else
    importantText = "current: " + localCompactSource(important.source_view(1)) + " / " + ...
        localCompactLabel(important.label(1));
end

titleText = sprintf('%s | latest crit=%d warn=%d miss=%d notice=%d | events=%d | %s', ...
    char(baseTitle), latestCounts.critical, latestCounts.warning, latestCounts.missing, ...
    latestCounts.notice, height(eventIndex), char(importantText));
end

function counts = localLatestSeverityCounts(eventIndex)
counts = struct('critical', 0, 'warning', 0, 'missing', 0, 'notice', 0, 'info', 0);
if isempty(eventIndex)
    return;
end

latestTime = max([eventIndex.t_end; eventIndex.t_mid], [], 'omitnan');
if ~isfinite(latestTime)
    return;
end

sourceViews = unique(string(eventIndex.source_view), 'stable');
for k = 1:numel(sourceViews)
    rows = eventIndex(string(eventIndex.source_view) == sourceViews(k), :);
    active = rows.t_start <= latestTime & rows.t_end >= latestTime;
    if any(active)
        rows = rows(active, :);
        [~, idx] = max(localSeverityRank(rows.severity));
    else
        [~, idx] = max(rows.t_mid);
    end
    severity = string(rows.severity(idx));
    if isfield(counts, char(severity))
        counts.(char(severity)) = counts.(char(severity)) + 1;
    end
end
end

function important = localMostImportantEvent(eventIndex)
important = eventIndex;
if isempty(important)
    return;
end
rank = localSeverityRank(important.severity);
[~, order] = sortrows([-rank -important.t_mid]);
important = important(order(1), :);
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

function label = localCompactSource(sourceView)
label = string(sourceView);
label = replace(label, "telemetry_freshness:", "fresh ");
label = replace(label, "_", " ");
label = replace(label, "state machine", "");
label = strtrim(label);
end

function label = localCompactLabel(label)
label = string(label);
label = replace(label, "_", " ");
if strlength(label) > 34
    label = extractBefore(label, 35);
end
end

function limits = localTimeLimits(eventIndex, T)
values = [eventIndex.t_start; eventIndex.t_end; eventIndex.t_mid];
if istable(T) && ~isempty(T) && ismember("t", string(T.Properties.VariableNames))
    values = [values; double(T.t(:))]; %#ok<AGROW>
end
values = values(isfinite(values));
if isempty(values)
    limits = [NaN NaN];
else
    limits = [min(values) max(values)];
    if limits(2) <= limits(1)
        limits = limits + [-0.5 0.5];
    end
end
end

function localPlotMissionLines(ax, events)
items = [ ...
    "launchTime_s"; ...
    "burnoutTime_s"; ...
    "apogeeTime_s"; ...
    "landingTime_s"];
yl = ylim(ax);
hold(ax, 'on');
for k = 1:numel(items)
    fieldName = char(items(k));
    if isstruct(events) && isfield(events, fieldName) && isfinite(events.(fieldName))
        xline(ax, events.(fieldName), ':', ...
            'Color', [0.78 0.78 0.78], ...
            'LineWidth', 0.75, ...
            'HandleVisibility', 'off');
    end
end
ylim(ax, yl);
end

function cmap = localSeverityColormap()
cmap = [ ...
    0.16 0.16 0.16; ...
    0.20 0.66 0.38; ...
    0.25 0.48 0.76; ...
    0.38 0.38 0.38; ...
    0.93 0.55 0.18; ...
    0.82 0.20 0.18];
end

function localShowUnavailable(ax, message)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end

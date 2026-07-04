function [nodes, edges, snapshot] = plotCompactCausalitySnapshot(ax, T, events, replay, cfg, options)
%PLOTCOMPACTCAUSALITYSNAPSHOT Axes-level sensor-to-actuator causality strip.
%
% The compact strip reuses buildCausalitySnapshotAudit so the dashboard view
% shares the same node, edge, severity, and rationale semantics as the
% standalone causality graph validation artifact.
arguments
    ax (1,1) matlab.graphics.axis.Axes
    T table
    events struct = struct()
    replay = table()
    cfg struct = caelum.defaultConfig()
    options.EventIndex table = table()
    options.AuditBundle struct = struct()
    options.Time (1,1) double = NaN
    options.Selector (1,1) string = "dashboard"
    options.Title (1,1) string = "Causality Snapshot"
end

cla(ax);
nodes = table();
edges = table();
snapshot = table();

if isempty(T) || height(T) < 1
    localShowUnavailable(ax, "Causality snapshot unavailable.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

try
    [nodes, edges, snapshot] = caelum.buildCausalitySnapshotAudit(T, events, replay, cfg, ...
        Time=options.Time, ...
        Selector=options.Selector, ...
        EventIndex=options.EventIndex, ...
        AuditBundle=options.AuditBundle);
catch ME
    localShowUnavailable(ax, "Causality snapshot unavailable: " + string(ME.message));
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

if isempty(nodes) || isempty(snapshot)
    localShowUnavailable(ax, "Causality snapshot produced no node evidence.");
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

theme = localTheme();
hold(ax, 'on');
axis(ax, [0 1 0 1]);
axis(ax, 'off');
set(ax, 'Color', theme.axesColor);

displayIds = ["sensor_freshness","attitude_gravity","estimator_trust", ...
    "replay_contract","trajectory_wind","phase_state", ...
    "apogee_prediction","policy_decision","actuator_output"];
displayLabels = ["source","att/g","estimate","replay","3D/wind", ...
    "phase","apogee","policy","actuator"];

nodeOrder = localNodeOrder(nodes, displayIds);
nodeCenters = linspace(0.055, 0.945, numel(displayIds));
nodeY = 0.50;
nodeW = 0.088;
nodeH = 0.50;

localDrawCompactEdges(ax, nodes, edges, displayIds, nodeCenters, nodeY, nodeW, theme);
for k = 1:numel(displayIds)
    row = nodeOrder(k);
    if row > 0
        localDrawNode(ax, nodes(row, :), displayLabels(k), nodeCenters(k), nodeY, nodeW, nodeH, theme);
    else
        localDrawMissingNode(ax, displayLabels(k), nodeCenters(k), nodeY, nodeW, nodeH, theme);
    end
end
title(ax, localTitleText(options.Title, snapshot), 'Interpreter', 'none');
end

function order = localNodeOrder(nodes, displayIds)
order = zeros(1, numel(displayIds));
ids = string(nodes.node_id);
for k = 1:numel(displayIds)
    idx = find(ids == displayIds(k), 1, 'first');
    if ~isempty(idx)
        order(k) = idx;
    end
end
end

function localDrawCompactEdges(ax, nodes, edges, displayIds, centers, y, nodeW, theme)
for k = 1:(numel(displayIds)-1)
    severity = localConnectingSeverity(edges, displayIds(k), displayIds(k+1));
    if severity == ""
        fromIdx = find(nodes.node_id == displayIds(k), 1, 'first');
        toIdx = find(nodes.node_id == displayIds(k+1), 1, 'first');
        severity = localWorstSeverity([localNodeSeverity(nodes, fromIdx), localNodeSeverity(nodes, toIdx)]);
    end
    color = localSeverityColor(severity, theme);
    x1 = centers(k) + 0.5 * nodeW + 0.006;
    x2 = centers(k+1) - 0.5 * nodeW - 0.006;
    quiver(ax, x1, y, x2 - x1, 0, 0, ...
        'Color', color, ...
        'LineWidth', 1.05, ...
        'MaxHeadSize', 0.9, ...
        'AutoScale', 'off');
end
end

function severity = localConnectingSeverity(edges, fromNode, toNode)
severity = "";
if isempty(edges) || ~istable(edges)
    return;
end
match = string(edges.from_node) == fromNode & string(edges.to_node) == toNode;
if any(match)
    rows = edges(match, :);
    severity = localWorstSeverity(rows.severity);
end
end

function severity = localNodeSeverity(nodes, idx)
if isempty(idx) || idx < 1 || idx > height(nodes)
    severity = "missing";
else
    severity = string(nodes.severity(idx));
end
end

function severity = localWorstSeverity(severityValues)
severityValues = string(severityValues(:));
if isempty(severityValues)
    severity = "info";
    return;
end
[~, idx] = max(localSeverityRank(severityValues));
severity = severityValues(idx);
end

function localDrawNode(ax, node, label, x, y, w, h, theme)
severity = string(node.severity(1));
color = localSeverityColor(severity, theme);
rectangle(ax, 'Position', [x - 0.5*w, y - 0.5*h, w, h], ...
    'Curvature', [0.04 0.04], ...
    'FaceColor', color .* 0.44 + theme.axesColor .* 0.56, ...
    'EdgeColor', color, ...
    'LineWidth', 1.2);
text(ax, x, y + 0.135, label, ...
    'Color', theme.textColor, ...
    'FontWeight', 'bold', ...
    'FontSize', 7.5, ...
    'HorizontalAlignment', 'center', ...
    'Interpreter', 'none');
text(ax, x, y - 0.070, localCompactLabel(node.status_label(1), 13), ...
    'Color', theme.textColor, ...
    'FontSize', 6.5, ...
    'HorizontalAlignment', 'center', ...
    'Interpreter', 'none');
end

function localDrawMissingNode(ax, label, x, y, w, h, theme)
color = localSeverityColor("missing", theme);
rectangle(ax, 'Position', [x - 0.5*w, y - 0.5*h, w, h], ...
    'Curvature', [0.04 0.04], ...
    'FaceColor', color .* 0.35 + theme.axesColor .* 0.65, ...
    'EdgeColor', color, ...
    'LineWidth', 1.0);
text(ax, x, y + 0.05, label, ...
    'Color', theme.textColor, ...
    'FontWeight', 'bold', ...
    'FontSize', 8, ...
    'HorizontalAlignment', 'center', ...
    'Interpreter', 'none');
text(ax, x, y - 0.07, "missing", ...
    'Color', theme.mutedTextColor, ...
    'FontSize', 7, ...
    'HorizontalAlignment', 'center', ...
    'Interpreter', 'none');
end

function titleText = localTitleText(baseTitle, snapshot)
if istable(snapshot) && ~isempty(snapshot)
    focus = localCompactLabel(snapshot.most_important_label(1), 20);
    titleText = sprintf('%s | t %.2f s | max %s | focus %s', ...
        char(baseTitle), snapshot.t(1), char(snapshot.max_severity(1)), char(focus));
else
    titleText = char(baseTitle);
end
end

function label = localCompactLabel(label, maxChars)
label = string(label);
label = erase(label, ["telemetry_","firmware_","contract_","evidence_"]);
label = replace(label, "_", " ");
label = strtrim(label);
if strlength(label) > maxChars
    label = extractBefore(label, maxChars + 1);
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

function color = localSeverityColor(severity, theme)
switch string(severity)
    case "critical"
        color = [0.82 0.20 0.18];
    case "warning"
        color = [0.94 0.55 0.18];
    case "missing"
        color = [0.35 0.35 0.35];
    case "notice"
        color = [0.25 0.48 0.76];
    otherwise
        color = theme.okColor;
end
end

function theme = localTheme()
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.mutedTextColor = [0.78 0.80 0.82];
theme.okColor = [0.20 0.66 0.38];
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

function fig = plotCausalityGraph(nodes, edges, snapshot, options)
%PLOTCAUSALITYGRAPH Plot a sensor-to-actuator causality snapshot.
arguments
    nodes table
    edges table
    snapshot table = table()
    options.Title (1,1) string = "End-to-End Causality Graph"
end

localValidateInputs(nodes, edges);
theme = localTheme();
fig = figure('Name', 'Caelum End-to-End Causality Graph', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.05 0.08 0.90 0.82]);

ax = axes('Parent', fig);
hold(ax, 'on');
axis(ax, [0 1 0 1]);
axis(ax, 'off');
set(ax, 'Color', theme.figureColor);

titleText = localTitleText(options.Title, snapshot);
title(ax, titleText, 'Color', theme.textColor, 'Interpreter', 'none', 'FontWeight', 'bold');

localDrawEdges(ax, nodes, edges, theme);
localDrawNodes(ax, nodes, theme);
localDrawLegend(ax, theme);
localDrawSummary(ax, nodes, edges, snapshot, theme);
end

function localValidateInputs(nodes, edges)
requiredNodes = ["node_id","node_label","node_group","severity","status_label", ...
    "value_text","rationale","source_fields","t","x","y"];
missingNodes = setdiff(requiredNodes, string(nodes.Properties.VariableNames), 'stable');
if ~isempty(missingNodes)
    error('caelum:plotCausalityGraph:MissingNodeFields', ...
        'Node table is missing required fields: %s', strjoin(cellstr(missingNodes), ', '));
end

requiredEdges = ["edge_id","from_node","to_node","edge_label","value_text", ...
    "severity","rationale","source_fields"];
missingEdges = setdiff(requiredEdges, string(edges.Properties.VariableNames), 'stable');
if ~isempty(missingEdges)
    error('caelum:plotCausalityGraph:MissingEdgeFields', ...
        'Edge table is missing required fields: %s', strjoin(cellstr(missingEdges), ', '));
end
end

function localDrawEdges(ax, nodes, edges, theme)
for k = 1:height(edges)
    fromIdx = find(nodes.node_id == edges.from_node(k), 1, 'first');
    toIdx = find(nodes.node_id == edges.to_node(k), 1, 'first');
    if isempty(fromIdx) || isempty(toIdx)
        continue;
    end
    x1 = nodes.x(fromIdx);
    y1 = nodes.y(fromIdx);
    x2 = nodes.x(toIdx);
    y2 = nodes.y(toIdx);
    color = localSeverityColor(edges.severity(k), theme);
    dx = x2 - x1;
    dy = y2 - y1;
    shrink = 0.055;
    span = hypot(dx, dy);
    if span > 0
        x1 = x1 + shrink .* dx ./ span;
        y1 = y1 + shrink .* dy ./ span;
        x2 = x2 - shrink .* dx ./ span;
        y2 = y2 - shrink .* dy ./ span;
    end
    quiver(ax, x1, y1, x2 - x1, y2 - y1, 0, ...
        'Color', color, ...
        'LineWidth', 1.35, ...
        'MaxHeadSize', 0.20, ...
        'AutoScale', 'off');
    localEdgeLabel(ax, x1, y1, x2, y2, edges.edge_label(k), theme);
end
end

function localEdgeLabel(ax, x1, y1, x2, y2, label, theme)
x = 0.5 * (x1 + x2);
y = 0.5 * (y1 + y2);
text(ax, x, y, localCompactText(label, 22), ...
    'Color', theme.mutedTextColor, ...
    'FontSize', 8, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none', ...
    'BackgroundColor', theme.figureColor, ...
    'Margin', 1);
end

function localDrawNodes(ax, nodes, theme)
w = 0.135;
h = 0.115;
for k = 1:height(nodes)
    color = localSeverityColor(nodes.severity(k), theme);
    x = nodes.x(k) - 0.5 * w;
    y = nodes.y(k) - 0.5 * h;
    rectangle(ax, 'Position', [x y w h], ...
        'Curvature', [0.06 0.06], ...
        'FaceColor', color .* 0.55 + theme.axesColor .* 0.45, ...
        'EdgeColor', color, ...
        'LineWidth', 1.3);
    text(ax, nodes.x(k), nodes.y(k) + 0.032, nodes.node_label(k), ...
        'Color', theme.textColor, ...
        'FontWeight', 'bold', ...
        'FontSize', 9, ...
        'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');
    text(ax, nodes.x(k), nodes.y(k), localCompactText(nodes.status_label(k), 26), ...
        'Color', theme.textColor, ...
        'FontSize', 8, ...
        'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');
    text(ax, nodes.x(k), nodes.y(k) - 0.032, localCompactText(nodes.value_text(k), 34), ...
        'Color', theme.mutedTextColor, ...
        'FontSize', 7, ...
        'HorizontalAlignment', 'center', ...
        'Interpreter', 'none');
end
end

function localDrawLegend(ax, theme)
labels = ["info","notice","missing","warning","critical"];
x0 = 0.03;
y0 = 0.05;
for k = 1:numel(labels)
    x = x0 + (k-1) * 0.075;
    color = localSeverityColor(labels(k), theme);
    rectangle(ax, 'Position', [x y0 0.016 0.016], ...
        'FaceColor', color, ...
        'EdgeColor', color);
    text(ax, x + 0.020, y0 + 0.008, labels(k), ...
        'Color', theme.mutedTextColor, ...
        'FontSize', 8, ...
        'VerticalAlignment', 'middle', ...
        'Interpreter', 'none');
end
end

function localDrawSummary(ax, nodes, edges, snapshot, theme)
lines = strings(0, 1);
lines(end+1) = "Causality Snapshot Summary";
if istable(snapshot) && ~isempty(snapshot)
    lines(end+1) = "t=" + string(sprintf('%.3f', snapshot.t(1))) + ...
        " s | max=" + string(snapshot.max_severity(1)) + ...
        " | focus=" + string(snapshot.most_important_node(1)) + ...
        " / " + string(snapshot.most_important_label(1));
end
rank = localSeverityRank(nodes.severity);
[~, order] = sort(rank, 'descend');
for k = 1:min(4, numel(order))
    row = order(k);
    lines(end+1) = nodes.node_id(row) + ": " + nodes.status_label(row) + ...
        " | " + nodes.value_text(row); %#ok<AGROW>
end
lines(end+1) = "Edges: " + string(height(edges)) + " | Nodes: " + string(height(nodes));

text(ax, 0.50, 0.06, strjoin(lines, newline), ...
    'Color', theme.textColor, ...
    'FontName', 'Consolas', ...
    'FontSize', 8, ...
    'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'bottom', ...
    'Interpreter', 'none');
end

function titleText = localTitleText(baseTitle, snapshot)
if istable(snapshot) && ~isempty(snapshot) && ismember("t", string(snapshot.Properties.VariableNames))
    titleText = sprintf('%s | t %.3f s | %s / %s', ...
        char(baseTitle), snapshot.t(1), ...
        char(snapshot.most_important_node(1)), char(snapshot.most_important_label(1)));
else
    titleText = char(baseTitle);
end
end

function out = localCompactText(value, maxChars)
out = string(value);
out = replace(out, "_", " ");
if strlength(out) > maxChars
    out = extractBefore(out, maxChars + 1);
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
        color = [0.36 0.36 0.36];
    case "notice"
        color = [0.25 0.48 0.76];
    otherwise
        color = theme.okColor;
end
end

function theme = localTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.mutedTextColor = [0.78 0.80 0.82];
theme.okColor = [0.20 0.66 0.38];
end

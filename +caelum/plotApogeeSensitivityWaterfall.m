function fig = plotApogeeSensitivityWaterfall(audit, cfg)
%PLOTAPOGEESENSITIVITYWATERFALL Plot apogee authority decomposition.
arguments
    audit table
    cfg struct = caelum.defaultConfig()
end

if isempty(audit) || height(audit) < 1
    error('caelum:plotApogeeSensitivityWaterfall:EmptyAudit', ...
        'Apogee sensitivity audit table must contain at least one row.');
end

required = ["t","component","component_label","value","unit","reference_value", ...
    "delta_value","normalized_value","authority_low_m","authority_high_m", ...
    "authority_span_m","target_selected_m","policy_cmd","actuator_position_norm", ...
    "actuator_tracking_error","decision_label","severity","audit_label","rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
if ~isempty(missing)
    error('caelum:plotApogeeSensitivityWaterfall:MissingAuditFields', ...
        'Apogee sensitivity audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

theme = localTheme();
fig = figure('Name', 'Caelum Apogee Sensitivity Waterfall', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.05 0.05 0.90 0.86]);

tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, localFigureTitle(audit));
hTitle.Color = theme.textColor;

axAuthority = nexttile(tl, 1, [1 2]);
localPlotAuthorityCorridor(axAuthority, audit, cfg, theme);

axDelta = nexttile(tl, 3);
localPlotTargetDeltas(axDelta, audit);

axCommand = nexttile(tl, 4);
localPlotCommandBars(axCommand, audit);

axFiniteDiff = nexttile(tl, 5);
localPlotFiniteDifferenceTerms(axFiniteDiff, audit);

axSensitivity = nexttile(tl, 6);
localPlotComponentStatus(axSensitivity, audit);

axSummary = nexttile(tl, 7, [1 2]);
localPlotSummary(axSummary, audit);

localApplyStyle(fig, theme);
end

function localPlotAuthorityCorridor(ax, audit, cfg, theme)
low = localFirstFinite(audit.authority_low_m);
high = localFirstFinite(audit.authority_high_m);
target = localFirstFinite(audit.target_selected_m);
span = localFirstFinite(audit.authority_span_m);

hold(ax, 'on');
if isfinite(low) && isfinite(high)
    patch(ax, [low high high low], [0.35 0.35 0.65 0.65], theme.corridorColor, ...
        'FaceAlpha', 0.22, ...
        'EdgeColor', theme.corridorColor, ...
        'DisplayName', 'reachable authority');
    plot(ax, [low low], [0.22 0.78], '-', 'LineWidth', 1.2, 'DisplayName', 'full-brake bound');
    plot(ax, [high high], [0.22 0.78], '-', 'LineWidth', 1.2, 'DisplayName', 'no-brake bound');
end
if isfinite(target)
    plot(ax, target, 0.50, 'o', 'MarkerSize', 7, 'LineWidth', 1.2, 'DisplayName', 'selected target');
end

localPlotComponentMarker(ax, audit, "policy_command_projection", 0.58, 's', "policy projection");
localPlotComponentMarker(ax, audit, "actuator_projection", 0.42, 'd', "actuator projection");
mission = localMissionProfile(cfg);
if ~isempty(fieldnames(mission)) && isfinite(mission.targetApogee_m)
    plot(ax, mission.targetApogee_m, 0.72, 'v', 'MarkerSize', 6, ...
        'DisplayName', sprintf('IREC %.0f ft target', mission.targetApogee_ft));
end

ylim(ax, [0.15 0.85]);
yticks(ax, []);
xlabel(ax, 'apogee [m]');
title(ax, sprintf('Authority Corridor | span %.2f m', span));
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotComponentMarker(ax, audit, component, y, marker, label)
row = audit(audit.component == component, :);
if isempty(row) || ~isfinite(row.value(1))
    return;
end
plot(ax, row.value(1), y, marker, ...
    'MarkerSize', 7, ...
    'LineWidth', 1.2, ...
    'DisplayName', label);
end

function localPlotTargetDeltas(ax, audit)
components = ["no_brake_prediction","full_brake_prediction", ...
    "policy_command_projection","actuator_projection"];
labels = ["no brake","full brake","policy","actuator"];
values = nan(numel(components), 1);
colors = zeros(numel(components), 3);
for k = 1:numel(components)
    row = audit(audit.component == components(k), :);
    if ~isempty(row)
        values(k) = row.delta_value(1);
        colors(k, :) = localSeverityColor(row.severity(1), localTheme());
    end
end
barHandle = bar(ax, categorical(labels, labels, 'Ordinal', true), values);
barHandle.FaceColor = 'flat';
barHandle.CData = colors;
yline(ax, 0, '--', 'target');
ylabel(ax, 'apogee - target [m]');
title(ax, 'Target Error Decomposition');
grid(ax, 'on');
end

function localPlotCommandBars(ax, audit)
components = ["demand_from_corridor","policy_command_projection","actuator_tracking"];
labels = ["demand","policy","actuator"];
values = nan(numel(components), 1);
for k = 1:numel(components)
    row = audit(audit.component == components(k), :);
    if isempty(row)
        continue;
    end
    if components(k) == "policy_command_projection"
        values(k) = row.policy_cmd(1);
    else
        values(k) = row.normalized_value(1);
    end
end
bar(ax, categorical(labels, labels, 'Ordinal', true), values);
ylim(ax, [-0.05 1.05]);
ylabel(ax, 'normalized command');
title(ax, 'Control Demand / Achieved Output');
grid(ax, 'on');
end

function localPlotComponentStatus(ax, audit)
components = string(audit.component_label);
rank = localSeverityRank(audit.severity);
barHandle = barh(ax, categorical(components, components, 'Ordinal', true), rank);
barHandle.FaceColor = 'flat';
colors = zeros(height(audit), 3);
theme = localTheme();
for k = 1:height(audit)
    colors(k, :) = localSeverityColor(audit.severity(k), theme);
end
barHandle.CData = colors;
xlim(ax, [0 5.5]);
xticks(ax, 1:5);
xticklabels(ax, {'info','notice','missing','warn','crit'});
title(ax, 'Component Status');
grid(ax, 'on');
end

function localPlotFiniteDifferenceTerms(ax, audit)
components = ["fd_altitude_step","fd_velocity_step","fd_command_step"];
labels = ["altitude step","velocity step","command step"];
values = nan(numel(components), 1);
slopes = nan(numel(components), 1);
colors = zeros(numel(components), 3);
theme = localTheme();
for k = 1:numel(components)
    row = audit(audit.component == components(k), :);
    if ~isempty(row)
        values(k) = row.delta_value(1);
        slopes(k) = row.normalized_value(1);
        colors(k, :) = localSeverityColor(row.severity(1), theme);
    else
        colors(k, :) = localSeverityColor("missing", theme);
    end
end
barHandle = bar(ax, categorical(labels, labels, 'Ordinal', true), values);
barHandle.FaceColor = 'flat';
barHandle.CData = colors;
yline(ax, 0, '--', 'base');
ylabel(ax, 'apogee response [m]');
title(ax, 'Finite-Difference Replay-State Response');
grid(ax, 'on');
for k = 1:numel(values)
    if isfinite(values(k)) && isfinite(slopes(k))
        if values(k) >= 0
            alignment = 'bottom';
        else
            alignment = 'top';
        end
        text(ax, categorical(labels(k), labels, 'Ordinal', true), values(k), sprintf(' %.2g/unit', slopes(k)), ...
            'Rotation', 90, ...
            'VerticalAlignment', alignment, ...
            'FontSize', 7, ...
            'Interpreter', 'none');
    end
end
end

function localPlotSummary(ax, audit)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
lines = strings(0, 1);
lines(end+1) = "Apogee Sensitivity Summary";
lines(end+1) = sprintf('t: %.3f s | selector: %s', audit.t(1), char(audit.selector(1)));
lines(end+1) = sprintf('decision: %s', char(audit.decision_label(1)));
lines(end+1) = sprintf('authority: %.3f to %.3f m | span %.3f m', ...
    audit.authority_low_m(1), audit.authority_high_m(1), audit.authority_span_m(1));
lines(end+1) = sprintf('target: %.3f m', audit.target_selected_m(1));
lines(end+1) = sprintf('policy cmd: %.3f | actuator norm: %.3f | err %.3f', ...
    audit.policy_cmd(1), audit.actuator_position_norm(1), audit.actuator_tracking_error(1));
base = localComponentRow(audit, "replay_model_base");
fdH = localComponentRow(audit, "fd_altitude_step");
fdV = localComponentRow(audit, "fd_velocity_step");
fdU = localComponentRow(audit, "fd_command_step");
if ~isempty(base)
    lines(end+1) = sprintf('replay model base: %.3f m | h %.3g m/m | v %.3g m/(m/s) | cmd %.3g m/cmd', ...
        base.value(1), localRowNumber(fdH, "normalized_value"), ...
        localRowNumber(fdV, "normalized_value"), localRowNumber(fdU, "normalized_value"));
end
lines(end+1) = "labels: " + localLabelSummary(audit);
worst = localWorstRow(audit);
if ~isempty(worst)
    lines(end+1) = "focus: " + worst.component_label(1) + " / " + worst.audit_label(1);
    lines(end+1) = localCompactText(worst.rationale(1), 96);
end
text(ax, 0.02, 0.98, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'FontSize', 8, ...
    'Interpreter', 'none');
end

function row = localComponentRow(audit, component)
row = audit(audit.component == component, :);
if height(row) > 1
    row = row(1, :);
end
end

function value = localRowNumber(row, fieldName)
if isempty(row) || ~ismember(fieldName, string(row.Properties.VariableNames))
    value = NaN;
else
    raw = row.(char(fieldName));
    value = raw(1);
end
end

function textOut = localFigureTitle(audit)
textOut = sprintf('Apogee Sensitivity Waterfall / Control Authority Decomposition | t %.3f s', audit.t(1));
end

function value = localFirstFinite(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = values(1);
end
end

function row = localWorstRow(audit)
row = table();
if isempty(audit)
    return;
end
[~, idx] = max(localSeverityRank(audit.severity));
row = audit(idx, :);
end

function textOut = localLabelSummary(audit)
labels = unique(audit.audit_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.audit_label == labels(k)));
end
textOut = strjoin(parts, "; ");
end

function textOut = localCompactText(textIn, maxChars)
textOut = string(textIn);
textOut = replace(textOut, newline, " ");
if strlength(textOut) > maxChars
    textOut = extractBefore(textOut, maxChars + 1);
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

function mission = localMissionProfile(cfg)
mission = struct();
if ~isstruct(cfg) || ~isfield(cfg, 'mission') || ~isstruct(cfg.mission)
    return;
end
required = ["targetApogee_m","targetApogee_ft"];
if all(isfield(cfg.mission, cellstr(required))) && isfinite(cfg.mission.targetApogee_m)
    mission = cfg.mission;
end
end

function localApplyStyle(fig, theme)
axesHandles = findall(fig, 'Type', 'axes');
for k = 1:numel(axesHandles)
    set(axesHandles(k), ...
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

function theme = localTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.okColor = [0.20 0.66 0.38];
theme.corridorColor = [0.16 0.48 0.75];
end

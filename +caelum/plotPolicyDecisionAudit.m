function fig = plotPolicyDecisionAudit(audit, cfg)
%PLOTPOLICYDECISIONAUDIT Plot airbrake decision evidence on a shared timebase.
arguments
    audit table
    cfg struct = caelum.defaultConfig()
end

if isempty(audit) || height(audit) < 1
    error('caelum:plotPolicyDecisionAudit:EmptyAudit', ...
        'Policy decision audit table must contain at least one row.');
end

required = ["t","apogee_no_brake_m","apogee_full_brake_m","target_selected_m", ...
    "policy_cmd","uncertainty_margin_m","apogee_error_m", ...
    "command_active","warning_active","phase_allows_brake", ...
    "decision_code","decision_label","decision_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames));
if ~isempty(missing)
    error('caelum:plotPolicyDecisionAudit:MissingAuditFields', ...
        'Policy decision audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

theme = localTheme();
fig = figure('Name', 'Caelum Airbrake Policy Decision Audit', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.07 0.92 0.84]);

tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, 'Airbrake Policy Decision Audit');
hTitle.Color = theme.textColor;

axCorridor = nexttile(tl, 1, [1 2]);
localPlotReachabilityCorridor(axCorridor, audit, cfg, theme);

axCommand = nexttile(tl, 3);
localPlotCommand(axCommand, audit);

axError = nexttile(tl, 4);
localPlotTargetError(axError, audit);

axPhase = nexttile(tl, 5);
localPlotPhaseEvidence(axPhase, audit);

axDecision = nexttile(tl, 6);
localPlotDecisionLabels(axDecision, audit);

axSummary = nexttile(tl, 7, [1 2]);
localPlotSummary(axSummary, audit);

localApplyStyle(fig, theme);
end

function localPlotReachabilityCorridor(ax, audit, cfg, theme)
t = audit.t;
low = audit.reachability_low_m;
high = audit.reachability_high_m;
valid = isfinite(t) & isfinite(low) & isfinite(high);

hold(ax, 'on');
if any(valid)
    fill(ax, [t(valid); flipud(t(valid))], [low(valid); flipud(high(valid))], ...
        theme.corridorColor, ...
        'FaceAlpha', 0.22, ...
        'EdgeColor', 'none', ...
        'DisplayName', 'reachable apogee corridor');
end

plot(ax, t, audit.apogee_no_brake_m, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'no brake prediction');
plot(ax, t, audit.apogee_full_brake_m, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'full brake prediction');
plot(ax, t, audit.target_selected_m, '--', ...
    'LineWidth', 1.1, ...
    'DisplayName', 'selected target');

if ismember("target_nominal_m", string(audit.Properties.VariableNames))
    plot(ax, t, audit.target_nominal_m, ':', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'nominal target');
end
if ismember("target_effective_m", string(audit.Properties.VariableNames))
    plot(ax, t, audit.target_effective_m, '-.', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'effective target');
end

mission = localMissionProfile(cfg);
if ~isempty(fieldnames(mission))
    localPlotMissionTargetReference(ax, audit, mission);
end

xlabel(ax, 't [s]');
ylabel(ax, 'apogee [m]');
title(ax, 'Apogee Reachability Corridor');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotCommand(ax, audit)
vars = string(audit.Properties.VariableNames);
hold(ax, 'on');

yyaxis(ax, 'left');
stairs(ax, audit.t, audit.policy_cmd, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'policy command');
if ismember("corridor_brake_demand_index", vars)
    plot(ax, audit.t, audit.corridor_brake_demand_index, '--', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'corridor demand index');
end
if ismember("policy_valid", vars)
    stairs(ax, audit.t, double(audit.policy_valid > 0.5), ':', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'policy valid');
end
ylabel(ax, 'normalized');
ylim(ax, [-0.05 1.05]);

if ismember("actuator_us", vars) && any(isfinite(audit.actuator_us))
    yyaxis(ax, 'right');
    plot(ax, audit.t, audit.actuator_us, ...
        'LineWidth', 1.0, ...
        'DisplayName', 'actuator');
    ylabel(ax, 'actuator [us]');
end

xlabel(ax, 't [s]');
title(ax, 'Command Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotTargetError(ax, audit)
vars = string(audit.Properties.VariableNames);
hold(ax, 'on');

if ismember("apogee_error_m", vars)
    plot(ax, audit.t, audit.apogee_error_m, ...
        'LineWidth', 1.1, ...
        'DisplayName', 'apogee error');
end
if ismember("uncertainty_margin_m", vars)
    plot(ax, audit.t, audit.uncertainty_margin_m, '--', ...
        'LineWidth', 1.1, ...
        'DisplayName', 'uncertainty margin');
end
if ismember("policy_command_residual", vars)
    yyaxis(ax, 'right');
    plot(ax, audit.t, audit.policy_command_residual, ':', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'cmd - demand');
    ylabel(ax, 'normalized residual');
    yyaxis(ax, 'left');
end

xlabel(ax, 't [s]');
ylabel(ax, 'm');
title(ax, 'Target Error / Margin');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotPhaseEvidence(ax, audit)
vars = string(audit.Properties.VariableNames);
hold(ax, 'on');

stairs(ax, audit.t, audit.phase, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'phase');
if ismember("phase_brake_active", vars)
    stairs(ax, audit.t, 4.4 * double(audit.phase_brake_active), '--', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'brake active evidence');
end
if ismember("phase_diag_valid", vars)
    stairs(ax, audit.t, -0.35 + 0.30 * double(audit.phase_diag_valid), ':', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'diag valid');
end

ylim(ax, [-0.6 4.7]);
yticks(ax, 0:4);
yticklabels(ax, {'IDLE','BOOST','COAST','BRAKE','DESCENT'});
xlabel(ax, 't [s]');
title(ax, 'Phase Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotDecisionLabels(ax, audit)
stairs(ax, audit.t, audit.decision_code, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'decision evidence label');
yticks(ax, 1:9);
yticklabels(ax, localDecisionTickLabels());
ylim(ax, [0.5 9.5]);
xlabel(ax, 't [s]');
title(ax, 'Audit Classification');
grid(ax, 'on');
end

function localPlotSummary(ax, audit)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

dt = localSampleDurations(audit.t);
duration = sum(dt, 'omitnan');
activeDuration = sum(dt(audit.command_active), 'omitnan');
warningDuration = sum(dt(audit.warning_active), 'omitnan');
brakePhaseDuration = sum(dt(audit.phase_allows_brake), 'omitnan');

lines = strings(0, 1);
lines(end+1) = "Audit Summary";
lines(end+1) = sprintf('Rows: %d | duration: %.3f s', height(audit), duration);
lines(end+1) = sprintf('Command-active duration: %.3f s', activeDuration);
lines(end+1) = sprintf('BRAKE-phase duration: %.3f s', brakePhaseDuration);
lines(end+1) = sprintf('Warning-active duration: %.3f s', warningDuration);
lines(end+1) = sprintf('Max command: %.3f', max(audit.policy_cmd, [], 'omitnan'));
lines(end+1) = sprintf('Max uncertainty margin: %.3f m', max(audit.uncertainty_margin_m, [], 'omitnan'));
lines(end+1) = sprintf('Max apogee error: %.3f m', max(audit.apogee_error_m, [], 'omitnan'));

labels = unique(audit.decision_label, 'stable');
labelCounts = strings(numel(labels), 1);
for k = 1:numel(labels)
    labelCounts(k) = sprintf('%s=%d', labels(k), nnz(audit.decision_label == labels(k)));
end
lines(end+1) = "Decision labels: " + strjoin(labelCounts, "; ");

idx = find(audit.decision_label ~= "", 1, 'last');
if ~isempty(idx)
    lines(end+1) = "Final label: " + audit.decision_label(idx);
    lines(end+1) = "Final rationale: " + audit.decision_rationale(idx);
end

text(ax, 0.01, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none');
end

function labels = localDecisionTickLabels()
labels = { ...
    'telemetry incomplete', ...
    'warning active', ...
    'diagnostic stale', ...
    'phase blocked', ...
    'policy invalid', ...
    'target above no-brake', ...
    'target below full-brake', ...
    'brake authorized', ...
    'inside corridor no cmd'};
end

function dt = localSampleDurations(t)
t = t(:);
dt = [diff(t); NaN];
fallback = median(diff(t), 'omitnan');
if ~isfinite(fallback) || fallback < 0
    fallback = 0;
end
bad = ~isfinite(dt) | dt < 0;
dt(bad) = fallback;
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

function localPlotMissionTargetReference(ax, audit, mission)
target_m = mission.targetApogee_m;
if ~isfinite(target_m)
    return;
end

values = [ ...
    audit.apogee_no_brake_m(:); ...
    audit.apogee_full_brake_m(:); ...
    audit.target_selected_m(:)];
values = values(isfinite(values));
if isempty(values)
    return;
end

span = max(values) - min(values);
if ~isfinite(span) || span <= 0
    span = max(1.0, abs(target_m) * 0.05);
end

if target_m < min(values) - 0.10 * span || target_m > max(values) + 0.50 * span
    return;
end

yline(ax, target_m, '--', ...
    'DisplayName', sprintf('IREC %.0f ft target', mission.targetApogee_ft), ...
    'Color', [0.20 0.70 0.90], ...
    'LineWidth', 1.0);
end

function theme = localTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.corridorColor = [0.20 0.55 0.80];
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

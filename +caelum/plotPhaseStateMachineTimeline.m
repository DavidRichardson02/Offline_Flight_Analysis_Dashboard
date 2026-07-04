function fig = plotPhaseStateMachineTimeline(audit)
%PLOTPHASESTATEMACHINETIMELINE Plot phase state-machine evidence.
arguments
    audit table
end

if isempty(audit) || height(audit) < 1
    error('caelum:plotPhaseStateMachineTimeline:EmptyAudit', ...
        'Phase state-machine audit table must contain at least one row.');
end

required = ["t","phase","phase_name","expected_phase_from_evidence", ...
    "phase_changed","transition_label","phase_diag_valid","phase_diag_updated", ...
    "phase_diag_age_ms","evidence_code","evidence_label","evidence_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
if ~isempty(missing)
    error('caelum:plotPhaseStateMachineTimeline:MissingAuditFields', ...
        'Phase state-machine audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

theme = localTheme();
fig = figure('Name', 'Caelum Phase State-Machine Evidence Timeline', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.07 0.92 0.84]);

tl = tiledlayout(fig, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, 'Phase State-Machine Evidence Timeline');
hTitle.Color = theme.textColor;

axPhase = nexttile(tl, 1, [1 2]);
localPlotPhaseRibbon(axPhase, audit, theme);

axCandidate = nexttile(tl, 3);
localPlotFlagRaster(axCandidate, audit, ...
    ["phase_launch_candidate","phase_boost_dwell_met","phase_burnout_candidate", ...
     "phase_coast_dwell_met","phase_descent_candidate"], ...
    ["launch candidate","boost dwell met","burnout candidate", ...
     "coast dwell met","descent candidate"], ...
    "Candidate / Dwell Evidence");

axLatch = nexttile(tl, 4);
localPlotFlagRaster(axLatch, audit, ...
    ["phase_launch_latched","phase_burnout_latched","phase_brake_active","phase_descent_latched"], ...
    ["launch latched","burnout latched","brake active","descent latched"], ...
    "Latch / Active-Phase Evidence");

axDiag = nexttile(tl, 5);
localPlotDiagnostics(axDiag, audit);

axKinematic = nexttile(tl, 6);
localPlotKinematicContext(axKinematic, audit);

axClass = nexttile(tl, 7);
localPlotEvidenceLabels(axClass, audit);

axSummary = nexttile(tl, 8);
localPlotSummary(axSummary, audit);

localApplyStyle(fig, theme);
end

function localPlotPhaseRibbon(ax, audit, theme)
hold(ax, 'on');
stairs(ax, audit.t, audit.phase, ...
    'Color', theme.primaryColor, ...
    'LineWidth', 1.3, ...
    'DisplayName', 'firmware phase');

if any(isfinite(audit.expected_phase_from_evidence))
    stairs(ax, audit.t, audit.expected_phase_from_evidence, '--', ...
        'Color', theme.secondaryColor, ...
        'LineWidth', 1.0, ...
        'DisplayName', 'expected from latch/brake evidence');
end

transitionIdx = find(audit.phase_changed & isfinite(audit.t));
for k = 1:numel(transitionIdx)
    idx = transitionIdx(k);
    xline(ax, audit.t(idx), ':', ...
        'Color', theme.transitionColor, ...
        'HandleVisibility', 'off');
end

ylim(ax, [-0.5 4.5]);
yticks(ax, 0:4);
yticklabels(ax, {'IDLE','BOOST','COAST','BRAKE','DESCENT'});
xlabel(ax, 't [s]');
title(ax, 'Firmware Phase vs. Latched Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotFlagRaster(ax, audit, fields, labels, plotTitle)
vars = string(audit.Properties.VariableNames);
presentMask = ismember(fields, vars);
fields = fields(presentMask);
labels = labels(presentMask);

if isempty(fields)
    localShowUnavailable(ax, "No phase evidence fields available.");
    title(ax, plotTitle, 'Interpreter', 'none');
    return;
end

matrix = zeros(numel(fields), height(audit));
for k = 1:numel(fields)
    matrix(k, :) = double(audit.(char(fields(k))) > 0.5).';
end

imagesc(ax, audit.t, 1:numel(fields), matrix);
set(ax, 'YDir', 'normal');
yticks(ax, 1:numel(fields));
yticklabels(ax, cellstr(labels));
colormap(ax, [0.12 0.13 0.14; 0.20 0.68 0.38]);
caxis(ax, [0 1]);
xlabel(ax, 't [s]');
title(ax, plotTitle, 'Interpreter', 'none');
grid(ax, 'on');
end

function localPlotDiagnostics(ax, audit)
hold(ax, 'on');
yyaxis(ax, 'left');
stairs(ax, audit.t, double(audit.phase_diag_valid > 0.5), ...
    'LineWidth', 1.1, ...
    'DisplayName', 'diag valid');
stairs(ax, audit.t, double(audit.phase_diag_updated > 0.5), '--', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'diag updated');
if ismember("phase_diag_seq_changed", string(audit.Properties.VariableNames))
    stairs(ax, audit.t, double(audit.phase_diag_seq_changed > 0.5), ':', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'seq advanced');
end
ylim(ax, [-0.05 1.05]);
ylabel(ax, 'flag');

yyaxis(ax, 'right');
plot(ax, audit.t, audit.phase_diag_age_ms, ...
    'LineWidth', 1.0, ...
    'DisplayName', 'diag age');
ylabel(ax, 'age [ms]');

xlabel(ax, 't [s]');
title(ax, 'Diagnostic Freshness');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotKinematicContext(ax, audit)
hasAltitude = any(isfinite(audit.altitude_m));
hasVelocity = any(isfinite(audit.velocity_mps));
hasAccel = any(isfinite(audit.accel_mps2));
if ~hasAltitude && ~hasVelocity && ~hasAccel
    localShowUnavailable(ax, "Kinematic evidence unavailable.");
    title(ax, 'Kinematic Context');
    return;
end

hold(ax, 'on');
if hasAltitude
    yyaxis(ax, 'left');
    plot(ax, audit.t, audit.altitude_m, ...
        'LineWidth', 1.0, ...
        'DisplayName', 'altitude');
    ylabel(ax, 'altitude [m]');
end

yyaxis(ax, 'right');
if hasVelocity
    plot(ax, audit.t, audit.velocity_mps, ...
        'LineWidth', 1.0, ...
        'DisplayName', 'velocity');
end
if hasAccel
    plot(ax, audit.t, audit.accel_mps2, '--', ...
        'LineWidth', 1.0, ...
        'DisplayName', 'vertical accel');
end
ylabel(ax, 'm/s or m/s^2');

xlabel(ax, 't [s]');
title(ax, 'Kinematic Context');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotEvidenceLabels(ax, audit)
stairs(ax, audit.t, audit.evidence_code, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'phase evidence label');
yticks(ax, 1:11);
yticklabels(ax, localEvidenceTickLabels());
ylim(ax, [0.5 11.5]);
xlabel(ax, 't [s]');
title(ax, 'Audit Classification');
grid(ax, 'on');
end

function localPlotSummary(ax, audit)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

dt = localSampleDurations(audit.t);
phaseDurations = localPhaseDurations(audit, dt);

lines = strings(0, 1);
lines(end+1) = "Phase Evidence Summary";
lines(end+1) = sprintf('Rows: %d | duration: %.3f s', height(audit), sum(dt, 'omitnan'));
lines(end+1) = sprintf('Phase durations [s]: IDLE %.2f | BOOST %.2f | COAST %.2f | BRAKE %.2f | DESCENT %.2f', ...
    phaseDurations(1), phaseDurations(2), phaseDurations(3), phaseDurations(4), phaseDurations(5));
lines(end+1) = sprintf('Transitions observed: %d', nnz(audit.phase_changed));
lines(end+1) = sprintf('Diagnostic stale rows: %d', nnz(audit.evidence_label == "diagnostic_stale"));
lines(end+1) = sprintf('Warning-active rows: %d', nnz(audit.evidence_label == "warning_active"));
lines(end+1) = sprintf('Evidence mismatch rows: %d', nnz(audit.evidence_label == "phase_evidence_mismatch"));
lines(end+1) = sprintf('Rollback rows: %d', nnz(audit.evidence_label == "nonmonotonic_phase"));
if any(isfinite(audit.phase_diag_age_ms))
    lines(end+1) = sprintf('Max diagnostic age: %.3f ms', max(audit.phase_diag_age_ms, [], 'omitnan'));
end

labels = unique(audit.evidence_label, 'stable');
labelCounts = strings(numel(labels), 1);
for k = 1:numel(labels)
    labelCounts(k) = sprintf('%s=%d', labels(k), nnz(audit.evidence_label == labels(k)));
end
lines(end+1) = "Evidence labels: " + strjoin(labelCounts, "; ");

idx = find(audit.evidence_label ~= "", 1, 'last');
if ~isempty(idx)
    lines(end+1) = "Final phase: " + audit.phase_name(idx);
    lines(end+1) = "Final expected phase: " + audit.expected_phase_name(idx);
    lines(end+1) = "Final label: " + audit.evidence_label(idx);
    lines(end+1) = "Final rationale: " + audit.evidence_rationale(idx);
end

text(ax, 0.02, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'FontSize', 8, ...
    'Interpreter', 'none');
end

function durations = localPhaseDurations(audit, dt)
durations = nan(1, 5);
for phaseValue = 0:4
    durations(phaseValue + 1) = sum(dt(round(audit.phase) == phaseValue), 'omitnan');
end
end

function labels = localEvidenceTickLabels()
labels = { ...
    'telemetry incomplete', ...
    'diagnostic stale', ...
    'warning active', ...
    'unexpected phase', ...
    'nonmonotonic phase', ...
    'evidence mismatch', ...
    'transition observed', ...
    'candidate pending', ...
    'dwell met', ...
    'latched hold', ...
    'nominal hold'};
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
theme.transitionColor = [0.72 0.72 0.72];
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

function fig = plotDashboard(T, events, replay, cfg)
%PLOTDASHBOARD Create the canonical dashboard with GPS/3D and firmware telemetry.
arguments
    T table
    events struct
    replay = []
    cfg struct = struct()
end

defaultCfg = caelum.defaultConfig();
if isempty(fieldnames(cfg))
    cfg = defaultCfg;
elseif ~isfield(cfg, 'mission') || isempty(cfg.mission)
    cfg.mission = defaultCfg.mission;
end

theme = localDashboardTheme();
widgets = localDashboardWidgetRegistry(cfg);
hasGps = all(ismember(["gps_x","gps_y","gps_z"], string(T.Properties.VariableNames))) || ...
         all(ismember(["gps_vx","gps_vy","gps_vz"], string(T.Properties.VariableNames)));

est3d = table();
if hasGps
    vars = string(T.Properties.VariableNames);
    if ~all(ismember(["q_w","q_x","q_y","q_z"], vars))
        attitude = caelum.runAttitudeReplay(T, cfg);
        T.q_w = interp1(attitude.t, attitude.q_w, T.t, 'linear', 1);
        T.q_x = interp1(attitude.t, attitude.q_x, T.t, 'linear', 0);
        T.q_y = interp1(attitude.t, attitude.q_y, T.t, 'linear', 0);
        T.q_z = interp1(attitude.t, attitude.q_z, T.t, 'linear', 0);
    end
    est3d = caelum.run3DEKF(T, cfg);
end

flightEventIndex = table();
auditBundle = struct();
if localWidgetEnabled(widgets, "flight_evidence_navigator") || ...
        localWidgetEnabled(widgets, "causality_sensor_to_actuator")
    try
        [flightEventIndex, auditBundle] = caelum.buildFlightEvidenceIndex(T, events, replay, cfg, ...
            Est3D=est3d);
    catch
        flightEventIndex = table();
        auditBundle = struct();
    end
end

fig = figure('Name', 'Caelum Flight Dashboard V4', 'Color', theme.figureColor, ...
    'Units', 'normalized', 'Position', [0.03 0.04 0.94 0.90], ...
    'Visible', 'on', 'WindowStyle', 'normal');

layout = localCreateDashboardLayout(fig, theme, widgets);
localRenderFlightStateRegion(layout.axes, T, replay, est3d, theme);
localRenderEstimatorRegion(layout.axes, T, events, replay, est3d, theme);
localRenderEvidenceRegion(layout.axes, T, events, replay, cfg, est3d, flightEventIndex, auditBundle, widgets);
localRenderPolicyRegion(layout.axes, T, cfg);
localRenderProvenanceRegion(layout.axes, T, cfg, est3d);
localRenderSummaryRegion(layout.axes.summary, T, events, cfg, est3d, theme);
localApplyDashboardStyle(fig, theme);
end

function layout = localCreateDashboardLayout(fig, theme, widgets)
spec = localDashboardLayoutSpec(widgets);
tl = tiledlayout(fig, spec.Rows, spec.Columns, ...
    'TileSpacing', spec.TileSpacing, ...
    'Padding', spec.Padding);
hTitle = title(tl, 'Caelum Integrated Dashboard V4');
hTitle.Color = theme.textColor;
hTitle.FontSize = theme.titleFontSize;
hTitle.FontWeight = 'bold';

ax = struct();
row = spec.Row;

% Primary flight-state region. These axes span two rows because they are the
% main review surface and must remain readable after diagnostics are enabled.
ax.altitude = nexttile(tl, localTileIndex(row.flightState, 1, spec), spec.Span.primary);
ax.velocity = nexttile(tl, localTileIndex(row.flightState, 2, spec), spec.Span.primary);
ax.acceleration = nexttile(tl, localTileIndex(row.flightState, 3, spec), spec.Span.primary);
ax.sensorHealth = nexttile(tl, localTileIndex(row.flightState, 4, spec), spec.Span.primary);

% Estimator, navigation, wind, and event context region.
ax.estimatorUncertainty = nexttile(tl, localTileIndex(row.estimatorTop, 1, spec));
ax.gpsPosition = nexttile(tl, localTileIndex(row.estimatorTop, 2, spec));
ax.gpsVelocity = nexttile(tl, localTileIndex(row.estimatorTop, 3, spec));
ax.trajectory3d = nexttile(tl, localTileIndex(row.estimatorTop, 4, spec));
ax.windEstimate = nexttile(tl, localTileIndex(row.estimatorBottom, 1, spec));
ax.windUncertainty = nexttile(tl, localTileIndex(row.estimatorBottom, 2, spec));
if localWidgetEnabled(widgets, "event_timing")
    ax.gpsFusion = nexttile(tl, localTileIndex(row.estimatorBottom, 3, spec));
    ax.eventTiming = nexttile(tl, localTileIndex(row.estimatorBottom, 4, spec));
else
    ax.gpsFusion = nexttile(tl, localTileIndex(row.estimatorBottom, 3, spec), spec.Span.twoColumns);
end

% Full-width evidence strips. Optional drill-down diagnostics are inserted
% here only when enabled in the widget registry.
if localWidgetEnabled(widgets, "flight_evidence_navigator")
    ax.flightEvidence = nexttile(tl, localTileIndex(row.flightEvidence, 1, spec), spec.Span.fullWidth);
end
if localWidgetEnabled(widgets, "replay_contract")
    ax.replayContract = nexttile(tl, localTileIndex(row.replayContract, 1, spec), spec.Span.fullWidth);
end
if localWidgetEnabled(widgets, "causality_sensor_to_actuator")
    ax.causality = nexttile(tl, localTileIndex(row.causality, 1, spec), spec.Span.fullWidth);
end

% Policy and phase diagnostic region.
if localWidgetEnabled(widgets, "policy")
    ax.phaseTimeline = nexttile(tl, localTileIndex(row.policy, 1, spec));
    ax.policyCommand = nexttile(tl, localTileIndex(row.policy, 2, spec));
    ax.policyPrediction = nexttile(tl, localTileIndex(row.policy, 3, spec));
    ax.phaseDiagnostics = nexttile(tl, localTileIndex(row.policy, 4, spec));
end

% Provenance and compact 3D/wind region.
showAttitudeGravity = localWidgetEnabled(widgets, "attitude_gravity_provenance");
showTrajectoryWind = localWidgetEnabled(widgets, "trajectory_wind");
if showAttitudeGravity && showTrajectoryWind
    ax.attitudeGravity = nexttile(tl, localTileIndex(row.provenance, 1, spec), spec.Span.provenanceHalf);
    ax.trajectoryWind = nexttile(tl, localTileIndex(row.provenance, 3, spec), spec.Span.provenanceHalf);
elseif showAttitudeGravity
    ax.attitudeGravity = nexttile(tl, localTileIndex(row.provenance, 1, spec), spec.Span.provenanceFull);
elseif showTrajectoryWind
    ax.trajectoryWind = nexttile(tl, localTileIndex(row.provenance, 1, spec), spec.Span.provenanceFull);
end

if localWidgetEnabled(widgets, "telemetry_freshness_source_provenance")
    ax.telemetryFreshness = nexttile(tl, localTileIndex(row.freshness, 1, spec), spec.Span.fullWidth);
end

% Reserved summary area. This is never drawn over data axes.
ax.summary = nexttile(tl, localTileIndex(row.summary, 1, spec), spec.Span.summary);

layout = struct();
layout.root = tl;
layout.axes = ax;
layout.spec = spec;
end

function spec = localDashboardLayoutSpec(widgets)
spec = struct();
spec.Columns = 4;
spec.TileSpacing = 'loose';
spec.Padding = 'compact';
spec.Span.primary = [2 1];
spec.Span.fullWidth = [1 4];
spec.Span.halfWidth = [1 2];
spec.Span.twoColumns = [1 2];
spec.Span.summary = [1 4];

row = 1;
spec.Row.flightState = row;
row = row + spec.Span.primary(1);
spec.Row.estimatorTop = row;
row = row + 1;
spec.Row.estimatorBottom = row;
row = row + 1;

spec.Row.flightEvidence = localOptionalRow(localWidgetEnabled(widgets, "flight_evidence_navigator"), row);
if isfinite(spec.Row.flightEvidence)
    row = row + 1;
end
spec.Row.replayContract = localOptionalRow(localWidgetEnabled(widgets, "replay_contract"), row);
if isfinite(spec.Row.replayContract)
    row = row + 1;
end
spec.Row.causality = localOptionalRow(localWidgetEnabled(widgets, "causality_sensor_to_actuator"), row);
if isfinite(spec.Row.causality)
    row = row + 1;
end
spec.Row.policy = localOptionalRow(localWidgetEnabled(widgets, "policy"), row);
if isfinite(spec.Row.policy)
    row = row + 1;
end

hasProvenanceRow = localWidgetEnabled(widgets, "attitude_gravity_provenance") || localWidgetEnabled(widgets, "trajectory_wind");
if localWidgetEnabled(widgets, "trajectory_wind")
    spec.ProvenanceRows = 2;
else
    spec.ProvenanceRows = 1;
end
spec.Span.provenanceFull = [spec.ProvenanceRows 4];
spec.Span.provenanceHalf = [spec.ProvenanceRows 2];
spec.Row.provenance = localOptionalRow(hasProvenanceRow, row);
if isfinite(spec.Row.provenance)
    row = row + spec.ProvenanceRows;
end
spec.Row.freshness = localOptionalRow(localWidgetEnabled(widgets, "telemetry_freshness_source_provenance"), row);
if isfinite(spec.Row.freshness)
    row = row + 1;
end

spec.Row.summary = row;
row = row + spec.Span.summary(1);
spec.Rows = row - 1;
end

function row = localOptionalRow(enabled, candidateRow)
if enabled
    row = candidateRow;
else
    row = NaN;
end
end

function idx = localTileIndex(row, column, spec)
idx = (row - 1) * spec.Columns + column;
end

function widgets = localDashboardWidgetRegistry(cfg)
% Central widget registry for the integrated dashboard. Standalone
% diagnostic builders remain available even when a compact widget is hidden.
widgets = struct();
widgets.flight_evidence_navigator = localWidgetSpec(false);
widgets.replay_contract = localWidgetSpec(false);
widgets.causality_sensor_to_actuator = localWidgetSpec(false);
widgets.event_timing = localWidgetSpec(false);
widgets.policy = localWidgetSpec(false);
widgets.attitude_gravity_provenance = localWidgetSpec(false);
widgets.trajectory_wind = localWidgetSpec(false);
widgets.telemetry_freshness_source_provenance = localWidgetSpec(false);

widgets = localApplyWidgetOverrides(widgets, cfg);
end

function widget = localWidgetSpec(enabled)
widget = struct();
widget.enabled = logical(enabled);
end

function widgets = localApplyWidgetOverrides(widgets, cfg)
names = string(fieldnames(widgets));
for k = 1:numel(names)
    name = char(names(k));
    enabled = widgets.(name).enabled;
    enabled = localReadConfigBoolean(cfg, ["dashboardWidgets", name, "enabled"], enabled);
    enabled = localReadConfigBoolean(cfg, ["dashboard", "widgets", name, "enabled"], enabled);
    enabled = localReadConfigBoolean(cfg, ["widgets", name, "enabled"], enabled);
    widgets.(name).enabled = enabled;
end

widgets.replay_contract.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "replayContract", "enabled"], widgets.replay_contract.enabled);
widgets.replay_contract.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "widgets", "replayContract", "enabled"], widgets.replay_contract.enabled);
widgets.replay_contract.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showReplayContract"], widgets.replay_contract.enabled);
widgets.replay_contract.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showReplayContract"], widgets.replay_contract.enabled);

widgets.causality_sensor_to_actuator.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "causalitySensorToActuator", "enabled"], widgets.causality_sensor_to_actuator.enabled);
widgets.causality_sensor_to_actuator.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "widgets", "causalitySensorToActuator", "enabled"], widgets.causality_sensor_to_actuator.enabled);
widgets.causality_sensor_to_actuator.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showCausalitySensorToActuator"], widgets.causality_sensor_to_actuator.enabled);
widgets.causality_sensor_to_actuator.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showCausalitySensorToActuator"], widgets.causality_sensor_to_actuator.enabled);

widgets.flight_evidence_navigator.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "flightEvidenceNavigator", "enabled"], widgets.flight_evidence_navigator.enabled);
widgets.flight_evidence_navigator.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "flight_evidence", "enabled"], widgets.flight_evidence_navigator.enabled);
widgets.flight_evidence_navigator.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showFlightEvidenceNavigator"], widgets.flight_evidence_navigator.enabled);
widgets.flight_evidence_navigator.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showFlightEvidenceNavigator"], widgets.flight_evidence_navigator.enabled);

widgets.event_timing.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "eventTiming", "enabled"], widgets.event_timing.enabled);
widgets.event_timing.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showEventTiming"], widgets.event_timing.enabled);
widgets.event_timing.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showEventTiming"], widgets.event_timing.enabled);

widgets.attitude_gravity_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "attitudeGravityProvenance", "enabled"], widgets.attitude_gravity_provenance.enabled);
widgets.attitude_gravity_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "attitude_gravity", "enabled"], widgets.attitude_gravity_provenance.enabled);
widgets.attitude_gravity_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showAttitudeGravityProvenance"], widgets.attitude_gravity_provenance.enabled);
widgets.attitude_gravity_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showAttitudeGravityProvenance"], widgets.attitude_gravity_provenance.enabled);

widgets.trajectory_wind.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "trajectoryWind", "enabled"], widgets.trajectory_wind.enabled);
widgets.trajectory_wind.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "widgets", "trajectoryWind", "enabled"], widgets.trajectory_wind.enabled);
widgets.trajectory_wind.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showTrajectoryWind"], widgets.trajectory_wind.enabled);
widgets.trajectory_wind.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showTrajectoryWind"], widgets.trajectory_wind.enabled);

widgets.telemetry_freshness_source_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "telemetryFreshnessSourceProvenance", "enabled"], widgets.telemetry_freshness_source_provenance.enabled);
widgets.telemetry_freshness_source_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["dashboardWidgets", "telemetry_freshness", "enabled"], widgets.telemetry_freshness_source_provenance.enabled);
widgets.telemetry_freshness_source_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["layout", "showTelemetryFreshnessSourceProvenance"], widgets.telemetry_freshness_source_provenance.enabled);
widgets.telemetry_freshness_source_provenance.enabled = localReadConfigBoolean(cfg, ...
    ["dashboard", "layout", "showTelemetryFreshnessSourceProvenance"], widgets.telemetry_freshness_source_provenance.enabled);
end

function value = localReadConfigBoolean(cfg, path, defaultValue)
value = defaultValue;
node = cfg;
for k = 1:numel(path)
    fieldName = char(path(k));
    if isstruct(node) && isscalar(node) && isfield(node, fieldName)
        node = node.(fieldName);
    else
        return;
    end
end

if (islogical(node) || isnumeric(node)) && isscalar(node)
    value = logical(node);
elseif isstring(node) && isscalar(node)
    value = localStringToBoolean(node, defaultValue);
elseif ischar(node)
    value = localStringToBoolean(string(node), defaultValue);
end
end

function value = localStringToBoolean(text, defaultValue)
normalized = lower(strtrim(text));
if any(normalized == ["true","on","yes","1"])
    value = true;
elseif any(normalized == ["false","off","no","0"])
    value = false;
else
    value = defaultValue;
end
end

function tf = localWidgetEnabled(widgets, name)
fieldName = char(name);
tf = isstruct(widgets) && isfield(widgets, fieldName) && ...
    isfield(widgets.(fieldName), 'enabled') && logical(widgets.(fieldName).enabled);
end

function localRenderFlightStateRegion(ax, T, replay, est3d, theme)
localPlotAltitude(ax.altitude, T, replay, est3d, theme);
localPlotVerticalVelocity(ax.velocity, T, replay, est3d, theme);
localPlotVerticalAcceleration(ax.acceleration, T, theme);
localPlotSensorHealth(ax.sensorHealth, T, theme);
end

function localRenderEstimatorRegion(ax, T, events, replay, est3d, theme) %#ok<INUSD>
vars = string(T.Properties.VariableNames);
localPlotEstimatorUncertainty(ax.estimatorUncertainty, T, est3d, theme);
localPlotGpsPosition(ax.gpsPosition, T, est3d, vars, theme);
localPlotGpsVelocity(ax.gpsVelocity, T, est3d, vars, theme);
localPlot3DTrajectory(ax.trajectory3d, T, est3d, vars, theme);
localPlotWindEstimate(ax.windEstimate, est3d, vars, theme);
localPlotWindUncertainty(ax.windUncertainty, est3d, vars, theme);
localPlotGpsFusion(ax.gpsFusion, est3d, vars, theme);
if isfield(ax, 'eventTiming')
    localPlotEventTiming(ax.eventTiming, events, theme);
end
end

function localRenderEvidenceRegion(ax, T, events, replay, cfg, est3d, flightEventIndex, auditBundle, widgets)
if localWidgetEnabled(widgets, "flight_evidence_navigator") && isfield(ax, 'flightEvidence')
    localRenderCompactWidget(ax.flightEvidence, "Flight Evidence Navigator unavailable", @() ...
        caelum.plotCompactFlightEvidenceNavigator(ax.flightEvidence, T, events, replay, cfg, ...
            EventIndex=flightEventIndex, ...
            Est3D=est3d, ...
            Title="Flight Evidence Navigator", ...
            MaxTimeBins=180));
end

if localWidgetEnabled(widgets, "replay_contract") && isfield(ax, 'replayContract')
    localRenderCompactWidget(ax.replayContract, "Replay Contract unavailable", @() ...
        caelum.plotCompactReplayContractDiff(ax.replayContract, T, replay, cfg, ...
            Title="Replay Contract / Firmware-vs-MATLAB Diff", ...
            MaxSamples=800));
end

if localWidgetEnabled(widgets, "causality_sensor_to_actuator") && isfield(ax, 'causality')
    localRenderCompactWidget(ax.causality, "Causality Snapshot unavailable", @() ...
        caelum.plotCompactCausalitySnapshot(ax.causality, T, events, replay, cfg, ...
            EventIndex=flightEventIndex, ...
            AuditBundle=auditBundle, ...
            Title="Causality: Sensor to Actuator"));
end
end

function localRenderPolicyRegion(ax, T, cfg)
if ~isfield(ax, 'phaseTimeline')
    return;
end
axes(ax.phaseTimeline);
localPlotPhaseTimeline(T);
axes(ax.policyCommand);
localPlotPolicyCommand(T);
axes(ax.policyPrediction);
localPlotPolicyPrediction(T, cfg);
axes(ax.phaseDiagnostics);
localPlotPhaseDiagnostics(T);
end

function localRenderProvenanceRegion(ax, T, cfg, est3d)
if isfield(ax, 'attitudeGravity')
    localRenderCompactWidget(ax.attitudeGravity, "Attitude / Gravity Provenance unavailable", @() ...
        caelum.plotCompactAttitudeGravityProvenance(ax.attitudeGravity, T, cfg, ...
            Title="Attitude / Gravity Provenance", ...
            MaxSamples=800));
end

if isfield(ax, 'trajectoryWind')
    localRenderCompactWidget(ax.trajectoryWind, "3D / Wind Uncertainty unavailable", @() ...
        caelum.plotCompactTrajectoryWindWidget(ax.trajectoryWind, est3d, T, ...
            MaxTubeRings=34, ...
            MaxWindVectors=16, ...
            ShowLegend=false, ...
            ShowStatus=false, ...
            PreserveMetricAspect=false, ...
            TubeAlpha=0.28, ...
            Title="3D / Wind Uncertainty Tube"));
end

if isfield(ax, 'telemetryFreshness')
    localRenderCompactWidget(ax.telemetryFreshness, "Telemetry Freshness unavailable", @() ...
        caelum.plotCompactTelemetryFreshness(ax.telemetryFreshness, T, ...
            Title="Telemetry Freshness / Source Provenance", ...
            MaxSamples=800, ...
            ShowColorbar=true));
end
end

function localRenderCompactWidget(ax, label, renderFcn)
try
    renderFcn();
catch ME
    cla(ax);
    axis(ax, [0 1 0 1]);
    axis(ax, 'off');
    detail = string(ME.message);
    if strlength(detail) > 180
        detail = extractBefore(detail, 178) + "...";
    end
    text(ax, 0.02, 0.68, label, ...
        'FontWeight', 'bold', ...
        'Interpreter', 'none', ...
        'Units', 'normalized');
    text(ax, 0.02, 0.36, detail, ...
        'FontName', 'Consolas', ...
        'FontSize', 8, ...
        'Interpreter', 'none', ...
        'Units', 'normalized');
end
end

function localRenderSummaryRegion(ax, T, events, cfg, est3d, theme)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
lines = {};
lines{end+1} = 'Mission Summary';
lines{end+1} = sprintf('Telemetry schema: %s', localTelemetrySchemaSummary(T));
lines{end+1} = sprintf('Peak KF altitude: %.3f m', max(T.kf_h, [], 'omitnan'));
lines{end+1} = sprintf('Peak baro altitude: %.3f m', max(T.bmp_alt_rel, [], 'omitnan'));
mission = localMissionProfile(cfg);
if ~isempty(fieldnames(mission))
    lines{end+1} = sprintf('IREC scoring target: %.3f m (%.0f ft AGL)', ...
        mission.targetApogee_m, mission.targetApogee_ft);
    if localMissionScoringApplicable(T, mission)
        lines{end+1} = sprintf('Peak KF altitude error to IREC target: %.3f m', ...
            max(T.kf_h, [], 'omitnan') - mission.targetApogee_m);
    else
        lines{end+1} = 'IREC scoring status: reference only for this log';
    end
end
lines{end+1} = sprintf('Launch time: %.3f s', localEventField(events, 'launchTime_s'));
lines{end+1} = sprintf('Apogee time: %.3f s', localEventField(events, 'apogeeTime_s'));
vars = string(T.Properties.VariableNames);
missingFirmwareFields = localMissingFirmwareDashboardFields(vars);
if ~isempty(missingFirmwareFields)
    lines{end+1} = sprintf('Missing firmware dashboard fields: %s', ...
        localFormatFieldList(missingFirmwareFields, 8));
end
diagnosticNotes = localDashboardAvailabilityNotes(T);
for k = 1:numel(diagnosticNotes)
    if strlength(diagnosticNotes(k)) > 0
        lines{end+1} = char("Diagnostics: " + diagnosticNotes(k));
    end
end
if ismember("phase", vars)
    lines{end+1} = sprintf('Final firmware phase: %s', localPhaseName(T.phase(end)));
end
if ismember("policy_cmd", vars)
    lines{end+1} = sprintf('Max policy command: %.3f', max(T.policy_cmd, [], 'omitnan'));
end
if ismember("apogee_error", vars)
    lines{end+1} = sprintf('Max apogee error: %.3f m', max(T.apogee_error, [], 'omitnan'));
end
if ~isempty(fieldnames(mission)) && localMissionScoringApplicable(T, mission)
    if ismember("target_apogee", vars)
        finalFirmwareTarget = localLastFinite(T.target_apogee);
        if isfinite(finalFirmwareTarget)
            lines{end+1} = sprintf('Final firmware target offset from IREC target: %.3f m', ...
                finalFirmwareTarget - mission.targetApogee_m);
        end
    end
end
if ismember("uncertainty_margin", vars)
    lines{end+1} = sprintf('Max uncertainty margin: %.3f m', max(T.uncertainty_margin, [], 'omitnan'));
end
if ismember("warn_mask", vars)
    finalWarn = localLastFinite(T.warn_mask);
    if isfinite(finalWarn)
        lines{end+1} = sprintf('Final warning mask: %u', uint32(finalWarn));
    else
        lines{end+1} = 'Final warning mask: unavailable';
    end
end
if istable(est3d) && ~isempty(est3d)
    lines{end+1} = sprintf('Final fused position: [%.2f %.2f %.2f] m', est3d.px(end), est3d.py(end), est3d.pz(end));
    lines{end+1} = sprintf('Final wind: [%.2f %.2f %.2f] m/s', est3d.wx(end), est3d.wy(end), est3d.wz(end));
    lines{end+1} = sprintf('GPS acceptance rate: %.1f%%', 100 * mean(double(est3d.gps_used), 'omitnan'));
end
lines = localClampSummaryLines(lines, 72);
localRenderSummaryColumns(ax, lines, theme);
end

function localRenderSummaryColumns(ax, lines, theme)
if isempty(lines)
    return;
end

columnCount = 3;
rowsPerColumn = ceil(numel(lines) / columnCount);
x = [0.02 0.35 0.68];
for col = 1:columnCount
    firstIdx = (col - 1) * rowsPerColumn + 1;
    lastIdx = min(col * rowsPerColumn, numel(lines));
    if firstIdx > lastIdx
        continue;
    end
    text(ax, x(col), 0.95, strjoin(lines(firstIdx:lastIdx), newline), ...
        'VerticalAlignment', 'top', ...
        'FontName', 'Consolas', ...
        'FontSize', theme.summaryFontSize, ...
        'Interpreter', 'none', ...
        'Units', 'normalized', ...
        'Clipping', 'on');
end
end

function lines = localClampSummaryLines(lines, maxChars)
for k = 1:numel(lines)
    value = string(lines{k});
    if strlength(value) > maxChars
        value = extractBefore(value, maxChars - 2) + "...";
    end
    lines{k} = char(value);
end
end

function localPlotAltitude(ax, T, replay, est3d, theme)
cla(ax);
hold(ax, 'on');
plot(ax, T.t, T.bmp_alt_rel, 'Color', theme.colors.altitudeRaw, 'DisplayName', 'baro');
plot(ax, T.t, T.kf_h, 'Color', theme.colors.altitude, 'DisplayName', 'logged KF');
if istable(replay) && ~isempty(replay)
    plot(ax, replay.t, replay.h, '--', 'Color', theme.colors.replay, 'DisplayName', 'replay');
end
if istable(est3d) && ~isempty(est3d)
    plot(ax, est3d.t, est3d.pz, ':', 'Color', theme.colors.position3d, 'DisplayName', '3D z');
end
grid(ax, 'on');
title(ax, 'Altitude');
xlabel(ax, 't [s]');
ylabel(ax, 'm');
localLegend(ax, 4, theme, "compact");
end

function localPlotVerticalVelocity(ax, T, replay, est3d, theme)
cla(ax);
hold(ax, 'on');
plot(ax, T.t, T.kf_v, 'Color', theme.colors.velocity, 'DisplayName', 'logged KF');
if istable(replay) && ~isempty(replay)
    plot(ax, replay.t, replay.v, '--', 'Color', theme.colors.replay, 'DisplayName', 'replay');
end
if istable(est3d) && ~isempty(est3d)
    plot(ax, est3d.t, est3d.vz, ':', 'Color', theme.colors.position3d, 'DisplayName', '3D v_z');
end
grid(ax, 'on');
title(ax, 'Vertical Velocity');
xlabel(ax, 't [s]');
ylabel(ax, 'm/s');
localLegend(ax, 3, theme, "compact");
end

function localPlotVerticalAcceleration(ax, T, theme)
cla(ax);
hold(ax, 'on');
plot(ax, T.t, T.a_vertical, 'Color', theme.colors.acceleration, 'DisplayName', 'a_z');
if ismember("smoothed_a_vertical", string(T.Properties.VariableNames))
    plot(ax, T.t, T.smoothed_a_vertical, 'Color', theme.colors.filtered, 'DisplayName', 'smoothed');
end
grid(ax, 'on');
title(ax, 'Vertical Acceleration');
xlabel(ax, 't [s]');
ylabel(ax, 'm/s^2');
localLegend(ax, 2, theme, "auto");
end

function localPlotSensorHealth(ax, T, theme)
cla(ax);
hold(ax, 'on');
plot(ax, T.t, T.acc_norm, 'Color', theme.colors.acceleration, 'DisplayName', '|acc|');
plot(ax, T.t, T.gyro_norm, 'Color', theme.colors.gyro, 'DisplayName', '|gyro|');
if ismember("g_norm", string(T.Properties.VariableNames))
    plot(ax, T.t, T.g_norm, 'Color', theme.colors.gravity, 'DisplayName', '|g_hat|');
end
grid(ax, 'on');
title(ax, 'Sensor Health');
xlabel(ax, 't [s]');
localLegend(ax, 3, theme, "compact");
end

function localPlotEstimatorUncertainty(ax, T, est3d, theme)
cla(ax);
hold(ax, 'on');
plot(ax, T.t, T.kf_sigma_h, 'Color', theme.colors.covariance, 'DisplayName', 'sigma_h');
plot(ax, T.t, T.kf_sigma_v, 'Color', theme.colors.velocity, 'DisplayName', 'sigma_v');
if istable(est3d) && ~isempty(est3d)
    plot(ax, est3d.t, est3d.sigma_pz, '--', 'Color', theme.colors.position3d, 'DisplayName', 'sigma_pz');
    plot(ax, est3d.t, est3d.sigma_vz, '--', 'Color', theme.colors.wind, 'DisplayName', 'sigma_vz');
end
grid(ax, 'on');
title(ax, 'Estimator Uncertainty');
xlabel(ax, 't [s]');
localLegend(ax, 4, theme, "compact");
end

function localPlotGpsPosition(ax, T, est3d, vars, theme)
cla(ax);
hasGpsPos = all(ismember(["gps_x","gps_y","gps_z"], vars));
if hasGpsPos
    hold(ax, 'on');
    plot(ax, T.t, T.gps_x, 'Color', theme.colors.gpsX, 'DisplayName', 'gps_x');
    plot(ax, T.t, T.gps_y, 'Color', theme.colors.gpsY, 'DisplayName', 'gps_y');
    plot(ax, T.t, T.gps_z, 'Color', theme.colors.gpsZ, 'DisplayName', 'gps_z');
    if istable(est3d) && ~isempty(est3d)
        plot(ax, est3d.t, est3d.px, '--', 'Color', theme.colors.gpsX, 'DisplayName', 'ekf_x');
        plot(ax, est3d.t, est3d.py, '--', 'Color', theme.colors.gpsY, 'DisplayName', 'ekf_y');
        plot(ax, est3d.t, est3d.pz, '--', 'Color', theme.colors.gpsZ, 'DisplayName', 'ekf_z');
    end
    grid(ax, 'on');
    localLegend(ax, 3, theme, "compact");
else
    localShowUnavailable(ax, 'GPS position unavailable', ["gps_x","gps_y","gps_z"], vars);
end
title(ax, 'GPS / 3D Position');
end

function localPlotGpsVelocity(ax, T, est3d, vars, theme)
cla(ax);
hasGpsVel = all(ismember(["gps_vx","gps_vy","gps_vz"], vars));
if hasGpsVel
    hold(ax, 'on');
    plot(ax, T.t, T.gps_vx, 'Color', theme.colors.gpsX, 'DisplayName', 'gps_vx');
    plot(ax, T.t, T.gps_vy, 'Color', theme.colors.gpsY, 'DisplayName', 'gps_vy');
    plot(ax, T.t, T.gps_vz, 'Color', theme.colors.gpsZ, 'DisplayName', 'gps_vz');
    if istable(est3d) && ~isempty(est3d)
        plot(ax, est3d.t, est3d.vx + est3d.wx, '--', 'Color', theme.colors.gpsX, 'DisplayName', 'fused_x');
        plot(ax, est3d.t, est3d.vy + est3d.wy, '--', 'Color', theme.colors.gpsY, 'DisplayName', 'fused_y');
        plot(ax, est3d.t, est3d.vz + est3d.wz, '--', 'Color', theme.colors.gpsZ, 'DisplayName', 'fused_z');
    end
    grid(ax, 'on');
    localLegend(ax, 3, theme, "compact");
else
    localShowUnavailable(ax, 'GPS velocity unavailable', ["gps_vx","gps_vy","gps_vz"], vars);
end
title(ax, 'GPS / Ground Velocity');
end

function localPlot3DTrajectory(ax, T, est3d, vars, theme)
cla(ax);
hasGpsPos = all(ismember(["gps_x","gps_y","gps_z"], vars));
if istable(est3d) && ~isempty(est3d)
    hold(ax, 'on');
    plot3(ax, est3d.px, est3d.py, est3d.pz, 'Color', theme.colors.position3d, 'DisplayName', '3D EKF');
    if hasGpsPos
        plot3(ax, T.gps_x, T.gps_y, T.gps_z, '--', 'Color', theme.colors.gps, 'DisplayName', 'GPS');
    end
    grid(ax, 'on');
    axis(ax, 'equal');
    view(ax, 3);
    xlabel(ax, 'x');
    ylabel(ax, 'y');
    zlabel(ax, 'z');
    localLegend(ax, 2, theme, "auto");
else
    localShowUnavailable(ax, '3D state unavailable', ["gps_x","gps_y","gps_z","q_w","q_x","q_y","q_z"], vars);
end
title(ax, '3D Trajectory');
end

function localPlotWindEstimate(ax, est3d, vars, theme)
cla(ax);
if istable(est3d) && ~isempty(est3d)
    hold(ax, 'on');
    plot(ax, est3d.t, est3d.wx, 'Color', theme.colors.gpsX, 'DisplayName', 'w_x');
    plot(ax, est3d.t, est3d.wy, 'Color', theme.colors.gpsY, 'DisplayName', 'w_y');
    plot(ax, est3d.t, est3d.wz, 'Color', theme.colors.gpsZ, 'DisplayName', 'w_z');
    grid(ax, 'on');
    localLegend(ax, 3, theme, "compact");
else
    localShowUnavailable(ax, 'Wind estimate unavailable', ["gps_x","gps_y","gps_z"], vars);
end
title(ax, 'Wind Estimate');
end

function localPlotWindUncertainty(ax, est3d, vars, theme)
cla(ax);
if istable(est3d) && ~isempty(est3d)
    hold(ax, 'on');
    plot(ax, est3d.t, est3d.sigma_px, 'Color', theme.colors.gpsX, 'DisplayName', 'sig_px');
    plot(ax, est3d.t, est3d.sigma_py, 'Color', theme.colors.gpsY, 'DisplayName', 'sig_py');
    plot(ax, est3d.t, est3d.sigma_pz, 'Color', theme.colors.gpsZ, 'DisplayName', 'sig_pz');
    plot(ax, est3d.t, est3d.sigma_wx, '--', 'Color', theme.colors.gpsX, 'DisplayName', 'sig_wx');
    plot(ax, est3d.t, est3d.sigma_wy, '--', 'Color', theme.colors.gpsY, 'DisplayName', 'sig_wy');
    plot(ax, est3d.t, est3d.sigma_wz, '--', 'Color', theme.colors.gpsZ, 'DisplayName', 'sig_wz');
    grid(ax, 'on');
    localLegend(ax, 3, theme, "compact");
else
    localShowUnavailable(ax, '3D uncertainties unavailable', ["gps_x","gps_y","gps_z"], vars);
end
title(ax, '3D / Wind Uncertainty');
end

function localPlotGpsFusion(ax, est3d, vars, theme)
cla(ax);
if istable(est3d) && ~isempty(est3d)
    hold(ax, 'on');
    stairs(ax, est3d.t, double(est3d.gps_used), 'Color', theme.colors.accepted, 'DisplayName', 'gps used');
    stairs(ax, est3d.t, double(est3d.gps_rejected), 'Color', theme.colors.rejected, 'DisplayName', 'gps rejected');
    plot(ax, est3d.t, est3d.innovation_pos_norm, 'Color', theme.colors.covariance, 'DisplayName', 'pos innov');
    plot(ax, est3d.t, est3d.innovation_vel_norm, 'Color', theme.colors.wind, 'DisplayName', 'vel innov');
    grid(ax, 'on');
    localLegend(ax, 4, theme, "compact");
else
    localShowUnavailable(ax, 'GPS fusion metrics unavailable', ["gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"], vars);
end
title(ax, 'GPS Fusion Health');
end

function localPlotEventTiming(ax, events, theme)
cla(ax);
eventLabels = {'Launch','Burnout','Apogee','Landing'};
eventTimes = [ ...
    localEventField(events, 'launchTime_s'), ...
    localEventField(events, 'burnoutTime_s'), ...
    localEventField(events, 'apogeeTime_s'), ...
    localEventField(events, 'landingTime_s')];
bar(ax, categorical(eventLabels, eventLabels, 'Ordinal', true), eventTimes, ...
    'FaceColor', theme.colors.event);
title(ax, 'Event Timing [s]');
ylabel(ax, 's');
grid(ax, 'on');
end

function value = localEventField(events, fieldName)
if isstruct(events) && isfield(events, fieldName) && isfinite(events.(fieldName))
    value = events.(fieldName);
else
    value = NaN;
end
end

function localPlotPhaseTimeline(T)
vars = string(T.Properties.VariableNames);
if ismember("phase", vars) && any(isfinite(T.phase))
    stairs(T.t, T.phase, 'LineWidth', 1.2, 'DisplayName', 'phase');
    ylim([-0.5 4.5]);
    yticks(0:4);
    yticklabels({'IDLE','BOOST','COAST','BRAKE','DESCENT'});
    xlabel('t'); grid on;
    title('Firmware Flight Phase');
else
    localShowUnavailable(gca, 'Firmware phase unavailable', "phase", vars);
end
end

function localPlotPolicyCommand(T)
vars = string(T.Properties.VariableNames);
hasPolicy = ismember("policy_cmd", vars) && any(isfinite(T.policy_cmd));
hasActuator = ismember("actuator_us", vars) && any(isfinite(T.actuator_us));

if hasPolicy || hasActuator
    if hasPolicy
        yyaxis left;
        stairs(T.t, T.policy_cmd, 'LineWidth', 1.2, 'DisplayName', 'policy cmd');
        hold on;
        if ismember("policy_valid", vars)
            stairs(T.t, double(T.policy_valid > 0.5), '--', 'DisplayName', 'policy valid');
        end
        ylabel('normalized');
        ylim([-0.05 1.05]);
    end
    if hasActuator
        yyaxis right;
        plot(T.t, T.actuator_us, 'DisplayName', 'actuator us');
        ylabel('us');
    end
    xlabel('t'); grid on;
    localLegend(gca, 3, localDashboardTheme(), "compact");
    title('Policy Command / Actuator');
else
    localShowUnavailable(gca, 'Policy command unavailable', ["policy_cmd","actuator_us"], vars);
end
end

function localPlotPolicyPrediction(T, cfg)
vars = string(T.Properties.VariableNames);
predictionFields = ["apogee_no_brake","apogee_full_brake","target_apogee"];
hasPrediction = any(ismember(predictionFields, vars));

if hasPrediction
    hold on;
    if ismember("apogee_no_brake", vars)
        plot(T.t, T.apogee_no_brake, 'DisplayName', 'no brake');
    end
    if ismember("apogee_full_brake", vars)
        plot(T.t, T.apogee_full_brake, 'DisplayName', 'full brake');
    end
    if ismember("target_apogee", vars)
        plot(T.t, T.target_apogee, '--', 'DisplayName', 'target');
    end
    if ismember("target_nominal", vars)
        plot(T.t, T.target_nominal, ':', 'DisplayName', 'target nominal');
    end
    if ismember("target_effective", vars)
        plot(T.t, T.target_effective, '-.', 'DisplayName', 'target effective');
    end
    mission = localMissionProfile(cfg);
    if ~isempty(fieldnames(mission))
        localPlotMissionTargetReference(gca, T, mission);
    end
    if ismember("apogee_error", vars)
        yyaxis right;
        plot(T.t, T.apogee_error, ':', 'DisplayName', 'error');
        if ismember("uncertainty_margin", vars)
            plot(T.t, T.uncertainty_margin, '-.', 'DisplayName', 'uncertainty margin');
        end
        ylabel('error [m]');
        yyaxis left;
    elseif ismember("uncertainty_margin", vars)
        yyaxis right;
        plot(T.t, T.uncertainty_margin, '-.', 'DisplayName', 'uncertainty margin');
        ylabel('margin [m]');
        yyaxis left;
    end
    xlabel('t'); ylabel('apogee [m]');
    grid on;
    localLegend(gca, 4, localDashboardTheme(), "compact");
    title('Apogee Policy Prediction');
else
    localShowUnavailable(gca, 'Apogee policy unavailable', predictionFields, vars);
end
end

function localPlotPhaseDiagnostics(T)
vars = string(T.Properties.VariableNames);
diagFields = [ ...
    "phase_launch_latched", ...
    "phase_burnout_latched", ...
    "phase_descent_latched", ...
    "phase_launch_candidate", ...
    "phase_burnout_candidate", ...
    "phase_descent_candidate", ...
    "phase_brake_active"];
present = diagFields(ismember(diagFields, vars));

if ~isempty(present)
    hold on;
    for k = 1:numel(present)
        name = present(k);
        stairs(T.t, double(T.(char(name)) > 0.5), 'DisplayName', erase(name, "phase_"));
    end
    ylim([-0.05 1.05]);
    xlabel('t'); ylabel('flag');
    grid on;
    localLegend(gca, 4, localDashboardTheme(), "compact");
    title('Phase Diagnostic Flags');
elseif ismember("warn_mask", vars)
    stairs(T.t, T.warn_mask, 'DisplayName', 'warn mask');
    xlabel('t'); ylabel('mask');
    grid on;
    localLegend(gca, 1, localDashboardTheme(), "auto");
    title('Warning Mask');
else
    localShowUnavailable(gca, 'Phase diagnostics unavailable', diagFields, vars);
end
end

function theme = localDashboardTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.titleFontSize = 13;
theme.axesFontSize = 8;
theme.legendFontSize = 7;
theme.summaryFontSize = 8;
theme.colors.altitudeRaw = [0.35 0.70 1.00];
theme.colors.altitude = [0.10 0.55 0.90];
theme.colors.velocity = [1.00 0.50 0.10];
theme.colors.acceleration = [0.95 0.78 0.20];
theme.colors.filtered = [0.95 0.45 0.12];
theme.colors.gyro = [0.90 0.35 0.25];
theme.colors.gravity = [0.95 0.85 0.25];
theme.colors.replay = [0.95 0.85 0.25];
theme.colors.position3d = [0.25 0.75 1.00];
theme.colors.gps = [0.20 0.80 0.35];
theme.colors.gpsX = [0.10 0.55 0.90];
theme.colors.gpsY = [1.00 0.50 0.10];
theme.colors.gpsZ = [0.95 0.85 0.25];
theme.colors.covariance = [0.68 0.38 0.95];
theme.colors.wind = [0.10 0.80 0.90];
theme.colors.accepted = [0.20 0.70 0.35];
theme.colors.rejected = [0.95 0.55 0.15];
theme.colors.warning = [0.90 0.25 0.20];
theme.colors.missing = [0.45 0.45 0.45];
theme.colors.event = [0.20 0.55 0.85];
end

function localApplyDashboardStyle(fig, theme)
axesHandles = findall(fig, 'Type', 'axes');
for k = 1:numel(axesHandles)
    ax = axesHandles(k);
    set(ax, ...
        'Color', theme.axesColor, ...
        'XColor', theme.textColor, ...
        'YColor', theme.textColor, ...
        'ZColor', theme.textColor, ...
        'GridColor', theme.gridColor, ...
        'MinorGridColor', theme.gridColor, ...
        'FontSize', theme.axesFontSize, ...
        'LineWidth', 0.8);
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

colorbarHandles = findall(fig, 'Type', 'ColorBar');
extraColorbarHandles = findall(fig, 'Type', 'colorbar');
colorbarHandles = [colorbarHandles(:); extraColorbarHandles(:)];
for k = 1:numel(colorbarHandles)
    try
        set(colorbarHandles(k), ...
            'Color', theme.textColor, ...
            'FontSize', theme.legendFontSize);
    catch
    end
end
end

function lgd = localLegend(ax, maxColumns, theme, mode)
if nargin < 4 || strlength(string(mode)) == 0
    mode = "auto";
else
    mode = string(mode);
end

lgd = gobjects(0);
try
    lgd = legend(ax, 'show');
    if isempty(lgd) || ~isvalid(lgd) || isempty(lgd.String)
        if ~isempty(lgd) && isvalid(lgd)
            delete(lgd);
        end
        return;
    end
    legendLabels = string(lgd.String);
    nItems = numel(legendLabels);
    collapseLegend = (mode == "compact") || (mode == "auto" && nItems > maxColumns);
    if collapseLegend
        lgd.Location = 'northeast';
        lgd.Orientation = 'vertical';
        if isprop(lgd, 'NumColumns')
            lgd.NumColumns = 1;
        end
        if isprop(lgd, 'ItemTokenSize')
            lgd.ItemTokenSize = [8 6];
        end
        lgd.FontSize = max(6, theme.legendFontSize - 1);
    else
        lgd.Location = 'northoutside';
        lgd.Orientation = 'horizontal';
        if isprop(lgd, 'NumColumns')
            lgd.NumColumns = min(maxColumns, max(1, nItems));
        end
        lgd.FontSize = theme.legendFontSize;
    end
    if isprop(lgd, 'NumColumns')
        currentColumns = lgd.NumColumns;
        if isempty(currentColumns)
            currentColumns = 1;
        end
        lgd.NumColumns = max(1, currentColumns);
    end
    lgd.Interpreter = 'none';
    lgd.Color = theme.axesColor;
    lgd.TextColor = theme.textColor;
    lgd.EdgeColor = theme.panelEdgeColor;
catch
end
end

function localShowUnavailable(ax, label, expectedFields, actualFields)
missing = setdiff(string(expectedFields), string(actualFields), 'stable');
if isempty(missing)
    detail = "Required columns are present, but no finite samples are available.";
else
    detail = sprintf('Missing %d fields:\n%s', numel(missing), localFormatFieldList(missing, 2));
end

cla(ax);
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.04, 0.68, label, ...
    'FontWeight', 'bold', ...
    'Interpreter', 'none', ...
    'Units', 'normalized');
text(ax, 0.04, 0.42, detail, ...
    'FontName', 'Consolas', ...
    'FontSize', 8, ...
    'Interpreter', 'none', ...
    'VerticalAlignment', 'top', ...
        'Units', 'normalized');
end

function notes = localDashboardAvailabilityNotes(T)
vars = string(T.Properties.VariableNames);
items = strings(0, 1);

items(end+1, 1) = localAvailabilityNote("phase", "phase", vars);
items(end+1, 1) = localAvailabilityNote("policy", ["policy_cmd","actuator_us"], vars);
items(end+1, 1) = localAvailabilityNote("apogee policy", ...
    ["apogee_no_brake","apogee_full_brake","target_apogee"], vars);
items(end+1, 1) = localAvailabilityNote("phase diag", ...
    ["phase_launch_latched","phase_burnout_latched","phase_descent_latched", ...
     "phase_launch_candidate","phase_burnout_candidate","phase_descent_candidate", ...
     "phase_brake_active"], vars);

notes = items;
end

function note = localAvailabilityNote(label, expectedFields, actualFields)
missing = setdiff(string(expectedFields), string(actualFields), 'stable');
if isempty(missing)
    note = label + " available";
else
    note = label + " missing " + string(localFormatFieldList(missing, 3));
end
end

function summary = localTelemetrySchemaSummary(T)
vars = string(T.Properties.VariableNames);
firmwareFields = ["phase","policy_cmd","actuator_us","phase_diag_valid","warn_mask"];
hasFirmwareFields = ismember(firmwareFields, vars);

if all(hasFirmwareFields)
    summary = 'latest firmware telemetry';
elseif any(hasFirmwareFields)
    summary = 'partial firmware telemetry';
else
    summary = 'legacy sensor/estimator log';
end
end

function missing = localMissingFirmwareDashboardFields(vars)
firmwareDashboardFields = [ ...
    "phase", ...
    "policy_valid", ...
    "policy_cmd", ...
    "actuator_us", ...
    "apogee_no_brake", ...
    "apogee_full_brake", ...
    "target_apogee", ...
    "warn_mask", ...
    "phase_diag_valid", ...
    "phase_launch_latched", ...
    "phase_burnout_latched", ...
    "phase_descent_latched"];
missing = setdiff(firmwareDashboardFields, string(vars), 'stable');
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

function localPlotMissionTargetReference(ax, T, mission)
target_m = mission.targetApogee_m;
if ~isfinite(target_m)
    return;
end

fields = [ ...
    "apogee_no_brake", ...
    "apogee_full_brake", ...
    "target_apogee", ...
    "target_nominal", ...
    "target_effective"];
values = [];
vars = string(T.Properties.VariableNames);
for k = 1:numel(fields)
    name = fields(k);
    if ismember(name, vars)
        values = [values; T.(char(name))(:)]; %#ok<AGROW>
    end
end
values = values(isfinite(values));
if isempty(values)
    return;
end

span = max(values) - min(values);
if ~isfinite(span) || span <= 0
    span = max(1.0, abs(target_m) * 0.05);
end

% Do not let a 10,000 ft scoring reference collapse low-altitude synthetic
% check plots. The summary always reports the mission target.
if target_m < min(values) - 0.10 * span || target_m > max(values) + 0.50 * span
    return;
end

yline(ax, target_m, '--', ...
    'DisplayName', sprintf('IREC %.0f ft target', mission.targetApogee_ft), ...
    'Color', [0.20 0.70 0.90], ...
    'LineWidth', 1.0);
end

function tf = localMissionScoringApplicable(T, mission)
target_m = mission.targetApogee_m;
if ~isfinite(target_m) || target_m <= 0
    tf = false;
    return;
end

vars = string(T.Properties.VariableNames);
values = [];
altitudeFields = ["kf_h","bmp_alt_rel","apogee_no_brake","apogee_full_brake"];
for k = 1:numel(altitudeFields)
    name = altitudeFields(k);
    if ismember(name, vars)
        values = [values; T.(char(name))(:)]; %#ok<AGROW>
    end
end

peakRelevantAltitude = max(values, [], 'omitnan');
if isempty(peakRelevantAltitude) || ~isfinite(peakRelevantAltitude)
    peakRelevantAltitude = NaN;
end

hasCompetitionScaleAltitude = isfinite(peakRelevantAltitude) && peakRelevantAltitude >= 0.50 * target_m;
hasMatchingFirmwareTarget = false;
targetFields = ["target_apogee","target_nominal","target_effective"];
for k = 1:numel(targetFields)
    name = targetFields(k);
    if ismember(name, vars)
        finalTarget = localLastFinite(T.(char(name)));
        hasMatchingFirmwareTarget = hasMatchingFirmwareTarget || ...
            (isfinite(finalTarget) && abs(finalTarget - target_m) <= 0.10 * target_m);
    end
end

tf = hasCompetitionScaleAltitude || hasMatchingFirmwareTarget;
end

function textOut = localFormatFieldList(fields, maxFields)
fields = string(fields(:)).';
if isempty(fields)
    textOut = 'none';
    return;
end

if numel(fields) > maxFields
    shown = fields(1:maxFields);
    textOut = sprintf('%s, +%d more', strjoin(cellstr(shown), ', '), numel(fields) - maxFields);
else
    textOut = strjoin(cellstr(fields), ', ');
end
end

function name = localPhaseName(value)
if ~isfinite(value)
    name = 'UNKNOWN';
    return;
end

switch round(value)
    case 0
        name = 'IDLE';
    case 1
        name = 'BOOST';
    case 2
        name = 'COAST';
    case 3
        name = 'BRAKE';
    case 4
        name = 'DESCENT';
    otherwise
        name = 'UNKNOWN';
end
end

function value = localLastFinite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
end

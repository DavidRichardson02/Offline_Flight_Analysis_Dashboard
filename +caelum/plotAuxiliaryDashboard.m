function fig = plotAuxiliaryDashboard(T, events, replay, cfg, options)
%PLOTAUXILIARYDASHBOARD Create secondary reference widgets omitted from the main dashboard.
%
% This figure is intentionally separate from plotDashboard: it keeps the
% release-facing dashboard readable while preserving drill-down evidence for
% replay contract, causality, provenance, telemetry freshness, and 3D/wind
% review.
arguments
    T table
    events struct = struct()
    replay = table()
    cfg struct = struct()
    options.Est3D table = table()
end

defaultCfg = caelum.defaultConfig();
if isempty(fieldnames(cfg))
    cfg = defaultCfg;
elseif ~isfield(cfg, 'mission') || isempty(cfg.mission)
    cfg.mission = defaultCfg.mission;
end
try
    cfg = caelum.localResolve3DConfig(cfg);
catch
end

theme = localAuxiliaryDashboardTheme();
est3d = options.Est3D;
if isempty(est3d)
    est3d = localBuild3DStateIfAvailable(T, cfg);
end

flightEventIndex = table();
auditBundle = struct();
try
    [flightEventIndex, auditBundle] = caelum.buildFlightEvidenceIndex(T, events, replay, cfg, ...
        Est3D=est3d);
catch
end
trajectoryWindAudit = localBuildTrajectoryWindAudit(est3d, T, auditBundle);

fig = figure('Name', 'Caelum Auxiliary Dashboard Reference', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.05 0.06 0.90 0.86], ...
    'Visible', 'on', ...
    'WindowStyle', 'normal');

tl = tiledlayout(fig, 10, 4, ...
    'TileSpacing', 'loose', ...
    'Padding', 'compact');
hTitle = title(tl, 'Caelum Auxiliary Dashboard Reference');
hTitle.Color = theme.textColor;
hTitle.FontSize = theme.titleFontSize;
hTitle.FontWeight = 'bold';

ax = struct();
localRenderTrajectoryWindTube(tl, 1, [5 4], trajectoryWindAudit);

ax.flightEvidence = nexttile(tl, 21, [1 2]);
ax.eventTiming = nexttile(tl, 23, [1 2]);
ax.replayContract = nexttile(tl, 25, [1 4]);
ax.causality = nexttile(tl, 29, [1 4]);
ax.attitudeGravity = nexttile(tl, 33, [1 2]);
ax.telemetryFreshness = nexttile(tl, 35, [1 2]);
ax.summary = nexttile(tl, 37, [1 4]);

localRenderCompactWidget(ax.flightEvidence, "Flight Evidence Navigator unavailable", @() ...
    caelum.plotCompactFlightEvidenceNavigator(ax.flightEvidence, T, events, replay, cfg, ...
        EventIndex=flightEventIndex, ...
        Est3D=est3d, ...
        MaxTimeBins=220, ...
        IncludeNominal=true, ...
        Title="Flight Evidence Navigator"));

localPlotEventTiming(ax.eventTiming, events, theme);

localRenderCompactWidget(ax.replayContract, "Replay Contract unavailable", @() ...
    caelum.plotCompactReplayContractDiff(ax.replayContract, T, replay, cfg, ...
        MaxSamples=1000, ...
        Title="Replay Contract / Firmware-vs-MATLAB Diff"));

localRenderCompactWidget(ax.causality, "Causality Snapshot unavailable", @() ...
    caelum.plotCompactCausalitySnapshot(ax.causality, T, events, replay, cfg, ...
        EventIndex=flightEventIndex, ...
        AuditBundle=auditBundle, ...
        Selector="dashboard", ...
        Title="Causality: Sensor to Actuator"));

localRenderCompactWidget(ax.attitudeGravity, "Attitude / Gravity Provenance unavailable", @() ...
    caelum.plotCompactAttitudeGravityProvenance(ax.attitudeGravity, T, cfg, ...
        MaxSamples=1000, ...
        Title="Attitude / Gravity Provenance"));

localRenderCompactWidget(ax.telemetryFreshness, "Telemetry Freshness unavailable", @() ...
    caelum.plotCompactTelemetryFreshness(ax.telemetryFreshness, T, ...
        MaxSamples=1000, ...
        ShowColorbar=true, ...
        Title="Telemetry Freshness / Source Provenance"));

localPlotAuxiliarySummary(ax.summary, T, replay, est3d, flightEventIndex, theme);
localApplyAuxiliaryDashboardStyle(fig, theme);
end

function est3d = localBuild3DStateIfAvailable(T, cfg)
est3d = table();
if isempty(T) || ~istable(T) || height(T) < 1
    return;
end

vars = string(T.Properties.VariableNames);
hasGps = all(ismember(["gps_x","gps_y","gps_z"], vars)) || ...
    all(ismember(["gps_vx","gps_vy","gps_vz"], vars));
if ~hasGps || ~(isfield(cfg, 'enable3DReplay') && cfg.enable3DReplay)
    return;
end

try
    work = T;
    if ~all(ismember(["q_w","q_x","q_y","q_z"], vars))
        attitude = caelum.runAttitudeReplay(work, cfg);
        work.q_w = interp1(attitude.t, attitude.q_w, work.t, 'linear', 1);
        work.q_x = interp1(attitude.t, attitude.q_x, work.t, 'linear', 0);
        work.q_y = interp1(attitude.t, attitude.q_y, work.t, 'linear', 0);
        work.q_z = interp1(attitude.t, attitude.q_z, work.t, 'linear', 0);
    end
    est3d = caelum.run3DEKF(work, cfg);
catch
    est3d = table();
end
end

function audit = localBuildTrajectoryWindAudit(est3d, T, auditBundle)
audit = table();
if isstruct(auditBundle) && isfield(auditBundle, 'trajectoryWind') && ...
        istable(auditBundle.trajectoryWind) && ~isempty(auditBundle.trajectoryWind)
    audit = auditBundle.trajectoryWind;
    return;
end

if isempty(est3d) || ~istable(est3d) || height(est3d) < 1
    return;
end

try
    audit = caelum.build3DTrajectoryWindAudit(est3d, T);
catch
    audit = table();
end
end

function localRenderTrajectoryWindTube(parentLayout, tile, tileSpan, audit)
try
    caelum.plot3DTrajectoryWindUncertaintyTube(audit, ...
        Parent=parentLayout, ...
        LayoutTile=tile, ...
        LayoutTileSpan=tileSpan, ...
        ShowTitle=true);
catch ME
    ax = nexttile(parentLayout, tile, tileSpan);
    identifier = string(ME.identifier);
    if strlength(identifier) == 0
        identifier = "caelum:plotAuxiliaryDashboard:TrajectoryWindTubeUnavailable";
    end
    localRenderCompactWidget(ax, "3D / Wind Uncertainty Tube unavailable", @() error(char(identifier), '%s', ME.message));
end
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

function localPlotAuxiliarySummary(ax, T, replay, est3d, eventIndex, theme)
cla(ax);
axis(ax, [0 1 0 1]);
axis(ax, 'off');

lines = strings(0, 1);
lines(end+1, 1) = "Auxiliary Reference Summary";
lines(end+1, 1) = "Main dashboard omits replay-contract and sensor-to-actuator causality strips by default.";
if istable(T) && ~isempty(T)
    lines(end+1, 1) = sprintf('Telemetry rows: %d | duration: %.3f s', height(T), max(T.t, [], 'omitnan') - min(T.t, [], 'omitnan'));
end
if istable(replay) && ~isempty(replay)
    lines(end+1, 1) = sprintf('Replay rows: %d', height(replay));
else
    lines(end+1, 1) = "Replay rows: unavailable";
end
if istable(est3d) && ~isempty(est3d)
    gpsUsed = NaN;
    if ismember("gps_used", string(est3d.Properties.VariableNames))
        gpsUsed = sum(double(est3d.gps_used), 'omitnan');
    end
    lines(end+1, 1) = sprintf('3D rows: %d | GPS used samples: %.0f', height(est3d), gpsUsed);
else
    lines(end+1, 1) = "3D/wind state: unavailable";
end
if istable(eventIndex) && ~isempty(eventIndex)
    if ismember("severity", string(eventIndex.Properties.VariableNames))
        severity = string(eventIndex.severity);
        lines(end+1, 1) = sprintf('Evidence events: %d | critical=%d warning=%d notice=%d', ...
            height(eventIndex), nnz(severity == "critical"), nnz(severity == "warning"), nnz(severity == "notice"));
    else
        lines(end+1, 1) = sprintf('Evidence events: %d', height(eventIndex));
    end
else
    lines(end+1, 1) = "Evidence index: unavailable";
end

text(ax, 0.02, 0.94, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'FontSize', theme.summaryFontSize, ...
    'Color', theme.textColor, ...
    'Interpreter', 'none', ...
    'Units', 'normalized');
end

function localRenderCompactWidget(ax, label, renderFcn)
try
    renderFcn();
catch ME
    theme = localAuxiliaryDashboardTheme();
    cla(ax);
    axis(ax, [0 1 0 1]);
    axis(ax, 'off');
    detail = string(ME.message);
    if strlength(detail) > 180
        detail = extractBefore(detail, 178) + "...";
    end
    text(ax, 0.02, 0.68, label, ...
        'FontWeight', 'bold', ...
        'Color', theme.textColor, ...
        'Interpreter', 'none', ...
        'Units', 'normalized');
    text(ax, 0.02, 0.36, detail, ...
        'FontName', 'Consolas', ...
        'FontSize', 8, ...
        'Color', theme.textColor, ...
        'Interpreter', 'none', ...
        'Units', 'normalized');
end
end

function localApplyAuxiliaryDashboardStyle(fig, theme)
axesHandles = findall(fig, 'Type', 'Axes');
for k = 1:numel(axesHandles)
    ax = axesHandles(k);
    try
        set(ax, ...
            'Color', theme.axesColor, ...
            'XColor', theme.textColor, ...
            'YColor', theme.textColor, ...
            'ZColor', theme.textColor, ...
            'GridColor', theme.gridColor, ...
            'MinorGridColor', theme.gridColor, ...
            'FontSize', theme.axesFontSize, ...
            'Box', 'on');
        title(ax, get(get(ax, 'Title'), 'String'), 'Color', theme.textColor, 'FontWeight', 'bold');
        xlabel(ax, get(get(ax, 'XLabel'), 'String'), 'Color', theme.textColor);
        ylabel(ax, get(get(ax, 'YLabel'), 'String'), 'Color', theme.textColor);
        zlabel(ax, get(get(ax, 'ZLabel'), 'String'), 'Color', theme.textColor);
    catch
    end
end

legendHandles = findall(fig, 'Type', 'Legend');
for k = 1:numel(legendHandles)
    try
        set(legendHandles(k), ...
            'Color', theme.axesColor, ...
            'TextColor', theme.textColor, ...
            'EdgeColor', theme.panelEdgeColor, ...
            'FontSize', theme.legendFontSize);
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

function theme = localAuxiliaryDashboardTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.titleFontSize = 13;
theme.axesFontSize = 8;
theme.legendFontSize = 7;
theme.summaryFontSize = 8;
theme.colors.event = [0.20 0.55 0.85];
end

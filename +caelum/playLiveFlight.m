function playback = playLiveFlight(source, options)
%PLAYLIVEFLIGHT Replay a flight log through a live-style dashboard.
%
% This is the first implementation step toward a true live dashboard.  It uses
% the same normalized data contract as the offline analysis pipeline, then
% advances a time cursor through position, phase, and policy telemetry.  A future
% serial source can feed the same plotting contract without changing the review
% surface.
arguments
    source = []
    options.Config struct = caelum.defaultConfig()
    options.PlaybackRate (1,1) double = 1.0
    options.MaxFrameRate (1,1) double = 20.0
    options.StartTime_s (1,1) double = NaN
    options.EndTime_s (1,1) double = NaN
    options.PositionSource (1,1) string = "auto"
    options.Run3DReplay (1,1) logical = true
end

if options.PlaybackRate <= 0 || ~isfinite(options.PlaybackRate)
    error('caelum:playLiveFlight:InvalidPlaybackRate', ...
        'PlaybackRate must be a finite positive scalar.');
end

if options.MaxFrameRate <= 0 || ~isfinite(options.MaxFrameRate)
    error('caelum:playLiveFlight:InvalidMaxFrameRate', ...
        'MaxFrameRate must be a finite positive scalar.');
end

cfg = caelum.localResolve3DConfig(options.Config);
[T, est3d, sourceInfo] = localPrepareSource(source, cfg, options.Run3DReplay);

if isempty(T) || height(T) < 1
    error('caelum:playLiveFlight:EmptyData', ...
        'No playback rows are available after import and cleaning.');
end

timeMask = true(height(T), 1);
if isfinite(options.StartTime_s)
    timeMask = timeMask & (T.t >= options.StartTime_s);
end
if isfinite(options.EndTime_s)
    timeMask = timeMask & (T.t <= options.EndTime_s);
end
T = T(timeMask, :);

if isempty(T)
    error('caelum:playLiveFlight:EmptyTimeWindow', ...
        'No rows remain inside the requested playback time window.');
end

[px, py, pz, positionSource] = localResolvePosition(T, est3d, options.PositionSource);

theme = localPlaybackTheme();
fig = figure('Name', 'Caelum Live-Style Flight Playback', 'Color', theme.figureColor, ...
    'Units', 'normalized', 'Position', [0.05 0.08 0.90 0.82]);
tl = tiledlayout(fig, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, sprintf('Caelum Flight Playback - %s position', char(positionSource)));
hTitle.Color = theme.textColor;

axTrajectory = nexttile(tl, [2 2]);
plot3(axTrajectory, px, py, pz, 'Color', [0.72 0.72 0.72], 'DisplayName', 'full path');
hold(axTrajectory, 'on');
hTrail = animatedline(axTrajectory, 'LineWidth', 1.6, 'DisplayName', 'played path');
hPoint = plot3(axTrajectory, px(1), py(1), pz(1), 'o', ...
    'MarkerFaceColor', [0.00 0.35 0.74], ...
    'MarkerEdgeColor', [0.00 0.20 0.45], ...
    'DisplayName', 'current state');
xlabel(axTrajectory, 'x [m]');
ylabel(axTrajectory, 'y [m]');
zlabel(axTrajectory, 'z [m]');
grid(axTrajectory, 'on');
axis(axTrajectory, 'equal');
view(axTrajectory, 3);
legend(axTrajectory, 'Location', 'best');
title(axTrajectory, 'Position Over Time');

axStatus = nexttile(tl, 3);
axis(axStatus, 'off');
hStatus = text(axStatus, 0.02, 0.98, '', ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none', ...
    'Color', theme.textColor);

axAltitude = nexttile(tl, 6);
plot(axAltitude, T.t, T.kf_h, 'DisplayName', 'firmware altitude');
hold(axAltitude, 'on');
hAltPoint = plot(axAltitude, T.t(1), T.kf_h(1), 'o', 'DisplayName', 'current');
hAltCursor = xline(axAltitude, T.t(1), '--', 'HandleVisibility', 'off');
xlabel(axAltitude, 't [s]');
ylabel(axAltitude, 'altitude [m]');
grid(axAltitude, 'on');
legend(axAltitude, 'Location', 'best');
title(axAltitude, 'Altitude Cursor');

axPhase = nexttile(tl, 7);
hPhaseCursor = localPlotPlaybackPhase(axPhase, T);

axPolicy = nexttile(tl, 8);
hPolicyCursor = localPlotPlaybackPolicy(axPolicy, T);

axApogee = nexttile(tl, 9);
hApogeeCursor = localPlotPlaybackApogee(axApogee, T, cfg);

localApplyPlaybackStyle(fig, theme);

medianDt = median(diff(T.t), 'omitnan');
if ~isfinite(medianDt) || medianDt <= 0
    frameStride = 1;
else
    inputRateHz = 1.0 / medianDt;
    frameStride = max(1, ceil(inputRateHz / options.MaxFrameRate));
end
frameIdx = unique([1:frameStride:height(T), height(T)]);

for ii = 1:numel(frameIdx)
    k = frameIdx(ii);
    addpoints(hTrail, px(k), py(k), pz(k));
    set(hPoint, 'XData', px(k), 'YData', py(k), 'ZData', pz(k));
    set(hAltPoint, 'XData', T.t(k), 'YData', T.kf_h(k));
    set(hAltCursor, 'Value', T.t(k));
    localMoveCursor(hPhaseCursor, T.t(k));
    localMoveCursor(hPolicyCursor, T.t(k));
    localMoveCursor(hApogeeCursor, T.t(k));
    set(hStatus, 'String', localStatusText(T, px, py, pz, k, positionSource));
    drawnow limitrate;

    if ii < numel(frameIdx)
        dtPlayback = (T.t(frameIdx(ii + 1)) - T.t(k)) / options.PlaybackRate;
        if isfinite(dtPlayback) && dtPlayback > 0
            pause(dtPlayback);
        end
    end
end

playback = struct();
playback.figure = fig;
playback.axes = struct( ...
    'trajectory', axTrajectory, ...
    'status', axStatus, ...
    'altitude', axAltitude, ...
    'phase', axPhase, ...
    'policy', axPolicy, ...
    'apogee', axApogee);
playback.handles = struct( ...
    'trail', hTrail, ...
    'position', hPoint, ...
    'status', hStatus, ...
    'altitudeCursor', hAltCursor, ...
    'phaseCursor', hPhaseCursor, ...
    'policyCursor', hPolicyCursor, ...
    'apogeeCursor', hApogeeCursor);
playback.data = T;
playback.est3d = est3d;
playback.position = table(T.t, px, py, pz, ...
    'VariableNames', {'t','x','y','z'});
playback.positionSource = positionSource;
playback.sourceInfo = sourceInfo;
end

function theme = localPlaybackTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
end

function localApplyPlaybackStyle(fig, theme)
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

function [T, est3d, info] = localPrepareSource(source, cfg, run3DReplay)
info = struct();
info.kind = "unknown";
info.importReport = struct();
info.cleanReport = struct();
est3d = table();

if isempty(source)
    error('caelum:playLiveFlight:MissingSource', ...
        'Provide a filename, cleaned table, or analyzeLog results struct.');
end

if isstruct(source) && isfield(source, 'kind') && string(source.kind) == "caelum-live-telemetry-buffer"
    [T, snapshotReport, source] = caelum.snapshotLiveTelemetryBuffer(source);
    info.kind = "live-telemetry-buffer";
    info.importReport = snapshotReport;
    info.buffer = source;
elseif isstruct(source) && isfield(source, 'data')
    T = source.data;
    info.kind = "analysis-results";
    if isfield(source, 'est3d')
        est3d = source.est3d;
    end
elseif istable(source)
    T = source;
    info.kind = "table";
elseif localIsSerialTextSource(source)
    [T, importReport] = caelum.importSerialTelemetry(source);
    info.kind = "serial-lines";
    info.importReport = localMarkImportReportComplete(importReport);
else
    filename = string(source);
    info.filename = filename;
    if localLooksLikeSerialTelemetryFile(filename)
        [raw, importReport] = caelum.importSerialTelemetry(filename);
        importReport = localMarkImportReportComplete(importReport);
        info.kind = "serial-file";
    else
        info.kind = "file";
        strictError = [];
        try
            [raw, importReport] = caelum.importLog(filename);
        catch ME
            strictError = ME;
            [raw, importReport] = caelum.importLogRobust(filename);
        end
        importReport.strictImportFailed = ~isempty(strictError);
        if isempty(strictError)
            importReport.strictImportErrorIdentifier = "";
            importReport.strictImportErrorMessage = "";
        else
            importReport.strictImportErrorIdentifier = string(strictError.identifier);
            importReport.strictImportErrorMessage = string(strictError.message);
        end
    end
    T = raw;
    info.importReport = importReport;
end

vars = string(T.Properties.VariableNames);
if ~all(ismember(["t","kf_sigma_h","acc_norm"], vars))
    T = caelum.alignImportedSchema(T, cfg);
    [T, cleanReport] = caelum.cleanLog(T, cfg);
    info.cleanReport = cleanReport;
end

if isempty(est3d) && run3DReplay
    [est3d, errText] = localTry3DReplay(T, cfg);
    info.est3dError = errText;
end
end

function report = localMarkImportReportComplete(report)
report.strictImportFailed = false;
report.strictImportErrorIdentifier = "";
report.strictImportErrorMessage = "";
end

function tf = localIsSerialTextSource(source)
if isstring(source)
    if ~isscalar(source)
        tf = true;
        return;
    end
    text = strip(source);
elseif iscellstr(source)
    tf = true;
    return;
elseif ischar(source)
    text = strip(string(source));
else
    tf = false;
    return;
end

tf = contains(text, newline) || startsWith(text, "HDR,") || startsWith(text, "TLM,");
end

function tf = localLooksLikeSerialTelemetryFile(filename)
tf = false;
if ~isfile(filename)
    return;
end

try
    raw = strip(readlines(filename));
catch
    return;
end

raw = raw(raw ~= "" & ~startsWith(raw, "#"));
if isempty(raw)
    return;
end

scanCount = min(numel(raw), 25);
prefix = raw(1:scanCount);
tf = any(startsWith(prefix, "HDR,")) || startsWith(prefix(1), "TLM,");
end

function [est3d, errText] = localTry3DReplay(T, cfg)
est3d = table();
errText = "";
vars = string(T.Properties.VariableNames);
hasGps = all(ismember(["gps_x","gps_y","gps_z"], vars)) && ...
    any(isfinite(T.gps_x) | isfinite(T.gps_y) | isfinite(T.gps_z));

if ~hasGps || ~cfg.enable3DReplay
    return;
end

try
    if ~all(ismember(["q_w","q_x","q_y","q_z"], vars))
        attitude = caelum.runAttitudeReplay(T, cfg);
        T.q_w = interp1(attitude.t, attitude.q_w, T.t, 'linear', 1);
        T.q_x = interp1(attitude.t, attitude.q_x, T.t, 'linear', 0);
        T.q_y = interp1(attitude.t, attitude.q_y, T.t, 'linear', 0);
        T.q_z = interp1(attitude.t, attitude.q_z, T.t, 'linear', 0);
    end
    est3d = caelum.run3DEKF(T, cfg);
catch ME
    est3d = table();
    errText = string(ME.message);
end
end

function [px, py, pz, sourceName] = localResolvePosition(T, est3d, requested)
vars = string(T.Properties.VariableNames);
requested = char(lower(requested));

if strcmp(requested, 'auto')
    if istable(est3d) && ~isempty(est3d) && all(ismember(["px","py","pz"], string(est3d.Properties.VariableNames))) && any(isfinite(est3d.px))
        requested = 'ekf3d';
    elseif all(ismember(["gps_x","gps_y","gps_z"], vars)) && any(isfinite(T.gps_x) | isfinite(T.gps_y) | isfinite(T.gps_z))
        requested = 'gps';
    else
        requested = 'vertical';
    end
end

switch requested
    case 'ekf3d'
        if isempty(est3d)
            error('caelum:playLiveFlight:Missing3DPosition', ...
                'PositionSource="ekf3d" requires available 3D replay output.');
        end
        px = interp1(est3d.t, est3d.px, T.t, 'linear', NaN);
        py = interp1(est3d.t, est3d.py, T.t, 'linear', NaN);
        pz = interp1(est3d.t, est3d.pz, T.t, 'linear', NaN);
        sourceName = "ekf3d";
    case 'gps'
        if ~all(ismember(["gps_x","gps_y","gps_z"], vars))
            error('caelum:playLiveFlight:MissingGPSPosition', ...
                'PositionSource="gps" requires gps_x, gps_y, and gps_z.');
        end
        px = T.gps_x;
        py = T.gps_y;
        pz = T.gps_z;
        sourceName = "gps";
    case 'vertical'
        px = zeros(height(T), 1);
        py = zeros(height(T), 1);
        pz = T.kf_h;
        sourceName = "vertical";
    otherwise
        error('caelum:playLiveFlight:InvalidPositionSource', ...
            'PositionSource must be "auto", "ekf3d", "gps", or "vertical".');
end
end

function hCursor = localPlotPlaybackPhase(ax, T)
vars = string(T.Properties.VariableNames);
if ismember("phase", vars) && any(isfinite(T.phase))
    stairs(ax, T.t, T.phase, 'LineWidth', 1.1);
    ylim(ax, [-0.5 4.5]);
    yticks(ax, 0:4);
    yticklabels(ax, {'IDLE','BOOST','COAST','BRAKE','DESCENT'});
    xlabel(ax, 't [s]');
    grid(ax, 'on');
    title(ax, 'Flight Phase');
    hCursor = xline(ax, T.t(1), '--');
else
    text(ax, 0.5, 0.5, 'Phase unavailable', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
    hCursor = gobjects(0);
end
end

function hCursor = localPlotPlaybackPolicy(ax, T)
vars = string(T.Properties.VariableNames);
if ismember("policy_cmd", vars) && any(isfinite(T.policy_cmd))
    stairs(ax, T.t, T.policy_cmd, 'LineWidth', 1.1, 'DisplayName', 'cmd');
    hold(ax, 'on');
    if ismember("policy_valid", vars)
        stairs(ax, T.t, double(T.policy_valid > 0.5), '--', 'DisplayName', 'valid');
    end
    ylim(ax, [-0.05 1.05]);
    xlabel(ax, 't [s]');
    ylabel(ax, 'normalized');
    grid(ax, 'on');
    legend(ax, 'Location', 'best');
    title(ax, 'Policy Command');
    hCursor = xline(ax, T.t(1), '--', 'HandleVisibility', 'off');
else
    text(ax, 0.5, 0.5, 'Policy unavailable', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
    hCursor = gobjects(0);
end
end

function hCursor = localPlotPlaybackApogee(ax, T, cfg)
vars = string(T.Properties.VariableNames);
hasApogee = any(ismember([ ...
    "apogee_no_brake","apogee_full_brake","target_apogee", ...
    "target_nominal","target_effective","uncertainty_margin","apogee_error"], vars));
if hasApogee
    hold(ax, 'on');
    if ismember("apogee_no_brake", vars)
        plot(ax, T.t, T.apogee_no_brake, 'DisplayName', 'no brake');
    end
    if ismember("apogee_full_brake", vars)
        plot(ax, T.t, T.apogee_full_brake, 'DisplayName', 'full brake');
    end
    if ismember("target_apogee", vars)
        plot(ax, T.t, T.target_apogee, '--', 'DisplayName', 'target');
    end
    if ismember("target_nominal", vars)
        plot(ax, T.t, T.target_nominal, ':', 'DisplayName', 'target nominal');
    end
    if ismember("target_effective", vars)
        plot(ax, T.t, T.target_effective, '-.', 'DisplayName', 'target effective');
    end
    if ismember("apogee_error", vars)
        plot(ax, T.t, T.apogee_error, ':', 'DisplayName', 'error');
    end
    if ismember("uncertainty_margin", vars)
        plot(ax, T.t, T.uncertainty_margin, '-.', 'DisplayName', 'uncertainty margin');
    end
    mission = localMissionProfile(cfg);
    if ~isempty(fieldnames(mission))
        localPlotMissionTargetReference(ax, T, mission);
    end
    xlabel(ax, 't [s]');
    ylabel(ax, 'm');
    grid(ax, 'on');
    legend(ax, 'Location', 'best');
    title(ax, 'Apogee Policy');
    hCursor = xline(ax, T.t(1), '--', 'HandleVisibility', 'off');
else
    text(ax, 0.5, 0.5, 'Apogee telemetry unavailable', 'HorizontalAlignment', 'center');
    axis(ax, 'off');
    hCursor = gobjects(0);
end
end

function localMoveCursor(hCursor, t)
if ~isempty(hCursor) && isvalid(hCursor)
    set(hCursor, 'Value', t);
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

if target_m < min(values) - 0.10 * span || target_m > max(values) + 0.50 * span
    return;
end

yline(ax, target_m, '--', ...
    'DisplayName', sprintf('IREC %.0f ft target', mission.targetApogee_ft), ...
    'Color', [0.20 0.70 0.90], ...
    'LineWidth', 1.0);
end

function textOut = localStatusText(T, px, py, pz, k, positionSource)
phase = "UNKNOWN";
if ismember("phase", string(T.Properties.VariableNames))
    phase = localPhaseName(T.phase(k));
end

policyCmd = NaN;
if ismember("policy_cmd", string(T.Properties.VariableNames))
    policyCmd = T.policy_cmd(k);
end

policyValid = NaN;
if ismember("policy_valid", string(T.Properties.VariableNames))
    policyValid = T.policy_valid(k);
end

warnMask = NaN;
if ismember("warn_mask", string(T.Properties.VariableNames))
    warnMask = T.warn_mask(k);
end

textOut = sprintf([ ...
    't: %.3f s\n', ...
    'phase: %s\n', ...
    'altitude: %.3f m\n', ...
    'velocity: %.3f m/s\n', ...
    'position source: %s\n', ...
    'position: [%.2f %.2f %.2f] m\n', ...
    'policy valid: %.0f\n', ...
    'policy cmd: %.3f\n', ...
    'warn mask: %.0f'], ...
    T.t(k), char(phase), T.kf_h(k), T.kf_v(k), char(positionSource), ...
    px(k), py(k), pz(k), policyValid, policyCmd, warnMask);
end

function name = localPhaseName(value)
if ~isfinite(value)
    name = "UNKNOWN";
    return;
end

switch round(value)
    case 0
        name = "IDLE";
    case 1
        name = "BOOST";
    case 2
        name = "COAST";
    case 3
        name = "BRAKE";
    case 4
        name = "DESCENT";
    otherwise
        name = "UNKNOWN";
end
end

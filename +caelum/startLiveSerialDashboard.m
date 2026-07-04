function session = startLiveSerialDashboard(port, baud, options)
%STARTLIVESERIALDASHBOARD Run a callback-driven live serial dashboard.
%
% This is the asynchronous counterpart to readLiveSerialTelemetry. Serial
% ingress is handled by a serialport terminator callback, while a UI timer takes
% normalized snapshots of the ring buffer for plotting. The raw accepted rows,
% parser counters, and freshness diagnostics remain owned by the live telemetry
% buffer so the UI cannot silently hide ingestion failures.
%
% Example:
%   session = caelum.startLiveSerialDashboard("/dev/cu.usbmodem101", 115200);
%   [T, report, buffer] = session.snapshot();
%   session.stop();
arguments
    port (1,1) string
    baud (1,1) double {mustBePositive} = 115200
    options.Capacity (1,1) double {mustBeInteger,mustBePositive} = 2000
    options.RefreshPeriod_s (1,1) double {mustBePositive} = 0.25
    options.Timeout_s (1,1) double {mustBePositive} = 1.0
    options.Terminator (1,1) string = "LF"
    options.FlushOnStart (1,1) logical = true
    options.NormalizeSnapshot (1,1) logical = true
    options.Config struct = caelum.defaultConfig()
    options.PositionSource (1,1) string = "auto"
    options.StaleAge_s (1,1) double {mustBeNonnegative} = 1.0
    options.Visible (1,1) string = "on"
end

positionSourceOption = lower(options.PositionSource);
if ~ismember(positionSourceOption, ["auto","gps","vertical"])
    error('caelum:startLiveSerialDashboard:InvalidPositionSource', ...
        'PositionSource must be "auto", "gps", or "vertical" for live dashboard mode.');
end

if ~ismember(lower(options.Visible), ["on","off"])
    error('caelum:startLiveSerialDashboard:InvalidVisibleOption', ...
        'Visible must be "on" or "off".');
end

if strlength(port) == 0
    available = serialportlist("available");
    error('caelum:startLiveSerialDashboard:MissingPort', ...
        'Provide a serial port name. Available ports: %s', strjoin(cellstr(string(available)), ', '));
end

cfg = options.Config;
buffer = caelum.createLiveTelemetryBuffer( ...
    Capacity=options.Capacity, ...
    Config=cfg, ...
    StaleAge_s=options.StaleAge_s);

serialObj = serialport(port, baud, "Timeout", options.Timeout_s);
configureTerminator(serialObj, options.Terminator);
if options.FlushOnStart
    flush(serialObj);
end

theme = localLiveTheme();
latestSnapshot = table();
latestReport = buffer.counters;
paused = false;
scrubIndex = 1;
stopped = false;
startTime = datetime("now", "TimeZone", "local");

fig = figure( ...
    'Name', 'Caelum Live Serial Dashboard', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.08 0.92 0.84], ...
    'Visible', char(lower(options.Visible)), ...
    'CloseRequestFcn', @onClose);

hPause = uicontrol(fig, ...
    'Style', 'togglebutton', ...
    'Units', 'normalized', ...
    'Position', [0.012 0.956 0.060 0.030], ...
    'String', 'Pause', ...
    'Callback', @onPauseToggle, ...
    'BackgroundColor', theme.controlColor, ...
    'ForegroundColor', theme.textColor);
hStop = uicontrol(fig, ...
    'Style', 'pushbutton', ...
    'Units', 'normalized', ...
    'Position', [0.080 0.956 0.052 0.030], ...
    'String', 'Stop', ...
    'Callback', @(~,~) stopDashboard(false), ...
    'BackgroundColor', theme.controlColor, ...
    'ForegroundColor', theme.textColor);
hScrub = uicontrol(fig, ...
    'Style', 'slider', ...
    'Units', 'normalized', ...
    'Position', [0.145 0.960 0.230 0.022], ...
    'Min', 1, ...
    'Max', 2, ...
    'Value', 1, ...
    'Enable', 'off', ...
    'Callback', @onScrub, ...
    'BackgroundColor', theme.controlColor);
hScrubLabel = uicontrol(fig, ...
    'Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.382 0.955 0.260 0.030], ...
    'String', 'Live cursor follows latest sample', ...
    'HorizontalAlignment', 'left', ...
    'BackgroundColor', theme.figureColor, ...
    'ForegroundColor', theme.textColor);

tl = tiledlayout(fig, 4, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, sprintf('Caelum Live Serial Dashboard - %s @ %.0f baud', char(port), baud), ...
    'Interpreter', 'none');
hTitle.Color = theme.textColor;

axTrajectory = nexttile(tl, 1, [2 2]);
axStatus = nexttile(tl, 3);
axFreshness = nexttile(tl, 6);
axAltitude = nexttile(tl, 7);
axPhase = nexttile(tl, 8);
axPolicy = nexttile(tl, 9);
axApogee = nexttile(tl, 10, [1 3]);

axis(axStatus, 'off');
hStatus = text(axStatus, 0.02, 0.98, 'Waiting for serial telemetry...', ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none', ...
    'Color', theme.textColor);

localShowMessage(axTrajectory, 'Waiting for live position telemetry', theme);
localShowMessage(axFreshness, 'Waiting for freshness evidence', theme);
localShowMessage(axAltitude, 'Waiting for altitude telemetry', theme);
localShowMessage(axPhase, 'Waiting for phase telemetry', theme);
localShowMessage(axPolicy, 'Waiting for policy telemetry', theme);
localShowMessage(axApogee, 'Waiting for apogee policy telemetry', theme);
localApplyLiveStyle(fig, theme);

refreshTimer = timer( ...
    'ExecutionMode', 'fixedSpacing', ...
    'Period', options.RefreshPeriod_s, ...
    'BusyMode', 'drop', ...
    'TimerFcn', @(~,~) refreshDisplay());

configureCallback(serialObj, "terminator", @onSerialLine);
refreshDisplay();
start(refreshTimer);

session = struct();
session.figure = fig;
session.axes = struct( ...
    'trajectory', axTrajectory, ...
    'status', axStatus, ...
    'freshness', axFreshness, ...
    'altitude', axAltitude, ...
    'phase', axPhase, ...
    'policy', axPolicy, ...
    'apogee', axApogee);
session.controls = struct( ...
    'pause', hPause, ...
    'stop', hStop, ...
    'scrub', hScrub, ...
    'scrubLabel', hScrubLabel);
session.serialInfo = struct( ...
    'port', port, ...
    'baud', baud, ...
    'terminator', options.Terminator);
session.timer = refreshTimer;
session.port = port;
session.baud = baud;
session.startedAt = startTime;
session.snapshot = @snapshotSession;
session.getBuffer = @getBuffer;
session.stop = @() stopDashboard(false);

    function onSerialLine(src, ~)
        if stopped
            return;
        end

        try
            line = readline(src);
            buffer = caelum.appendLiveTelemetryBuffer(buffer, line);
        catch ME
            buffer.counters.serialReadErrors = buffer.counters.serialReadErrors + 1;
            buffer.counters.lastErrorMessage = string(ME.message);
        end
    end

    function refreshDisplay()
        if stopped || ~ishghandle(fig)
            return;
        end

        try
            [T, report, buffer] = caelum.snapshotLiveTelemetryBuffer( ...
                buffer, Normalize=true, Config=cfg);
            latestSnapshot = T;
            latestReport = report;
        catch ME
            latestSnapshot = table();
            latestReport = buffer.counters;
            latestReport.lastErrorMessage = string(ME.message);
            set(hStatus, 'String', localStatusText(table(), latestReport, NaN, ...
                "unavailable", "snapshot error", NaN, NaN, NaN));
            drawnow limitrate;
            return;
        end

        if isempty(latestSnapshot)
            set(hStatus, 'String', localStatusText(table(), latestReport, NaN, ...
                "unavailable", "waiting", NaN, NaN, NaN));
            drawnow limitrate;
            return;
        end

        [px, py, pz, positionSource] = localResolveLivePosition(latestSnapshot, positionSourceOption);
        k = localResolveCursorIndex(height(latestSnapshot));
        cursorTime = latestSnapshot.t(k);

        localUpdateScrubControl(height(latestSnapshot), k);
        localRenderTrajectory(axTrajectory, latestSnapshot, px, py, pz, k, positionSource, theme);
        localRenderAltitude(axAltitude, latestSnapshot, k, theme);
        localRenderPhase(axPhase, latestSnapshot, cursorTime, theme);
        localRenderPolicy(axPolicy, latestSnapshot, cursorTime, theme);
        localRenderApogee(axApogee, latestSnapshot, cursorTime, theme, cfg);
        localRenderFreshness(axFreshness, latestSnapshot, latestReport, cursorTime, theme, 1000 * options.StaleAge_s);
        set(hStatus, 'String', localStatusText(latestSnapshot, latestReport, k, ...
            positionSource, sessionModeText(), px(k), py(k), pz(k)));
        localApplyLiveStyle(fig, theme);
        drawnow limitrate;
    end

    function k = localResolveCursorIndex(numRows)
        if numRows <= 0
            k = 1;
            return;
        end

        if paused
            k = max(1, min(numRows, round(scrubIndex)));
        else
            k = numRows;
            scrubIndex = k;
        end
    end

    function localUpdateScrubControl(numRows, k)
        if ~ishghandle(hScrub)
            return;
        end

        sliderMax = max(2, numRows);
        if sliderMax > 1
            smallStep = min(1, 1 / max(1, sliderMax - 1));
            largeStep = min(1, 10 / max(1, sliderMax - 1));
        else
            smallStep = 1;
            largeStep = 1;
        end

        set(hScrub, ...
            'Min', 1, ...
            'Max', sliderMax, ...
            'SliderStep', [smallStep largeStep], ...
            'Value', max(1, min(sliderMax, k)));
    end

    function onPauseToggle(src, ~)
        paused = get(src, 'Value') ~= 0;
        if paused
            scrubIndex = localResolveCursorIndex(max(1, height(latestSnapshot)));
            set(hPause, 'String', 'Resume');
            set(hScrub, 'Enable', 'on');
            set(hScrubLabel, 'String', 'Paused: scrub through buffered samples');
        else
            set(hPause, 'String', 'Pause');
            set(hScrub, 'Enable', 'off');
            set(hScrubLabel, 'String', 'Live cursor follows latest sample');
        end
        refreshDisplay();
    end

    function onScrub(src, ~)
        scrubIndex = round(get(src, 'Value'));
        if ~paused
            set(hPause, 'Value', 1);
            onPauseToggle(hPause, []);
        else
            refreshDisplay();
        end
    end

    function text = sessionModeText()
        if stopped
            text = "stopped";
        elseif paused
            text = "paused";
        else
            text = "live";
        end
    end

    function [T, report, liveBuffer] = snapshotSession()
        [T, report, buffer] = caelum.snapshotLiveTelemetryBuffer( ...
            buffer, Normalize=options.NormalizeSnapshot, Config=cfg);
        latestSnapshot = T;
        latestReport = report;
        liveBuffer = buffer;
    end

    function liveBuffer = getBuffer()
        liveBuffer = buffer;
    end

    function stopDashboard(deleteFigure)
        if stopped
            if deleteFigure && ishghandle(fig)
                delete(fig);
            end
            return;
        end

        stopped = true;
        try
            configureCallback(serialObj, "off");
        catch
        end
        try
            stop(refreshTimer);
        catch
        end
        try
            delete(refreshTimer);
        catch
        end
        try
            delete(serialObj);
        catch
        end
        serialObj = [];

        if ishghandle(hPause)
            set(hPause, 'Enable', 'off');
        end
        if ishghandle(hScrub)
            set(hScrub, 'Enable', 'off');
        end
        if ishghandle(hStop)
            set(hStop, 'Enable', 'off', 'String', 'Stopped');
        end
        if ishghandle(hStatus)
            set(hStatus, 'String', sprintf('%s\n\nlive session stopped', ...
                get(hStatus, 'String')));
        end

        if deleteFigure && ishghandle(fig)
            delete(fig);
        end
    end

    function onClose(~, ~)
        stopDashboard(true);
    end
end

function theme = localLiveTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.mutedTextColor = [0.62 0.66 0.70];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.controlColor = [0.14 0.16 0.18];
theme.primaryColor = [0.18 0.49 0.85];
theme.secondaryColor = [0.88 0.53 0.17];
theme.warningColor = [0.90 0.72 0.20];
theme.pathColor = [0.72 0.72 0.72];
end

function localApplyLiveStyle(fig, theme)
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

function localShowMessage(ax, message, theme)
cla(ax);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none', ...
    'Color', theme.mutedTextColor);
end

function [px, py, pz, sourceName] = localResolveLivePosition(T, requested)
vars = string(T.Properties.VariableNames);
requested = lower(string(requested));

if requested == "auto"
    if all(ismember(["gps_x","gps_y","gps_z"], vars)) && ...
            any(isfinite(T.gps_x) | isfinite(T.gps_y) | isfinite(T.gps_z))
        requested = "gps";
    else
        requested = "vertical";
    end
end

switch requested
    case "gps"
        if all(ismember(["gps_x","gps_y","gps_z"], vars))
            px = T.gps_x;
            py = T.gps_y;
            pz = T.gps_z;
            sourceName = "gps";
        else
            px = nan(height(T), 1);
            py = nan(height(T), 1);
            pz = nan(height(T), 1);
            sourceName = "gps unavailable";
        end
    case "vertical"
        px = zeros(height(T), 1);
        py = zeros(height(T), 1);
        if ismember("kf_h", vars)
            pz = T.kf_h;
        else
            pz = nan(height(T), 1);
        end
        sourceName = "vertical";
    otherwise
        px = nan(height(T), 1);
        py = nan(height(T), 1);
        pz = nan(height(T), 1);
        sourceName = "unavailable";
end
end

function localRenderTrajectory(ax, T, px, py, pz, k, positionSource, theme)
cla(ax);
valid = isfinite(px) & isfinite(py) & isfinite(pz);
if ~any(valid)
    localShowMessage(ax, 'Position telemetry unavailable', theme);
    title(ax, 'Position Over Time');
    return;
end

plot3(ax, px(valid), py(valid), pz(valid), ...
    'Color', theme.pathColor, ...
    'LineWidth', 0.9, ...
    'DisplayName', 'buffered path');
hold(ax, 'on');
playedMask = valid;
if k < numel(playedMask)
    playedMask((k + 1):end) = false;
end
plot3(ax, px(playedMask), py(playedMask), pz(playedMask), ...
    'Color', theme.primaryColor, ...
    'LineWidth', 1.6, ...
    'DisplayName', 'cursor path');
plot3(ax, px(k), py(k), pz(k), 'o', ...
    'MarkerFaceColor', theme.secondaryColor, ...
    'MarkerEdgeColor', theme.secondaryColor, ...
    'DisplayName', 'cursor');
xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
zlabel(ax, 'z [m]');
grid(ax, 'on');
axis(ax, 'equal');
view(ax, 3);
legend(ax, 'Location', 'best');
title(ax, sprintf('Position Over Time (%s)', char(positionSource)));
end

function localRenderAltitude(ax, T, k, theme)
cla(ax);
vars = string(T.Properties.VariableNames);
if ~ismember("kf_h", vars) || ~ismember("t", vars) || ~any(isfinite(T.kf_h))
    localShowMessage(ax, 'Altitude telemetry unavailable', theme);
    title(ax, 'Altitude Cursor');
    return;
end

plot(ax, T.t, T.kf_h, ...
    'Color', theme.primaryColor, ...
    'DisplayName', 'firmware altitude');
hold(ax, 'on');
plot(ax, T.t(k), T.kf_h(k), 'o', ...
    'MarkerFaceColor', theme.secondaryColor, ...
    'MarkerEdgeColor', theme.secondaryColor, ...
    'DisplayName', 'cursor');
xline(ax, T.t(k), '--', 'Color', theme.pathColor, 'HandleVisibility', 'off');
xlabel(ax, 't [s]');
ylabel(ax, 'altitude [m]');
grid(ax, 'on');
legend(ax, 'Location', 'best');
title(ax, 'Altitude Cursor');
end

function localRenderPhase(ax, T, cursorTime, theme)
cla(ax);
vars = string(T.Properties.VariableNames);
if ~ismember("phase", vars) || ~any(isfinite(T.phase))
    localShowMessage(ax, 'Phase telemetry unavailable', theme);
    title(ax, 'Flight Phase');
    return;
end

stairs(ax, T.t, T.phase, ...
    'Color', theme.primaryColor, ...
    'LineWidth', 1.1);
hold(ax, 'on');
xline(ax, cursorTime, '--', 'Color', theme.pathColor);
ylim(ax, [-0.5 4.5]);
yticks(ax, 0:4);
yticklabels(ax, {'IDLE','BOOST','COAST','BRAKE','DESCENT'});
xlabel(ax, 't [s]');
grid(ax, 'on');
title(ax, 'Flight Phase');
end

function localRenderPolicy(ax, T, cursorTime, theme)
cla(ax);
vars = string(T.Properties.VariableNames);
if ~ismember("policy_cmd", vars) || ~any(isfinite(T.policy_cmd))
    localShowMessage(ax, 'Policy command unavailable', theme);
    title(ax, 'Policy Command');
    return;
end

stairs(ax, T.t, T.policy_cmd, ...
    'Color', theme.primaryColor, ...
    'LineWidth', 1.1, ...
    'DisplayName', 'cmd');
hold(ax, 'on');
if ismember("policy_valid", vars)
    stairs(ax, T.t, double(T.policy_valid > 0.5), '--', ...
        'Color', theme.secondaryColor, ...
        'DisplayName', 'valid');
end
xline(ax, cursorTime, '--', 'Color', theme.pathColor, 'HandleVisibility', 'off');
ylim(ax, [-0.05 1.05]);
xlabel(ax, 't [s]');
ylabel(ax, 'normalized');
grid(ax, 'on');
legend(ax, 'Location', 'best');
title(ax, 'Policy Command');
end

function localRenderApogee(ax, T, cursorTime, theme, cfg)
cla(ax);
vars = string(T.Properties.VariableNames);
hasApogee = any(ismember([ ...
    "apogee_no_brake","apogee_full_brake","target_apogee", ...
    "target_nominal","target_effective","uncertainty_margin","apogee_error"], vars));
if ~hasApogee
    localShowMessage(ax, 'Apogee policy telemetry unavailable', theme);
    title(ax, 'Apogee Policy');
    return;
end

hold(ax, 'on');
if ismember("apogee_no_brake", vars)
    plot(ax, T.t, T.apogee_no_brake, ...
        'Color', theme.primaryColor, ...
        'DisplayName', 'no brake');
end
if ismember("apogee_full_brake", vars)
    plot(ax, T.t, T.apogee_full_brake, ...
        'Color', theme.secondaryColor, ...
        'DisplayName', 'full brake');
end
if ismember("target_apogee", vars)
    plot(ax, T.t, T.target_apogee, '--', ...
        'Color', theme.warningColor, ...
        'DisplayName', 'target');
end
if ismember("target_nominal", vars)
    plot(ax, T.t, T.target_nominal, ':', ...
        'Color', theme.warningColor, ...
        'DisplayName', 'target nominal');
end
if ismember("target_effective", vars)
    plot(ax, T.t, T.target_effective, '-.', ...
        'Color', theme.warningColor, ...
        'DisplayName', 'target effective');
end
if ismember("apogee_error", vars)
    plot(ax, T.t, T.apogee_error, ':', ...
        'Color', [0.55 0.35 0.80], ...
        'DisplayName', 'error');
end
if ismember("uncertainty_margin", vars)
    plot(ax, T.t, T.uncertainty_margin, '-.', ...
        'Color', [0.45 0.80 0.80], ...
        'DisplayName', 'uncertainty margin');
end
mission = localMissionProfile(cfg);
if ~isempty(fieldnames(mission))
    localPlotMissionTargetReference(ax, T, mission);
end
xline(ax, cursorTime, '--', 'Color', theme.pathColor, 'HandleVisibility', 'off');
xlabel(ax, 't [s]');
ylabel(ax, 'm');
grid(ax, 'on');
legend(ax, 'Location', 'best');
title(ax, 'Apogee Policy');
end

function localRenderFreshness(ax, T, report, cursorTime, theme, sourceMaxAge_ms)
cla(ax);
if isempty(T) || height(T) < 1
    localShowMessage(ax, 'Freshness evidence unavailable', theme);
    title(ax, 'Telemetry Freshness');
    return;
end

try
    caelum.plotCompactTelemetryFreshness(ax, T, ...
        Report=report, ...
        MaxAge_ms=sourceMaxAge_ms, ...
        RecentWindow_s=15, ...
        MaxSamples=240, ...
        CursorTime=cursorTime, ...
        Title="Telemetry Freshness");
catch ME
    localShowMessage(ax, sprintf('Freshness unavailable\n%s', ME.message), theme);
    title(ax, 'Telemetry Freshness');
end
end

function textOut = localStatusText(T, report, k, positionSource, modeText, px, py, pz)
if isempty(T) || ~isfinite(k) || k < 1 || k > height(T)
    t = NaN;
    altitude = NaN;
    velocity = NaN;
    phase = "UNKNOWN";
    policyValid = NaN;
    policyCmd = NaN;
    warnMask = NaN;
else
    vars = string(T.Properties.VariableNames);
    t = T.t(k);
    altitude = localColumnValue(T, "kf_h", k);
    velocity = localColumnValue(T, "kf_v", k);
    phase = localPhaseName(localColumnValue(T, "phase", k));
    policyValid = localColumnValue(T, "policy_valid", k);
    policyCmd = localColumnValue(T, "policy_cmd", k);
    warnMask = localColumnValue(T, "warn_mask", k);
    if ~ismember("phase", vars)
        phase = "UNKNOWN";
    end
end

textOut = sprintf([ ...
    'mode: %s\n', ...
    't: %.3f s\n', ...
    'phase: %s\n', ...
    'altitude: %.3f m\n', ...
    'velocity: %.3f m/s\n', ...
    'position source: %s\n', ...
    'position: [%.2f %.2f %.2f] m\n', ...
    'policy valid: %.0f\n', ...
    'policy cmd: %.3f\n', ...
    'warn mask: %.0f\n\n', ...
    'rows in buffer: %.0f / %.0f\n', ...
    'accepted rows: %.0f\n', ...
    'dropped malformed: %.0f\n', ...
    'dropped nonnumeric: %.0f\n', ...
    'dropped nonmonotonic: %.0f\n', ...
    'dropped by capacity: %.0f\n', ...
    'latest age: %.3f s\n', ...
    'snapshot stale: %.0f\n', ...
    'serial read errors: %.0f\n', ...
    'last error: %s'], ...
    char(modeText), ...
    t, char(phase), altitude, velocity, char(positionSource), ...
    px, py, pz, policyValid, policyCmd, warnMask, ...
    localReportScalar(report, 'rowsInBuffer', 0), ...
    localReportScalar(report, 'capacity', NaN), ...
    localReportScalar(report, 'acceptedRows', 0), ...
    localReportScalar(report, 'droppedMalformedRows', 0), ...
    localReportScalar(report, 'droppedNonNumericRows', 0), ...
    localReportScalar(report, 'droppedNonmonotonicRows', 0), ...
    localReportScalar(report, 'droppedRowsFromCapacity', 0), ...
    localReportScalar(report, 'latestAge_s', NaN), ...
    localReportScalar(report, 'snapshotStale', 0), ...
    localReportScalar(report, 'serialReadErrors', 0), ...
    char(localReportString(report, 'lastErrorMessage', "")));
end

function value = localColumnValue(T, name, idx)
if ismember(name, string(T.Properties.VariableNames))
    column = T.(char(name));
    value = column(idx);
else
    value = NaN;
end
end

function value = localReportScalar(report, name, defaultValue)
if isfield(report, name)
    value = report.(name);
    if islogical(value)
        value = double(value);
    end
    if ~isnumeric(value) || isempty(value)
        value = defaultValue;
    else
        value = value(1);
    end
else
    value = defaultValue;
end
end

function value = localReportString(report, name, defaultValue)
if isfield(report, name)
    value = string(report.(name));
    if isempty(value)
        value = string(defaultValue);
    else
        value = value(1);
    end
else
    value = string(defaultValue);
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

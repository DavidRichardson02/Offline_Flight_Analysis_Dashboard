function audit = plotCompactTrajectoryWindWidget(ax, est3d, T, options)
%PLOTCOMPACTTRAJECTORYWINDWIDGET Axes-level 3D/wind uncertainty widget.
%
% This compact widget reuses build3DTrajectoryWindAudit so dashboard evidence
% matches the standalone trajectory/wind validation artifact.
arguments
    ax (1,1) matlab.graphics.axis.Axes
    est3d table = table()
    T table = table()
    options.MaxTubeRings (1,1) double {mustBeInteger,mustBePositive} = 18
    options.MaxWindVectors (1,1) double {mustBeInteger,mustBeNonnegative} = 12
    options.ShowLegend (1,1) logical = false
    options.ShowStatus (1,1) logical = true
    options.TubeAlpha (1,1) double {mustBeNonnegative} = 0.24
    options.PreserveMetricAspect (1,1) logical = false
    options.ViewAzimuth (1,1) double = -38
    options.ViewElevation (1,1) double = 24
    options.Title (1,1) string = "3D / Wind Uncertainty"
end

cla(ax);
audit = table();

if isempty(est3d) || ~istable(est3d) || height(est3d) < 1
    localShowUnavailable(ax, "3D/wind audit unavailable.");
    title(ax, options.Title);
    return;
end

try
    audit = caelum.build3DTrajectoryWindAudit(est3d, T);
catch ME
    localShowUnavailable(ax, "3D/wind audit unavailable: " + string(ME.message));
    title(ax, options.Title, 'Interpreter', 'none');
    return;
end

valid = all(isfinite([audit.px_m audit.py_m audit.pz_m]), 2);
if nnz(valid) < 1
    localShowUnavailable(ax, "3D/wind state has no finite position samples.");
    title(ax, options.Title);
    return;
end

theme = localTheme();
tubeAlpha = min(options.TubeAlpha, 1);
hold(ax, 'on');
localPlotTubeSurface(ax, audit, valid, options.MaxTubeRings, tubeAlpha, theme);
plot3(ax, audit.px_m(valid), audit.py_m(valid), audit.pz_m(valid), ...
    'Color', theme.primaryColor, ...
    'LineWidth', 1.3, ...
    'DisplayName', '3D EKF');

gpsValid = all(isfinite([audit.gps_x_m audit.gps_y_m audit.gps_z_m]), 2);
if any(gpsValid)
    plot3(ax, audit.gps_x_m(gpsValid), audit.gps_y_m(gpsValid), audit.gps_z_m(gpsValid), ...
        '.', ...
        'Color', theme.gpsColor, ...
        'MarkerSize', 5, ...
        'DisplayName', 'GPS');
end

gpsUsed = gpsValid & audit.gps_used;
if any(gpsUsed)
    plot3(ax, audit.gps_x_m(gpsUsed), audit.gps_y_m(gpsUsed), audit.gps_z_m(gpsUsed), ...
        'o', ...
        'Color', theme.acceptColor, ...
        'MarkerFaceColor', theme.acceptColor, ...
        'MarkerSize', 3, ...
        'DisplayName', 'GPS used');
end

localPlotWindVectors(ax, audit, valid, options.MaxWindVectors, theme);

xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
zlabel(ax, 'z [m]');
grid(ax, 'on');
axis(ax, 'tight');
localPad3DLimits(ax);
if options.PreserveMetricAspect
    axis(ax, 'equal');
else
    pbaspect(ax, [1.15 1 1.15]);
end
view(ax, options.ViewAzimuth, options.ViewElevation);
try
    camproj(ax, 'perspective');
catch
end
if options.ShowLegend
    legend(ax, 'Location', 'northeastoutside', 'Interpreter', 'none');
else
    legend(ax, 'off');
end
title(ax, options.Title, 'Interpreter', 'none');
if options.ShowStatus
    localPlotStatusText(ax, audit, theme);
end
end

function localPlotTubeSurface(ax, audit, valid, maxRings, alphaValue, theme)
tubeValid = valid & all(isfinite([audit.display_tube_radius_m ...
    audit.display_tube_vertical_half_width_m]), 2);
idx = find(tubeValid);
idx = localSubsampleIndex(idx, maxRings);
if isempty(idx)
    return;
end

theta = linspace(0, 2*pi, 20);
radius = audit.display_tube_radius_m(idx);
vertical = audit.display_tube_vertical_half_width_m(idx);
if numel(idx) >= 2
    X = repmat(audit.px_m(idx), 1, numel(theta)) + radius * cos(theta);
    Y = repmat(audit.py_m(idx), 1, numel(theta)) + radius * sin(theta);
    Z = repmat(audit.pz_m(idx), 1, numel(theta)) + vertical * sin(theta);
    surf(ax, X, Y, Z, ...
        'FaceColor', theme.tubeColor, ...
        'FaceAlpha', alphaValue, ...
        'EdgeColor', 'none', ...
        'DisplayName', 'uncertainty tube');
else
    r = radius(1);
    v = vertical(1);
    x = audit.px_m(idx) + r .* cos(theta);
    y = audit.py_m(idx) + r .* sin(theta);
    z = audit.pz_m(idx) + v .* sin(theta);
    plot3(ax, x, y, z, ...
        'Color', theme.tubeColor, ...
        'LineWidth', 0.8, ...
        'DisplayName', 'uncertainty tube');
end
end

function localPlotWindVectors(ax, audit, valid, maxVectors, theme)
if maxVectors < 1
    return;
end
windValid = valid & all(isfinite([audit.wx_mps audit.wy_mps audit.wz_mps]), 2);
idx = find(windValid);
idx = localSubsampleIndex(idx, maxVectors);
if isempty(idx)
    return;
end

span = max([localFiniteRange(audit.px_m), localFiniteRange(audit.py_m), localFiniteRange(audit.pz_m)]);
if ~isfinite(span) || span <= 0
    span = 1;
end
windSpeed = max(audit.wind_speed_mps(idx), [], 'omitnan');
if ~isfinite(windSpeed) || windSpeed <= 0
    scale = 1;
else
    scale = 0.18 * span / windSpeed;
end
quiver3(ax, audit.px_m(idx), audit.py_m(idx), audit.pz_m(idx), ...
    scale .* audit.wx_mps(idx), ...
    scale .* audit.wy_mps(idx), ...
    scale .* audit.wz_mps(idx), ...
    0, ...
    'Color', theme.windColor, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'wind vectors');
end

function localPlotStatusText(ax, audit, theme)
statusText = localStatusText(audit);
try
    text(ax, 0.02, 0.02, statusText, ...
        'Units', 'normalized', ...
        'Color', theme.textColor, ...
        'BackgroundColor', theme.labelBackgroundColor, ...
        'Margin', 2, ...
        'FontSize', 7, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'bottom', ...
        'Interpreter', 'none');
catch
end
end

function statusText = localStatusText(audit)
positionSigma = localLastFinite(audit.position_sigma_norm_m);
windSigma = localLastFinite(audit.wind_sigma_norm_mps);
windSpeed = localLastFinite(audit.wind_speed_mps);
gpsUsed = nnz(audit.gps_used);
gpsRejected = nnz(audit.gps_rejected);
latestIdx = find(audit.evidence_label ~= "", 1, 'last');
if isempty(latestIdx)
    latestLabel = "unclassified";
else
    latestLabel = localCompactLabel(audit.evidence_label(latestIdx));
end
statusText = sprintf('pSig %.2f m | wSig %.2f | wind %.2f | GPS %d/%d | %s', ...
    positionSigma, windSigma, windSpeed, gpsUsed, gpsRejected, latestLabel);
end

function label = localCompactLabel(label)
label = erase(string(label), ["gps_","position_","wind_","uncertainty_"]);
label = replace(label, "_", " ");
if strlength(label) > 24
    label = extractBefore(label, 25);
end
end

function idxOut = localSubsampleIndex(idxIn, maxCount)
idxIn = idxIn(:);
if numel(idxIn) <= maxCount
    idxOut = idxIn;
else
    pick = unique(round(linspace(1, numel(idxIn), maxCount))).';
    idxOut = idxIn(pick);
end
end

function span = localFiniteRange(values)
values = values(isfinite(values));
if isempty(values)
    span = NaN;
else
    span = max(values) - min(values);
end
end

function localPad3DLimits(ax)
try
    xlim(ax, localPaddedLimits(xlim(ax)));
    ylim(ax, localPaddedLimits(ylim(ax)));
    zlim(ax, localPaddedLimits(zlim(ax)));
catch
end
end

function lim = localPaddedLimits(lim)
if numel(lim) ~= 2 || any(~isfinite(lim))
    lim = [-1 1];
    return;
end
span = lim(2) - lim(1);
if span <= 0
    center = mean(lim);
    span = max(abs(center), 1);
    lim = center + [-0.5 0.5] .* span;
    return;
end
pad = 0.08 * span;
lim = lim + [-pad pad];
end

function value = localLastFinite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
end

function localShowUnavailable(ax, message)
axis(ax, [0 1 0 1]);
axis(ax, 'off');
text(ax, 0.5, 0.5, message, ...
    'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end

function theme = localTheme()
theme.primaryColor = [0.18 0.49 0.85];
theme.gpsColor = [0.88 0.88 0.36];
theme.acceptColor = [0.20 0.75 0.42];
theme.windColor = [0.78 0.42 0.86];
theme.tubeColor = [0.20 0.55 0.80];
theme.textColor = [0.93 0.93 0.93];
theme.labelBackgroundColor = [0.04 0.05 0.06];
end

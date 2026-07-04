function fig = plot3DTrajectoryWindUncertaintyTube(audit, options)
%PLOT3DTRAJECTORYWINDUNCERTAINTYTUBE Plot 3D trajectory/wind uncertainty evidence.
arguments
    audit table
    options.Parent = []
    options.LayoutTile = []
    options.LayoutTileSpan = []
    options.ShowTitle (1,1) logical = true
end

if isempty(audit) || height(audit) < 1
    error('caelum:plot3DTrajectoryWindUncertaintyTube:EmptyAudit', ...
        '3D trajectory/wind audit table must contain at least one row.');
end

required = ["t","px_m","py_m","pz_m","wx_mps","wy_mps","wz_mps", ...
    "display_tube_radius_m","display_tube_vertical_half_width_m", ...
    "position_sigma_norm_m","wind_sigma_norm_mps", ...
    "gps_used","gps_rejected","evidence_code","evidence_label","evidence_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
if ~isempty(missing)
    error('caelum:plot3DTrajectoryWindUncertaintyTube:MissingAuditFields', ...
        '3D trajectory/wind audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

theme = localTheme();
if isempty(options.Parent)
    fig = figure('Name', 'Caelum 3D Trajectory / Wind Uncertainty Tube', ...
        'Color', theme.figureColor, ...
        'Units', 'normalized', ...
        'Position', [0.03 0.06 0.94 0.88]);
    parent = fig;
else
    parent = options.Parent;
    fig = ancestor(parent, 'figure');
    if isempty(fig) || ~isgraphics(fig)
        fig = gcf;
    end
end

tl = tiledlayout(parent, 5, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
if ~isempty(options.LayoutTile)
    tl.Layout.Tile = options.LayoutTile;
end
if ~isempty(options.LayoutTileSpan)
    tl.Layout.TileSpan = options.LayoutTileSpan;
end
if options.ShowTitle
    hTitle = title(tl, '3D Trajectory / Wind Uncertainty Tube');
    hTitle.Color = theme.textColor;
end

axTrajectory = nexttile(tl, 1, [2 2]);
localPlotTrajectoryTube(axTrajectory, audit, theme);

axWind = nexttile(tl, 5);
localPlotWindComponents(axWind, audit, theme);

axUncertainty = nexttile(tl, 6);
localPlotUncertainty(axUncertainty, audit);

axFusion = nexttile(tl, 7);
localPlotGpsFusion(axFusion, audit);

axClass = nexttile(tl, 8);
localPlotEvidenceLabels(axClass, audit);

axSummary = nexttile(tl, 9, [1 2]);
localPlotSummary(axSummary, audit);

localApplyStyle(tl, theme);
end

function localPlotTrajectoryTube(ax, audit, theme)
validTube = all(isfinite([audit.px_m audit.py_m audit.pz_m ...
    audit.display_tube_radius_m audit.display_tube_vertical_half_width_m]), 2);
if nnz(validTube) < 2
    localShowUnavailable(ax, "3D trajectory uncertainty tube unavailable.");
    title(ax, 'Trajectory Tube');
    return;
end

idx = find(validTube);
idx = localSubsampleIndex(idx, 220);
theta = linspace(0, 2*pi, 24);
radius = audit.display_tube_radius_m(idx);
vertical = audit.display_tube_vertical_half_width_m(idx);

X = repmat(audit.px_m(idx), 1, numel(theta)) + radius * cos(theta);
Y = repmat(audit.py_m(idx), 1, numel(theta)) + radius * sin(theta);
Z = repmat(audit.pz_m(idx), 1, numel(theta)) + vertical * sin(theta);

surf(ax, X, Y, Z, ...
    'FaceColor', theme.tubeColor, ...
    'FaceAlpha', 0.18, ...
    'EdgeColor', 'none', ...
    'DisplayName', 'display-capped uncertainty tube');
hold(ax, 'on');
plot3(ax, audit.px_m(validTube), audit.py_m(validTube), audit.pz_m(validTube), ...
    'Color', theme.primaryColor, ...
    'LineWidth', 1.5, ...
    'DisplayName', '3D EKF trajectory');

gpsValid = all(isfinite([audit.gps_x_m audit.gps_y_m audit.gps_z_m]), 2);
if any(gpsValid)
    plot3(ax, audit.gps_x_m(gpsValid), audit.gps_y_m(gpsValid), audit.gps_z_m(gpsValid), ...
        '.', ...
        'Color', theme.gpsColor, ...
        'MarkerSize', 8, ...
        'DisplayName', 'GPS position samples');
end

gpsUsed = gpsValid & audit.gps_used;
if any(gpsUsed)
    plot3(ax, audit.gps_x_m(gpsUsed), audit.gps_y_m(gpsUsed), audit.gps_z_m(gpsUsed), ...
        'o', ...
        'Color', theme.acceptColor, ...
        'MarkerFaceColor', theme.acceptColor, ...
        'MarkerSize', 4, ...
        'DisplayName', 'accepted GPS updates');
end

windValid = validTube & all(isfinite([audit.wx_mps audit.wy_mps audit.wz_mps]), 2);
windIdx = find(windValid);
windIdx = localSubsampleIndex(windIdx, 24);
if ~isempty(windIdx)
    scale = localWindVectorScale(audit, windIdx);
    quiver3(ax, audit.px_m(windIdx), audit.py_m(windIdx), audit.pz_m(windIdx), ...
        scale .* audit.wx_mps(windIdx), ...
        scale .* audit.wy_mps(windIdx), ...
        scale .* audit.wz_mps(windIdx), ...
        0, ...
        'Color', theme.windColor, ...
        'LineWidth', 1.0, ...
        'DisplayName', sprintf('wind vectors x %.2f s', scale));
end

xlabel(ax, 'x [m]');
ylabel(ax, 'y [m]');
zlabel(ax, 'z [m]');
grid(ax, 'on');
axis(ax, 'equal');
view(ax, 3);
title(ax, '3D Position With Wind and Position Uncertainty');
legend(ax, 'Location', 'best');
end

function localPlotWindComponents(ax, audit, theme)
hold(ax, 'on');
localPlotComponentBand(ax, audit.t, audit.wx_mps, audit.sigma_wx_mps, theme.primaryColor, 'w_x');
localPlotComponentBand(ax, audit.t, audit.wy_mps, audit.sigma_wy_mps, theme.secondaryColor, 'w_y');
localPlotComponentBand(ax, audit.t, audit.wz_mps, audit.sigma_wz_mps, theme.windColor, 'w_z');
plot(ax, audit.t, audit.wind_speed_mps, ':', ...
    'Color', theme.textColor, ...
    'LineWidth', 1.0, ...
    'DisplayName', '|wind|');
xlabel(ax, 't [s]');
ylabel(ax, 'm/s');
title(ax, 'Wind Components With 2-Sigma Bands');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotComponentBand(ax, t, value, sigma, color, labelText)
valid = isfinite(t) & isfinite(value) & isfinite(sigma);
if any(valid)
    low = value(valid) - 2 .* sigma(valid);
    high = value(valid) + 2 .* sigma(valid);
    fill(ax, [t(valid); flipud(t(valid))], [low; flipud(high)], color, ...
        'FaceAlpha', 0.10, ...
        'EdgeColor', 'none', ...
        'HandleVisibility', 'off');
end
plot(ax, t, value, ...
    'Color', color, ...
    'LineWidth', 1.1, ...
    'DisplayName', labelText);
end

function localPlotUncertainty(ax, audit)
hold(ax, 'on');
plot(ax, audit.t, audit.position_sigma_norm_m, ...
    'LineWidth', 1.1, ...
    'DisplayName', 'position sigma norm');
plot(ax, audit.t, audit.position_sigma_horizontal_m, '--', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'horizontal sigma');
plot(ax, audit.t, audit.sigma_pz_m, ':', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'vertical sigma');
yyaxis(ax, 'right');
plot(ax, audit.t, audit.wind_sigma_norm_mps, ...
    'LineWidth', 1.1, ...
    'DisplayName', 'wind sigma norm');
ylabel(ax, 'wind sigma [m/s]');
yyaxis(ax, 'left');
ylabel(ax, 'position sigma [m]');
xlabel(ax, 't [s]');
title(ax, 'Position / Wind Uncertainty');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotGpsFusion(ax, audit)
hold(ax, 'on');
yyaxis(ax, 'left');
stairs(ax, audit.t, double(audit.gps_used), ...
    'LineWidth', 1.1, ...
    'DisplayName', 'gps used');
stairs(ax, audit.t, double(audit.gps_rejected), '--', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'gps rejected');
ylim(ax, [-0.05 1.05]);
ylabel(ax, 'flag');

yyaxis(ax, 'right');
plot(ax, audit.t, audit.innovation_pos_norm_m, ...
    'LineWidth', 1.0, ...
    'DisplayName', 'pos innovation');
plot(ax, audit.t, audit.innovation_vel_norm_mps, ':', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'vel innovation');
plot(ax, audit.t, audit.gps_position_residual_norm_m, '--', ...
    'LineWidth', 1.0, ...
    'DisplayName', 'GPS-pos residual');
ylabel(ax, 'residual / innovation');

xlabel(ax, 't [s]');
title(ax, 'GPS Fusion Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotEvidenceLabels(ax, audit)
stairs(ax, audit.t, audit.evidence_code, ...
    'LineWidth', 1.2, ...
    'DisplayName', '3D/wind evidence label');
yticks(ax, 1:10);
yticklabels(ax, localEvidenceTickLabels());
ylim(ax, [0.5 10.5]);
xlabel(ax, 't [s]');
title(ax, 'Audit Classification');
grid(ax, 'on');
end

function localPlotSummary(ax, audit)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

dt = localSampleDurations(audit.t);
validTruthPosition = isfinite(audit.truth_position_error_norm_m);
validTruthWind = isfinite(audit.truth_wind_error_norm_mps);

lines = strings(0, 1);
lines(end+1) = "3D / Wind Summary";
lines(end+1) = sprintf('Rows: %d | duration: %.3f s', height(audit), sum(dt, 'omitnan'));
lines(end+1) = sprintf('GPS accepted/rejected samples: %d / %d', nnz(audit.gps_used), nnz(audit.gps_rejected));
lines(end+1) = sprintf('GPS position samples: %d | velocity samples: %d', ...
    nnz(audit.gps_position_available), nnz(audit.gps_velocity_available));
lines(end+1) = sprintf('Final position: [%.2f %.2f %.2f] m', ...
    localLastFinite(audit.px_m), localLastFinite(audit.py_m), localLastFinite(audit.pz_m));
lines(end+1) = sprintf('Final wind: [%.2f %.2f %.2f] m/s | speed %.2f m/s', ...
    localLastFinite(audit.wx_mps), localLastFinite(audit.wy_mps), ...
    localLastFinite(audit.wz_mps), localLastFinite(audit.wind_speed_mps));
lines(end+1) = sprintf('Max position sigma norm: %.3f m', max(audit.position_sigma_norm_m, [], 'omitnan'));
lines(end+1) = sprintf('Max wind sigma norm: %.3f m/s', max(audit.wind_sigma_norm_mps, [], 'omitnan'));
if any(validTruthPosition)
    lines(end+1) = sprintf('Truth position RMSE norm: %.3f m', ...
        sqrt(mean(audit.truth_position_error_norm_m(validTruthPosition).^2, 'omitnan')));
end
if any(validTruthWind)
    lines(end+1) = sprintf('Final truth wind error: %.3f m/s', ...
        localLastFinite(audit.truth_wind_error_norm_mps));
end

labels = unique(audit.evidence_label, 'stable');
labelCounts = strings(numel(labels), 1);
for k = 1:numel(labels)
    labelCounts(k) = sprintf('%s=%d', labels(k), nnz(audit.evidence_label == labels(k)));
end
lines(end+1) = "Evidence labels: " + strjoin(labelCounts, "; ");

idx = find(audit.evidence_label ~= "", 1, 'last');
if ~isempty(idx)
    lines(end+1) = "Final label: " + audit.evidence_label(idx);
    lines(end+1) = "Final rationale: " + audit.evidence_rationale(idx);
end

text(ax, 0.02, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'FontSize', 8, ...
    'Interpreter', 'none');
end

function labels = localEvidenceTickLabels()
labels = { ...
    'state incomplete', ...
    'covariance incomplete', ...
    'GPS rejected', ...
    'GPS pos residual high', ...
    'GPS vel residual high', ...
    'position uncertainty high', ...
    'wind uncertainty high', ...
    'GPS update used', ...
    'GPS measurement not used', ...
    'inertial only'};
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

function scale = localWindVectorScale(audit, idx)
span = max([ ...
    localFiniteRange(audit.px_m), ...
    localFiniteRange(audit.py_m), ...
    localFiniteRange(audit.pz_m)]);
maxWind = max(audit.wind_speed_mps(idx), [], 'omitnan');
if ~isfinite(span) || span <= 0
    span = 1;
end
if ~isfinite(maxWind) || maxWind <= 0
    scale = 1;
else
    scale = 0.10 * span / maxWind;
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

function value = localLastFinite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
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
theme.gpsColor = [0.88 0.88 0.36];
theme.acceptColor = [0.20 0.75 0.42];
theme.windColor = [0.78 0.42 0.86];
theme.tubeColor = [0.20 0.55 0.80];
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

function fig = plotEstimatorTrustDashboard(audit, cfg)
%PLOTESTIMATORTRUSTDASHBOARD Plot vertical estimator trust evidence.
arguments
    audit table
    cfg struct = caelum.defaultConfig()
end

if isempty(audit) || height(audit) < 1
    error('caelum:plotEstimatorTrustDashboard:EmptyAudit', ...
        'Estimator trust audit table must contain at least one row.');
end

required = [ ...
    "t", ...
    "baro_alt_m", ...
    "logged_h_m", ...
    "logged_v_mps", ...
    "replay_h_m", ...
    "replay_v_mps", ...
    "replay_sigma_h_m", ...
    "replay_sigma_v_mps", ...
    "innovation_h_m", ...
    "innovation_sigma_h_m", ...
    "innovation_nis", ...
    "baro_used", ...
    "baro_rejected", ...
    "logged_minus_replay_h_m", ...
    "logged_minus_replay_v_mps", ...
    "replay_b_a_mps2", ...
    "replay_beta", ...
    "trust_code", ...
    "trust_label", ...
    "trust_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames));
if ~isempty(missing)
    error('caelum:plotEstimatorTrustDashboard:MissingAuditFields', ...
        'Estimator trust audit table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

theme = localTheme();
fig = figure('Name', 'Caelum Estimator Trust Dashboard', ...
    'Color', theme.figureColor, ...
    'Units', 'normalized', ...
    'Position', [0.04 0.07 0.92 0.84]);

tl = tiledlayout(fig, 5, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
hTitle = title(tl, 'Estimator Trust / Innovation Consistency Dashboard');
hTitle.Color = theme.textColor;

axAlt = nexttile(tl, 1, [1 2]);
localPlotAltitudeConsistency(axAlt, audit, theme);

axVel = nexttile(tl, 3);
localPlotVelocityConsistency(axVel, audit, theme);

axInnov = nexttile(tl, 4);
localPlotInnovation(axInnov, audit, cfg);

axGate = nexttile(tl, 5);
localPlotUpdateRaster(axGate, audit);

axBias = nexttile(tl, 6);
localPlotBiasBeta(axBias, audit);

axDelta = nexttile(tl, 7);
localPlotLoggedReplayDelta(axDelta, audit);

axTrust = nexttile(tl, 8);
localPlotTrustLabels(axTrust, audit);

axSummary = nexttile(tl, 9, [1 2]);
localPlotSummary(axSummary, audit);

localApplyStyle(fig, theme);
end

function localPlotAltitudeConsistency(ax, audit, theme)
t = audit.t;
sigma = audit.replay_sigma_h_m;
upper = audit.replay_h_m + 3 .* sigma;
lower = audit.replay_h_m - 3 .* sigma;
validBand = isfinite(t) & isfinite(upper) & isfinite(lower);

hold(ax, 'on');
if any(validBand)
    fill(ax, [t(validBand); flipud(t(validBand))], ...
        [lower(validBand); flipud(upper(validBand))], ...
        theme.bandColor, ...
        'FaceAlpha', 0.20, ...
        'EdgeColor', 'none', ...
        'DisplayName', 'replay +/- 3 sigma');
end
plot(ax, t, audit.baro_alt_m, ':', 'LineWidth', 1.0, 'DisplayName', 'baro altitude');
plot(ax, t, audit.logged_h_m, 'LineWidth', 1.1, 'DisplayName', 'logged firmware h');
plot(ax, t, audit.replay_h_m, '--', 'LineWidth', 1.1, 'DisplayName', 'MATLAB replay h');

if ismember("truth_h_m", string(audit.Properties.VariableNames)) && any(isfinite(audit.truth_h_m))
    plot(ax, t, audit.truth_h_m, '-.', 'LineWidth', 1.0, 'DisplayName', 'truth h');
end

xlabel(ax, 't [s]');
ylabel(ax, 'altitude [m]');
title(ax, 'Altitude Consistency');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotVelocityConsistency(ax, audit, theme)
t = audit.t;
sigma = audit.replay_sigma_v_mps;
upper = audit.replay_v_mps + 3 .* sigma;
lower = audit.replay_v_mps - 3 .* sigma;
validBand = isfinite(t) & isfinite(upper) & isfinite(lower);

hold(ax, 'on');
if any(validBand)
    fill(ax, [t(validBand); flipud(t(validBand))], ...
        [lower(validBand); flipud(upper(validBand))], ...
        theme.bandColor, ...
        'FaceAlpha', 0.20, ...
        'EdgeColor', 'none', ...
        'DisplayName', 'replay +/- 3 sigma');
end
plot(ax, t, audit.logged_v_mps, 'LineWidth', 1.1, 'DisplayName', 'logged firmware v');
plot(ax, t, audit.replay_v_mps, '--', 'LineWidth', 1.1, 'DisplayName', 'MATLAB replay v');

if ismember("truth_v_mps", string(audit.Properties.VariableNames)) && any(isfinite(audit.truth_v_mps))
    plot(ax, t, audit.truth_v_mps, '-.', 'LineWidth', 1.0, 'DisplayName', 'truth v');
end

xlabel(ax, 't [s]');
ylabel(ax, 'velocity [m/s]');
title(ax, 'Velocity Consistency');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotInnovation(ax, audit, cfg)
hold(ax, 'on');

yyaxis(ax, 'left');
plot(ax, audit.t, audit.innovation_h_m, 'LineWidth', 1.0, 'DisplayName', 'innovation h');
plot(ax, audit.t, 3 .* audit.innovation_sigma_h_m, '--', 'LineWidth', 1.0, 'DisplayName', '+3 sigma');
plot(ax, audit.t, -3 .* audit.innovation_sigma_h_m, '--', 'LineWidth', 1.0, 'DisplayName', '-3 sigma');
ylabel(ax, 'innovation [m]');

yyaxis(ax, 'right');
plot(ax, audit.t, audit.innovation_nis, ':', 'LineWidth', 1.0, 'DisplayName', 'NIS');
gate = localConfigScalar(cfg, "kBaroNISGate", NaN);
if isfinite(gate)
    yline(ax, gate, '--', 'DisplayName', 'NIS gate');
end
ylabel(ax, 'NIS');

xlabel(ax, 't [s]');
title(ax, 'Innovation / NIS Gate');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotUpdateRaster(ax, audit)
hold(ax, 'on');
stairs(ax, audit.t, double(audit.baro_used), 'LineWidth', 1.1, 'DisplayName', 'baro used');
stairs(ax, audit.t, 0.5 .* double(audit.baro_rejected), 'LineWidth', 1.1, 'DisplayName', 'baro rejected');
if ismember("sample_gap", string(audit.Properties.VariableNames))
    stairs(ax, audit.t, -0.4 .* double(audit.sample_gap), ':', 'LineWidth', 1.0, 'DisplayName', 'sample gap');
end
ylim(ax, [-0.55 1.15]);
xlabel(ax, 't [s]');
ylabel(ax, 'flag');
title(ax, 'Measurement Update Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotBiasBeta(ax, audit)
hold(ax, 'on');
yyaxis(ax, 'left');
plot(ax, audit.t, audit.replay_b_a_mps2, 'LineWidth', 1.0, 'DisplayName', 'accel bias');
if ismember("replay_sigma_b_a_mps2", string(audit.Properties.VariableNames))
    plot(ax, audit.t, audit.replay_sigma_b_a_mps2, '--', 'LineWidth', 1.0, 'DisplayName', 'sigma bias');
end
ylabel(ax, 'bias [m/s^2]');

yyaxis(ax, 'right');
plot(ax, audit.t, audit.replay_beta, 'LineWidth', 1.0, 'DisplayName', 'beta');
if ismember("replay_sigma_beta", string(audit.Properties.VariableNames))
    plot(ax, audit.t, audit.replay_sigma_beta, '--', 'LineWidth', 1.0, 'DisplayName', 'sigma beta');
end
ylabel(ax, 'beta');

xlabel(ax, 't [s]');
title(ax, 'Bias / Drag State');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotLoggedReplayDelta(ax, audit)
hold(ax, 'on');
plot(ax, audit.t, audit.logged_minus_replay_h_m, 'LineWidth', 1.0, 'DisplayName', 'logged - replay h');
yyaxis(ax, 'right');
plot(ax, audit.t, audit.logged_minus_replay_v_mps, '--', 'LineWidth', 1.0, 'DisplayName', 'logged - replay v');
ylabel(ax, 'velocity delta [m/s]');
yyaxis(ax, 'left');
ylabel(ax, 'altitude delta [m]');

if ismember("replay_truth_error_h_m", string(audit.Properties.VariableNames)) && any(isfinite(audit.replay_truth_error_h_m))
    plot(ax, audit.t, audit.replay_truth_error_h_m, ':', 'LineWidth', 1.0, 'DisplayName', 'replay - truth h');
end

xlabel(ax, 't [s]');
title(ax, 'State Delta Evidence');
grid(ax, 'on');
legend(ax, 'Location', 'best');
end

function localPlotTrustLabels(ax, audit)
stairs(ax, audit.t, audit.trust_code, ...
    'LineWidth', 1.2, ...
    'DisplayName', 'trust evidence label');
yticks(ax, 1:9);
yticklabels(ax, localTrustTickLabels());
ylim(ax, [0.5 9.5]);
xlabel(ax, 't [s]');
title(ax, 'Trust Classification');
grid(ax, 'on');
end

function labels = localTrustTickLabels()
labels = { ...
    'replay incomplete', ...
    'sample gap', ...
    'baro rejected', ...
    'NIS gate exceeded', ...
    'innovation outside band', ...
    'logged/replay divergent', ...
    'truth error high', ...
    'trusted update', ...
    'predict only'};
end

function localPlotSummary(ax, audit)
axis(ax, [0 1 0 1]);
axis(ax, 'off');

validInnovation = isfinite(audit.innovation_h_m);
validNis = isfinite(audit.innovation_nis);
coverage3 = mean(double(audit.innovation_within_sigma_band(validInnovation)), 'omitnan');
acceptance = mean(double(audit.baro_used(validInnovation)), 'omitnan');
rejection = mean(double(audit.baro_rejected(validInnovation)), 'omitnan');
meanNis = mean(audit.innovation_nis(validNis), 'omitnan');
rmseLoggedReplayH = sqrt(mean(audit.logged_minus_replay_h_m.^2, 'omitnan'));
rmseLoggedReplayV = sqrt(mean(audit.logged_minus_replay_v_mps.^2, 'omitnan'));
rmseTruthH = sqrt(mean(audit.replay_truth_error_h_m.^2, 'omitnan'));
rmseTruthV = sqrt(mean(audit.replay_truth_error_v_mps.^2, 'omitnan'));

lines = strings(0, 1);
lines(end+1) = "Trust Summary";
lines(end+1) = sprintf('Rows: %d | innovation samples: %d', height(audit), nnz(validInnovation));
lines(end+1) = sprintf('3-sigma innovation coverage: %.3f', coverage3);
lines(end+1) = sprintf('Mean NIS: %.3f', meanNis);
lines(end+1) = sprintf('Baro acceptance/rejection: %.3f / %.3f', acceptance, rejection);
lines(end+1) = sprintf('Logged-vs-replay RMSE: h=%.3f m, v=%.3f m/s', ...
    rmseLoggedReplayH, rmseLoggedReplayV);
if isfinite(rmseTruthH) || isfinite(rmseTruthV)
    lines(end+1) = sprintf('Replay-vs-truth RMSE: h=%.3f m, v=%.3f m/s', ...
        rmseTruthH, rmseTruthV);
end

labels = unique(audit.trust_label, 'stable');
labelCounts = strings(numel(labels), 1);
for k = 1:numel(labels)
    labelCounts(k) = sprintf('%s=%d', labels(k), nnz(audit.trust_label == labels(k)));
end
lines(end+1) = "Trust labels: " + strjoin(labelCounts, "; ");

idx = find(audit.trust_label ~= "", 1, 'last');
if ~isempty(idx)
    lines(end+1) = "Final label: " + audit.trust_label(idx);
    lines(end+1) = "Final rationale: " + audit.trust_rationale(idx);
end

text(ax, 0.02, 0.96, strjoin(lines, newline), ...
    'VerticalAlignment', 'top', ...
    'FontName', 'Consolas', ...
    'Interpreter', 'none');
end

function value = localConfigScalar(cfg, fieldName, defaultValue)
if isstruct(cfg) && isfield(cfg, fieldName) && isfinite(cfg.(fieldName))
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end

function theme = localTheme()
theme.figureColor = [0.07 0.08 0.09];
theme.axesColor = [0.06 0.06 0.06];
theme.textColor = [0.92 0.92 0.92];
theme.gridColor = [0.38 0.38 0.38];
theme.panelEdgeColor = [0.28 0.31 0.34];
theme.bandColor = [0.20 0.55 0.80];
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

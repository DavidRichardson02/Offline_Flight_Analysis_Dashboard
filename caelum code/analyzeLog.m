function results = analyzeLog(filename, options)
%ANALYZELOG Canonical V3 end-to-end analysis with optional GPS fusion, 3D state, and wind.
arguments
    filename (1,1) string
    options.MakePlots (1,1) logical = true
    options.ReplayEstimator (1,1) logical = true
    options.Config struct = caelum.defaultConfig()
    options.MakeDashboard (1,1) logical = true
    options.Truth struct = struct()
    options.ExportFigures (1,1) logical = false
    options.ExportDir (1,1) string = "exports"
end

cfg = caelum.localResolve3DConfig(options.Config);

strictError = [];
try
    [raw, importReport] = caelum.importLog(filename);
catch ME
    strictError = ME;
    [raw, importReport] = caelum.importLogRobust(filename);
end

raw = caelum.alignImportedSchema(raw, cfg);

[clean, cleanReport] = caelum.cleanLog(raw, cfg);
events = caelum.detectEvents(clean, cfg);

attitude = table();
attitudeMetrics = struct();
if isfield(cfg, 'enableAttitudeReplay') && cfg.enableAttitudeReplay
    attitude = caelum.runAttitudeReplay(clean, cfg);
    [clean, attitude] = caelum.attachPhase1AttitudeFields(clean, attitude);
    clean = localAttachAttitudeFields(clean, attitude);

    attitudeMetrics.gravity_update_fraction = mean(double(attitude.gravity_update_used), 'omitnan');
    attitudeMetrics.gravity_innovation_rms = sqrt(mean(attitude.gravity_innovation.^2, 'omitnan'));
    attitudeMetrics.gravity_residual_rms_mps2 = sqrt(mean(attitude.gravity_residual.^2, 'omitnan'));
    attitudeMetrics.final_roll_deg = localLastFinite(attitude.roll_deg);
    attitudeMetrics.final_pitch_deg = localLastFinite(attitude.pitch_deg);
    attitudeMetrics.final_yaw_deg = localLastFinite(attitude.yaw_deg);
    attitudeMetrics.final_gyro_bias_x_rps = localLastFinite(attitude.b_gx);
    attitudeMetrics.final_gyro_bias_y_rps = localLastFinite(attitude.b_gy);
    attitudeMetrics.final_gyro_bias_z_rps = localLastFinite(attitude.b_gz);
end

if options.ReplayEstimator
    replay = caelum.replayEstimator(clean, cfg);
else
    replay = table();
end

truth = options.Truth;
truthError = struct();
truthMetrics = struct();
consistencyMetrics = struct();
h_replay_interp = [];
v_replay_interp = [];

if ~isempty(replay)
    replayVarNames = string(replay.Properties.VariableNames);
else
    replayVarNames = strings(0,1);
end

if ~isempty(replay) && all(ismember(["innovation_h","innovation_sigma_h","innovation_nis"], replayVarNames))
    consistencyMetrics.replay_innovation_bias_m = mean(replay.innovation_h, 'omitnan');
    consistencyMetrics.replay_innovation_rmse_m = sqrt(mean(replay.innovation_h.^2, 'omitnan'));
    consistencyMetrics.replay_innovation_coverage_3sigma = localCoverage( ...
        replay.innovation_h, replay.innovation_sigma_h, ...
        cfg.consistencySigmaThreshold, cfg.consistencyMinSigma);
    consistencyMetrics.replay_mean_nis = mean(replay.innovation_nis, 'omitnan');
end

if ~isempty(replay) && all(ismember(["innovation_h","baro_used","baro_rejected"], replayVarNames))
    baroAttemptMask = isfinite(replay.innovation_h);
    consistencyMetrics.replay_num_baro_attempts = nnz(baroAttemptMask);
    consistencyMetrics.replay_num_baro_rejections = sum(double(replay.baro_rejected(baroAttemptMask)), 'omitnan');
    if any(baroAttemptMask)
        consistencyMetrics.replay_baro_acceptance_rate = mean(double(replay.baro_used(baroAttemptMask)), 'omitnan');
        consistencyMetrics.replay_baro_rejection_rate = mean(double(replay.baro_rejected(baroAttemptMask)), 'omitnan');
    else
        consistencyMetrics.replay_baro_acceptance_rate = NaN;
        consistencyMetrics.replay_baro_rejection_rate = NaN;
    end
end

if ~isempty(replay) && ismember("b_a", replayVarNames)
    consistencyMetrics.replay_final_accel_bias_mps2 = localLastFinite(replay.b_a);
    consistencyMetrics.replay_mean_accel_bias_mps2 = mean(replay.b_a, 'omitnan');
    if ismember("sigma_b_a", replayVarNames)
        consistencyMetrics.replay_final_accel_bias_sigma_mps2 = localLastFinite(replay.sigma_b_a);
    end
end

if ~isempty(replay) && ismember("beta", replayVarNames)
    consistencyMetrics.replay_final_beta = localLastFinite(replay.beta);
    consistencyMetrics.replay_mean_beta = mean(replay.beta, 'omitnan');
    if ismember("sigma_beta", replayVarNames)
        consistencyMetrics.replay_final_beta_sigma = localLastFinite(replay.sigma_beta);
    end
end

if ~isempty(replay) && ismember("beta_learning_enabled", replayVarNames)
    consistencyMetrics.replay_beta_learning_fraction = mean(double(replay.beta_learning_enabled), 'omitnan');
end
consistencyMetrics.replay_baro_gate_threshold_nis = cfg.kBaroNISGate;

if ~isempty(attitude)
    consistencyMetrics.attitude_gravity_update_fraction = localGetMetric(attitudeMetrics, 'gravity_update_fraction');
    consistencyMetrics.attitude_gravity_innovation_rms = localGetMetric(attitudeMetrics, 'gravity_innovation_rms');
    consistencyMetrics.attitude_gravity_residual_rms_mps2 = localGetMetric(attitudeMetrics, 'gravity_residual_rms_mps2');
end

if ~isempty(fieldnames(truth)) && isfield(truth, 't') && isfield(truth, 'h_true') && isfield(truth, 'v_true')
    h_true_interp = interp1(truth.t, truth.h_true, clean.t, 'linear', NaN);
    v_true_interp = interp1(truth.t, truth.v_true, clean.t, 'linear', NaN);

    truthError.h_logged = clean.kf_h - h_true_interp;
    truthError.v_logged = clean.kf_v - v_true_interp;
    truthMetrics.rmse_h_logged = sqrt(mean(truthError.h_logged.^2, 'omitnan'));
    truthMetrics.rmse_v_logged = sqrt(mean(truthError.v_logged.^2, 'omitnan'));
    truthMetrics.mae_h_logged = mean(abs(truthError.h_logged), 'omitnan');
    truthMetrics.mae_v_logged = mean(abs(truthError.v_logged), 'omitnan');

    if ~isempty(replay) && all(ismember(["t","h","v"], replayVarNames))
        h_replay_interp = interp1(replay.t, replay.h, clean.t, 'linear', NaN);
        v_replay_interp = interp1(replay.t, replay.v, clean.t, 'linear', NaN);
        truthError.h_replay = h_replay_interp - h_true_interp;
        truthError.v_replay = v_replay_interp - v_true_interp;
        truthMetrics.rmse_h_replay = sqrt(mean(truthError.h_replay.^2, 'omitnan'));
        truthMetrics.rmse_v_replay = sqrt(mean(truthError.v_replay.^2, 'omitnan'));
        truthMetrics.mae_h_replay = mean(abs(truthError.h_replay), 'omitnan');
        truthMetrics.mae_v_replay = mean(abs(truthError.v_replay), 'omitnan');
    end
end

cfg.truth = truth;
cfg.truthMetrics = truthMetrics;
cfg.consistencyMetrics = consistencyMetrics;
cfg.attitudeMetrics = attitudeMetrics;

summary = caelum.summarizeLog(clean, events, cfg);
summaryTable = caelum.makeSummaryTable(summary);

% Canonical V3 3D/GPS layer
vars = string(clean.Properties.VariableNames);
hasGpsPos = all(ismember(["gps_x","gps_y","gps_z"], vars));
hasGpsVel = all(ismember(["gps_vx","gps_vy","gps_vz"], vars));
if (hasGpsPos || hasGpsVel) && cfg.enable3DReplay
    if ~all(ismember(["q_w","q_x","q_y","q_z"], vars))
        attitude3 = caelum.runAttitudeReplay(clean, cfg);
        clean.q_w = interp1(attitude3.t, attitude3.q_w, clean.t, 'linear', 1);
        clean.q_x = interp1(attitude3.t, attitude3.q_x, clean.t, 'linear', 0);
        clean.q_y = interp1(attitude3.t, attitude3.q_y, clean.t, 'linear', 0);
        clean.q_z = interp1(attitude3.t, attitude3.q_z, clean.t, 'linear', 0);
    end
    est3d = caelum.run3DEKF(clean, cfg);
    wind = caelum.estimateWind(est3d);
else
    est3d = table();
    wind = struct('mean',[NaN NaN NaN], 'final',[NaN NaN NaN], 'speedMean',NaN, 'speedFinal',NaN);
end

if options.MakePlots
    figs = caelum.plotOverview(clean, events, replay);
    figs3D = caelum.plotOverview3D(est3d, clean);
else
    figs = gobjects(0, 1);
    figs3D = gobjects(0, 1);
end

if options.MakeDashboard
    dashboardFigure = caelum.plotDashboard(clean, events, replay, cfg);
else
    dashboardFigure = gobjects(0, 1);
end

importReport.strictImportFailed = ~isempty(strictError);
if isempty(strictError)
    importReport.strictImportErrorIdentifier = "";
    importReport.strictImportErrorMessage = "";
else
    importReport.strictImportErrorIdentifier = string(strictError.identifier);
    importReport.strictImportErrorMessage = string(strictError.message);
end

importReport.nonmonotonicTimestampsRemoved = cleanReport.nonmonotonicTimestampsRemoved;
importReport.duplicateTimestampsRemoved = cleanReport.duplicateTimestampsRemoved;
importReport.rowsRemovedMissingTimestamp = cleanReport.rowsRemovedMissingTimestamp;
importReport.rowsBeforeCleaning = cleanReport.rowsBeforeCleaning;
importReport.rowsAfterCleaning = cleanReport.rowsAfterCleaning;

results = struct();
results.filename = filename;
results.config = cfg;
results.raw = raw;
results.data = clean;
results.events = events;
results.replay = replay;
results.attitude = attitude;
results.summary = summary;
results.summaryTable = summaryTable;
results.figures = figs;
results.figures3D = figs3D;
results.dashboardFigure = dashboardFigure;
results.importReport = importReport;
results.cleanReport = cleanReport;
results.truth = truth;
results.truthError = truthError;
results.truthMetrics = truthMetrics;
results.consistencyMetrics = consistencyMetrics;
results.attitudeMetrics = attitudeMetrics;
results.est3d = est3d;
results.wind = wind;
results.exportInfo = struct();

if options.ExportFigures
    results.exportInfo = caelum.exportFigures(results, options.ExportDir);
end
end

function coverage = localCoverage(err, sigma, sigmaThreshold, minSigma)
valid = isfinite(err) & isfinite(sigma) & (sigma > minSigma);
if ~any(valid), coverage = NaN; return; end
coverage = mean(abs(err(valid)) <= sigmaThreshold * sigma(valid));
end

function value = localLastFinite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx), value = NaN; else, value = x(idx); end
end

function value = localGetMetric(s, name)
if isfield(s, name) && ~isempty(s.(name)), value = s.(name); else, value = NaN; end
end

function T = localAttachAttitudeFields(T, attitude)
if isempty(attitude), return; end
fieldNames = ["a_vertical_attitude","roll_deg","pitch_deg","yaw_deg","b_gx","b_gy","b_gz","gravity_update_used","gravity_innovation","gravity_residual","tilt_error_deg"];
for k = 1:numel(fieldNames)
    fieldName = fieldNames(k);
    if ~ismember(fieldName, string(attitude.Properties.VariableNames)), continue; end
    if fieldName == "gravity_update_used"
        values = interp1(attitude.t, double(attitude.(char(fieldName))), T.t, 'nearest', 0);
        T.(char(fieldName)) = logical(values > 0.5);
    else
        T.(char(fieldName)) = interp1(attitude.t, attitude.(char(fieldName)), T.t, 'linear', NaN);
    end
end
end

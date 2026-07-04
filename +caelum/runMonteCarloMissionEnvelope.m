function mc = runMonteCarloMissionEnvelope(outputDir, options)
%RUNMONTECARLOMISSIONENVELOPE Generate mission-envelope Monte Carlo evidence.
%
% Runs use deterministic input perturbations around the truth-aware synthetic
% flight generator. Each run records the input knobs and mission outcomes so
% downstream sensitivity calculations remain reproducible and reviewable.
arguments
    outputDir (1,1) string = fullfile("exports", "monte_carlo_mission_envelope", "logs")
    options.NumRuns (1,1) double {mustBeInteger,mustBePositive} = 24
    options.Seed (1,1) double = 700
    options.SaveLogs (1,1) logical = true
    options.MakePlots (1,1) logical = false
    options.MakeDashboard (1,1) logical = false
    options.Config struct = caelum.defaultConfig()
end

if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

cfg = caelum.localResolve3DConfig(options.Config);
runMetrics = localEmptyRunMetrics(options.NumRuns);

for k = 1:options.NumRuns
    params = localDesignRunParameters(k, options.NumRuns, options.Seed);
    file = fullfile(outputDir, sprintf('MC_ENV_%03d.csv', k));
    startedAt = tic;

    runMetrics = localWriteParameters(runMetrics, k, params, file);
    try
        [~, truth] = caelum.generateTruthAwareCaelumLogV2(file, ...
            seed=params.seed, ...
            duration_s=params.duration_s, ...
            launchDelay_s=params.launchDelay_s, ...
            boostDuration_s=params.boostDuration_s, ...
            boostAccel_mps2=params.boostAccel_mps2, ...
            dragCoeff=params.dragCoeff, ...
            baroAltNoise_m=params.baroAltNoise_m, ...
            accelNoise_mps2=params.accelNoise_mps2, ...
            gyroNoise_rps=params.gyroNoise_rps, ...
            gpsRateHz=params.gpsRateHz, ...
            windXYZ=[params.wind_x_mps params.wind_y_mps params.wind_z_mps], ...
            addTimingJitter=params.timingJitterStd_s > 0, ...
            timingJitterStd_s=params.timingJitterStd_s, ...
            addNaNs=params.nanFraction > 0, ...
            nanFraction=params.nanFraction, ...
            addDropouts=params.dropoutFraction > 0, ...
            dropoutFraction=params.dropoutFraction);

        results = caelum.analyzeLog(file, ...
            MakePlots=options.MakePlots, ...
            MakeDashboard=options.MakeDashboard, ...
            Truth=truth, ...
            Config=cfg);

        runMetrics.success(k) = true;
        runMetrics.status(k) = "ok";
        runMetrics = localWriteOutcomeMetrics(runMetrics, k, results, truth, cfg);
    catch ME
        runMetrics.success(k) = false;
        runMetrics.status(k) = string(ME.identifier);
        if strlength(runMetrics.status(k)) == 0
            runMetrics.status(k) = "error";
        end
    end

    runMetrics.analysisTime_s(k) = toc(startedAt);
    if ~options.SaveLogs && isfile(file)
        delete(file);
    end
end

[envelopeAudit, sensitivity] = caelum.buildMonteCarloMissionEnvelopeAudit(runMetrics, cfg);

mc = struct();
mc.outputDir = outputDir;
mc.runMetrics = runMetrics;
mc.envelopeAudit = envelopeAudit;
mc.sensitivity = sensitivity;
mc.aggregate = localAggregate(envelopeAudit);
end

function T = localEmptyRunMetrics(numRuns)
varNames = { ...
    'runIndex','success','status','logPath','seed', ...
    'duration_s','launchDelay_s','boostDuration_s','boostAccel_mps2','dragCoeff', ...
    'baroAltNoise_m','accelNoise_mps2','gyroNoise_rps','gpsRateHz', ...
    'wind_x_mps','wind_y_mps','wind_z_mps','wind_speed_mps', ...
    'timingJitterStd_s','nanFraction','dropoutFraction', ...
    'truth_peak_altitude_m','truth_apogee_time_s','truth_landing_time_s', ...
    'logged_peak_altitude_m','baro_peak_altitude_m','replay_peak_altitude_m','est3d_peak_z_m', ...
    'detected_apogee_time_s','detected_landing_time_s', ...
    'peak_altitude_error_m','detected_apogee_time_error_s','detected_landing_time_error_s', ...
    'rmse_h_m','rmse_v_mps','rmse_pz_m','rmse_vz_mps', ...
    'gpsAcceptanceRate','gpsRejectionRate','windError_mps','finalPositionError_m', ...
    'maxPositionSigma_m','maxWindSigma_m','maxPolicyCommand','analysisTime_s'};
varTypes = { ...
    'double','logical','string','string','double', ...
    'double','double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double', ...
    'double','double','double', ...
    'double','double','double','double', ...
    'double','double', ...
    'double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double', ...
    'double','double','double','double'};
T = table('Size', [numRuns numel(varNames)], ...
    'VariableTypes', varTypes, ...
    'VariableNames', varNames);

T.success(:) = false;
T.status(:) = "";
T.logPath(:) = "";
numericVars = setdiff(string(varNames), ["success","status","logPath"], 'stable');
for k = 1:numel(numericVars)
    name = numericVars(k);
    T.(char(name))(:) = NaN;
end
end

function params = localDesignRunParameters(runIndex, numRuns, seed)
rng(seed + 1000 * runIndex);
gpsRates = [2 5 10 20];

params = struct();
params.runIndex = runIndex;
params.seed = seed + runIndex - 1;
params.duration_s = 14.0;
params.launchDelay_s = 0.8 + 0.4 * rand();
params.boostDuration_s = 1.0 + 0.5 * rand();
params.boostAccel_mps2 = 16.0 + 8.0 * rand();
params.dragCoeff = 0.014 + 0.014 * rand();
params.baroAltNoise_m = 0.10 + 0.65 * rand();
params.accelNoise_mps2 = 0.06 + 0.35 * rand();
params.gyroNoise_rps = 0.008 + 0.045 * rand();
params.gpsRateHz = gpsRates(1 + mod(runIndex - 1, numel(gpsRates)));
params.wind_x_mps = -2.5 + 5.0 * rand();
params.wind_y_mps = -2.5 + 5.0 * rand();
params.wind_z_mps = -0.5 + 1.0 * rand();
params.wind_speed_mps = norm([params.wind_x_mps params.wind_y_mps params.wind_z_mps]);
params.timingJitterStd_s = 0.0030 * rand();
params.nanFraction = 0.020 * rand();
params.dropoutFraction = 0.030 * rand();

% Ensure the design includes at least one near-clean and one degraded corner.
if runIndex == 1
    params.baroAltNoise_m = 0.10;
    params.accelNoise_mps2 = 0.06;
    params.gyroNoise_rps = 0.008;
    params.gpsRateHz = 20;
    params.timingJitterStd_s = 0;
    params.nanFraction = 0;
    params.dropoutFraction = 0;
elseif runIndex == numRuns
    params.baroAltNoise_m = 0.75;
    params.accelNoise_mps2 = 0.41;
    params.gyroNoise_rps = 0.053;
    params.gpsRateHz = 2;
    params.timingJitterStd_s = 0.0030;
    params.nanFraction = 0.020;
    params.dropoutFraction = 0.030;
end
end

function T = localWriteParameters(T, idx, params, file)
T.runIndex(idx) = params.runIndex;
T.logPath(idx) = string(file);
T.seed(idx) = params.seed;
T.duration_s(idx) = params.duration_s;
T.launchDelay_s(idx) = params.launchDelay_s;
T.boostDuration_s(idx) = params.boostDuration_s;
T.boostAccel_mps2(idx) = params.boostAccel_mps2;
T.dragCoeff(idx) = params.dragCoeff;
T.baroAltNoise_m(idx) = params.baroAltNoise_m;
T.accelNoise_mps2(idx) = params.accelNoise_mps2;
T.gyroNoise_rps(idx) = params.gyroNoise_rps;
T.gpsRateHz(idx) = params.gpsRateHz;
T.wind_x_mps(idx) = params.wind_x_mps;
T.wind_y_mps(idx) = params.wind_y_mps;
T.wind_z_mps(idx) = params.wind_z_mps;
T.wind_speed_mps(idx) = params.wind_speed_mps;
T.timingJitterStd_s(idx) = params.timingJitterStd_s;
T.nanFraction(idx) = params.nanFraction;
T.dropoutFraction(idx) = params.dropoutFraction;
end

function T = localWriteOutcomeMetrics(T, idx, results, truth, cfg)
clean = results.data;
events = results.events;

[truthPeakAltitude, truthApogeeTime] = localPeakMetric(truth.t, truth.h_true);
truthLandingTime = localTruthLandingTime(truth);

T.truth_peak_altitude_m(idx) = truthPeakAltitude;
T.truth_apogee_time_s(idx) = truthApogeeTime;
T.truth_landing_time_s(idx) = truthLandingTime;
T.logged_peak_altitude_m(idx) = max(clean.kf_h, [], 'omitnan');
T.baro_peak_altitude_m(idx) = max(clean.bmp_alt_rel, [], 'omitnan');
T.detected_apogee_time_s(idx) = events.apogeeTime_s;
T.detected_landing_time_s(idx) = events.landingTime_s;
T.peak_altitude_error_m(idx) = T.logged_peak_altitude_m(idx) - truthPeakAltitude;
T.detected_apogee_time_error_s(idx) = events.apogeeTime_s - truthApogeeTime;
T.detected_landing_time_error_s(idx) = events.landingTime_s - truthLandingTime;

hTruthClean = interp1(truth.t, truth.h_true, clean.t, 'linear', NaN);
vTruthClean = interp1(truth.t, truth.v_true, clean.t, 'linear', NaN);
T.rmse_h_m(idx) = localRmse(clean.kf_h - hTruthClean);
T.rmse_v_mps(idx) = localRmse(clean.kf_v - vTruthClean);

if isfield(results, 'replay') && istable(results.replay) && ~isempty(results.replay)
    replay = results.replay;
    T.replay_peak_altitude_m(idx) = max(replay.h, [], 'omitnan');
end

if isfield(results, 'est3d') && istable(results.est3d) && ~isempty(results.est3d)
    est3d = results.est3d;
    zTruth = interp1(truth.t, truth.z_true, est3d.t, 'linear', NaN);
    vzTruth = interp1(truth.t, truth.v_true, est3d.t, 'linear', NaN);
    T.est3d_peak_z_m(idx) = max(est3d.pz, [], 'omitnan');
    T.rmse_pz_m(idx) = localRmse(est3d.pz - zTruth);
    T.rmse_vz_mps(idx) = localRmse(est3d.vz - vzTruth);
    T.gpsAcceptanceRate(idx) = mean(double(est3d.gps_used), 'omitnan');
    T.gpsRejectionRate(idx) = mean(double(est3d.gps_rejected), 'omitnan');
    T.maxPositionSigma_m(idx) = max(localVectorNorm(est3d.sigma_px, est3d.sigma_py, est3d.sigma_pz), [], 'omitnan');
    T.maxWindSigma_m(idx) = max(localVectorNorm(est3d.sigma_wx, est3d.sigma_wy, est3d.sigma_wz), [], 'omitnan');

    finalIdx = find(all(isfinite([est3d.px est3d.py est3d.pz]), 2), 1, 'last');
    if ~isempty(finalIdx)
        truthX = interp1(truth.t, truth.x_true, est3d.t(finalIdx), 'linear', NaN);
        truthY = interp1(truth.t, truth.y_true, est3d.t(finalIdx), 'linear', NaN);
        truthZ = interp1(truth.t, truth.z_true, est3d.t(finalIdx), 'linear', NaN);
        T.finalPositionError_m(idx) = norm([ ...
            est3d.px(finalIdx) - truthX, ...
            est3d.py(finalIdx) - truthY, ...
            est3d.pz(finalIdx) - truthZ]);
    end
end

if isfield(results, 'wind') && isstruct(results.wind) && isfield(results.wind, 'final')
    T.windError_mps(idx) = norm(results.wind.final - truth.wind_true(end,:));
end

vars = string(clean.Properties.VariableNames);
if ismember("policy_cmd", vars)
    T.maxPolicyCommand(idx) = max(clean.policy_cmd, [], 'omitnan');
end

% cfg is accepted to keep the function signature aligned with analysis
% helpers; target-relative scoring is derived in the envelope builder.
end

function [peakValue, peakTime] = localPeakMetric(t, value)
valid = isfinite(t) & isfinite(value);
if ~any(valid)
    peakValue = NaN;
    peakTime = NaN;
else
    idxValid = find(valid);
    [peakValue, localIdx] = max(value(valid));
    peakTime = t(idxValid(localIdx));
end
end

function landingTime = localTruthLandingTime(truth)
mask = truth.t > 1.5 & truth.h_true <= 0.1 & abs(truth.v_true) <= 0.5;
idx = find(mask, 1, 'first');
if isempty(idx)
    landingTime = truth.t(end);
else
    landingTime = truth.t(idx);
end
end

function value = localRmse(error)
valid = isfinite(error);
if ~any(valid)
    value = NaN;
else
    value = sqrt(mean(error(valid).^2, 'omitnan'));
end
end

function normValue = localVectorNorm(x, y, z)
normValue = sqrt(x(:).^2 + y(:).^2 + z(:).^2);
normValue(~isfinite(x(:)) | ~isfinite(y(:)) | ~isfinite(z(:))) = NaN;
end

function aggregate = localAggregate(envelope)
aggregate = struct();
aggregate.numRuns = height(envelope);
aggregate.successRate = mean(double(envelope.success), 'omitnan');
successful = envelope.success;
aggregate.meanAbsPeakAltitudeError_m = mean(envelope.peak_altitude_abs_error_m(successful), 'omitnan');
aggregate.p95AbsPeakAltitudeError_m = localPercentile(envelope.peak_altitude_abs_error_m(successful), 95);
aggregate.meanRmseH_m = mean(envelope.rmse_h_m(successful), 'omitnan');
aggregate.meanRmsePz_m = mean(envelope.rmse_pz_m(successful), 'omitnan');
aggregate.meanWindError_mps = mean(envelope.windError_mps(successful), 'omitnan');
aggregate.meanGpsAcceptanceRate = mean(envelope.gpsAcceptanceRate(successful), 'omitnan');
end

function value = localPercentile(values, percent)
values = sort(values(isfinite(values)));
if isempty(values)
    value = NaN;
    return;
end

percent = min(max(percent, 0), 100);
if numel(values) == 1
    value = values(1);
    return;
end

position = 1 + (numel(values) - 1) * percent / 100;
lo = floor(position);
hi = ceil(position);
if lo == hi
    value = values(lo);
else
    alpha = position - lo;
    value = (1 - alpha) * values(lo) + alpha * values(hi);
end
end

function [envelope, sensitivity] = buildMonteCarloMissionEnvelopeAudit(runMetrics, cfg, options)
%BUILDMONTECARLOMISSIONENVELOPEAUDIT Derive mission envelope and sensitivity evidence.
%
% The envelope table keeps every Monte Carlo input knob next to derived
% mission outcomes, threshold flags, and one reviewable classification label
% per run. The sensitivity table reports deterministic linear relationships
% between input stressors and outcome metrics.
arguments
    runMetrics table
    cfg struct = caelum.defaultConfig()
    options.PeakAltitudeErrorWarn_m (1,1) double {mustBeNonnegative} = 8.0
    options.EstimatorRmseWarn_m (1,1) double {mustBeNonnegative} = 8.0
    options.ThreeDRmseWarn_m (1,1) double {mustBeNonnegative} = 8.0
    options.WindErrorWarn_mps (1,1) double {mustBeNonnegative} = 2.5
    options.GpsAcceptanceWarn (1,1) double {mustBeNonnegative} = 0.30
    options.DataLossWarnFraction (1,1) double {mustBeNonnegative} = 0.030
end

if isempty(runMetrics)
    error('caelum:buildMonteCarloMissionEnvelopeAudit:EmptyRunMetrics', ...
        'Monte Carlo run metrics table must contain at least one row.');
end

required = [ ...
    "runIndex", ...
    "success", ...
    "status", ...
    "seed", ...
    "boostDuration_s", ...
    "boostAccel_mps2", ...
    "dragCoeff", ...
    "baroAltNoise_m", ...
    "accelNoise_mps2", ...
    "gyroNoise_rps", ...
    "gpsRateHz", ...
    "wind_speed_mps", ...
    "timingJitterStd_s", ...
    "nanFraction", ...
    "dropoutFraction", ...
    "truth_peak_altitude_m", ...
    "logged_peak_altitude_m", ...
    "replay_peak_altitude_m", ...
    "est3d_peak_z_m", ...
    "peak_altitude_error_m", ...
    "detected_apogee_time_error_s", ...
    "rmse_h_m", ...
    "rmse_pz_m", ...
    "gpsAcceptanceRate", ...
    "windError_mps"];
missing = setdiff(required, string(runMetrics.Properties.VariableNames), 'stable');
if ~isempty(missing)
    error('caelum:buildMonteCarloMissionEnvelopeAudit:MissingRunMetricFields', ...
        'Monte Carlo run metrics table is missing required fields: %s', ...
        strjoin(cellstr(missing), ', '));
end

envelope = runMetrics;
n = height(envelope);

missionTarget_m = localMissionTarget(cfg);
envelope.mission_target_m = repmat(missionTarget_m, n, 1);
envelope.peak_altitude_abs_error_m = abs(envelope.peak_altitude_error_m);
envelope.peak_altitude_percent_error = localSafeDivide( ...
    envelope.peak_altitude_abs_error_m, envelope.truth_peak_altitude_m);
envelope.target_error_logged_peak_m = envelope.logged_peak_altitude_m - missionTarget_m;
envelope.data_loss_fraction = max(0, envelope.nanFraction) + max(0, envelope.dropoutFraction);

envelope.peak_altitude_error_warn = envelope.peak_altitude_abs_error_m > options.PeakAltitudeErrorWarn_m;
envelope.estimator_rmse_warn = envelope.rmse_h_m > options.EstimatorRmseWarn_m;
envelope.three_d_rmse_warn = envelope.rmse_pz_m > options.ThreeDRmseWarn_m;
envelope.wind_error_warn = envelope.windError_mps > options.WindErrorWarn_mps;
envelope.gps_acceptance_warn = envelope.gpsAcceptanceRate < options.GpsAcceptanceWarn;
envelope.data_loss_warn = envelope.data_loss_fraction > options.DataLossWarnFraction;

envelope.composite_error_score = localCompositeScore(envelope, options);
[envelope.envelope_code, envelope.envelope_label, envelope.envelope_rationale] = ...
    localClassifyEnvelope(envelope, options);

sensitivity = localBuildSensitivityTable(envelope);
end

function ratio = localSafeDivide(num, den)
ratio = nan(size(num));
valid = isfinite(num) & isfinite(den) & abs(den) > eps;
ratio(valid) = num(valid) ./ den(valid);
end

function target_m = localMissionTarget(cfg)
target_m = NaN;
if isstruct(cfg) && isfield(cfg, 'mission') && isstruct(cfg.mission) && ...
        isfield(cfg.mission, 'targetApogee_m')
    target_m = cfg.mission.targetApogee_m;
end
end

function score = localCompositeScore(envelope, options)
n = height(envelope);
score = nan(n, 1);
for k = 1:n
    components = [ ...
        localFiniteRatio(envelope.peak_altitude_abs_error_m(k), options.PeakAltitudeErrorWarn_m), ...
        localFiniteRatio(envelope.rmse_h_m(k), options.EstimatorRmseWarn_m), ...
        localFiniteRatio(envelope.rmse_pz_m(k), options.ThreeDRmseWarn_m), ...
        localFiniteRatio(envelope.windError_mps(k), options.WindErrorWarn_mps), ...
        localFiniteRatio(envelope.data_loss_fraction(k), options.DataLossWarnFraction), ...
        localGpsPenalty(envelope.gpsAcceptanceRate(k), options.GpsAcceptanceWarn)];
    valid = isfinite(components);
    if any(valid)
        score(k) = mean(components(valid), 'omitnan');
    end
end
end

function ratio = localFiniteRatio(value, scale)
if isfinite(value) && isfinite(scale) && scale > eps
    ratio = abs(value) / scale;
else
    ratio = NaN;
end
end

function penalty = localGpsPenalty(gpsAcceptanceRate, warnThreshold)
if isfinite(gpsAcceptanceRate) && isfinite(warnThreshold) && warnThreshold > eps
    penalty = max(0, warnThreshold - gpsAcceptanceRate) / warnThreshold;
else
    penalty = NaN;
end
end

function [codes, labels, rationales] = localClassifyEnvelope(envelope, options)
n = height(envelope);
codes = nan(n, 1);
labels = strings(n, 1);
rationales = strings(n, 1);

for k = 1:n
    if ~envelope.success(k)
        codes(k) = 1;
        labels(k) = "run_failed";
        rationales(k) = "Monte Carlo analysis did not complete: " + string(envelope.status(k)) + ".";
    elseif ~localRequiredMetricsFinite(envelope, k)
        codes(k) = 2;
        labels(k) = "metric_incomplete";
        rationales(k) = "One or more required outcome metrics are unavailable for this run.";
    elseif envelope.peak_altitude_error_warn(k)
        codes(k) = 3;
        labels(k) = "high_peak_altitude_error";
        rationales(k) = sprintf('Absolute peak-altitude error %.3f m exceeded %.3f m.', ...
            envelope.peak_altitude_abs_error_m(k), options.PeakAltitudeErrorWarn_m);
    elseif envelope.estimator_rmse_warn(k)
        codes(k) = 4;
        labels(k) = "high_estimator_rmse";
        rationales(k) = sprintf('Vertical estimator RMSE %.3f m exceeded %.3f m.', ...
            envelope.rmse_h_m(k), options.EstimatorRmseWarn_m);
    elseif envelope.three_d_rmse_warn(k)
        codes(k) = 5;
        labels(k) = "high_3d_rmse";
        rationales(k) = sprintf('3D vertical RMSE %.3f m exceeded %.3f m.', ...
            envelope.rmse_pz_m(k), options.ThreeDRmseWarn_m);
    elseif envelope.wind_error_warn(k)
        codes(k) = 6;
        labels(k) = "high_wind_error";
        rationales(k) = sprintf('Final wind-vector error %.3f m/s exceeded %.3f m/s.', ...
            envelope.windError_mps(k), options.WindErrorWarn_mps);
    elseif envelope.gps_acceptance_warn(k)
        codes(k) = 7;
        labels(k) = "low_gps_acceptance";
        rationales(k) = sprintf('GPS acceptance rate %.3f fell below %.3f.', ...
            envelope.gpsAcceptanceRate(k), options.GpsAcceptanceWarn);
    elseif envelope.data_loss_warn(k)
        codes(k) = 8;
        labels(k) = "high_data_loss";
        rationales(k) = sprintf('Synthetic NaN/dropout fraction %.3f exceeded %.3f.', ...
            envelope.data_loss_fraction(k), options.DataLossWarnFraction);
    else
        codes(k) = 9;
        labels(k) = "nominal";
        rationales(k) = "Run stayed within configured mission-envelope warning thresholds.";
    end
end
end

function tf = localRequiredMetricsFinite(envelope, idx)
required = [ ...
    envelope.truth_peak_altitude_m(idx), ...
    envelope.logged_peak_altitude_m(idx), ...
    envelope.peak_altitude_error_m(idx), ...
    envelope.rmse_h_m(idx), ...
    envelope.rmse_pz_m(idx), ...
    envelope.gpsAcceptanceRate(idx), ...
    envelope.windError_mps(idx)];
tf = all(isfinite(required));
end

function sensitivity = localBuildSensitivityTable(envelope)
inputNames = localSensitivityInputNames();
outputNames = localSensitivityOutputNames();

numRows = numel(inputNames) * numel(outputNames);
sensitivity = table('Size', [numRows 7], ...
    'VariableTypes', {'string','string','double','double','double','double','double'}, ...
    'VariableNames', {'input_name','output_name','correlation','abs_correlation','slope','valid_runs','rank'});

row = 0;
for i = 1:numel(inputNames)
    inputName = inputNames(i);
    if ~ismember(inputName, string(envelope.Properties.VariableNames))
        continue;
    end
    x = envelope.(char(inputName));
    for j = 1:numel(outputNames)
        outputName = outputNames(j);
        if ~ismember(outputName, string(envelope.Properties.VariableNames))
            continue;
        end
        y = envelope.(char(outputName));
        valid = envelope.success & isfinite(x) & isfinite(y);
        row = row + 1;
        sensitivity.input_name(row) = inputName;
        sensitivity.output_name(row) = outputName;
        sensitivity.valid_runs(row) = nnz(valid);
        if nnz(valid) >= 3
            sensitivity.correlation(row) = localCorrelation(x(valid), y(valid));
            sensitivity.abs_correlation(row) = abs(sensitivity.correlation(row));
            sensitivity.slope(row) = localSlope(x(valid), y(valid));
        else
            sensitivity.correlation(row) = NaN;
            sensitivity.abs_correlation(row) = NaN;
            sensitivity.slope(row) = NaN;
        end
    end
end

sensitivity = sensitivity(1:row, :);
if isempty(sensitivity)
    return;
end

sortKey = sensitivity.abs_correlation;
sortKey(~isfinite(sortKey)) = -Inf;
[~, order] = sort(sortKey, 'descend');
sensitivity = sensitivity(order, :);
sensitivity.rank = (1:height(sensitivity)).';
end

function names = localSensitivityInputNames()
names = [ ...
    "boostAccel_mps2", ...
    "boostDuration_s", ...
    "dragCoeff", ...
    "baroAltNoise_m", ...
    "accelNoise_mps2", ...
    "gyroNoise_rps", ...
    "gpsRateHz", ...
    "wind_speed_mps", ...
    "timingJitterStd_s", ...
    "nanFraction", ...
    "dropoutFraction"];
end

function names = localSensitivityOutputNames()
names = [ ...
    "truth_peak_altitude_m", ...
    "peak_altitude_abs_error_m", ...
    "rmse_h_m", ...
    "rmse_pz_m", ...
    "windError_mps", ...
    "gpsAcceptanceRate", ...
    "detected_apogee_time_error_s"];
end

function r = localCorrelation(x, y)
x = x(:);
y = y(:);
xCentered = x - mean(x, 'omitnan');
yCentered = y - mean(y, 'omitnan');
den = sqrt(sum(xCentered.^2, 'omitnan') * sum(yCentered.^2, 'omitnan'));
if ~isfinite(den) || den <= eps
    r = NaN;
else
    r = sum(xCentered .* yCentered, 'omitnan') / den;
end
end

function slope = localSlope(x, y)
x = x(:);
y = y(:);
xCentered = x - mean(x, 'omitnan');
yCentered = y - mean(y, 'omitnan');
den = sum(xCentered.^2, 'omitnan');
if ~isfinite(den) || den <= eps
    slope = NaN;
else
    slope = sum(xCentered .* yCentered, 'omitnan') / den;
end
end

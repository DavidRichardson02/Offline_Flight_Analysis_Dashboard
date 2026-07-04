function summary = summarizeLog(T, events, cfg)
%SUMMARIZELOG Compute summary metrics from a cleaned log.

arguments
    T table
    events struct
    cfg struct = caelum.defaultConfig()
end

summary = struct();

summary.launchTime_s = events.launchTime_s;
summary.burnoutTime_s = events.burnoutTime_s;
summary.apogeeTime_s = events.apogeeTime_s;
summary.landingTime_s = events.landingTime_s;

summary.maxKFAltitude_m = max(T.kf_h, [], 'omitnan');
summary.maxBaroRelAltitude_m = max(T.bmp_alt_rel, [], 'omitnan');
summary.maxVerticalVelocity_mps = max(T.kf_v, [], 'omitnan');
summary.minVerticalVelocity_mps = min(T.kf_v, [], 'omitnan');
summary.maxVerticalAccel_mps2 = max(T.a_vertical, [], 'omitnan');
summary.minVerticalAccel_mps2 = min(T.a_vertical, [], 'omitnan');

summary.meanSamplePeriod_s = mean(T.dt(2:end), 'omitnan');
summary.stdSamplePeriod_s = std(T.dt(2:end), 'omitnan');
summary.numGapSamples = nnz(T.sample_gap);
summary.numBadCovarianceSamples = nnz(T.is_bad_covariance);
summary.numMissingBaroSamples = nnz(T.is_missing_baro);
summary.numMissingImuSamples = nnz(T.is_missing_imu);
summary.numMissingLisSamples = nnz(T.is_missing_lis);
summary.numMissingEstimatorSamples = nnz(T.is_missing_estimator);

summary.finalAltitudeSigma_m = T.kf_sigma_h(end);
summary.finalVelocitySigma_mps = T.kf_sigma_v(end);

vars = string(T.Properties.VariableNames);
if ismember("phase", vars)
    summary.finalPhase = string(localPhaseName(T.phase(end)));
    summary.boostPhaseFraction = mean(double(T.phase == 1), 'omitnan');
    summary.coastPhaseFraction = mean(double(T.phase == 2), 'omitnan');
    summary.brakePhaseFraction = mean(double(T.phase == 3), 'omitnan');
    summary.descentPhaseFraction = mean(double(T.phase == 4), 'omitnan');
end

if ismember("policy_valid", vars)
    summary.policyValidSamples = nnz(T.policy_valid > 0.5);
    summary.policyValidFraction = mean(double(T.policy_valid > 0.5), 'omitnan');
end

if ismember("policy_cmd", vars)
    summary.maxPolicyCommand01 = max(T.policy_cmd, [], 'omitnan');
end

if ismember("apogee_error", vars)
    summary.maxApogeeError_m = max(T.apogee_error, [], 'omitnan');
end

if ismember("target_effective", vars)
    summary.finalEffectiveTargetApogee_m = localLastFinite(T.target_effective);
end

if isfield(cfg, 'mission') && isstruct(cfg.mission) && isfield(cfg.mission, 'targetApogee_m')
    scoringTarget_m = cfg.mission.targetApogee_m;
    summary.scoringTargetApogee_m = scoringTarget_m;
    if isfield(cfg.mission, 'targetApogee_ft')
        summary.scoringTargetApogee_ft = cfg.mission.targetApogee_ft;
    end
    summary.missionScoringApplicable = localMissionScoringApplicable(T, cfg.mission);

    if summary.missionScoringApplicable
        summary.dashboardPeakKFAltitudeErrorToScoringTarget_m = ...
            summary.maxKFAltitude_m - scoringTarget_m;
        summary.dashboardPeakKFAltitudePercentErrorToScoringTarget = ...
            abs(summary.dashboardPeakKFAltitudeErrorToScoringTarget_m) / scoringTarget_m;
    else
        summary.missionScoringApplicabilityNote = ...
            "Reference target only for this log; telemetry is below competition-scale altitude and has no matching firmware target.";
    end

    if ismember("target_apogee", vars)
        finalFirmwareTarget_m = localLastFinite(T.target_apogee);
        summary.finalFirmwareTargetApogee_m = finalFirmwareTarget_m;
        if summary.missionScoringApplicable
            summary.finalFirmwareTargetOffsetFromScoringTarget_m = ...
                finalFirmwareTarget_m - scoringTarget_m;
        end
    end
end

if ismember("uncertainty_margin", vars)
    summary.maxUncertaintyMargin_m = max(T.uncertainty_margin, [], 'omitnan');
end

if ismember("actuator_us", vars)
    summary.minActuatorUs = min(T.actuator_us, [], 'omitnan');
    summary.maxActuatorUs = max(T.actuator_us, [], 'omitnan');
end

if ismember("warn_mask", vars)
    summary.samplesWithWarnMask = nnz(T.warn_mask ~= 0);
    summary.finalWarnMask = T.warn_mask(end);
end

if isfield(cfg, 'truthMetrics') && ~isempty(fieldnames(cfg.truthMetrics))
    names = fieldnames(cfg.truthMetrics);
    for k = 1:numel(names)
        summary.(names{k}) = cfg.truthMetrics.(names{k});
    end
end

if isfield(cfg, 'consistencyMetrics') && ~isempty(fieldnames(cfg.consistencyMetrics))
    names = fieldnames(cfg.consistencyMetrics);
    for k = 1:numel(names)
        summary.(names{k}) = cfg.consistencyMetrics.(names{k});
    end
end

if isfield(cfg, 'attitudeMetrics') && ~isempty(fieldnames(cfg.attitudeMetrics))
    names = fieldnames(cfg.attitudeMetrics);
    for k = 1:numel(names)
        summary.(names{k}) = cfg.attitudeMetrics.(names{k});
    end
end
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

function value = localLastFinite(x)
idx = find(isfinite(x), 1, 'last');
if isempty(idx)
    value = NaN;
else
    value = x(idx);
end
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

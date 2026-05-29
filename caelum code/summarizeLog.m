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

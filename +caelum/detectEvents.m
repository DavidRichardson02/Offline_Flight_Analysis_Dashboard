function events = detectEvents(T, cfg)
%DETECTEVENTS Detect major flight events from the cleaned log.

arguments
    T table
    cfg struct = caelum.defaultConfig()
end

n = height(T);
idx = (1:n)';

events = struct();
events.launchIdx = [];
events.burnoutIdx = [];
events.apogeeIdx = [];
events.landingIdx = [];

launchMask = T.smoothed_a_vertical > cfg.launchAccelThreshold;
launchIdx = localFindFirstPersistentTrue(launchMask, cfg.launchPersistenceSamples);

if isempty(launchIdx)
    launchIdx = find(T.kf_h > 0.5, 1, 'first');
end
if isempty(launchIdx)
    launchIdx = 1;
end
events.launchIdx = launchIdx;

burnoutStartIdx = min(n, launchIdx + max(1, round(cfg.burnoutSearchDelay_s * cfg.sampleRateHz)));
burnoutMask = false(n, 1);
burnoutMask(burnoutStartIdx:end) = ...
    (T.smoothed_a_vertical(burnoutStartIdx:end) <= cfg.burnoutAccelThreshold) & ...
    (T.smoothed_kf_v(burnoutStartIdx:end) >= cfg.burnoutVelocityThreshold);

burnoutCandidates = localFindFirstPersistentTrue(burnoutMask, cfg.burnoutPersistenceSamples);
if isempty(burnoutCandidates)
    burnoutCandidates = find( ...
        idx >= burnoutStartIdx & ...
        T.smoothed_a_vertical <= cfg.burnoutAccelThreshold, ...
        1, 'first');
end
if isempty(burnoutCandidates)
    burnoutCandidates = min(n, launchIdx + round(1.5 * cfg.sampleRateHz));
end
events.burnoutIdx = burnoutCandidates;

crossIdx = find( ...
    T.smoothed_kf_v(1:end-1) > 0 & ...
    T.smoothed_kf_v(2:end) <= 0 & ...
    idx(1:end-1) >= events.burnoutIdx, ...
    1, 'first');
if isempty(crossIdx)
    [~, crossIdx] = max(T.kf_h);
end
events.apogeeIdx = crossIdx;

landingSearch = idx > crossIdx;
stableVelocity = abs(T.smoothed_kf_v) < cfg.landingVelocityThreshold;
stableAltitude = abs(T.kf_h - median(T.kf_h(max(crossIdx, n-20):n), 'omitnan')) < cfg.landingAltitudeWindow_m;
landingIdx = find(landingSearch & stableVelocity & stableAltitude, 1, 'first');
if isempty(landingIdx)
    landingIdx = n;
end
events.landingIdx = landingIdx;

events.launchTime_s = T.t(events.launchIdx);
events.burnoutTime_s = T.t(events.burnoutIdx);
events.apogeeTime_s = T.t(events.apogeeIdx);
events.landingTime_s = T.t(events.landingIdx);
end

function idx = localFindFirstPersistentTrue(mask, persistenceSamples)
idx = [];
if isempty(mask)
    return;
end

required = max(1, round(persistenceSamples));
score = conv(double(mask(:)), ones(required, 1), 'valid');
startIdx = find(score >= required, 1, 'first');
if ~isempty(startIdx)
    idx = startIdx;
end
end

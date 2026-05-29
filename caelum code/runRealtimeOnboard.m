function onboard = runRealtimeOnboard(samples, cfg)
%RUNREALTIMEONBOARD Streaming real-time processor with parity-capable vertical replay.
arguments
    samples struct
    cfg struct = caelum.defaultConfig()
end
cfg = caelum.localResolve3DConfig(cfg);
n = numel(samples);
if n == 0
    error('caelum:runRealtimeOnboard:EmptySamples', ...
        'samples must contain at least one element.');
end

raw = localBuildRawTable(samples);
raw = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = localCleanRealtimeTable(raw, cfg);

att = caelum.runAttitudeReplay(clean, cfg);
[clean, att] = caelum.attachPhase1AttitudeFields(clean, att);
clean = localAttachAttitudeDiagnostics(clean, att);

verticalHistory = table();
if ismember("bmp_alt_rel", string(clean.Properties.VariableNames))
    verticalHistory = caelum.runFirmwareVerticalEstimator(clean, cfg);
end

clean.q_w = interp1(att.t, att.q_w, clean.t, 'linear', 1);
clean.q_x = interp1(att.t, att.q_x, clean.t, 'linear', 0);
clean.q_y = interp1(att.t, att.q_y, clean.t, 'linear', 0);
clean.q_z = interp1(att.t, att.q_z, clean.t, 'linear', 0);

vars = string(clean.Properties.VariableNames);
hasGpsPos = all(ismember(["gps_x","gps_y","gps_z"], vars));
hasGpsVel = all(ismember(["gps_vx","gps_vy","gps_vz"], vars));
if cfg.enable3DReplay && (hasGpsPos || hasGpsVel)
    est3d = caelum.run3DEKF(clean, cfg);
else
    est3d = table();
end

onboard = struct();
onboard.cleanData = clean;
onboard.cleanReport = cleanReport;
onboard.verticalHistory = verticalHistory;
onboard.stateHistory = est3d;
onboard.attitudeHistory = att;
onboard.wind = caelum.estimateWind(est3d);
end

function raw = localBuildRawTable(samples)
n = numel(samples);
raw = table();

raw.t_us = zeros(n, 1);
for k = 1:n
    if ~isfield(samples(k), 't')
        error('caelum:runRealtimeOnboard:MissingTime', ...
            'samples(%d) is missing the required field t.', k);
    end
    raw.t_us(k) = round(double(samples(k).t) * 1e6);
end

requiredFields = ["ax","ay","az","gx","gy","gz","bmp_alt_rel"];
for i = 1:numel(requiredFields)
    fieldName = requiredFields(i);
    raw.(char(fieldName)) = localExtractField(samples, fieldName, NaN, true);
end

optionalFields = [ ...
    "bmp_T","bmp_P","bmp_alt", ...
    "lis_ax","lis_ay","lis_az", ...
    "g_bx","g_by","g_bz", ...
    "a_vertical","kf_h","kf_v","P00","P01","P10","P11", ...
    "gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"];
for i = 1:numel(optionalFields)
    fieldName = optionalFields(i);
    raw.(char(fieldName)) = localExtractField(samples, fieldName, NaN, false);
end
end

function values = localExtractField(samples, fieldName, defaultValue, required)
n = numel(samples);
values = zeros(n, 1);
for k = 1:n
    if isfield(samples(k), fieldName)
        values(k) = double(samples(k).(fieldName));
    elseif required
        error('caelum:runRealtimeOnboard:MissingField', ...
            'samples(%d) is missing the required field %s.', k, fieldName);
    else
        values(k) = defaultValue;
    end
end
end

function [clean, report] = localCleanRealtimeTable(raw, cfg)
report = struct();
report.rowsBeforeCleaning = height(raw);

missingTimestampMask = isnan(raw.t_us);
report.rowsRemovedMissingTimestamp = nnz(missingTimestampMask);
clean = raw(~missingTimestampMask, :);

[~, ia] = unique(clean.t_us, 'stable');
duplicateMask = true(height(clean), 1);
duplicateMask(ia) = false;
report.duplicateTimestampsRemoved = nnz(duplicateMask);
clean = clean(ia, :);

nonmonotonicMask = [false; diff(clean.t_us) <= 0];
report.nonmonotonicTimestampsRemoved = nnz(nonmonotonicMask);
clean = clean(~nonmonotonicMask, :);
report.rowsAfterCleaning = height(clean);

if isempty(clean)
    error('caelum:runRealtimeOnboard:NoRowsAfterCleaning', ...
        'No valid rows remain after realtime sample cleaning.');
end

clean.t = (clean.t_us - clean.t_us(1)) * 1e-6;
clean.dt = [NaN; diff(clean.t)];
clean.sample_gap = [false; diff(clean.t) > cfg.sampleGapThreshold];
end

function T = localAttachAttitudeDiagnostics(T, attitude)
if isempty(attitude)
    return;
end

fieldNames = ["a_vertical_attitude","roll_deg","pitch_deg","yaw_deg", ...
    "b_gx","b_gy","b_gz","gravity_update_used","gravity_innovation", ...
    "gravity_residual","tilt_error_deg"];
for k = 1:numel(fieldNames)
    fieldName = fieldNames(k);
    if ~ismember(fieldName, string(attitude.Properties.VariableNames))
        continue;
    end
    if fieldName == "gravity_update_used"
        values = interp1(attitude.t, double(attitude.(char(fieldName))), T.t, 'nearest', 0);
        T.(char(fieldName)) = logical(values > 0.5);
    else
        T.(char(fieldName)) = interp1(attitude.t, attitude.(char(fieldName)), T.t, 'linear', NaN);
    end
end
end

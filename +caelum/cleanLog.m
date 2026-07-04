function [T, cleanReport] = cleanLog(T, cfg)
%CLEANLOG Clean imported data and add derived analysis columns.

arguments
    T table
    cfg struct = caelum.defaultConfig()
end

required = [ ...
    "t_us","bmp_T","bmp_P","bmp_alt","bmp_alt_rel", ...
    "ax","ay","az","gx","gy","gz", ...
    "lis_ax","lis_ay","lis_az", ...
    "g_bx","g_by","g_bz", ...
    "a_vertical","kf_h","kf_v", ...
    "P00","P01","P10","P11"];

missing = setdiff(required, string(T.Properties.VariableNames));
if ~isempty(missing)
    error('caelum:cleanLog:MissingColumns', ...
        'Missing expected columns: %s', strjoin(cellstr(missing), ', '));
end

for k = 1:numel(required)
    name = required(k);
    if ~isnumeric(T.(name))
        T.(name) = str2double(string(T.(name)));
    end
end

cleanReport = struct();
cleanReport.rowsBeforeCleaning = height(T);

missingTimestampMask = isnan(T.t_us);
cleanReport.rowsRemovedMissingTimestamp = nnz(missingTimestampMask);
T = T(~missingTimestampMask, :);

[~, ia] = unique(T.t_us, 'stable');
duplicateMask = true(height(T), 1);
duplicateMask(ia) = false;
cleanReport.duplicateTimestampsRemoved = nnz(duplicateMask);
T = T(ia, :);

nonmonotonicMask = [false; diff(T.t_us) <= 0];
cleanReport.nonmonotonicTimestampsRemoved = nnz(nonmonotonicMask);
T = T(~nonmonotonicMask, :);

cleanReport.rowsAfterCleaning = height(T);

if isempty(T)
    error('caelum:cleanLog:NoRows', ...
        'No valid rows remain after timestamp cleaning.');
end

T.t = (T.t_us - T.t_us(1)) * 1e-6;
T.dt = [NaN; diff(T.t)];
T.sample_gap = [false; diff(T.t) > cfg.sampleGapThreshold];
T.sample_rate_hz = nan(height(T), 1);
validDt = T.dt > 0;
T.sample_rate_hz(validDt) = 1 ./ T.dt(validDt);

T.acc_norm = hypot(hypot(T.ax, T.ay), T.az);
T.gyro_norm = hypot(hypot(T.gx, T.gy), T.gz);
T.lis_acc_norm = hypot(hypot(T.lis_ax, T.lis_ay), T.lis_az);
T.g_norm = hypot(hypot(T.g_bx, T.g_by), T.g_bz);

T.kf_sigma_h = sqrt(max(T.P00, 0));
T.kf_sigma_v = sqrt(max(T.P11, 0));

T.acc_norm_minus_g = T.acc_norm - cfg.gravity;
T.smoothed_a_vertical = movmean(T.a_vertical, cfg.smoothWindow, 'omitnan');
T.smoothed_kf_v = movmean(T.kf_v, cfg.smoothWindow, 'omitnan');
T.smoothed_bmp_alt_rel = movmean(T.bmp_alt_rel, cfg.smoothWindow, 'omitnan');
T.smoothed_kf_h = movmean(T.kf_h, cfg.smoothWindow, 'omitnan');

T.is_bad_covariance = ...
    (T.P00 < 0) | (T.P11 < 0) | ~isfinite(T.P00) | ~isfinite(T.P11);

T.is_bad_gravity_norm = abs(T.g_norm - cfg.gravity) > 1.0;
T.is_bad_pressure = ~isfinite(T.bmp_P) | (T.bmp_P <= 0);
T.is_bad_altitude = ~isfinite(T.bmp_alt_rel) | ~isfinite(T.kf_h);

T.is_missing_baro = ...
    ~isfinite(T.bmp_T) | ~isfinite(T.bmp_P) | ...
    ~isfinite(T.bmp_alt) | ~isfinite(T.bmp_alt_rel);

T.is_missing_imu = ...
    ~isfinite(T.ax) | ~isfinite(T.ay) | ~isfinite(T.az) | ...
    ~isfinite(T.gx) | ~isfinite(T.gy) | ~isfinite(T.gz);

T.is_missing_lis = ...
    ~isfinite(T.lis_ax) | ~isfinite(T.lis_ay) | ~isfinite(T.lis_az);

T.is_missing_estimator = ...
    ~isfinite(T.a_vertical) | ~isfinite(T.kf_h) | ~isfinite(T.kf_v);

T.is_any_bad = ...
    T.is_bad_covariance | ...
    T.is_bad_gravity_norm | ...
    T.is_bad_pressure | ...
    T.is_bad_altitude;

T = localAttachLatestFirmwareDerivedFields(T);
end

function T = localAttachLatestFirmwareDerivedFields(T)
vars = string(T.Properties.VariableNames);
n = height(T);

if ismember("phase", vars)
    phase_name = strings(n, 1);
    for k = 1:n
        phase_name(k) = localPhaseName(T.phase(k));
    end
    T.phase_name = categorical(phase_name, ...
        ["IDLE","BOOST","COAST","BRAKE","DESCENT","UNKNOWN"], ...
        'Ordinal', true);
end

if ismember("arm_state", vars)
    arm_state_name = strings(n, 1);
    for k = 1:n
        arm_state_name(k) = localArmStateName(T.arm_state(k));
    end
    T.arm_state_name = categorical(arm_state_name, ...
        ["DISARMED","SAFE","ARMED","UNKNOWN"], ...
        'Ordinal', true);
end

if ismember("policy_cmd", vars)
    T.policy_cmd_percent = 100.0 .* T.policy_cmd;
end

if all(ismember(["apogee_no_brake","target_apogee"], vars)) && ~ismember("apogee_error", vars)
    T.apogee_error = T.apogee_no_brake - T.target_apogee;
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

function name = localArmStateName(value)
if ~isfinite(value)
    name = "UNKNOWN";
    return;
end

switch round(value)
    case 0
        name = "DISARMED";
    case 1
        name = "SAFE";
    case 2
        name = "ARMED";
    otherwise
        name = "UNKNOWN";
end
end

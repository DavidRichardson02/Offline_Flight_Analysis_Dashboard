function audit = buildAttitudeGravityProvenanceAudit(T, attitude, cfg, options)
%BUILDATTITUDEGRAVITYPROVENANCEAUDIT Derive attitude/gravity acceleration evidence.
%
% The audit preserves raw body acceleration, logged firmware gravity and
% vertical acceleration, replayed attitude gravity, and optional truth on the
% cleaned telemetry timebase. Classification labels are analysis evidence,
% not firmware state.
arguments
    T table
    attitude table = table()
    cfg struct = caelum.defaultConfig()
    options.Truth struct = struct()
    options.GravityNormTolerance_mps2 (1,1) double {mustBeNonnegative} = 1.0
    options.TiltWarn_deg (1,1) double {mustBeNonnegative} = 10.0
    options.GravityResidualWarn_mps2 (1,1) double {mustBeNonnegative} = 2.0
    options.VerticalAccelDisagreementWarn_mps2 (1,1) double {mustBeNonnegative} = 3.0
    options.TruthVerticalAccelWarn_mps2 (1,1) double {mustBeNonnegative} = 3.0
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

n = height(T);
vars = string(T.Properties.VariableNames);
attitudeVars = localTableVars(attitude);

audit = table();
audit.t = localColumn(T, vars, "t", n, NaN);
audit.sample_gap = localLogicalColumn(T, vars, "sample_gap", n);

audit.ax_mps2 = localColumn(T, vars, "ax", n, NaN);
audit.ay_mps2 = localColumn(T, vars, "ay", n, NaN);
audit.az_mps2 = localColumn(T, vars, "az", n, NaN);
audit.gx_rps = localColumn(T, vars, "gx", n, NaN);
audit.gy_rps = localColumn(T, vars, "gy", n, NaN);
audit.gz_rps = localColumn(T, vars, "gz", n, NaN);
audit.accel_norm_mps2 = localFirstAvailableNumeric(T, vars, ["acc_norm","accel_norm"], n, NaN);
audit.gyro_norm_rps = localFirstAvailableNumeric(T, vars, ["gyro_norm"], n, NaN);
audit.accel_norm_minus_g_mps2 = audit.accel_norm_mps2 - localConfigScalar(cfg, "gravity", 9.8);

audit.logged_g_bx_mps2 = localColumn(T, vars, "g_bx", n, NaN);
audit.logged_g_by_mps2 = localColumn(T, vars, "g_by", n, NaN);
audit.logged_g_bz_mps2 = localColumn(T, vars, "g_bz", n, NaN);
audit.logged_g_norm_mps2 = localVectorNorm( ...
    audit.logged_g_bx_mps2, audit.logged_g_by_mps2, audit.logged_g_bz_mps2);
audit.logged_g_norm_error_mps2 = audit.logged_g_norm_mps2 - localConfigScalar(cfg, "gravity", 9.8);

audit.logged_a_vertical_mps2 = localColumn(T, vars, "a_vertical", n, NaN);
audit.smoothed_a_vertical_mps2 = localFirstAvailableNumeric(T, vars, ...
    ["smoothed_a_vertical","a_vertical"], n, NaN);
audit.gravity_projected_a_vertical_mps2 = localGravityProjectedVerticalAccel(audit, cfg);

audit.attitude_g_bx_mps2 = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "g_bx_att", audit.t, n, NaN);
audit.attitude_g_by_mps2 = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "g_by_att", audit.t, n, NaN);
audit.attitude_g_bz_mps2 = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "g_bz_att", audit.t, n, NaN);
audit.attitude_g_norm_mps2 = localVectorNorm( ...
    audit.attitude_g_bx_mps2, audit.attitude_g_by_mps2, audit.attitude_g_bz_mps2);
audit.attitude_g_norm_error_mps2 = audit.attitude_g_norm_mps2 - localConfigScalar(cfg, "gravity", 9.8);

audit.attitude_a_vertical_mps2 = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, ...
    "a_vertical_attitude", audit.t, n, NaN);
audit.a_vertical_used_mps2 = localFirstAvailableNumeric(T, vars, ...
    ["a_vertical_used","a_vertical"], n, NaN);
audit.attitude_fallback_used = localLogicalColumn(T, vars, "attitude_fallback_used", n);
audit.vertical_input_mode = localStringColumn(T, vars, "vertical_input_mode", n, "unknown");

audit.logged_minus_attitude_a_vertical_mps2 = audit.logged_a_vertical_mps2 - audit.attitude_a_vertical_mps2;
audit.projected_minus_logged_a_vertical_mps2 = audit.gravity_projected_a_vertical_mps2 - audit.logged_a_vertical_mps2;
audit.attitude_minus_projected_a_vertical_mps2 = audit.attitude_a_vertical_mps2 - audit.gravity_projected_a_vertical_mps2;
audit.smoothed_minus_logged_a_vertical_mps2 = audit.smoothed_a_vertical_mps2 - audit.logged_a_vertical_mps2;

audit.logged_q_w = localFirstAvailableNumeric(T, vars, ["q_w","q0"], n, NaN);
audit.logged_q_x = localFirstAvailableNumeric(T, vars, ["q_x","q1"], n, NaN);
audit.logged_q_y = localFirstAvailableNumeric(T, vars, ["q_y","q2"], n, NaN);
audit.logged_q_z = localFirstAvailableNumeric(T, vars, ["q_z","q3"], n, NaN);
[audit.logged_roll_deg, audit.logged_pitch_deg, audit.logged_yaw_deg] = ...
    localEulerFromQuaternion(audit.logged_q_w, audit.logged_q_x, audit.logged_q_y, audit.logged_q_z);

audit.replay_q_w = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "q_w", audit.t, n, NaN);
audit.replay_q_x = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "q_x", audit.t, n, NaN);
audit.replay_q_y = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "q_y", audit.t, n, NaN);
audit.replay_q_z = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "q_z", audit.t, n, NaN);
audit.replay_roll_deg = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "roll_deg", audit.t, n, NaN);
audit.replay_pitch_deg = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "pitch_deg", audit.t, n, NaN);
audit.replay_yaw_deg = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "yaw_deg", audit.t, n, NaN);

audit.gravity_update_used = localAttitudeOrCleanLogical(attitude, attitudeVars, T, vars, ...
    "gravity_update_used", audit.t, n);
audit.gravity_innovation = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, ...
    "gravity_innovation", audit.t, n, NaN);
audit.gravity_residual_mps2 = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, ...
    "gravity_residual", audit.t, n, NaN);
audit.tilt_error_deg = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, ...
    "tilt_error_deg", audit.t, n, NaN);
audit.attitude_bias_gx_rps = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "b_gx", audit.t, n, NaN);
audit.attitude_bias_gy_rps = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "b_gy", audit.t, n, NaN);
audit.attitude_bias_gz_rps = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, "b_gz", audit.t, n, NaN);

audit.raw_imu_available = all(isfinite([audit.ax_mps2 audit.ay_mps2 audit.az_mps2 ...
    audit.gx_rps audit.gy_rps audit.gz_rps]), 2);
audit.logged_gravity_available = all(isfinite([audit.logged_g_bx_mps2 ...
    audit.logged_g_by_mps2 audit.logged_g_bz_mps2]), 2);
audit.attitude_gravity_available = all(isfinite([audit.attitude_g_bx_mps2 ...
    audit.attitude_g_by_mps2 audit.attitude_g_bz_mps2]), 2);
audit.logged_vertical_available = isfinite(audit.logged_a_vertical_mps2);
audit.attitude_vertical_available = isfinite(audit.attitude_a_vertical_mps2);
audit.attitude_evidence_available = audit.attitude_vertical_available | ...
    isfinite(audit.gravity_residual_mps2) | isfinite(audit.tilt_error_deg);
audit.logged_quaternion_available = all(isfinite([audit.logged_q_w audit.logged_q_x ...
    audit.logged_q_y audit.logged_q_z]), 2);
audit.replay_quaternion_available = all(isfinite([audit.replay_q_w audit.replay_q_x ...
    audit.replay_q_y audit.replay_q_z]), 2);

truth = options.Truth;
audit.truth_a_vertical_mps2 = localTruthNumeric(truth, ["a_vertical_true","a_true"], audit.t);
audit.truth_roll_deg = localTruthNumeric(truth, ["roll_true_deg","roll_deg"], audit.t);
audit.truth_pitch_deg = localTruthNumeric(truth, ["pitch_true_deg","pitch_deg"], audit.t);
audit.truth_yaw_deg = localTruthNumeric(truth, ["yaw_true_deg","yaw_deg"], audit.t);
audit.logged_truth_error_a_vertical_mps2 = audit.logged_a_vertical_mps2 - audit.truth_a_vertical_mps2;
audit.attitude_truth_error_a_vertical_mps2 = audit.attitude_a_vertical_mps2 - audit.truth_a_vertical_mps2;
audit.projected_truth_error_a_vertical_mps2 = audit.gravity_projected_a_vertical_mps2 - audit.truth_a_vertical_mps2;
audit.replay_truth_tilt_error_deg = localTiltError(audit.replay_roll_deg, audit.replay_pitch_deg, ...
    audit.truth_roll_deg, audit.truth_pitch_deg);
audit.logged_truth_tilt_error_deg = localTiltError(audit.logged_roll_deg, audit.logged_pitch_deg, ...
    audit.truth_roll_deg, audit.truth_pitch_deg);

audit.gravity_norm_tolerance_mps2 = repmat(options.GravityNormTolerance_mps2, n, 1);
audit.tilt_warn_deg = repmat(options.TiltWarn_deg, n, 1);
audit.gravity_residual_warn_mps2 = repmat(options.GravityResidualWarn_mps2, n, 1);
audit.vertical_accel_disagreement_warn_mps2 = repmat(options.VerticalAccelDisagreementWarn_mps2, n, 1);
audit.truth_vertical_accel_warn_mps2 = repmat(options.TruthVerticalAccelWarn_mps2, n, 1);

[audit.evidence_code, audit.evidence_label, audit.evidence_rationale] = ...
    localClassifyEvidence(audit, options);
end

function values = localColumn(T, vars, fieldName, n, defaultValue)
if ismember(fieldName, vars)
    values = double(T.(char(fieldName)));
else
    values = repmat(defaultValue, n, 1);
end
values = values(:);
end

function values = localFirstAvailableNumeric(T, vars, fieldNames, n, defaultValue)
values = repmat(defaultValue, n, 1);
for k = 1:numel(fieldNames)
    fieldName = fieldNames(k);
    if ismember(fieldName, vars)
        values = double(T.(char(fieldName)));
        values = values(:);
        return;
    end
end
end

function values = localLogicalColumn(T, vars, fieldName, n)
if ismember(fieldName, vars)
    values = double(T.(char(fieldName))) > 0.5;
else
    values = false(n, 1);
end
values = values(:);
end

function values = localStringColumn(T, vars, fieldName, n, defaultValue)
values = repmat(string(defaultValue), n, 1);
if ismember(fieldName, vars)
    source = T.(char(fieldName));
    values = string(source(:));
end
end

function vars = localTableVars(T)
if istable(T) && ~isempty(T)
    vars = string(T.Properties.VariableNames);
else
    vars = strings(0, 1);
end
end

function values = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, fieldName, t, n, defaultValue)
if istable(attitude) && ~isempty(attitude) && ismember("t", attitudeVars) && ismember(fieldName, attitudeVars)
    values = localInterpolateNumeric(attitude.t, attitude.(char(fieldName)), t, defaultValue);
elseif ismember(fieldName, vars)
    values = double(T.(char(fieldName)));
else
    values = repmat(defaultValue, n, 1);
end
values = values(:);
end

function values = localAttitudeOrCleanLogical(attitude, attitudeVars, T, vars, fieldName, t, n)
numeric = localAttitudeOrCleanNumeric(attitude, attitudeVars, T, vars, fieldName, t, n, NaN);
values = false(n, 1);
values(isfinite(numeric)) = numeric(isfinite(numeric)) > 0.5;
end

function values = localInterpolateNumeric(sourceTime, sourceValues, targetTime, defaultValue)
n = numel(targetTime);
values = repmat(defaultValue, n, 1);
sourceTime = double(sourceTime(:));
sourceValues = double(sourceValues(:));
valid = isfinite(sourceTime) & isfinite(sourceValues);
if ~any(valid)
    return;
end
if nnz(valid) == 1
    values(:) = sourceValues(valid);
    return;
end
values = interp1(sourceTime(valid), sourceValues(valid), targetTime, 'linear', defaultValue);
end

function aVertical = localGravityProjectedVerticalAccel(audit, cfg)
g = localConfigScalar(cfg, "gravity", 9.8);
n = height(audit);
aVertical = nan(n, 1);
valid = all(isfinite([audit.ax_mps2 audit.ay_mps2 audit.az_mps2 ...
    audit.logged_g_bx_mps2 audit.logged_g_by_mps2 audit.logged_g_bz_mps2]), 2) & ...
    audit.logged_g_norm_mps2 > 1.0e-9;
if any(valid)
    zux = audit.logged_g_bx_mps2(valid) ./ audit.logged_g_norm_mps2(valid);
    zuy = audit.logged_g_by_mps2(valid) ./ audit.logged_g_norm_mps2(valid);
    zuz = audit.logged_g_bz_mps2(valid) ./ audit.logged_g_norm_mps2(valid);
    aUpMeas = audit.ax_mps2(valid) .* zux + ...
        audit.ay_mps2(valid) .* zuy + ...
        audit.az_mps2(valid) .* zuz;
    aVertical(valid) = aUpMeas - g;
end
end

function normValue = localVectorNorm(x, y, z)
normValue = sqrt(x(:).^2 + y(:).^2 + z(:).^2);
normValue(~isfinite(x(:)) | ~isfinite(y(:)) | ~isfinite(z(:))) = NaN;
end

function [rollDeg, pitchDeg, yawDeg] = localEulerFromQuaternion(qw, qx, qy, qz)
n = numel(qw);
rollDeg = nan(n, 1);
pitchDeg = nan(n, 1);
yawDeg = nan(n, 1);
for k = 1:n
    q = [qw(k); qx(k); qy(k); qz(k)];
    if all(isfinite(q))
        [rollDeg(k), pitchDeg(k), yawDeg(k)] = caelum.quaternionToEulerZYX(q);
    end
end
end

function values = localTruthNumeric(truth, fieldNames, t)
values = nan(numel(t), 1);
if ~isstruct(truth) || ~isfield(truth, 't')
    return;
end

selected = "";
for k = 1:numel(fieldNames)
    if isfield(truth, char(fieldNames(k)))
        selected = fieldNames(k);
        break;
    end
end
if selected == ""
    return;
end

sourceT = double(truth.t(:));
sourceV = double(truth.(char(selected))(:));
valid = isfinite(sourceT) & isfinite(sourceV);
if nnz(valid) < 2
    return;
end
values = interp1(sourceT(valid), sourceV(valid), t, 'linear', NaN);
end

function tilt = localTiltError(rollDeg, pitchDeg, truthRollDeg, truthPitchDeg)
tilt = nan(numel(rollDeg), 1);
valid = isfinite(rollDeg) & isfinite(pitchDeg) & ...
    isfinite(truthRollDeg) & isfinite(truthPitchDeg);
tilt(valid) = hypot(rollDeg(valid) - truthRollDeg(valid), ...
    pitchDeg(valid) - truthPitchDeg(valid));
end

function value = localConfigScalar(cfg, fieldName, defaultValue)
if isstruct(cfg) && isfield(cfg, fieldName) && isfinite(cfg.(fieldName))
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end

function [code, label, rationale] = localClassifyEvidence(audit, options)
n = height(audit);
code = zeros(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

for k = 1:n
    verticalDisagreement = ...
        (isfinite(audit.logged_minus_attitude_a_vertical_mps2(k)) && ...
            abs(audit.logged_minus_attitude_a_vertical_mps2(k)) > options.VerticalAccelDisagreementWarn_mps2) || ...
        (isfinite(audit.projected_minus_logged_a_vertical_mps2(k)) && ...
            abs(audit.projected_minus_logged_a_vertical_mps2(k)) > options.VerticalAccelDisagreementWarn_mps2);
    truthAccelHigh = ...
        (isfinite(audit.logged_truth_error_a_vertical_mps2(k)) && ...
            abs(audit.logged_truth_error_a_vertical_mps2(k)) > options.TruthVerticalAccelWarn_mps2) || ...
        (isfinite(audit.attitude_truth_error_a_vertical_mps2(k)) && ...
            abs(audit.attitude_truth_error_a_vertical_mps2(k)) > options.TruthVerticalAccelWarn_mps2);

    if ~audit.raw_imu_available(k) || ~audit.logged_vertical_available(k)
        code(k) = 1;
        label(k) = "telemetry_incomplete";
        rationale(k) = "Raw IMU or logged vertical-acceleration telemetry is unavailable.";
    elseif audit.sample_gap(k)
        code(k) = 2;
        label(k) = "sample_gap";
        rationale(k) = "Timestamp gap exceeded the configured sample-gap threshold.";
    elseif audit.logged_gravity_available(k) && ...
            abs(audit.logged_g_norm_error_mps2(k)) > options.GravityNormTolerance_mps2
        code(k) = 3;
        label(k) = "logged_gravity_norm_bad";
        rationale(k) = "Logged firmware gravity vector norm is outside tolerance.";
    elseif audit.attitude_gravity_available(k) && ...
            abs(audit.attitude_g_norm_error_mps2(k)) > options.GravityNormTolerance_mps2
        code(k) = 4;
        label(k) = "attitude_gravity_norm_bad";
        rationale(k) = "Replayed attitude gravity vector norm is outside tolerance.";
    elseif isfinite(audit.tilt_error_deg(k)) && audit.tilt_error_deg(k) > options.TiltWarn_deg
        code(k) = 5;
        label(k) = "tilt_error_high";
        rationale(k) = "Accelerometer gravity direction and attitude-predicted gravity direction disagree.";
    elseif isfinite(audit.gravity_residual_mps2(k)) && ...
            abs(audit.gravity_residual_mps2(k)) > options.GravityResidualWarn_mps2
        code(k) = 6;
        label(k) = "gravity_residual_high";
        rationale(k) = "Accelerometer norm is far from gravity, so gravity correction is not inertial-only evidence.";
    elseif verticalDisagreement
        code(k) = 7;
        label(k) = "vertical_accel_disagreement";
        rationale(k) = "Logged, projected, and attitude-derived vertical acceleration disagree beyond tolerance.";
    elseif truthAccelHigh
        code(k) = 8;
        label(k) = "truth_accel_error_high";
        rationale(k) = "A vertical-acceleration source exceeds the truth-aware error threshold.";
    elseif ~audit.attitude_evidence_available(k)
        code(k) = 9;
        label(k) = "attitude_evidence_missing";
        rationale(k) = "Attitude replay/update evidence is unavailable, so only logged projection can be audited.";
    elseif audit.gravity_update_used(k)
        code(k) = 10;
        label(k) = "gravity_update_used";
        rationale(k) = "Attitude replay accepted an accelerometer gravity update.";
    elseif audit.attitude_evidence_available(k)
        code(k) = 11;
        label(k) = "attitude_propagated";
        rationale(k) = "Attitude replay propagated gyro state without an accelerometer gravity update.";
    else
        code(k) = 12;
        label(k) = "nominal";
        rationale(k) = "Vertical acceleration and gravity evidence are finite and within configured tolerances.";
    end
end
end

function audit = build3DTrajectoryWindAudit(est3d, T, options)
%BUILD3DTRAJECTORYWINDAUDIT Derive 3D trajectory and wind uncertainty evidence.
%
% The audit preserves replayed 3D EKF state, covariance-derived uncertainty,
% raw GPS measurements where they occur, and optional truth deltas. Display
% radii are capped separately from the raw uncertainty columns.
arguments
    est3d table
    T table = table()
    options.Truth struct = struct()
    options.TubeSigmaScale (1,1) double {mustBePositive} = 2.0
    options.MinDisplayTubeRadius_m (1,1) double {mustBeNonnegative} = 0.25
    options.MaxDisplayTubeRadius_m (1,1) double {mustBePositive} = 50.0
    options.PositionSigmaWarn_m (1,1) double {mustBePositive} = 25.0
    options.WindSigmaWarn_m (1,1) double {mustBePositive} = 6.0
    options.PositionResidualWarn_m (1,1) double {mustBePositive} = 15.0
    options.VelocityResidualWarn_mps (1,1) double {mustBePositive} = 5.0
end

n = height(est3d);
vars = string(est3d.Properties.VariableNames);

audit = table();
audit.t = localColumn(est3d, vars, "t", n, NaN);
audit.px_m = localColumn(est3d, vars, "px", n, NaN);
audit.py_m = localColumn(est3d, vars, "py", n, NaN);
audit.pz_m = localColumn(est3d, vars, "pz", n, NaN);
audit.vx_mps = localColumn(est3d, vars, "vx", n, NaN);
audit.vy_mps = localColumn(est3d, vars, "vy", n, NaN);
audit.vz_mps = localColumn(est3d, vars, "vz", n, NaN);
audit.wx_mps = localColumn(est3d, vars, "wx", n, NaN);
audit.wy_mps = localColumn(est3d, vars, "wy", n, NaN);
audit.wz_mps = localColumn(est3d, vars, "wz", n, NaN);

audit.sigma_px_m = localColumn(est3d, vars, "sigma_px", n, NaN);
audit.sigma_py_m = localColumn(est3d, vars, "sigma_py", n, NaN);
audit.sigma_pz_m = localColumn(est3d, vars, "sigma_pz", n, NaN);
audit.sigma_vx_mps = localColumn(est3d, vars, "sigma_vx", n, NaN);
audit.sigma_vy_mps = localColumn(est3d, vars, "sigma_vy", n, NaN);
audit.sigma_vz_mps = localColumn(est3d, vars, "sigma_vz", n, NaN);
audit.sigma_wx_mps = localColumn(est3d, vars, "sigma_wx", n, NaN);
audit.sigma_wy_mps = localColumn(est3d, vars, "sigma_wy", n, NaN);
audit.sigma_wz_mps = localColumn(est3d, vars, "sigma_wz", n, NaN);

audit.gps_used = localLogicalColumn(est3d, vars, "gps_used", n);
audit.gps_rejected = localLogicalColumn(est3d, vars, "gps_rejected", n);
audit.innovation_pos_norm_m = localColumn(est3d, vars, "innovation_pos_norm", n, NaN);
audit.innovation_vel_norm_mps = localColumn(est3d, vars, "innovation_vel_norm", n, NaN);

audit.gps_x_m = localTelemetryColumnAtReplayTime(T, audit.t, "gps_x");
audit.gps_y_m = localTelemetryColumnAtReplayTime(T, audit.t, "gps_y");
audit.gps_z_m = localTelemetryColumnAtReplayTime(T, audit.t, "gps_z");
audit.gps_vx_mps = localTelemetryColumnAtReplayTime(T, audit.t, "gps_vx");
audit.gps_vy_mps = localTelemetryColumnAtReplayTime(T, audit.t, "gps_vy");
audit.gps_vz_mps = localTelemetryColumnAtReplayTime(T, audit.t, "gps_vz");
audit.gps_position_available = all(isfinite([audit.gps_x_m audit.gps_y_m audit.gps_z_m]), 2);
audit.gps_velocity_available = all(isfinite([audit.gps_vx_mps audit.gps_vy_mps audit.gps_vz_mps]), 2);
audit.gps_measurement_available = audit.gps_position_available | audit.gps_velocity_available;

audit.fused_ground_vx_mps = audit.vx_mps + audit.wx_mps;
audit.fused_ground_vy_mps = audit.vy_mps + audit.wy_mps;
audit.fused_ground_vz_mps = audit.vz_mps + audit.wz_mps;

audit.gps_position_residual_norm_m = localVectorNorm( ...
    audit.gps_x_m - audit.px_m, ...
    audit.gps_y_m - audit.py_m, ...
    audit.gps_z_m - audit.pz_m, ...
    audit.gps_position_available);
audit.gps_velocity_residual_norm_mps = localVectorNorm( ...
    audit.gps_vx_mps - audit.fused_ground_vx_mps, ...
    audit.gps_vy_mps - audit.fused_ground_vy_mps, ...
    audit.gps_vz_mps - audit.fused_ground_vz_mps, ...
    audit.gps_velocity_available);

audit.position_sigma_horizontal_m = hypot(audit.sigma_px_m, audit.sigma_py_m);
audit.position_sigma_norm_m = localVectorNorm( ...
    audit.sigma_px_m, audit.sigma_py_m, audit.sigma_pz_m, ...
    all(isfinite([audit.sigma_px_m audit.sigma_py_m audit.sigma_pz_m]), 2));
audit.velocity_sigma_norm_mps = localVectorNorm( ...
    audit.sigma_vx_mps, audit.sigma_vy_mps, audit.sigma_vz_mps, ...
    all(isfinite([audit.sigma_vx_mps audit.sigma_vy_mps audit.sigma_vz_mps]), 2));
audit.wind_sigma_norm_mps = localVectorNorm( ...
    audit.sigma_wx_mps, audit.sigma_wy_mps, audit.sigma_wz_mps, ...
    all(isfinite([audit.sigma_wx_mps audit.sigma_wy_mps audit.sigma_wz_mps]), 2));
audit.wind_speed_mps = localVectorNorm( ...
    audit.wx_mps, audit.wy_mps, audit.wz_mps, ...
    all(isfinite([audit.wx_mps audit.wy_mps audit.wz_mps]), 2));

audit.tube_sigma_scale = repmat(options.TubeSigmaScale, n, 1);
audit.tube_radius_m = options.TubeSigmaScale .* audit.position_sigma_horizontal_m;
audit.tube_vertical_half_width_m = options.TubeSigmaScale .* audit.sigma_pz_m;
audit.display_tube_radius_m = min(max(audit.tube_radius_m, options.MinDisplayTubeRadius_m), ...
    options.MaxDisplayTubeRadius_m);
audit.display_tube_vertical_half_width_m = min(max(audit.tube_vertical_half_width_m, ...
    options.MinDisplayTubeRadius_m), options.MaxDisplayTubeRadius_m);

audit.truth_x_m = localTruthColumn(options.Truth, audit.t, ["x_true","x","px"]);
audit.truth_y_m = localTruthColumn(options.Truth, audit.t, ["y_true","y","py"]);
audit.truth_z_m = localTruthColumn(options.Truth, audit.t, ["z_true","h_true","z","pz"]);
audit.truth_position_available = all(isfinite([audit.truth_x_m audit.truth_y_m audit.truth_z_m]), 2);
audit.truth_position_error_norm_m = localVectorNorm( ...
    audit.px_m - audit.truth_x_m, ...
    audit.py_m - audit.truth_y_m, ...
    audit.pz_m - audit.truth_z_m, ...
    audit.truth_position_available);

[truthWx, truthWy, truthWz] = localTruthWind(options.Truth, audit.t);
audit.truth_wx_mps = truthWx;
audit.truth_wy_mps = truthWy;
audit.truth_wz_mps = truthWz;
audit.truth_wind_available = all(isfinite([truthWx truthWy truthWz]), 2);
audit.truth_wind_error_norm_mps = localVectorNorm( ...
    audit.wx_mps - truthWx, ...
    audit.wy_mps - truthWy, ...
    audit.wz_mps - truthWz, ...
    audit.truth_wind_available);

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

function values = localLogicalColumn(T, vars, fieldName, n)
if ismember(fieldName, vars)
    values = double(T.(char(fieldName))) > 0.5;
else
    values = false(n, 1);
end
values = values(:);
end

function values = localTelemetryColumnAtReplayTime(T, replayTime, fieldName)
n = numel(replayTime);
values = nan(n, 1);
if isempty(T) || ~istable(T)
    return;
end
vars = string(T.Properties.VariableNames);
if ~ismember(fieldName, vars) || ~ismember("t", vars)
    return;
end

sourceTime = double(T.t(:));
sourceValues = double(T.(char(fieldName)));
for k = 1:n
    if ~isfinite(replayTime(k))
        continue;
    end
    idx = find(abs(sourceTime - replayTime(k)) <= 1e-9, 1, 'first');
    if ~isempty(idx)
        values(k) = sourceValues(idx);
    end
end
end

function values = localTruthColumn(truth, replayTime, fieldNames)
n = numel(replayTime);
values = nan(n, 1);
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

truthTime = double(truth.t(:));
truthValues = double(truth.(char(selected)));
if numel(truthValues) ~= numel(truthTime)
    return;
end
values = interp1(truthTime, truthValues(:), replayTime, 'linear', NaN);
end

function [wx, wy, wz] = localTruthWind(truth, replayTime)
n = numel(replayTime);
wx = nan(n, 1);
wy = nan(n, 1);
wz = nan(n, 1);
if ~isstruct(truth)
    return;
end

if isfield(truth, 'wind_true') && isfield(truth, 't')
    windTrue = double(truth.wind_true);
    truthTime = double(truth.t(:));
    if size(windTrue, 1) == numel(truthTime) && size(windTrue, 2) >= 3
        wx = interp1(truthTime, windTrue(:,1), replayTime, 'linear', NaN);
        wy = interp1(truthTime, windTrue(:,2), replayTime, 'linear', NaN);
        wz = interp1(truthTime, windTrue(:,3), replayTime, 'linear', NaN);
        return;
    end
end

if all(isfield(truth, {'wx_true','wy_true','wz_true'})) && isfield(truth, 't')
    truthTime = double(truth.t(:));
    wx = interp1(truthTime, double(truth.wx_true(:)), replayTime, 'linear', NaN);
    wy = interp1(truthTime, double(truth.wy_true(:)), replayTime, 'linear', NaN);
    wz = interp1(truthTime, double(truth.wz_true(:)), replayTime, 'linear', NaN);
end
end

function normValue = localVectorNorm(x, y, z, validMask)
normValue = nan(numel(x), 1);
valid = validMask(:) & isfinite(x(:)) & isfinite(y(:)) & isfinite(z(:));
normValue(valid) = sqrt(x(valid).^2 + y(valid).^2 + z(valid).^2);
end

function [code, label, rationale] = localClassifyEvidence(audit, options)
n = height(audit);
code = zeros(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

for k = 1:n
    stateMissing = ~all(isfinite([audit.px_m(k), audit.py_m(k), audit.pz_m(k), ...
        audit.vx_mps(k), audit.vy_mps(k), audit.vz_mps(k), ...
        audit.wx_mps(k), audit.wy_mps(k), audit.wz_mps(k)]));
    covarianceMissing = ~isfinite(audit.position_sigma_norm_m(k)) || ...
        ~isfinite(audit.wind_sigma_norm_mps(k));

    if stateMissing
        code(k) = 1;
        label(k) = "state_incomplete";
        rationale(k) = "3D EKF position, velocity, or wind state is unavailable.";
    elseif covarianceMissing
        code(k) = 2;
        label(k) = "covariance_incomplete";
        rationale(k) = "3D EKF position or wind covariance evidence is unavailable.";
    elseif audit.gps_rejected(k)
        code(k) = 3;
        label(k) = "gps_rejected";
        rationale(k) = "GPS update was rejected by the 3D EKF gate or covariance checks.";
    elseif isfinite(audit.gps_position_residual_norm_m(k)) && ...
            audit.gps_position_residual_norm_m(k) > options.PositionResidualWarn_m
        code(k) = 4;
        label(k) = "gps_position_residual_high";
        rationale(k) = "GPS position residual exceeds the configured warning threshold.";
    elseif isfinite(audit.gps_velocity_residual_norm_mps(k)) && ...
            audit.gps_velocity_residual_norm_mps(k) > options.VelocityResidualWarn_mps
        code(k) = 5;
        label(k) = "gps_velocity_residual_high";
        rationale(k) = "GPS ground-velocity residual exceeds the configured warning threshold.";
    elseif audit.position_sigma_norm_m(k) > options.PositionSigmaWarn_m
        code(k) = 6;
        label(k) = "position_uncertainty_high";
        rationale(k) = "3D position covariance norm exceeds the configured warning threshold.";
    elseif audit.wind_sigma_norm_mps(k) > options.WindSigmaWarn_m
        code(k) = 7;
        label(k) = "wind_uncertainty_high";
        rationale(k) = "Wind covariance norm exceeds the configured warning threshold.";
    elseif audit.gps_used(k)
        code(k) = 8;
        label(k) = "gps_update_used";
        rationale(k) = "GPS position or ground-velocity update was accepted.";
    elseif audit.gps_measurement_available(k)
        code(k) = 9;
        label(k) = "gps_measurement_not_used";
        rationale(k) = "GPS measurement fields are present but no accepted/rejected update was logged.";
    else
        code(k) = 10;
        label(k) = "inertial_propagation_only";
        rationale(k) = "No GPS measurement was available at this sample; 3D state propagated inertially.";
    end
end
end

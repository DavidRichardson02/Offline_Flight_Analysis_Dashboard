function audit = buildEstimatorTrustAudit(T, replay, cfg, options)
%BUILDESTIMATORTRUSTAUDIT Derive vertical-estimator trust evidence.
%
% The audit separates logged firmware state, MATLAB replay state, measurement
% innovation evidence, covariance, and optional truth error on a common
% timebase. Classification labels are dashboard evidence, not firmware state.
arguments
    T table
    replay table = table()
    cfg struct = caelum.defaultConfig()
    options.Truth struct = struct()
    options.InnovationSigmaThreshold (1,1) double = 3.0
    options.LoggedReplayAltitudeTolerance_m (1,1) double = 5.0
    options.LoggedReplayVelocityTolerance_mps (1,1) double = 5.0
    options.TruthAltitudeTolerance_m (1,1) double = 10.0
    options.TruthVelocityTolerance_mps (1,1) double = 10.0
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

n = height(T);
vars = string(T.Properties.VariableNames);
t = localColumn(T, vars, "t", n, NaN);
replayVars = localTableVars(replay);

audit = table();
audit.t = t;
audit.sample_gap = localLogicalColumn(T, vars, "sample_gap", n);
audit.baro_alt_m = localColumn(T, vars, "bmp_alt_rel", n, NaN);
audit.logged_h_m = localColumn(T, vars, "kf_h", n, NaN);
audit.logged_v_mps = localColumn(T, vars, "kf_v", n, NaN);
audit.logged_sigma_h_m = localColumn(T, vars, "kf_sigma_h", n, NaN);
audit.logged_sigma_v_mps = localColumn(T, vars, "kf_sigma_v", n, NaN);

if ~ismember("kf_sigma_h", vars) && ismember("P00", vars)
    audit.logged_sigma_h_m = sqrt(max(localColumn(T, vars, "P00", n, NaN), 0));
end
if ~ismember("kf_sigma_v", vars) && ismember("P11", vars)
    audit.logged_sigma_v_mps = sqrt(max(localColumn(T, vars, "P11", n, NaN), 0));
end

audit.replay_h_m = localReplayNumeric(replay, replayVars, "h", t, NaN);
audit.replay_v_mps = localReplayNumeric(replay, replayVars, "v", t, NaN);
audit.replay_b_a_mps2 = localReplayNumeric(replay, replayVars, "b_a", t, NaN);
audit.replay_beta = localReplayNumeric(replay, replayVars, "beta", t, NaN);
audit.replay_sigma_h_m = localReplayNumeric(replay, replayVars, "sigma_h", t, NaN);
audit.replay_sigma_v_mps = localReplayNumeric(replay, replayVars, "sigma_v", t, NaN);
audit.replay_sigma_b_a_mps2 = localReplayNumeric(replay, replayVars, "sigma_b_a", t, NaN);
audit.replay_sigma_beta = localReplayNumeric(replay, replayVars, "sigma_beta", t, NaN);

audit.logged_minus_replay_h_m = audit.logged_h_m - audit.replay_h_m;
audit.logged_minus_replay_v_mps = audit.logged_v_mps - audit.replay_v_mps;

audit.innovation_h_m = localReplayNumeric(replay, replayVars, "innovation_h", t, NaN);
audit.innovation_sigma_h_m = localReplayNumeric(replay, replayVars, "innovation_sigma_h", t, NaN);
audit.innovation_z_h = localReplayNumeric(replay, replayVars, "innovation_z_h", t, NaN);
audit.innovation_nis = localReplayNumeric(replay, replayVars, "innovation_nis", t, NaN);
audit.baro_used = localReplayLogical(replay, replayVars, "baro_used", t, n);
audit.baro_rejected = localReplayLogical(replay, replayVars, "baro_rejected", t, n);

audit.baro_gate_threshold_nis = repmat(localConfigScalar(cfg, "kBaroNISGate", NaN), n, 1);
audit.innovation_sigma_threshold = repmat(options.InnovationSigmaThreshold, n, 1);
audit.innovation_within_sigma_band = isfinite(audit.innovation_h_m) & ...
    isfinite(audit.innovation_sigma_h_m) & ...
    abs(audit.innovation_h_m) <= options.InnovationSigmaThreshold .* audit.innovation_sigma_h_m;
audit.nis_within_gate = isfinite(audit.innovation_nis) & ...
    (isnan(audit.baro_gate_threshold_nis) | audit.innovation_nis <= audit.baro_gate_threshold_nis);

audit.a_vertical_used_mps2 = localReplayNumeric(replay, replayVars, "a_vertical_used", t, NaN);
audit.accel_input_mps2 = localReplayNumeric(replay, replayVars, "accel_input", t, NaN);
audit.accel_effective_mps2 = localReplayNumeric(replay, replayVars, "accel_effective", t, NaN);
audit.drag_accel_mps2 = localReplayNumeric(replay, replayVars, "drag_accel", t, NaN);
audit.beta_learning_enabled = localReplayLogical(replay, replayVars, "beta_learning_enabled", t, n);
audit.attitude_fallback_used = localReplayLogical(replay, replayVars, "attitude_fallback_used", t, n);
audit.vertical_input_mode = localReplayString(replay, replayVars, "vertical_input_mode", t, "unknown");

truth = options.Truth;
audit.truth_h_m = localTruthNumeric(truth, "h_true", t);
audit.truth_v_mps = localTruthNumeric(truth, "v_true", t);
audit.logged_truth_error_h_m = audit.logged_h_m - audit.truth_h_m;
audit.logged_truth_error_v_mps = audit.logged_v_mps - audit.truth_v_mps;
audit.replay_truth_error_h_m = audit.replay_h_m - audit.truth_h_m;
audit.replay_truth_error_v_mps = audit.replay_v_mps - audit.truth_v_mps;

audit.logged_replay_h_divergent = isfinite(audit.logged_minus_replay_h_m) & ...
    abs(audit.logged_minus_replay_h_m) > options.LoggedReplayAltitudeTolerance_m;
audit.logged_replay_v_divergent = isfinite(audit.logged_minus_replay_v_mps) & ...
    abs(audit.logged_minus_replay_v_mps) > options.LoggedReplayVelocityTolerance_mps;
audit.replay_truth_h_high = isfinite(audit.replay_truth_error_h_m) & ...
    abs(audit.replay_truth_error_h_m) > options.TruthAltitudeTolerance_m;
audit.replay_truth_v_high = isfinite(audit.replay_truth_error_v_mps) & ...
    abs(audit.replay_truth_error_v_mps) > options.TruthVelocityTolerance_mps;

[audit.trust_code, audit.trust_label, audit.trust_rationale] = ...
    localClassifyTrustEvidence(audit);
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

function vars = localTableVars(T)
if istable(T) && ~isempty(T)
    vars = string(T.Properties.VariableNames);
else
    vars = strings(0, 1);
end
end

function values = localReplayNumeric(replay, replayVars, fieldName, t, defaultValue)
n = numel(t);
values = repmat(defaultValue, n, 1);
if ~istable(replay) || isempty(replay) || ~ismember("t", replayVars) || ~ismember(fieldName, replayVars)
    return;
end

sourceT = double(replay.t(:));
sourceV = double(replay.(char(fieldName))(:));
validT = isfinite(sourceT);
if ~any(validT)
    return;
end
if nnz(validT) == 1
    values(:) = sourceV(validT);
    return;
end
values = interp1(sourceT(validT), sourceV(validT), t, 'linear', NaN);
end

function values = localReplayLogical(replay, replayVars, fieldName, t, n)
numeric = localReplayNumeric(replay, replayVars, fieldName, t, NaN);
values = false(n, 1);
values(isfinite(numeric)) = numeric(isfinite(numeric)) > 0.5;
end

function values = localReplayString(replay, replayVars, fieldName, t, defaultValue)
n = numel(t);
values = repmat(string(defaultValue), n, 1);
if ~istable(replay) || isempty(replay) || ~ismember("t", replayVars) || ~ismember(fieldName, replayVars)
    return;
end

sourceT = double(replay.t(:));
sourceIdx = (1:height(replay)).';
valid = isfinite(sourceT);
if ~any(valid)
    return;
end
idx = interp1(sourceT(valid), sourceIdx(valid), t, 'nearest', NaN);
target = string(replay.(char(fieldName)));
for k = 1:n
    if isfinite(idx(k)) && idx(k) >= 1 && idx(k) <= numel(target)
        values(k) = target(round(idx(k)));
    end
end
end

function values = localTruthNumeric(truth, fieldName, t)
values = nan(numel(t), 1);
if ~isstruct(truth) || ~isfield(truth, "t") || ~isfield(truth, fieldName)
    return;
end

sourceT = double(truth.t(:));
sourceV = double(truth.(fieldName)(:));
valid = isfinite(sourceT) & isfinite(sourceV);
if nnz(valid) < 2
    return;
end
values = interp1(sourceT(valid), sourceV(valid), t, 'linear', NaN);
end

function value = localConfigScalar(cfg, fieldName, defaultValue)
if isstruct(cfg) && isfield(cfg, fieldName) && isfinite(cfg.(fieldName))
    value = cfg.(fieldName);
else
    value = defaultValue;
end
end

function [code, label, rationale] = localClassifyTrustEvidence(audit)
n = height(audit);
code = zeros(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

for k = 1:n
    missingReplay = ~isfinite(audit.replay_h_m(k)) || ...
        ~isfinite(audit.replay_v_mps(k)) || ...
        ~isfinite(audit.replay_sigma_h_m(k)) || ...
        ~isfinite(audit.replay_sigma_v_mps(k));
    missingInnovation = ~isfinite(audit.innovation_h_m(k)) || ...
        ~isfinite(audit.innovation_sigma_h_m(k)) || ...
        ~isfinite(audit.innovation_nis(k));

    if missingReplay
        code(k) = 1;
        label(k) = "replay_incomplete";
        rationale(k) = "Replay state or covariance is unavailable at this sample.";
    elseif audit.sample_gap(k)
        code(k) = 2;
        label(k) = "sample_gap";
        rationale(k) = "Timestamp gap exceeded the configured sample-gap threshold.";
    elseif audit.baro_rejected(k)
        code(k) = 3;
        label(k) = "baro_rejected";
        rationale(k) = "Barometric measurement was rejected by estimator gating.";
    elseif ~missingInnovation && ~audit.nis_within_gate(k)
        code(k) = 4;
        label(k) = "nis_gate_exceeded";
        rationale(k) = "Barometric innovation NIS exceeds the configured gate.";
    elseif ~missingInnovation && ~audit.innovation_within_sigma_band(k)
        code(k) = 5;
        label(k) = "innovation_outside_band";
        rationale(k) = "Barometric innovation exceeds the configured sigma band.";
    elseif audit.logged_replay_h_divergent(k) || audit.logged_replay_v_divergent(k)
        code(k) = 6;
        label(k) = "logged_replay_divergent";
        rationale(k) = "Logged firmware state differs materially from MATLAB replay.";
    elseif audit.replay_truth_h_high(k) || audit.replay_truth_v_high(k)
        code(k) = 7;
        label(k) = "truth_error_high";
        rationale(k) = "Replay state error exceeds truth-aware validation threshold.";
    elseif audit.baro_used(k)
        code(k) = 8;
        label(k) = "trusted_update";
        rationale(k) = "Replay state is finite and a barometric update was accepted.";
    else
        code(k) = 9;
        label(k) = "predict_only";
        rationale(k) = "Replay state is finite, but no barometric update was accepted at this sample.";
    end
end
end

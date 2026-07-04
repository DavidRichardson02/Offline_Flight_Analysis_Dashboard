function [sampleAudit, fieldSummary] = buildReplayContractDiffAudit(T, replay, cfg, options)
%BUILDREPLAYCONTRACTDIFFAUDIT Compare logged firmware estimator state to replay.
%
% The sample audit preserves time-local evidence: logged firmware telemetry,
% MATLAB replay state, deltas, update/gating flags, and one classification
% label per sample. The field summary provides the review-facing contract
% table: coverage, tolerance, max/mean/RMSE delta, match rate, and pass state.
arguments
    T table
    replay table = table()
    cfg struct = caelum.defaultConfig()
    options.FieldContract table = table()
    options.TimeTolerance_s (1,1) double {mustBeNonnegative} = 1.0e-9
    options.InputTolerance_mps2 (1,1) double {mustBeNonnegative} = 1.0e-6
    options.AltitudeTolerance_m (1,1) double {mustBeNonnegative} = 5.0
    options.VelocityTolerance_mps (1,1) double {mustBeNonnegative} = 5.0
    options.SigmaTolerance (1,1) double {mustBeNonnegative} = 2.0
    options.CovarianceTolerance (1,1) double {mustBeNonnegative} = 5.0
end

if isempty(T) || height(T) < 1
    error('caelum:buildReplayContractDiffAudit:EmptyLog', ...
        'Clean log table must contain at least one row.');
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

fieldContract = options.FieldContract;
if isempty(fieldContract)
    fieldContract = caelum.getVerticalReplayFieldContract();
end

t = localColumn(T, "t", height(T), NaN);
replayVars = localTableVars(replay);

sampleAudit = table();
sampleAudit.t = t;
sampleAudit.sample_gap = localLogicalColumn(T, "sample_gap", height(T));
sampleAudit.logged_estimator_available = localAnyFieldFinite(T, ["a_vertical","kf_h","kf_v","P00","P11"]);
sampleAudit.replay_available = localReplayAvailable(replay, replayVars, t);
sampleAudit.nearest_replay_dt_s = localNearestReplayDelta(replay, replayVars, t);
sampleAudit.time_aligned = isfinite(sampleAudit.nearest_replay_dt_s) & ...
    abs(sampleAudit.nearest_replay_dt_s) <= options.TimeTolerance_s;

sampleAudit.logged_a_vertical_mps2 = localColumn(T, "a_vertical", height(T), NaN);
sampleAudit.replay_a_vertical_used_mps2 = localReplayNumeric(replay, replayVars, "a_vertical_used", t, NaN);
sampleAudit.delta_a_vertical_mps2 = sampleAudit.logged_a_vertical_mps2 - sampleAudit.replay_a_vertical_used_mps2;

sampleAudit.logged_h_m = localColumn(T, "kf_h", height(T), NaN);
sampleAudit.replay_h_m = localReplayNumeric(replay, replayVars, "h", t, NaN);
sampleAudit.delta_h_m = sampleAudit.logged_h_m - sampleAudit.replay_h_m;

sampleAudit.logged_v_mps = localColumn(T, "kf_v", height(T), NaN);
sampleAudit.replay_v_mps = localReplayNumeric(replay, replayVars, "v", t, NaN);
sampleAudit.delta_v_mps = sampleAudit.logged_v_mps - sampleAudit.replay_v_mps;

sampleAudit.logged_sigma_h_m = localLoggedSigma(T, "P00", height(T));
sampleAudit.replay_sigma_h_m = localReplayNumeric(replay, replayVars, "sigma_h", t, NaN);
sampleAudit.delta_sigma_h_m = sampleAudit.logged_sigma_h_m - sampleAudit.replay_sigma_h_m;

sampleAudit.logged_sigma_v_mps = localLoggedSigma(T, "P11", height(T));
sampleAudit.replay_sigma_v_mps = localReplayNumeric(replay, replayVars, "sigma_v", t, NaN);
sampleAudit.delta_sigma_v_mps = sampleAudit.logged_sigma_v_mps - sampleAudit.replay_sigma_v_mps;

sampleAudit.logged_P00 = localColumn(T, "P00", height(T), NaN);
sampleAudit.replay_P00 = localReplayNumeric(replay, replayVars, "P00", t, NaN);
sampleAudit.delta_P00 = sampleAudit.logged_P00 - sampleAudit.replay_P00;

sampleAudit.logged_P11 = localColumn(T, "P11", height(T), NaN);
sampleAudit.replay_P11 = localReplayNumeric(replay, replayVars, "P11", t, NaN);
sampleAudit.delta_P11 = sampleAudit.logged_P11 - sampleAudit.replay_P11;

sampleAudit.replay_baro_used = localReplayLogical(replay, replayVars, "baro_used", t, height(T));
sampleAudit.replay_baro_rejected = localReplayLogical(replay, replayVars, "baro_rejected", t, height(T));
sampleAudit.replay_vertical_input_mode = localReplayString(replay, replayVars, "vertical_input_mode", t, "unknown");
sampleAudit.replay_attitude_fallback_used = localReplayLogical(replay, replayVars, "attitude_fallback_used", t, height(T));
sampleAudit.est_valid = localLogicalColumn(T, "est_valid", height(T));
sampleAudit.est_updated = localLogicalColumn(T, "est_updated", height(T));
sampleAudit.warn_mask = localColumn(T, "warn_mask", height(T), NaN);

sampleAudit.input_delta_high = isfinite(sampleAudit.delta_a_vertical_mps2) & ...
    abs(sampleAudit.delta_a_vertical_mps2) > options.InputTolerance_mps2;
sampleAudit.state_delta_high = (isfinite(sampleAudit.delta_h_m) & abs(sampleAudit.delta_h_m) > options.AltitudeTolerance_m) | ...
    (isfinite(sampleAudit.delta_v_mps) & abs(sampleAudit.delta_v_mps) > options.VelocityTolerance_mps);
sampleAudit.sigma_delta_high = (isfinite(sampleAudit.delta_sigma_h_m) & abs(sampleAudit.delta_sigma_h_m) > options.SigmaTolerance) | ...
    (isfinite(sampleAudit.delta_sigma_v_mps) & abs(sampleAudit.delta_sigma_v_mps) > options.SigmaTolerance);
sampleAudit.covariance_delta_high = (isfinite(sampleAudit.delta_P00) & abs(sampleAudit.delta_P00) > options.CovarianceTolerance) | ...
    (isfinite(sampleAudit.delta_P11) & abs(sampleAudit.delta_P11) > options.CovarianceTolerance);
sampleAudit.warning_active = isfinite(sampleAudit.warn_mask) & sampleAudit.warn_mask ~= 0;

[sampleAudit.contract_code, sampleAudit.contract_label, sampleAudit.contract_rationale] = ...
    localClassifySamples(sampleAudit);

fieldSummary = localBuildFieldSummary(T, replay, replayVars, t, fieldContract, options);
end

function value = localColumn(T, fieldName, n, defaultValue)
if istable(T) && ismember(fieldName, string(T.Properties.VariableNames))
    value = double(T.(char(fieldName)));
else
    value = repmat(defaultValue, n, 1);
end
value = value(:);
end

function value = localLogicalColumn(T, fieldName, n)
if istable(T) && ismember(fieldName, string(T.Properties.VariableNames))
    value = double(T.(char(fieldName))) > 0.5;
else
    value = false(n, 1);
end
value = value(:);
end

function value = localAnyFieldFinite(T, fields)
value = false(height(T), 1);
vars = string(T.Properties.VariableNames);
for k = 1:numel(fields)
    fieldName = fields(k);
    if ismember(fieldName, vars)
        value = value | isfinite(double(T.(char(fieldName))));
    end
end
end

function value = localLoggedSigma(T, covarianceField, n)
value = localColumn(T, covarianceField, n, NaN);
value = sqrt(max(value, 0));
value(~isfinite(localColumn(T, covarianceField, n, NaN))) = NaN;
end

function vars = localTableVars(T)
if istable(T) && ~isempty(T)
    vars = string(T.Properties.VariableNames);
else
    vars = strings(0, 1);
end
end

function value = localReplayAvailable(replay, replayVars, t)
value = false(numel(t), 1);
if ~istable(replay) || isempty(replay) || ~ismember("t", replayVars)
    return;
end
sourceT = double(replay.t(:));
valid = isfinite(sourceT);
if any(valid)
    value = t >= min(sourceT(valid)) & t <= max(sourceT(valid));
end
end

function value = localReplayNumeric(replay, replayVars, fieldName, t, defaultValue)
n = numel(t);
value = repmat(defaultValue, n, 1);
if ~istable(replay) || isempty(replay) || ~ismember("t", replayVars) || ~ismember(fieldName, replayVars)
    return;
end

sourceT = double(replay.t(:));
sourceV = double(replay.(char(fieldName))(:));
validT = isfinite(sourceT);
if nnz(validT) < 1
    return;
elseif nnz(validT) == 1
    value(:) = sourceV(validT);
else
    value = interp1(sourceT(validT), sourceV(validT), t, 'linear', NaN);
end
end

function value = localReplayLogical(replay, replayVars, fieldName, t, n)
numeric = localReplayNumeric(replay, replayVars, fieldName, t, NaN);
value = false(n, 1);
value(isfinite(numeric)) = numeric(isfinite(numeric)) > 0.5;
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

function dt = localNearestReplayDelta(replay, replayVars, t)
dt = nan(numel(t), 1);
if ~istable(replay) || isempty(replay) || ~ismember("t", replayVars)
    return;
end

sourceT = double(replay.t(:));
valid = isfinite(sourceT);
if ~any(valid)
    return;
end

sourceT = sourceT(valid);
sourceIdx = (1:numel(sourceT)).';
idx = interp1(sourceT, sourceIdx, t, 'nearest', NaN);
for k = 1:numel(t)
    if isfinite(idx(k)) && idx(k) >= 1 && idx(k) <= numel(sourceT)
        dt(k) = t(k) - sourceT(round(idx(k)));
    end
end
end

function [code, label, rationale] = localClassifySamples(audit)
n = height(audit);
code = nan(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

for k = 1:n
    if ~audit.logged_estimator_available(k)
        code(k) = 1;
        label(k) = "logged_firmware_incomplete";
        rationale(k) = "Logged firmware estimator fields are unavailable at this sample.";
    elseif ~audit.replay_available(k)
        code(k) = 2;
        label(k) = "replay_incomplete";
        rationale(k) = "MATLAB replay state is unavailable at this sample.";
    elseif ~audit.time_aligned(k)
        code(k) = 3;
        label(k) = "timebase_mismatch";
        rationale(k) = "Nearest replay timestamp exceeds the configured alignment tolerance.";
    elseif audit.sample_gap(k)
        code(k) = 4;
        label(k) = "sample_gap";
        rationale(k) = "Cleaned telemetry contains a timestamp gap at this sample.";
    elseif audit.input_delta_high(k)
        code(k) = 5;
        label(k) = "input_contract_delta";
        rationale(k) = "Logged vertical acceleration input differs from replay input.";
    elseif audit.state_delta_high(k)
        code(k) = 6;
        label(k) = "state_contract_delta";
        rationale(k) = "Logged altitude or velocity state differs from MATLAB replay beyond tolerance.";
    elseif audit.covariance_delta_high(k) || audit.sigma_delta_high(k)
        code(k) = 7;
        label(k) = "covariance_contract_delta";
        rationale(k) = "Logged covariance or sigma evidence differs from MATLAB replay beyond tolerance.";
    elseif audit.warning_active(k)
        code(k) = 8;
        label(k) = "firmware_warning_active";
        rationale(k) = "Firmware warn_mask is nonzero while comparing replay contract evidence.";
    elseif audit.replay_baro_rejected(k)
        code(k) = 9;
        label(k) = "replay_baro_rejected";
        rationale(k) = "Replay rejected the barometric update at this sample.";
    else
        code(k) = 10;
        label(k) = "contract_nominal";
        rationale(k) = "Logged firmware and MATLAB replay evidence are within configured tolerances.";
    end
end
end

function summary = localBuildFieldSummary(T, replay, replayVars, t, fieldContract, options)
fieldMap = localFieldMap(options);
summary = table('Size', [size(fieldMap, 1) 15], ...
    'VariableTypes', {'string','string','string','string','string','logical','logical','double','double','double','double','double','double','logical','string'}, ...
    'VariableNames', {'contract_field','logged_field','replay_field','units','comparison','required_for_firmware','parity_checked', ...
    'tolerance','samples_compared','finite_fraction_logged','finite_fraction_replay','match_rate','max_abs_diff','pass','notes'});

for k = 1:size(fieldMap, 1)
    contractField = fieldMap(k, 1);
    loggedField = fieldMap(k, 2);
    replayField = fieldMap(k, 3);
    tolerance = str2double(fieldMap(k, 4));

    summary.contract_field(k) = contractField;
    summary.logged_field(k) = loggedField;
    summary.replay_field(k) = replayField;
    summary.tolerance(k) = tolerance;
    summary.units(k) = localContractText(fieldContract, contractField, "units", "");
    summary.required_for_firmware(k) = localContractLogical(fieldContract, contractField, "required_for_firmware");
    summary.parity_checked(k) = localContractLogical(fieldContract, contractField, "parity_checked");

    if ~ismember(loggedField, string(T.Properties.VariableNames)) || ...
            ~ismember(replayField, replayVars)
        summary.comparison(k) = "missing";
        summary.samples_compared(k) = 0;
        summary.finite_fraction_logged(k) = localFiniteFraction(T, loggedField);
        summary.finite_fraction_replay(k) = localReplayFiniteFraction(replay, replayVars, replayField);
        summary.match_rate(k) = NaN;
        summary.max_abs_diff(k) = NaN;
        summary.pass(k) = false;
        summary.notes(k) = "Field missing from logged firmware table or MATLAB replay table.";
        continue;
    end

    logged = localColumn(T, loggedField, height(T), NaN);
    replayValue = localReplayNumeric(replay, replayVars, replayField, t, NaN);
    valid = isfinite(logged) & isfinite(replayValue);
    diff = abs(logged(valid) - replayValue(valid));

    summary.comparison(k) = "numeric";
    summary.samples_compared(k) = nnz(valid);
    summary.finite_fraction_logged(k) = mean(isfinite(logged));
    summary.finite_fraction_replay(k) = mean(isfinite(replayValue));
    if isempty(diff)
        summary.match_rate(k) = NaN;
        summary.max_abs_diff(k) = NaN;
        summary.pass(k) = false;
        summary.notes(k) = "No overlapping finite samples.";
    else
        matches = diff <= tolerance;
        summary.match_rate(k) = mean(matches);
        summary.max_abs_diff(k) = max(diff);
        summary.pass(k) = all(matches);
        summary.notes(k) = "";
    end
end

summary.mean_abs_diff = nan(height(summary), 1);
summary.rmse_diff = nan(height(summary), 1);
for k = 1:height(summary)
    if summary.comparison(k) ~= "numeric" || summary.samples_compared(k) < 1
        continue;
    end
    logged = localColumn(T, summary.logged_field(k), height(T), NaN);
    replayValue = localReplayNumeric(replay, replayVars, summary.replay_field(k), t, NaN);
    valid = isfinite(logged) & isfinite(replayValue);
    diff = logged(valid) - replayValue(valid);
    summary.mean_abs_diff(k) = mean(abs(diff), 'omitnan');
    summary.rmse_diff(k) = sqrt(mean(diff.^2, 'omitnan'));
end

summary = movevars(summary, {'mean_abs_diff','rmse_diff'}, 'After', 'max_abs_diff');
end

function fieldMap = localFieldMap(options)
fieldMap = [ ...
    "a_vertical_used","a_vertical","a_vertical_used",string(options.InputTolerance_mps2); ...
    "h","kf_h","h",string(options.AltitudeTolerance_m); ...
    "v","kf_v","v",string(options.VelocityTolerance_mps); ...
    "sigma_h","kf_sigma_h","sigma_h",string(options.SigmaTolerance); ...
    "sigma_v","kf_sigma_v","sigma_v",string(options.SigmaTolerance); ...
    "P00","P00","P00",string(options.CovarianceTolerance); ...
    "P11","P11","P11",string(options.CovarianceTolerance)];
end

function value = localFiniteFraction(T, fieldName)
if ~istable(T) || ~ismember(fieldName, string(T.Properties.VariableNames))
    value = 0;
else
    value = mean(isfinite(double(T.(char(fieldName)))));
end
end

function value = localReplayFiniteFraction(replay, replayVars, fieldName)
if ~istable(replay) || isempty(replay) || ~ismember(fieldName, replayVars)
    value = 0;
else
    value = mean(isfinite(double(replay.(char(fieldName)))));
end
end

function value = localContractText(fieldContract, sourceName, columnName, defaultValue)
value = string(defaultValue);
if ~istable(fieldContract) || isempty(fieldContract) || ...
        ~ismember("source_name", string(fieldContract.Properties.VariableNames)) || ...
        ~ismember(columnName, string(fieldContract.Properties.VariableNames))
    return;
end
idx = find(string(fieldContract.source_name) == sourceName, 1, 'first');
if ~isempty(idx)
    value = string(fieldContract.(char(columnName))(idx));
end
end

function value = localContractLogical(fieldContract, sourceName, columnName)
value = false;
if ~istable(fieldContract) || isempty(fieldContract) || ...
        ~ismember("source_name", string(fieldContract.Properties.VariableNames)) || ...
        ~ismember(columnName, string(fieldContract.Properties.VariableNames))
    return;
end
idx = find(string(fieldContract.source_name) == sourceName, 1, 'first');
if ~isempty(idx)
    value = logical(fieldContract.(char(columnName))(idx));
end
end

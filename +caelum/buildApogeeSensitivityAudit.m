function audit = buildApogeeSensitivityAudit(T, cfg, options)
%BUILDAPOGEESENSITIVITYAUDIT Build a time-local apogee authority decomposition.
%
% The first layer uses the logged firmware policy corridor. The second layer
% adds finite-difference perturbations around the replayed vertical state using
% the same quadratic-drag apogee equation as the firmware policy.
arguments
    T table
    cfg struct = caelum.defaultConfig()
    options.Time (1,1) double = NaN
    options.Selector (1,1) string = "max_command"
    options.PolicyAudit table = table()
    options.Replay table = table()
    options.ServoMin_us (1,1) double = 1000
    options.ServoMax_us (1,1) double = 2000
    options.AltitudeStep_m (1,1) double = 1.0
    options.VelocityStep_mps (1,1) double = 1.0
    options.CommandStep (1,1) double = 0.05
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

if isempty(options.PolicyAudit)
    policyAudit = caelum.buildPolicyDecisionAudit(T, cfg);
else
    policyAudit = options.PolicyAudit;
end

if isempty(policyAudit) || height(policyAudit) < 1
    audit = localEmptyAuditTable();
    return;
end

snapshotTime = options.Time;
if ~isfinite(snapshotTime)
    snapshotTime = localResolveSelectorTime(options.Selector, T, policyAudit);
end
row = localNearestRow(policyAudit, snapshotTime);
if isempty(row)
    audit = localEmptyAuditTable();
    return;
end

t = localTableNumber(row, "t", snapshotTime);
noBrake = localTableNumber(row, "apogee_no_brake_m", NaN);
fullBrake = localTableNumber(row, "apogee_full_brake_m", NaN);
target = localTableNumber(row, "target_selected_m", NaN);
targetNominal = localTableNumber(row, "target_nominal_m", NaN);
targetEffective = localTableNumber(row, "target_effective_m", target);
margin = localTableNumber(row, "uncertainty_margin_m", NaN);
demand = localTableNumber(row, "corridor_brake_demand_index", NaN);
policyCmd = localTableNumber(row, "policy_cmd", NaN);
actuatorUs = localTableNumber(row, "actuator_us", NaN);
decisionLabel = localTableString(row, "decision_label", "unclassified");

low = min(noBrake, fullBrake);
high = max(noBrake, fullBrake);
span = high - low;
validCorridor = isfinite(low) && isfinite(high) && isfinite(span) && span > 0;

actuatorNorm = NaN;
servoSpan = options.ServoMax_us - options.ServoMin_us;
if isfinite(actuatorUs) && isfinite(servoSpan) && servoSpan > 0
    actuatorNorm = min(max((actuatorUs - options.ServoMin_us) ./ servoSpan, 0), 1);
end

policyProjection = NaN;
actuatorProjection = NaN;
if validCorridor
    if isfinite(policyCmd)
        policyProjection = high - min(max(policyCmd, 0), 1) .* span;
    end
    if isfinite(actuatorNorm)
        actuatorProjection = high - actuatorNorm .* span;
    end
end

common = struct();
common.t = t;
common.selector = string(options.Selector);
common.decision_label = decisionLabel;
common.authority_low_m = low;
common.authority_high_m = high;
common.authority_span_m = span;
common.target_selected_m = target;
common.policy_cmd = policyCmd;
common.actuator_position_norm = actuatorNorm;
common.actuator_tracking_error = actuatorNorm - policyCmd;

rows = localEmptyAuditTable();
rows = [rows; localComponent(common, "no_brake_prediction", "No brake", noBrake, "m", target, ...
    noBrake - target, NaN, "apogee_no_brake", ...
    "No-brake predicted apogee relative to selected target.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "full_brake_prediction", "Full brake", fullBrake, "m", target, ...
    fullBrake - target, NaN, "apogee_full_brake", ...
    "Full-brake predicted apogee relative to selected target.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "target_effective", "Effective target", targetEffective, "m", targetNominal, ...
    targetEffective - targetNominal, NaN, "target_effective,target_nominal", ...
    "Effective target after uncertainty and firmware target selection.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "uncertainty_margin", "Uncertainty margin", margin, "m", 0, ...
    margin, NaN, "uncertainty_margin", ...
    "Margin applied to make the policy target conservative.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "reachable_span", "Reachable span", span, "m", 0, ...
    span, NaN, "apogee_no_brake,apogee_full_brake", ...
    "Signed authority range between no-brake and full-brake predictions.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "demand_from_corridor", "Corridor demand", demand, "norm", policyCmd, ...
    policyCmd - demand, demand, "corridor_brake_demand_index,policy_cmd", ...
    "Normalized command demand implied by target location in the authority corridor.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "policy_command_projection", "Policy projection", policyProjection, "m", target, ...
    policyProjection - target, policyCmd, "policy_cmd,apogee_no_brake,apogee_full_brake", ...
    "Apogee projection implied by the logged policy command within the corridor.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "actuator_projection", "Actuator projection", actuatorProjection, "m", target, ...
    actuatorProjection - target, actuatorNorm, "actuator_us,apogee_no_brake,apogee_full_brake", ...
    "Apogee projection implied by the normalized actuator pulse within the corridor.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "actuator_tracking", "Actuator tracking", actuatorNorm, "norm", policyCmd, ...
    actuatorNorm - policyCmd, actuatorNorm, "actuator_us,policy_cmd", ...
    "Normalized actuator pulse compared with the logged policy command.")]; %#ok<AGROW>

rows = [rows; localFiniteDifferenceRows(common, T, options.Replay, cfg, options)]; %#ok<AGROW>

audit = rows;
audit = localClassifyRows(audit);
end

function row = localComponent(common, component, label, value, unit, referenceValue, deltaValue, normalizedValue, sourceFields, rationale)
row = table(common.t, common.selector, string(component), string(label), ...
    double(value), string(unit), double(referenceValue), double(deltaValue), double(normalizedValue), ...
    double(common.authority_low_m), double(common.authority_high_m), double(common.authority_span_m), ...
    double(common.target_selected_m), double(common.policy_cmd), double(common.actuator_position_norm), ...
    double(common.actuator_tracking_error), common.decision_label, ...
    string(rationale), string(sourceFields), "info", "unclassified", ...
    'VariableNames', {'t','selector','component','component_label','value','unit', ...
    'reference_value','delta_value','normalized_value','authority_low_m','authority_high_m', ...
    'authority_span_m','target_selected_m','policy_cmd','actuator_position_norm', ...
    'actuator_tracking_error','decision_label','rationale','source_fields','severity','audit_label'});
end

function audit = localClassifyRows(audit)
n = height(audit);
audit.severity = repmat("info", n, 1);
audit.audit_label = repmat("nominal", n, 1);

validCorridor = isfinite(audit.authority_low_m) & isfinite(audit.authority_high_m) & ...
    isfinite(audit.authority_span_m) & audit.authority_span_m > 0;
targetInside = validCorridor & isfinite(audit.target_selected_m) & ...
    audit.target_selected_m >= audit.authority_low_m & audit.target_selected_m <= audit.authority_high_m;

for k = 1:n
    if ~isfinite(audit.value(k))
        audit.severity(k) = "missing";
        audit.audit_label(k) = "telemetry_incomplete";
    elseif localIsFiniteDifferenceComponent(audit.component(k))
        audit.severity(k) = "info";
        audit.audit_label(k) = "finite_difference_model";
    elseif ~validCorridor(k)
        audit.severity(k) = "missing";
        audit.audit_label(k) = "authority_unavailable";
    elseif ~isfinite(audit.target_selected_m(k))
        audit.severity(k) = "missing";
        audit.audit_label(k) = "target_unavailable";
    elseif audit.component(k) == "reachable_span" && audit.value(k) <= 0
        audit.severity(k) = "critical";
        audit.audit_label(k) = "authority_invalid";
    elseif audit.component(k) == "demand_from_corridor" && ...
            (audit.value(k) < -1.0e-9 || audit.value(k) > 1 + 1.0e-9)
        audit.severity(k) = "critical";
        audit.audit_label(k) = "demand_out_of_bounds";
    elseif audit.component(k) == "actuator_tracking" && ...
            isfinite(audit.delta_value(k)) && abs(audit.delta_value(k)) > 0.10
        audit.severity(k) = "warning";
        audit.audit_label(k) = "actuator_tracking_error";
    elseif ~targetInside(k)
        if audit.target_selected_m(k) < audit.authority_low_m(k)
            audit.severity(k) = "warning";
            audit.audit_label(k) = "target_below_full_brake";
        else
            audit.severity(k) = "notice";
            audit.audit_label(k) = "target_above_no_brake";
        end
    elseif audit.component(k) == "policy_command_projection" && ...
            isfinite(audit.delta_value(k)) && abs(audit.delta_value(k)) > max(1, 0.05 * audit.authority_span_m(k))
        audit.severity(k) = "notice";
        audit.audit_label(k) = "policy_projection_off_target";
    else
        audit.severity(k) = "info";
        audit.audit_label(k) = "authority_nominal";
    end
end
end

function rows = localFiniteDifferenceRows(common, T, replay, cfg, options)
rows = localEmptyAuditTable();

[h_m, v_mps, stateSource] = localVerticalStateAtTime(replay, T, common.t);
baseCommand = localFirstFinite([common.policy_cmd, common.actuator_position_norm, 0]);
model = localPolicyModel(cfg);

baseApogee = localPredictPolicyApogee(h_m, v_mps, baseCommand, model);
hStep = max(abs(options.AltitudeStep_m), eps);
vStep = max(abs(options.VelocityStep_mps), eps);
cStep = max(abs(options.CommandStep), eps);

hPlusApogee = localPredictPolicyApogee(h_m + hStep, v_mps, baseCommand, model);
vPlusApogee = localPredictPolicyApogee(h_m, v_mps + vStep, baseCommand, model);
commandPlus = min(max(baseCommand + cStep, 0), model.maxCommand01);
commandDelta = commandPlus - baseCommand;
commandPlusApogee = localPredictPolicyApogee(h_m, v_mps, commandPlus, model);

sourcePrefix = stateSource + ".h," + stateSource + ".v,policy_cmd,firmware_policy_model";
rows = [rows; localComponent(common, "replay_model_base", "Replay model base", ...
    baseApogee, "m", common.target_selected_m, baseApogee - common.target_selected_m, ...
    baseCommand, sourcePrefix, ...
    "Firmware-equivalent quadratic-drag apogee prediction evaluated at the selected replay state.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "fd_altitude_step", sprintf("FD altitude +%.3g m", hStep), ...
    hPlusApogee, "m", baseApogee, hPlusApogee - baseApogee, ...
    (hPlusApogee - baseApogee) ./ hStep, sourcePrefix + ",altitude_step", ...
    "Finite-difference apogee response to a positive replay-altitude perturbation.")]; %#ok<AGROW>
rows = [rows; localComponent(common, "fd_velocity_step", sprintf("FD velocity +%.3g m/s", vStep), ...
    vPlusApogee, "m", baseApogee, vPlusApogee - baseApogee, ...
    (vPlusApogee - baseApogee) ./ vStep, sourcePrefix + ",velocity_step", ...
    "Finite-difference apogee response to a positive replay-vertical-velocity perturbation.")]; %#ok<AGROW>

if isfinite(commandDelta) && abs(commandDelta) > eps
    commandSensitivity = (commandPlusApogee - baseApogee) ./ commandDelta;
else
    commandSensitivity = NaN;
end
rows = [rows; localComponent(common, "fd_command_step", sprintf("FD command +%.3g", commandDelta), ...
    commandPlusApogee, "m", baseApogee, commandPlusApogee - baseApogee, ...
    commandSensitivity, sourcePrefix + ",command_step", ...
    "Finite-difference apogee response to a positive normalized-command perturbation.")]; %#ok<AGROW>
end

function tf = localIsFiniteDifferenceComponent(component)
component = string(component);
tf = component == "replay_model_base" || startsWith(component, "fd_");
end

function [h_m, v_mps, source] = localVerticalStateAtTime(replay, T, snapshotTime)
h_m = NaN;
v_mps = NaN;
source = "replay";

if istable(replay) && ~isempty(replay) && ...
        all(ismember(["t","h","v"], string(replay.Properties.VariableNames)))
    row = localNearestRow(replay, snapshotTime);
    h_m = localTableNumber(row, "h", NaN);
    v_mps = localTableNumber(row, "v", NaN);
end

if ~(isfinite(h_m) && isfinite(v_mps))
    source = "logged";
    row = localNearestRow(T, snapshotTime);
    h_m = localTableNumber(row, "kf_h", NaN);
    v_mps = localTableNumber(row, "kf_v", NaN);
end
end

function model = localPolicyModel(cfg)
model.gravity = localConfigScalar(cfg, ["policyGravity","gravity"], 9.8);
model.vehicleMass_kg = localConfigScalar(cfg, ["policyVehicleMass_kg","policy_vehicle_mass_kg"], 2.50);
model.rho_kgpm3 = localConfigScalar(cfg, ["policyRho_kgpm3","policy_rho_kgpm3"], 1.225);
model.cdaBody_m2 = localConfigScalar(cfg, ["policyCdaBody_m2","policy_cda_body_m2"], 0.0040);
model.cdaBrake_m2 = localConfigScalar(cfg, ["policyCdaBrake_m2","policy_cda_brake_m2"], 0.0200);
model.maxCommand01 = localConfigScalar(cfg, ["policyMaxCommand01","policy_max_command01"], 1.0);
model.maxCommand01 = min(max(model.maxCommand01, 0), 1);
end

function value = localConfigScalar(cfg, names, defaultValue)
value = defaultValue;
if ~isstruct(cfg)
    return;
end
for k = 1:numel(names)
    fieldName = char(names(k));
    if isfield(cfg, fieldName)
        candidate = localScalarDouble(cfg.(fieldName));
        if isfinite(candidate)
            value = candidate;
            return;
        end
    end
end
if isfield(cfg, 'airbrakePolicy') && isstruct(cfg.airbrakePolicy)
    policy = cfg.airbrakePolicy;
    for k = 1:numel(names)
        fieldName = char(names(k));
        if isfield(policy, fieldName)
            candidate = localScalarDouble(policy.(fieldName));
            if isfinite(candidate)
                value = candidate;
                return;
            end
        end
    end
end
end

function value = localScalarDouble(raw)
value = NaN;
try
    value = double(raw);
    value = value(1);
catch
    value = NaN;
end
end

function apogee_m = localPredictPolicyApogee(h_m, v_mps, command01, model)
apogee_m = NaN;
if ~isfinite(h_m) || ~isfinite(v_mps) || ~isfinite(command01)
    return;
end
if v_mps <= 0
    apogee_m = h_m;
    return;
end
g = model.gravity;
if ~isfinite(g) || g <= 0
    return;
end
u = min(max(command01, 0), model.maxCommand01);
cda = model.cdaBody_m2 + u .* model.cdaBrake_m2;
if ~isfinite(model.rho_kgpm3) || model.rho_kgpm3 <= 0 || ...
        ~isfinite(model.vehicleMass_kg) || model.vehicleMass_kg <= 0 || ...
        ~isfinite(cda) || cda < 0
    k = 0;
else
    k = (model.rho_kgpm3 .* cda) ./ (2 .* model.vehicleMass_kg);
end
v2 = v_mps .* v_mps;
if ~isfinite(k) || k < 1.0e-7
    apogee_m = h_m + v2 ./ (2 .* g);
    return;
end
argument = 1 + (k .* v2) ./ g;
if ~isfinite(argument) || argument <= 0
    return;
end
apogee_m = h_m + log(argument) ./ (2 .* k);
end

function t = localResolveSelectorTime(selector, T, policyAudit)
selector = string(selector);
t = NaN;
switch selector
    case "max_command"
        if ismember("policy_cmd", string(policyAudit.Properties.VariableNames))
            valid = isfinite(policyAudit.t) & isfinite(policyAudit.policy_cmd);
            if any(valid)
                [~, idx] = max(policyAudit.policy_cmd(valid));
                validIdx = find(valid);
                t = policyAudit.t(validIdx(idx));
            end
        end
    case "brake_start"
        if ismember("policy_cmd", string(policyAudit.Properties.VariableNames))
            idx = find(isfinite(policyAudit.t) & isfinite(policyAudit.policy_cmd) & ...
                policyAudit.policy_cmd >= 0.05, 1, 'first');
            if ~isempty(idx)
                t = policyAudit.t(idx);
            end
        end
    case "apogee"
        vars = string(T.Properties.VariableNames);
        if ismember("kf_h", vars) && ismember("t", vars)
            valid = isfinite(T.t) & isfinite(T.kf_h);
            if any(valid)
                [~, idx] = max(T.kf_h(valid));
                validIdx = find(valid);
                t = T.t(validIdx(idx));
            end
        end
end
if ~isfinite(t) && ismember("t", string(policyAudit.Properties.VariableNames))
    tv = policyAudit.t(isfinite(policyAudit.t));
    if ~isempty(tv)
        t = median(tv, 'omitnan');
    end
end
end

function row = localNearestRow(T, snapshotTime)
row = table();
if ~istable(T) || isempty(T)
    return;
end
if ~ismember("t", string(T.Properties.VariableNames))
    row = T(1, :);
    return;
end
t = double(T.t(:));
valid = isfinite(t);
if ~any(valid)
    row = T(1, :);
    return;
end
[~, nearest] = min(abs(t(valid) - snapshotTime));
validIdx = find(valid);
row = T(validIdx(nearest), :);
end

function value = localTableNumber(row, fieldName, defaultValue)
value = defaultValue;
if ~istable(row) || isempty(row) || ~ismember(fieldName, string(row.Properties.VariableNames))
    return;
end
raw = row.(char(fieldName));
if isempty(raw)
    return;
end
try
    value = double(raw(1));
catch
    value = defaultValue;
end
end

function value = localTableString(row, fieldName, defaultValue)
value = string(defaultValue);
if ~istable(row) || isempty(row) || ~ismember(fieldName, string(row.Properties.VariableNames))
    return;
end
raw = row.(char(fieldName));
if isempty(raw)
    return;
end
value = string(raw(1));
end

function audit = localEmptyAuditTable()
audit = table('Size', [0 21], ...
    'VariableTypes', {'double','string','string','string','double','string', ...
    'double','double','double','double','double','double','double','double', ...
    'double','double','string','string','string','string','string'}, ...
    'VariableNames', {'t','selector','component','component_label','value','unit', ...
    'reference_value','delta_value','normalized_value','authority_low_m', ...
    'authority_high_m','authority_span_m','target_selected_m','policy_cmd', ...
    'actuator_position_norm','actuator_tracking_error','decision_label', ...
    'rationale','source_fields','severity','audit_label'});
end

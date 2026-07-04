function audit = buildPolicyDecisionAudit(T, cfg, options)
%BUILDPOLICYDECISIONAUDIT Derive a review table for airbrake policy decisions.
%
% This is a dashboard-side evidence classifier, not a firmware source of truth.
% It preserves the recorded policy fields and adds deterministic labels that
% explain which telemetry evidence should be inspected for each sample.
arguments
    T table
    cfg struct = caelum.defaultConfig()
    options.MaxPhaseDiagAge_ms (1,1) double = 500
    options.CommandActiveThreshold (1,1) double = 0.05
    options.CommandSaturatedThreshold (1,1) double = 0.95
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

n = height(T);
vars = string(T.Properties.VariableNames);

audit = table();
audit.t = localColumn(T, vars, "t", n, NaN);
audit.phase = localColumn(T, vars, "phase", n, NaN);
audit.phase_name = localPhaseNames(audit.phase);
audit.policy_valid = localColumn(T, vars, "policy_valid", n, NaN);
audit.policy_cmd = localColumn(T, vars, "policy_cmd", n, NaN);
audit.actuator_us = localColumn(T, vars, "actuator_us", n, NaN);

audit.apogee_no_brake_m = localColumn(T, vars, "apogee_no_brake", n, NaN);
audit.apogee_full_brake_m = localColumn(T, vars, "apogee_full_brake", n, NaN);
audit.target_apogee_m = localColumn(T, vars, "target_apogee", n, NaN);
audit.target_nominal_m = localColumn(T, vars, "target_nominal", n, NaN);
audit.target_effective_m = localColumn(T, vars, "target_effective", n, NaN);
audit.target_selected_m = localSelectTarget(audit.target_effective_m, ...
    audit.target_apogee_m, audit.target_nominal_m);
audit.uncertainty_margin_m = localColumn(T, vars, "uncertainty_margin", n, NaN);
audit.apogee_error_m = localColumn(T, vars, "apogee_error", n, NaN);

audit.reachability_low_m = min(audit.apogee_no_brake_m, audit.apogee_full_brake_m);
audit.reachability_high_m = max(audit.apogee_no_brake_m, audit.apogee_full_brake_m);
audit.reachability_span_m = audit.reachability_high_m - audit.reachability_low_m;

validCorridor = isfinite(audit.reachability_low_m) & ...
    isfinite(audit.reachability_high_m) & audit.reachability_span_m > 0;
audit.target_inside_corridor = validCorridor & ...
    audit.target_selected_m >= audit.reachability_low_m & ...
    audit.target_selected_m <= audit.reachability_high_m;
audit.target_above_no_brake = validCorridor & ...
    audit.target_selected_m > audit.reachability_high_m;
audit.target_below_full_brake = validCorridor & ...
    audit.target_selected_m < audit.reachability_low_m;

audit.corridor_brake_demand_index = nan(n, 1);
audit.corridor_brake_demand_index(validCorridor) = ...
    (audit.reachability_high_m(validCorridor) - audit.target_selected_m(validCorridor)) ./ ...
    audit.reachability_span_m(validCorridor);
audit.corridor_brake_demand_index = min(max(audit.corridor_brake_demand_index, 0), 1);
audit.policy_command_residual = audit.policy_cmd - audit.corridor_brake_demand_index;

audit.phase_allows_brake = isfinite(audit.phase) & round(audit.phase) == 3;
audit.phase_brake_active = localLogicalColumn(T, vars, "phase_brake_active", n);
audit.phase_diag_valid = localLogicalColumn(T, vars, "phase_diag_valid", n);
audit.phase_diag_updated = localLogicalColumn(T, vars, "phase_diag_updated", n);
audit.phase_diag_age_ms = localColumn(T, vars, "phase_diag_age_ms", n, NaN);
audit.phase_launch_latched = localLogicalColumn(T, vars, "phase_launch_latched", n);
audit.phase_burnout_latched = localLogicalColumn(T, vars, "phase_burnout_latched", n);
audit.phase_descent_latched = localLogicalColumn(T, vars, "phase_descent_latched", n);
audit.phase_boost_dwell_met = localLogicalColumn(T, vars, "phase_boost_dwell_met", n);
audit.phase_coast_dwell_met = localLogicalColumn(T, vars, "phase_coast_dwell_met", n);

audit.warn_mask = localColumn(T, vars, "warn_mask", n, NaN);
audit.warning_active = isfinite(audit.warn_mask) & audit.warn_mask ~= 0;
audit.command_active = isfinite(audit.policy_cmd) & ...
    audit.policy_cmd >= options.CommandActiveThreshold;
audit.command_saturated = isfinite(audit.policy_cmd) & ...
    audit.policy_cmd >= options.CommandSaturatedThreshold;

mission = localMissionProfile(cfg);
if isempty(fieldnames(mission))
    audit.mission_target_m = nan(n, 1);
else
    audit.mission_target_m = repmat(mission.targetApogee_m, n, 1);
end
audit.target_effective_offset_from_mission_m = audit.target_effective_m - audit.mission_target_m;

[audit.decision_code, audit.decision_label, audit.decision_rationale] = ...
    localClassifyDecisionEvidence(audit, vars, options);
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

function selected = localSelectTarget(targetEffective, targetApogee, targetNominal)
selected = targetEffective;
missing = ~isfinite(selected) & isfinite(targetApogee);
selected(missing) = targetApogee(missing);
missing = ~isfinite(selected) & isfinite(targetNominal);
selected(missing) = targetNominal(missing);
end

function names = localPhaseNames(phase)
names = strings(numel(phase), 1);
for k = 1:numel(phase)
    if ~isfinite(phase(k))
        names(k) = "UNKNOWN";
        continue;
    end
    switch round(phase(k))
        case 0
            names(k) = "IDLE";
        case 1
            names(k) = "BOOST";
        case 2
            names(k) = "COAST";
        case 3
            names(k) = "BRAKE";
        case 4
            names(k) = "DESCENT";
        otherwise
            names(k) = "UNKNOWN";
    end
end
end

function [code, label, rationale] = localClassifyDecisionEvidence(audit, vars, options)
n = height(audit);
code = zeros(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

hasDiagAge = ismember("phase_diag_age_ms", vars);
hasDiagValid = ismember("phase_diag_valid", vars);

for k = 1:n
    missingRoutingEvidence = ~isfinite(audit.phase(k)) || ...
        ~isfinite(audit.policy_valid(k)) || ...
        ~isfinite(audit.policy_cmd(k));

    missingActiveDecisionEvidence = ~isfinite(audit.target_selected_m(k)) || ...
        ~isfinite(audit.reachability_span_m(k)) || ...
        audit.reachability_span_m(k) <= 0;

    diagStale = false;
    if hasDiagValid && ~audit.phase_diag_valid(k)
        diagStale = true;
    end
    if hasDiagAge && isfinite(audit.phase_diag_age_ms(k)) && ...
            audit.phase_diag_age_ms(k) > options.MaxPhaseDiagAge_ms
        diagStale = true;
    end

    if missingRoutingEvidence
        code(k) = 1;
        label(k) = "telemetry_incomplete";
        rationale(k) = "Required phase or policy-command telemetry is unavailable.";
    elseif audit.warning_active(k)
        code(k) = 2;
        label(k) = "warning_active";
        rationale(k) = "warn_mask is nonzero; inspect firmware warning evidence before interpreting the command.";
    elseif diagStale
        code(k) = 3;
        label(k) = "diagnostic_stale";
        rationale(k) = "Phase diagnostic evidence is invalid or older than the configured age threshold.";
    elseif ~audit.phase_allows_brake(k)
        code(k) = 4;
        label(k) = "phase_blocked";
        rationale(k) = "Firmware phase is not BRAKE, so braking intent is phase-gated in this audit.";
    elseif missingActiveDecisionEvidence
        code(k) = 1;
        label(k) = "telemetry_incomplete";
        rationale(k) = "Required active-phase target or apogee-corridor telemetry is unavailable.";
    elseif audit.policy_valid(k) <= 0.5
        code(k) = 5;
        label(k) = "policy_invalid";
        rationale(k) = "Policy telemetry reports that nonzero command intent is not authorized.";
    elseif audit.target_above_no_brake(k)
        code(k) = 6;
        label(k) = "target_above_no_brake";
        rationale(k) = "Effective target is above the no-brake apogee prediction; braking is not demanded by the corridor.";
    elseif audit.target_below_full_brake(k)
        code(k) = 7;
        label(k) = "target_below_full_brake";
        rationale(k) = "Effective target is below the full-brake prediction; maximum braking authority may still overshoot.";
    elseif audit.command_active(k)
        code(k) = 8;
        label(k) = "brake_authorized";
        rationale(k) = "Target lies inside the reachability corridor and policy command is nonzero.";
    else
        code(k) = 9;
        label(k) = "inside_corridor_no_command";
        rationale(k) = "Target lies inside the reachability corridor but command remains below the active threshold.";
    end
end
end

function mission = localMissionProfile(cfg)
mission = struct();
if ~isstruct(cfg) || ~isfield(cfg, 'mission') || ~isstruct(cfg.mission)
    return;
end

required = ["targetApogee_m","targetApogee_ft"];
if all(isfield(cfg.mission, cellstr(required))) && isfinite(cfg.mission.targetApogee_m)
    mission = cfg.mission;
end
end

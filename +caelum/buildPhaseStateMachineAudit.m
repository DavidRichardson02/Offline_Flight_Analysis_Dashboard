function audit = buildPhaseStateMachineAudit(T, options)
%BUILDPHASESTATEMACHINEAUDIT Derive firmware phase-transition evidence.
%
% This audit is dashboard-side evidence. It does not infer a new flight phase;
% it preserves the firmware phase and records whether the logged diagnostic
% flags explain the current state and transitions.
arguments
    T table
    options.MaxPhaseDiagAge_ms (1,1) double = 500
end

n = height(T);
vars = string(T.Properties.VariableNames);

audit = table();
audit.t = localColumn(T, vars, "t", n, NaN);
audit.phase = localColumn(T, vars, "phase", n, NaN);
audit.phase_name = localPhaseNames(audit.phase);
if n > 0
    audit.phase_prev = [NaN; audit.phase(1:end-1)];
    audit.phase_delta = [NaN; diff(audit.phase)];
else
    audit.phase_prev = nan(0, 1);
    audit.phase_delta = nan(0, 1);
end
audit.phase_changed = isfinite(audit.phase_delta) & audit.phase_delta ~= 0;
audit.phase_rollback = isfinite(audit.phase_delta) & audit.phase_delta < 0;
audit.transition_label = localTransitionLabels(audit.phase_prev, audit.phase, audit.phase_changed);

audit.phase_diag_valid = localLogicalColumn(T, vars, "phase_diag_valid", n);
audit.phase_diag_updated = localLogicalColumn(T, vars, "phase_diag_updated", n);
audit.phase_diag_seq = localColumn(T, vars, "phase_diag_seq", n, NaN);
audit.phase_diag_seq_delta = localSeqDelta(audit.phase_diag_seq);
audit.phase_diag_seq_changed = isfinite(audit.phase_diag_seq_delta) & audit.phase_diag_seq_delta > 0;
audit.phase_diag_t_ms = localColumn(T, vars, "phase_diag_t_ms", n, NaN);
audit.phase_diag_age_ms = localColumn(T, vars, "phase_diag_age_ms", n, NaN);

audit.phase_launch_latched = localLogicalColumn(T, vars, "phase_launch_latched", n);
audit.phase_burnout_latched = localLogicalColumn(T, vars, "phase_burnout_latched", n);
audit.phase_descent_latched = localLogicalColumn(T, vars, "phase_descent_latched", n);
audit.phase_launch_candidate = localLogicalColumn(T, vars, "phase_launch_candidate", n);
audit.phase_burnout_candidate = localLogicalColumn(T, vars, "phase_burnout_candidate", n);
audit.phase_descent_candidate = localLogicalColumn(T, vars, "phase_descent_candidate", n);
audit.phase_boost_dwell_met = localLogicalColumn(T, vars, "phase_boost_dwell_met", n);
audit.phase_coast_dwell_met = localLogicalColumn(T, vars, "phase_coast_dwell_met", n);
audit.phase_brake_active = localLogicalColumn(T, vars, "phase_brake_active", n);

audit.phase_launch_confirm_ms = localColumn(T, vars, "phase_launch_confirm_ms", n, NaN);
audit.phase_burnout_confirm_ms = localColumn(T, vars, "phase_burnout_confirm_ms", n, NaN);
audit.phase_descent_confirm_ms = localColumn(T, vars, "phase_descent_confirm_ms", n, NaN);
audit.phase_since_launch_ms = localColumn(T, vars, "phase_since_launch_ms", n, NaN);
audit.phase_since_burnout_ms = localColumn(T, vars, "phase_since_burnout_ms", n, NaN);

audit.arm_state = localColumn(T, vars, "arm_state", n, NaN);
audit.policy_runtime_enabled = localColumn(T, vars, "policy_runtime_enabled", n, NaN);
audit.software_arm_token = localColumn(T, vars, "software_arm_token", n, NaN);
audit.warn_mask = localColumn(T, vars, "warn_mask", n, NaN);
audit.warning_active = isfinite(audit.warn_mask) & audit.warn_mask ~= 0;

audit.altitude_m = localFirstAvailableColumn(T, vars, ["kf_h","est_h","bmp_alt_rel","bmp_alt"], n);
audit.velocity_mps = localFirstAvailableColumn(T, vars, ["kf_v","est_v"], n);
audit.accel_mps2 = localFirstAvailableColumn(T, vars, ["a_vertical","est_a","smoothed_a_vertical"], n);

expectedAvailable = all(ismember([ ...
    "phase_launch_latched", ...
    "phase_burnout_latched", ...
    "phase_descent_latched", ...
    "phase_brake_active"], vars));
audit.expected_phase_from_evidence = localExpectedPhaseFromEvidence(audit, expectedAvailable);
audit.expected_phase_name = localPhaseNames(audit.expected_phase_from_evidence);
audit.phase_evidence_mismatch = expectedAvailable & ...
    isfinite(audit.phase) & isfinite(audit.expected_phase_from_evidence) & ...
    round(audit.phase) ~= round(audit.expected_phase_from_evidence);

[audit.evidence_code, audit.evidence_label, audit.evidence_rationale] = ...
    localClassifyEvidence(audit, vars, expectedAvailable, options.MaxPhaseDiagAge_ms);
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

function values = localFirstAvailableColumn(T, vars, fields, n)
values = nan(n, 1);
for k = 1:numel(fields)
    name = fields(k);
    if ismember(name, vars)
        values = double(T.(char(name)));
        values = values(:);
        return;
    end
end
end

function delta = localSeqDelta(seqValue)
if isempty(seqValue)
    delta = nan(0, 1);
    return;
end
delta = [NaN; diff(seqValue)];
delta(~isfinite(seqValue)) = NaN;
delta([false; ~isfinite(seqValue(1:end-1))]) = NaN;
end

function expected = localExpectedPhaseFromEvidence(audit, expectedAvailable)
n = height(audit);
expected = nan(n, 1);
if ~expectedAvailable
    return;
end

expected(:) = 0;
expected(audit.phase_launch_latched) = 1;
expected(audit.phase_burnout_latched) = 2;
expected(audit.phase_brake_active) = 3;
expected(audit.phase_descent_latched) = 4;
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

function labels = localTransitionLabels(prevPhase, phase, changed)
n = numel(phase);
labels = strings(n, 1);
labels(:) = "hold";
for k = 1:n
    if ~changed(k)
        continue;
    end
    if ~isfinite(prevPhase(k)) || ~isfinite(phase(k))
        labels(k) = "unknown_transition";
    else
        labels(k) = localPhaseNames(prevPhase(k)) + "_to_" + localPhaseNames(phase(k));
    end
end
end

function [code, label, rationale] = localClassifyEvidence(audit, vars, expectedAvailable, maxPhaseDiagAge_ms)
n = height(audit);
code = zeros(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

hasDiagValid = ismember("phase_diag_valid", vars);
hasDiagAge = ismember("phase_diag_age_ms", vars);

for k = 1:n
    phaseValue = audit.phase(k);
    unknownPhase = ~isfinite(phaseValue) || round(phaseValue) < 0 || round(phaseValue) > 4;

    diagStale = false;
    if hasDiagValid && ~audit.phase_diag_valid(k)
        diagStale = true;
    end
    if hasDiagAge && isfinite(audit.phase_diag_age_ms(k)) && ...
            audit.phase_diag_age_ms(k) > maxPhaseDiagAge_ms
        diagStale = true;
    end

    hasCandidate = audit.phase_launch_candidate(k) || ...
        audit.phase_burnout_candidate(k) || ...
        audit.phase_descent_candidate(k);
    hasDwell = audit.phase_boost_dwell_met(k) || audit.phase_coast_dwell_met(k);
    hasLatch = audit.phase_launch_latched(k) || audit.phase_burnout_latched(k) || ...
        audit.phase_descent_latched(k) || audit.phase_brake_active(k);

    if ~isfinite(phaseValue)
        code(k) = 1;
        label(k) = "telemetry_incomplete";
        rationale(k) = "Firmware phase field is unavailable.";
    elseif diagStale
        code(k) = 2;
        label(k) = "diagnostic_stale";
        rationale(k) = "Phase diagnostic validity or age evidence is stale.";
    elseif audit.warning_active(k)
        code(k) = 3;
        label(k) = "warning_active";
        rationale(k) = "warn_mask is nonzero; inspect firmware warning evidence before interpreting phase transitions.";
    elseif unknownPhase
        code(k) = 4;
        label(k) = "unexpected_phase_value";
        rationale(k) = "Firmware phase is outside the expected IDLE..DESCENT enumeration.";
    elseif audit.phase_rollback(k)
        code(k) = 5;
        label(k) = "nonmonotonic_phase";
        rationale(k) = "Firmware phase moved backward in the state sequence.";
    elseif expectedAvailable && audit.phase_evidence_mismatch(k)
        code(k) = 6;
        label(k) = "phase_evidence_mismatch";
        rationale(k) = "Latch/brake-active evidence does not match the reported phase.";
    elseif audit.phase_changed(k)
        code(k) = 7;
        label(k) = "transition_observed";
        rationale(k) = "Firmware phase changed; inspect candidates, dwell, and latch evidence at this boundary.";
    elseif hasCandidate
        code(k) = 8;
        label(k) = "candidate_pending";
        rationale(k) = "A transition candidate is asserted but the firmware phase has not changed on this sample.";
    elseif hasDwell
        code(k) = 9;
        label(k) = "dwell_met";
        rationale(k) = "A phase dwell criterion is met while the current phase is held.";
    elseif hasLatch
        code(k) = 10;
        label(k) = "latched_hold";
        rationale(k) = "The current phase is supported by latched phase evidence.";
    else
        code(k) = 11;
        label(k) = "nominal_hold";
        rationale(k) = "No transition candidate, stale diagnostic, or mismatch evidence is active.";
    end
end
end

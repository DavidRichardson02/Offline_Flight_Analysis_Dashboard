function [eventIndex, auditBundle] = buildFlightEvidenceIndex(T, events, replay, cfg, options)
%BUILDFLIGHTEVIDENCEINDEX Build a shared time-indexed dashboard event table.
%
% The event index is an analysis artifact. It does not replace any firmware
% field or audit table; it compresses existing audit labels into intervals that
% can be reviewed on a shared mission time axis.
arguments
    T table
    events struct = struct()
    replay = table()
    cfg struct = caelum.defaultConfig()
    options.Attitude = table()
    options.Est3D = table()
    options.Report struct = struct()
    options.Truth struct = struct()
    options.IncludeNominal (1,1) logical = false
    options.MaxPhaseDiagAge_ms (1,1) double = 500
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

replay = localTableOrEmpty(replay);
attitude = localTableOrEmpty(options.Attitude);
est3d = localTableOrEmpty(options.Est3D);

t = localTimeColumn(T);
[t0, t1] = localTimeBounds(t);

eventIndex = localEmptyEventTable();
auditBundle = struct();
auditBundle.policy = table();
auditBundle.estimatorTrust = table();
auditBundle.telemetryFreshness = table();
auditBundle.phaseState = table();
auditBundle.attitudeGravity = table();
auditBundle.trajectoryWind = table();
auditBundle.replayContractDiff = table();
auditBundle.replayContractFieldSummary = table();
auditBundle.attitude = attitude;
auditBundle.est3d = est3d;
auditBundle.errors = localEmptyErrorTable();

eventIndex = localAppendMissionEvents(eventIndex, events);

[auditBundle.policy, ok, note] = localTryBuildOne(@() caelum.buildPolicyDecisionAudit(T, cfg, ...
    MaxPhaseDiagAge_ms=options.MaxPhaseDiagAge_ms));
if ok
    eventIndex = localAppendRunEvents(eventIndex, auditBundle.policy, ...
        "decision_label", "decision_rationale", "policy_decision", ...
        "policy_decision", "phase,policy_valid,policy_cmd,actuator_us,target_effective,apogee_no_brake,apogee_full_brake", ...
        options.IncludeNominal);
else
    [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
        t0, t1, "policy_decision", "policy_decision", note);
end

[auditBundle.estimatorTrust, ok, note] = localTryBuildOne(@() caelum.buildEstimatorTrustAudit(T, replay, cfg, ...
    Truth=options.Truth));
if ok
    eventIndex = localAppendRunEvents(eventIndex, auditBundle.estimatorTrust, ...
        "trust_label", "trust_rationale", "estimator_trust", ...
        "estimator_trust", "kf_h,kf_v,P00,P11,innovation_h,innovation_nis,baro_used,baro_rejected", ...
        options.IncludeNominal);
else
    [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
        t0, t1, "estimator_trust", "estimator_trust", note);
end

[auditBundle.telemetryFreshness, ok, note] = localTryBuildOne(@() caelum.buildTelemetryFreshnessAudit(T, ...
    Report=options.Report));
if ok
    eventIndex = localAppendFreshnessEvents(eventIndex, auditBundle.telemetryFreshness, options.IncludeNominal);
else
    [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
        t0, t1, "telemetry_freshness", "telemetry_freshness", note);
end

[auditBundle.phaseState, ok, note] = localTryBuildOne(@() caelum.buildPhaseStateMachineAudit(T, ...
    MaxPhaseDiagAge_ms=options.MaxPhaseDiagAge_ms));
if ok
    eventIndex = localAppendRunEvents(eventIndex, auditBundle.phaseState, ...
        "evidence_label", "evidence_rationale", "phase_state_machine", ...
        "phase_transition", "phase,phase_diag_valid,phase_diag_age_ms,phase_latches,phase_candidates", ...
        options.IncludeNominal);
else
    [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
        t0, t1, "phase_state_machine", "phase_transition", note);
end

if isempty(attitude)
    attitude = localBuildAttitude(T, cfg);
    auditBundle.attitude = attitude;
end
[auditBundle.attitudeGravity, ok, note] = localTryBuildOne(@() caelum.buildAttitudeGravityProvenanceAudit(T, attitude, cfg, ...
    Truth=options.Truth));
if ok
    eventIndex = localAppendRunEvents(eventIndex, auditBundle.attitudeGravity, ...
        "evidence_label", "evidence_rationale", "attitude_gravity", ...
        "attitude_gravity", "ax,ay,az,g_bx,g_by,g_bz,a_vertical,q_w,q_x,q_y,q_z", ...
        options.IncludeNominal);
else
    [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
        t0, t1, "attitude_gravity", "attitude_gravity", note);
end

if isempty(est3d)
    est3d = localBuild3DState(T, cfg, attitude);
    auditBundle.est3d = est3d;
end
if isempty(est3d)
    eventIndex = localAppendSingleEvent(eventIndex, t0, t1, "trajectory_wind", "missing", ...
        "trajectory_wind", "trajectory_wind_unavailable", ...
        "3D/GPS state was not available, so trajectory and wind evidence could not be indexed.", ...
        "gps_x,gps_y,gps_z,gps_vx,gps_vy,gps_vz,q_w,q_x,q_y,q_z");
else
    [auditBundle.trajectoryWind, ok, note] = localTryBuildOne(@() caelum.build3DTrajectoryWindAudit(est3d, T, ...
        Truth=options.Truth));
    if ok
        eventIndex = localAppendRunEvents(eventIndex, auditBundle.trajectoryWind, ...
            "evidence_label", "evidence_rationale", "trajectory_wind", ...
            "trajectory_wind", "gps_x,gps_y,gps_z,gps_vx,gps_vy,gps_vz,px,py,pz,wx,wy,wz", ...
            options.IncludeNominal);
    else
        [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
            t0, t1, "trajectory_wind", "trajectory_wind", note);
    end
end

[replayContractDiff, replayContractFieldSummary, ok, note] = localTryBuildTwo(@() caelum.buildReplayContractDiffAudit(T, replay, cfg));
if ok
    auditBundle.replayContractDiff = replayContractDiff;
    auditBundle.replayContractFieldSummary = replayContractFieldSummary;
    eventIndex = localAppendRunEvents(eventIndex, auditBundle.replayContractDiff, ...
        "contract_label", "contract_rationale", "replay_contract", ...
        "replay_contract", "a_vertical,kf_h,kf_v,P00,P11,replay_h,replay_v,replay_covariance", ...
        options.IncludeNominal);
else
    [eventIndex, auditBundle.errors] = localAppendBuilderFailure(eventIndex, auditBundle.errors, ...
        t0, t1, "replay_contract", "replay_contract", note);
end

eventIndex = localFinalizeEventIndex(eventIndex);
end

function [result, ok, note] = localTryBuildOne(fn)
ok = true;
note = "";
try
    result = fn();
catch ME
    ok = false;
    note = string(ME.message);
    result = table();
end
end

function [first, second, ok, note] = localTryBuildTwo(fn)
ok = true;
note = "";
try
    [first, second] = fn();
catch ME
    ok = false;
    note = string(ME.message);
    first = table();
    second = table();
end
end

function T = localTableOrEmpty(value)
if istable(value)
    T = value;
else
    T = table();
end
end

function t = localTimeColumn(T)
if istable(T) && ~isempty(T) && ismember("t", string(T.Properties.VariableNames))
    t = double(T.t(:));
elseif istable(T) && ~isempty(T) && ismember("t_us", string(T.Properties.VariableNames))
    t = double(T.t_us(:) - T.t_us(1)) * 1e-6;
elseif istable(T)
    t = (0:max(height(T)-1, 0)).';
else
    t = nan(0, 1);
end
end

function [t0, t1] = localTimeBounds(t)
valid = isfinite(t);
if any(valid)
    t0 = min(t(valid));
    t1 = max(t(valid));
else
    t0 = NaN;
    t1 = NaN;
end
end

function eventIndex = localAppendMissionEvents(eventIndex, events)
missionFields = [ ...
    "launchTime_s", "launch", "Launch detected"; ...
    "burnoutTime_s", "burnout", "Burnout detected"; ...
    "apogeeTime_s", "apogee", "Apogee detected"; ...
    "landingTime_s", "landing", "Landing detected"];
for k = 1:size(missionFields, 1)
    fieldName = char(missionFields(k, 1));
    if isstruct(events) && isfield(events, fieldName) && isfinite(events.(fieldName))
        eventIndex = localAppendSingleEvent(eventIndex, events.(fieldName), events.(fieldName), ...
            "mission_event", "info", "mission", missionFields(k, 2), missionFields(k, 3), fieldName);
    end
end
end

function eventIndex = localAppendRunEvents(eventIndex, audit, labelField, rationaleField, sourceView, eventType, fieldNames, includeNominal)
if isempty(audit) || ~istable(audit) || ~ismember("t", string(audit.Properties.VariableNames)) || ...
        ~ismember(labelField, string(audit.Properties.VariableNames))
    return;
end

t = double(audit.t(:));
labels = string(audit.(char(labelField))(:));
if ismember(rationaleField, string(audit.Properties.VariableNames))
    rationales = string(audit.(char(rationaleField))(:));
else
    rationales = repmat("", numel(labels), 1);
end

include = isfinite(t) & labels ~= "";
for k = 1:numel(labels)
    if ~include(k)
        continue;
    end
    if ~includeNominal && localIsNominalLabel(sourceView, labels(k))
        include(k) = false;
    end
end

idx = find(include);
if isempty(idx)
    return;
end

runStart = idx(1);
runEnd = idx(1);
for j = 2:numel(idx)
    current = idx(j);
    if current == runEnd + 1 && labels(current) == labels(runEnd)
        runEnd = current;
    else
        eventIndex = localAppendRun(eventIndex, t, labels, rationales, runStart, runEnd, ...
            sourceView, eventType, fieldNames);
        runStart = current;
        runEnd = current;
    end
end
eventIndex = localAppendRun(eventIndex, t, labels, rationales, runStart, runEnd, ...
    sourceView, eventType, fieldNames);
end

function eventIndex = localAppendFreshnessEvents(eventIndex, audit, includeNominal)
if isempty(audit) || ~istable(audit)
    return;
end
sources = unique(string(audit.source), 'stable');
for k = 1:numel(sources)
    sourceAudit = audit(string(audit.source) == sources(k), :);
    if isempty(sourceAudit)
        continue;
    end
    sourceLabel = "telemetry_freshness:" + string(sourceAudit.source_label(1));
    eventIndex = localAppendRunEvents(eventIndex, sourceAudit, ...
        "status_label", "status_rationale", sourceLabel, ...
        "telemetry_freshness", "valid,updated,seq,age_ms,warn_mask", includeNominal);
end
end

function eventIndex = localAppendRun(eventIndex, t, labels, rationales, runStart, runEnd, sourceView, eventType, fieldNames)
label = labels(runStart);
rationale = localFirstNonempty(rationales(runStart:runEnd));
if rationale == ""
    rationale = "Audit classified this interval as " + label + ".";
end
severity = localSeverityForLabel(label);
eventIndex = localAppendSingleEvent(eventIndex, t(runStart), t(runEnd), ...
    eventType, severity, sourceView, label, rationale, fieldNames);
end

function text = localFirstNonempty(values)
values = string(values(:));
idx = find(values ~= "", 1, 'first');
if isempty(idx)
    text = "";
else
    text = values(idx);
end
end

function tf = localIsNominalLabel(sourceView, label)
label = string(label);
sourceView = string(sourceView);
nominalLabels = ["nominal","nominal_hold","contract_nominal","predict_only","valid_updated"];
if any(label == nominalLabels)
    tf = true;
elseif sourceView == "trajectory_wind" && label == "inertial_propagation_only"
    tf = true;
else
    tf = false;
end
end

function severity = localSeverityForLabel(label)
label = string(label);
missingLabels = ["telemetry_incomplete","logged_firmware_incomplete","replay_incomplete", ...
    "state_incomplete","covariance_incomplete","attitude_evidence_missing","missing"];
criticalLabels = ["nonmonotonic_phase","phase_evidence_mismatch","unexpected_phase_value", ...
    "logged_replay_divergent","truth_error_high","state_contract_delta","input_contract_delta", ...
    "timebase_mismatch","vertical_accel_disagreement","truth_accel_error_high"];
warningLabels = ["warning_active","firmware_warning_active","diagnostic_stale","sample_gap", ...
    "nis_gate_exceeded","innovation_outside_band","covariance_contract_delta", ...
    "logged_gravity_norm_bad","attitude_gravity_norm_bad","tilt_error_high", ...
    "gravity_residual_high","gps_rejected","gps_position_residual_high", ...
    "gps_velocity_residual_high","position_uncertainty_high","wind_uncertainty_high", ...
    "target_below_full_brake","invalid","stale","warning"];
noticeLabels = ["transition_observed","candidate_pending","dwell_met","latched_hold", ...
    "policy_invalid","phase_blocked","target_above_no_brake","brake_authorized","inside_corridor_no_command", ...
    "baro_rejected","trusted_update","replay_baro_rejected","gravity_update_used", ...
    "attitude_propagated","gps_update_used","gps_measurement_not_used","valid_held"];

if any(label == criticalLabels)
    severity = "critical";
elseif any(label == warningLabels)
    severity = "warning";
elseif any(label == missingLabels) || contains(label, "unavailable")
    severity = "missing";
elseif any(label == noticeLabels)
    severity = "notice";
else
    severity = "info";
end
end

function eventIndex = localAppendSingleEvent(eventIndex, tStart, tEnd, eventType, severity, sourceView, label, rationale, fieldNames)
tMid = mean([tStart tEnd], 'omitnan');
if ~isfinite(tMid)
    tMid = NaN;
end
row = table(tStart, tEnd, tMid, string(eventType), string(severity), ...
    string(sourceView), string(label), string(rationale), ...
    localConfidenceForSeverity(severity), string(fieldNames), ...
    'VariableNames', {'t_start','t_end','t_mid','event_type','severity', ...
    'source_view','label','rationale','confidence','field_names'});
eventIndex = [eventIndex; row]; %#ok<AGROW>
end

function value = localConfidenceForSeverity(severity)
switch string(severity)
    case "critical"
        value = 1.0;
    case "warning"
        value = 0.9;
    case "missing"
        value = 0.8;
    case "notice"
        value = 0.7;
    otherwise
        value = 0.5;
end
end

function [eventIndex, errors] = localAppendBuilderFailure(eventIndex, errors, t0, t1, sourceView, eventType, message)
eventIndex = localAppendSingleEvent(eventIndex, t0, t1, eventType, "missing", sourceView, ...
    sourceView + "_unavailable", "Audit builder failed or evidence was unavailable: " + message, "audit_builder");
row = table(string(sourceView), string(message), ...
    'VariableNames', {'source_view','message'});
errors = [errors; row]; %#ok<AGROW>
end

function attitude = localBuildAttitude(T, cfg)
attitude = table();
try
    if istable(T) && ~isempty(T)
        attitude = caelum.runAttitudeReplay(T, cfg);
    end
catch
    attitude = table();
end
end

function est3d = localBuild3DState(T, cfg, attitude)
est3d = table();
if ~istable(T) || isempty(T)
    return;
end
vars = string(T.Properties.VariableNames);
hasGps = all(ismember(["gps_x","gps_y","gps_z"], vars)) || ...
    all(ismember(["gps_vx","gps_vy","gps_vz"], vars));
if ~hasGps
    return;
end

try
    T3 = T;
    vars = string(T3.Properties.VariableNames);
    if ~all(ismember(["q_w","q_x","q_y","q_z"], vars))
        if isempty(attitude)
            attitude = caelum.runAttitudeReplay(T3, cfg);
        end
        if istable(attitude) && ~isempty(attitude) && ismember("t", string(attitude.Properties.VariableNames))
            T3.q_w = interp1(attitude.t, attitude.q_w, T3.t, 'linear', 1);
            T3.q_x = interp1(attitude.t, attitude.q_x, T3.t, 'linear', 0);
            T3.q_y = interp1(attitude.t, attitude.q_y, T3.t, 'linear', 0);
            T3.q_z = interp1(attitude.t, attitude.q_z, T3.t, 'linear', 0);
        end
    end
    est3d = caelum.run3DEKF(T3, cfg);
catch
    est3d = table();
end
end

function eventIndex = localFinalizeEventIndex(eventIndex)
if isempty(eventIndex)
    return;
end
eventIndex.t_start = double(eventIndex.t_start);
eventIndex.t_end = double(eventIndex.t_end);
eventIndex.t_mid = double(eventIndex.t_mid);
eventIndex.confidence = double(eventIndex.confidence);
[~, order] = sortrows([eventIndex.t_start localSeveritySortValue(eventIndex.severity)]);
eventIndex = eventIndex(order, :);
end

function value = localSeveritySortValue(severity)
severity = string(severity(:));
value = zeros(numel(severity), 1);
for k = 1:numel(severity)
    switch severity(k)
        case "critical"
            value(k) = 5;
        case "warning"
            value(k) = 4;
        case "missing"
            value(k) = 3;
        case "notice"
            value(k) = 2;
        otherwise
            value(k) = 1;
    end
end
end

function eventIndex = localEmptyEventTable()
eventIndex = table('Size', [0 10], ...
    'VariableTypes', {'double','double','double','string','string','string','string','string','double','string'}, ...
    'VariableNames', {'t_start','t_end','t_mid','event_type','severity', ...
    'source_view','label','rationale','confidence','field_names'});
end

function errors = localEmptyErrorTable()
errors = table('Size', [0 2], ...
    'VariableTypes', {'string','string'}, ...
    'VariableNames', {'source_view','message'});
end

function [nodes, edges, snapshot] = buildCausalitySnapshotAudit(T, events, replay, cfg, options)
%BUILDCAUSALITYSNAPSHOTAUDIT Build a time-local control causality graph.
%
% The causality snapshot is a dashboard-side forensic artifact. It reuses the
% established evidence audits and records, at one mission time, the chain from
% source freshness through estimator trust, apogee authority, policy decision,
% and actuator output.
arguments
    T table
    events struct = struct()
    replay = table()
    cfg struct = caelum.defaultConfig()
    options.Time (1,1) double = NaN
    options.Selector (1,1) string = "default"
    options.EventIndex table = table()
    options.AuditBundle struct = struct()
    options.Report struct = struct()
    options.Truth struct = struct()
    options.Attitude table = table()
    options.Est3D table = table()
    options.ServoMin_us (1,1) double = 1000
    options.ServoMax_us (1,1) double = 2000
end

if isempty(fieldnames(cfg))
    cfg = caelum.defaultConfig();
end

requestedTime = options.Time;
snapshotTime = requestedTime;
if ~isfinite(snapshotTime)
    snapshotTime = localDefaultSnapshotTime(T, events);
end

if isempty(options.EventIndex) || isempty(fieldnames(options.AuditBundle))
    [eventIndex, auditBundle] = caelum.buildFlightEvidenceIndex(T, events, replay, cfg, ...
        Report=options.Report, ...
        Truth=options.Truth, ...
        Attitude=options.Attitude, ...
        Est3D=options.Est3D);
else
    eventIndex = options.EventIndex;
    auditBundle = options.AuditBundle;
end

nodes = localEmptyNodeTable();
edges = localEmptyEdgeTable();

[sensorNode, sensorEdgeValue] = localSensorFreshnessNode(auditBundle, snapshotTime);
[attNode, attEdgeValue] = localAuditNode(auditBundle, "attitudeGravity", snapshotTime, ...
    "attitude_gravity", "Attitude / Gravity", "source", ...
    ["logged_a_vertical_mps2","gravity_residual_mps2","tilt_error_deg"], ...
    ["a_v","g_res","tilt"], ["%.2f","%.2f","%.1f"], ...
    "evidence_label", "evidence_rationale", 0.25, 0.82);
[estNode, estEdgeValue] = localAuditNode(auditBundle, "estimatorTrust", snapshotTime, ...
    "estimator_trust", "Estimator Trust", "estimate", ...
    ["logged_h_m","logged_v_mps","innovation_nis"], ...
    ["h","v","NIS"], ["%.1f","%.2f","%.2f"], ...
    "trust_label", "trust_rationale", 0.25, 0.56);
[replayNode, replayEdgeValue] = localAuditNode(auditBundle, "replayContractDiff", snapshotTime, ...
    "replay_contract", "Replay Contract", "validation", ...
    ["delta_h_m","delta_v_mps","delta_a_vertical_mps2"], ...
    ["dh","dv","da"], ["%.2f","%.2f","%.3g"], ...
    "contract_label", "contract_rationale", 0.43, 0.70);
[trajNode, trajEdgeValue] = localAuditNode(auditBundle, "trajectoryWind", snapshotTime, ...
    "trajectory_wind", "3D / Wind", "context", ...
    ["position_sigma_norm_m","wind_sigma_norm_mps","wind_speed_mps"], ...
    ["pSig","wSig","wind"], ["%.2f","%.2f","%.2f"], ...
    "evidence_label", "evidence_rationale", 0.43, 0.38);

phaseNode = localPhaseNode(auditBundle, T, snapshotTime);
apogeeNode = localApogeeNode(auditBundle, snapshotTime);
policyNode = localPolicyNode(auditBundle, snapshotTime);
actuatorNode = localActuatorNode(auditBundle, snapshotTime, options.ServoMin_us, options.ServoMax_us);

nodes = [nodes; sensorNode; attNode; estNode; replayNode; trajNode; ...
    phaseNode; apogeeNode; policyNode; actuatorNode]; %#ok<AGROW>

edges = [edges; ...
    localEdge("source_attitude", "sensor_freshness", "attitude_gravity", ...
        "fresh source data", sensorEdgeValue, sensorNode.severity, ...
        "IMU and attitude-domain freshness support gravity projection.", ...
        "imu_valid,imu_updated,att_valid,att_updated"); ...
    localEdge("source_estimator", "sensor_freshness", "estimator_trust", ...
        "fresh estimator inputs", sensorEdgeValue, sensorNode.severity, ...
        "Barometer, IMU, and estimator freshness bound estimator trust.", ...
        "baro_valid,imu_valid,est_valid,est_updated"); ...
    localEdge("attitude_estimator", "attitude_gravity", "estimator_trust", ...
        "vertical acceleration", attEdgeValue, attNode.severity, ...
        "Vertical acceleration provenance feeds estimator propagation.", ...
        "a_vertical,g_bx,g_by,g_bz,q_w,q_x,q_y,q_z"); ...
    localEdge("estimator_replay", "estimator_trust", "replay_contract", ...
        "logged vs replay", replayEdgeValue, replayNode.severity, ...
        "Replay contract checks whether the logged estimator state is reproducible.", ...
        "kf_h,kf_v,P00,P11,replay_h,replay_v"); ...
    localEdge("estimator_apogee", "estimator_trust", "apogee_prediction", ...
        "state to apogee", estEdgeValue, estNode.severity, ...
        "Altitude, velocity, and covariance evidence feed apogee prediction.", ...
        "kf_h,kf_v,P00,P11"); ...
    localEdge("trajectory_apogee", "trajectory_wind", "apogee_prediction", ...
        "3D context", trajEdgeValue, trajNode.severity, ...
        "3D/wind evidence contextualizes apogee interpretation and demonstration.", ...
        "gps_x,gps_y,gps_z,wx,wy,wz"); ...
    localEdge("phase_policy", "phase_state", "policy_decision", ...
        "phase gate", phaseNode.value_text, phaseNode.severity, ...
        "Firmware phase gates whether braking intent is meaningful.", ...
        "phase,phase_brake_active,phase_latches"); ...
    localEdge("apogee_policy", "apogee_prediction", "policy_decision", ...
        "authority corridor", apogeeNode.value_text, apogeeNode.severity, ...
        "No-brake/full-brake reachability and target margin drive policy demand.", ...
        "apogee_no_brake,apogee_full_brake,target_effective,uncertainty_margin"); ...
    localEdge("replay_policy", "replay_contract", "policy_decision", ...
        "estimator contract", replayEdgeValue, replayNode.severity, ...
        "Replay contract confidence qualifies the estimator state consumed by policy.", ...
        "replay_contract_diff"); ...
    localEdge("policy_actuator", "policy_decision", "actuator_output", ...
        "command to pulse", actuatorNode.value_text, actuatorNode.severity, ...
        "Policy command and logged actuator pulse show the final commanded output.", ...
        "policy_cmd,actuator_us")]; %#ok<AGROW>

snapshot = localBuildSnapshotTable(snapshotTime, requestedTime, options.Selector, nodes, edges, eventIndex);
end

function [node, valueText] = localSensorFreshnessNode(auditBundle, snapshotTime)
audit = localBundleTable(auditBundle, "telemetryFreshness");
if isempty(audit) || ~ismember("t", string(audit.Properties.VariableNames))
    valueText = "freshness unavailable";
    node = localNode("sensor_freshness", "Sensor Freshness", "source", "missing", ...
        "telemetry_freshness_unavailable", valueText, ...
        "Telemetry freshness audit was unavailable for this snapshot.", ...
        "baro_valid,imu_valid,est_valid,warn_mask", snapshotTime, 0.08, 0.70);
    return;
end

t = double(audit.t(:));
valid = isfinite(t);
if ~any(valid)
    valueText = "freshness time unavailable";
    node = localNode("sensor_freshness", "Sensor Freshness", "source", "missing", ...
        "telemetry_freshness_unavailable", valueText, ...
        "Telemetry freshness audit had no finite timestamps.", ...
        "baro_valid,imu_valid,est_valid,warn_mask", snapshotTime, 0.08, 0.70);
    return;
end

[~, nearestIdx] = min(abs(t(valid) - snapshotTime));
validIdx = find(valid);
nearestT = t(validIdx(nearestIdx));
rows = audit(abs(t - nearestT) <= max(1.0e-9, 1.0e-9 * max(1, abs(nearestT))), :);
labels = string(rows.status_label);
statusLabel = localWorstLabel(labels);
severity = localWorstSeverity(labels);
valueText = sprintf('updated=%d held=%d invalid=%d stale=%d missing=%d warn=%d', ...
    nnz(labels == "valid_updated"), nnz(labels == "valid_held"), ...
    nnz(labels == "invalid"), nnz(labels == "stale"), ...
    nnz(labels == "missing"), nnz(labels == "warning_active"));
node = localNode("sensor_freshness", "Sensor Freshness", "source", severity, ...
    statusLabel, valueText, ...
    "Freshness/provenance status for all telemetry domains at the nearest sample.", ...
    "baro_valid,imu_valid,aux_valid,att_valid,est_valid,warn_mask", nearestT, 0.08, 0.70);
end

function [node, valueText] = localAuditNode(auditBundle, bundleField, snapshotTime, nodeId, label, group, fields, names, formats, labelField, rationaleField, x, y)
audit = localBundleTable(auditBundle, bundleField);
if isempty(audit)
    valueText = label + " unavailable";
    node = localNode(nodeId, label, group, "missing", nodeId + "_unavailable", ...
        valueText, label + " audit was unavailable for this snapshot.", ...
        strjoin(cellstr(fields), ","), snapshotTime, x, y);
    return;
end

row = localNearestRow(audit, snapshotTime);
if isempty(row)
    valueText = label + " unavailable";
    node = localNode(nodeId, label, group, "missing", nodeId + "_unavailable", ...
        valueText, label + " audit had no finite row near this snapshot.", ...
        strjoin(cellstr(fields), ","), snapshotTime, x, y);
    return;
end

statusLabel = localTableString(row, labelField, "unclassified");
rationale = localTableString(row, rationaleField, label + " evidence at the selected snapshot.");
severity = localSeverityForLabel(statusLabel);
valueText = localFormattedValues(row, fields, names, formats);
node = localNode(nodeId, label, group, severity, statusLabel, valueText, rationale, ...
    strjoin(cellstr(fields), ","), localTableNumber(row, "t", snapshotTime), x, y);
end

function node = localPhaseNode(auditBundle, T, snapshotTime)
audit = localBundleTable(auditBundle, "phaseState");
row = localNearestRow(audit, snapshotTime);
if ~isempty(row)
    statusLabel = localTableString(row, "evidence_label", "unclassified");
    rationale = localTableString(row, "evidence_rationale", "Phase evidence at the selected snapshot.");
    severity = localSeverityForLabel(statusLabel);
    phaseName = localTableString(row, "phase_name", localPhaseName(localTableNumber(row, "phase", NaN)));
    valueText = "phase=" + phaseName + "; brake_active=" + localFormatNumber(localTableNumber(row, "phase_brake_active", NaN), "%.0f");
    node = localNode("phase_state", "Phase State", "gate", severity, statusLabel, valueText, rationale, ...
        "phase,phase_brake_active,phase_latches", localTableNumber(row, "t", snapshotTime), 0.60, 0.82);
    return;
end

rowT = localNearestRow(T, snapshotTime);
phase = localTableNumber(rowT, "phase", NaN);
if isfinite(phase)
    valueText = "phase=" + localPhaseName(phase);
    statusLabel = "phase_from_log";
    severity = "info";
    rationale = "Phase state was read directly from the clean log.";
else
    valueText = "phase unavailable";
    statusLabel = "telemetry_incomplete";
    severity = "missing";
    rationale = "No phase evidence was available at this snapshot.";
end
node = localNode("phase_state", "Phase State", "gate", severity, statusLabel, valueText, rationale, ...
    "phase", snapshotTime, 0.60, 0.82);
end

function node = localApogeeNode(auditBundle, snapshotTime)
policy = localBundleTable(auditBundle, "policy");
row = localNearestRow(policy, snapshotTime);
if isempty(row)
    node = localNode("apogee_prediction", "Apogee Authority", "prediction", "missing", ...
        "apogee_prediction_unavailable", "apogee corridor unavailable", ...
        "Policy/apogee prediction audit was unavailable for this snapshot.", ...
        "apogee_no_brake,apogee_full_brake,target_effective", snapshotTime, 0.60, 0.56);
    return;
end

span = localTableNumber(row, "reachability_span_m", NaN);
target = localTableNumber(row, "target_selected_m", NaN);
demand = localTableNumber(row, "corridor_brake_demand_index", NaN);
noBrake = localTableNumber(row, "apogee_no_brake_m", NaN);
fullBrake = localTableNumber(row, "apogee_full_brake_m", NaN);
margin = localTableNumber(row, "uncertainty_margin_m", NaN);

if ~isfinite(span) || span <= 0 || ~isfinite(target)
    statusLabel = "telemetry_incomplete";
    severity = "missing";
    rationale = "Apogee reachability corridor or target telemetry is unavailable.";
elseif localTableLogical(row, "target_above_no_brake")
    statusLabel = "target_above_no_brake";
    severity = "notice";
    rationale = "Target is above the no-brake prediction, so additional braking is not demanded.";
elseif localTableLogical(row, "target_below_full_brake")
    statusLabel = "target_below_full_brake";
    severity = "warning";
    rationale = "Target is below the full-brake prediction; available authority may still overshoot.";
else
    statusLabel = "target_inside_corridor";
    severity = "info";
    rationale = "Target lies inside the no-brake/full-brake reachability corridor.";
end

valueText = "no=" + localFormatNumber(noBrake, "%.0f") + ...
    "; full=" + localFormatNumber(fullBrake, "%.0f") + ...
    "; tgt=" + localFormatNumber(target, "%.0f") + ...
    "; span=" + localFormatNumber(span, "%.1f") + ...
    "; margin=" + localFormatNumber(margin, "%.1f") + ...
    "; demand=" + localFormatNumber(demand, "%.2f");
node = localNode("apogee_prediction", "Apogee Authority", "prediction", severity, ...
    statusLabel, valueText, rationale, ...
    "apogee_no_brake,apogee_full_brake,target_effective,uncertainty_margin", ...
    localTableNumber(row, "t", snapshotTime), 0.60, 0.56);
end

function node = localPolicyNode(auditBundle, snapshotTime)
policy = localBundleTable(auditBundle, "policy");
row = localNearestRow(policy, snapshotTime);
if isempty(row)
    node = localNode("policy_decision", "Policy Decision", "control", "missing", ...
        "policy_unavailable", "policy unavailable", ...
        "Policy decision audit was unavailable for this snapshot.", ...
        "policy_valid,policy_cmd", snapshotTime, 0.78, 0.70);
    return;
end

statusLabel = localTableString(row, "decision_label", "unclassified");
rationale = localTableString(row, "decision_rationale", "Policy evidence at the selected snapshot.");
severity = localSeverityForLabel(statusLabel);
valueText = "valid=" + localFormatNumber(localTableNumber(row, "policy_valid", NaN), "%.0f") + ...
    "; cmd=" + localFormatNumber(localTableNumber(row, "policy_cmd", NaN), "%.3f") + ...
    "; residual=" + localFormatNumber(localTableNumber(row, "policy_command_residual", NaN), "%.3f");
node = localNode("policy_decision", "Policy Decision", "control", severity, ...
    statusLabel, valueText, rationale, "policy_valid,policy_cmd,policy_command_residual", ...
    localTableNumber(row, "t", snapshotTime), 0.78, 0.70);
end

function node = localActuatorNode(auditBundle, snapshotTime, servoMin_us, servoMax_us)
policy = localBundleTable(auditBundle, "policy");
row = localNearestRow(policy, snapshotTime);
if isempty(row)
    node = localNode("actuator_output", "Actuator Output", "output", "missing", ...
        "actuator_unavailable", "actuator unavailable", ...
        "Policy/actuator audit was unavailable for this snapshot.", ...
        "policy_cmd,actuator_us", snapshotTime, 0.94, 0.70);
    return;
end

cmd = localTableNumber(row, "policy_cmd", NaN);
actuatorUs = localTableNumber(row, "actuator_us", NaN);
span = servoMax_us - servoMin_us;
if isfinite(actuatorUs) && isfinite(span) && span > 0
    actuator01 = min(max((actuatorUs - servoMin_us) ./ span, 0), 1);
else
    actuator01 = NaN;
end
residual = actuator01 - cmd;

if ~isfinite(cmd) || ~isfinite(actuatorUs)
    statusLabel = "actuator_telemetry_missing";
    severity = "missing";
    rationale = "Policy command or actuator pulse telemetry is unavailable.";
elseif isfinite(residual) && abs(residual) > 0.10
    statusLabel = "actuator_policy_mismatch";
    severity = "warning";
    rationale = "Logged actuator pulse differs from the normalized policy command by more than 0.10.";
elseif cmd >= 0.05
    statusLabel = "actuator_following_policy";
    severity = "notice";
    rationale = "Logged actuator pulse is consistent with a nonzero policy command.";
else
    statusLabel = "actuator_idle";
    severity = "info";
    rationale = "Policy command and logged actuator pulse are both near idle.";
end

valueText = "cmd=" + localFormatNumber(cmd, "%.3f") + ...
    "; us=" + localFormatNumber(actuatorUs, "%.0f") + ...
    "; pos=" + localFormatNumber(actuator01, "%.3f") + ...
    "; err=" + localFormatNumber(residual, "%.3f");
node = localNode("actuator_output", "Actuator Output", "output", severity, ...
    statusLabel, valueText, rationale, "policy_cmd,actuator_us", ...
    localTableNumber(row, "t", snapshotTime), 0.94, 0.70);
end

function snapshot = localBuildSnapshotTable(snapshotTime, requestedTime, selector, nodes, edges, eventIndex)
rank = localSeverityRank(nodes.severity);
[maxRank, idx] = max(rank);
if isempty(idx) || ~isfinite(maxRank)
    maxSeverity = "info";
    importantNode = "";
    importantLabel = "";
else
    maxSeverity = string(nodes.severity(idx));
    importantNode = string(nodes.node_id(idx));
    importantLabel = string(nodes.status_label(idx));
end
snapshot = table(snapshotTime, requestedTime, string(selector), maxSeverity, ...
    importantNode, importantLabel, height(nodes), height(edges), height(eventIndex), ...
    'VariableNames', {'t','requested_t','selector','max_severity', ...
    'most_important_node','most_important_label','node_count','edge_count','event_count'});
end

function eventTime = localDefaultSnapshotTime(T, events)
eventTime = NaN;
vars = string(T.Properties.VariableNames);
if istable(T) && ~isempty(T) && ismember("t", vars) && ismember("policy_cmd", vars)
    cmd = double(T.policy_cmd(:));
    t = double(T.t(:));
    valid = isfinite(cmd) & isfinite(t);
    if any(valid)
        [~, idx] = max(cmd(valid));
        validIdx = find(valid);
        eventTime = t(validIdx(idx));
        return;
    end
end
if isstruct(events) && isfield(events, 'apogeeTime_s') && isfinite(events.apogeeTime_s)
    eventTime = events.apogeeTime_s;
    return;
end
if istable(T) && ~isempty(T) && ismember("t", vars)
    t = double(T.t(:));
    t = t(isfinite(t));
    if ~isempty(t)
        eventTime = median(t, 'omitnan');
    end
end
end

function T = localBundleTable(bundle, fieldName)
if isstruct(bundle) && isfield(bundle, fieldName) && istable(bundle.(fieldName))
    T = bundle.(fieldName);
else
    T = table();
end
end

function row = localNearestRow(T, snapshotTime)
row = table();
if ~istable(T) || isempty(T)
    return;
end
vars = string(T.Properties.VariableNames);
if ~ismember("t", vars)
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
idx = find(valid);
row = T(idx(nearest), :);
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

function value = localTableLogical(row, fieldName)
value = false;
if ~istable(row) || isempty(row) || ~ismember(fieldName, string(row.Properties.VariableNames))
    return;
end
raw = row.(char(fieldName));
if isempty(raw)
    return;
end
try
    numericValue = double(raw(1));
    if isfinite(numericValue)
        value = numericValue > 0.5;
        return;
    end
catch
end
textValue = lower(strtrim(string(raw(1))));
value = any(textValue == ["true","t","yes","y","1"]);
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

function textOut = localFormattedValues(row, fields, names, formats)
parts = strings(0, 1);
for k = 1:numel(fields)
    value = localTableNumber(row, fields(k), NaN);
    if isfinite(value)
        parts(end+1) = names(k) + "=" + localFormatNumber(value, formats(k)); %#ok<AGROW>
    end
end
if isempty(parts)
    textOut = "values unavailable";
else
    textOut = strjoin(parts, "; ");
end
end

function textOut = localFormatNumber(value, formatSpec)
if isfinite(value)
    textOut = string(sprintf(char(formatSpec), value));
else
    textOut = "NaN";
end
end

function label = localWorstLabel(labels)
labels = string(labels(:));
if isempty(labels)
    label = "unclassified";
    return;
end
severities = strings(numel(labels), 1);
for k = 1:numel(labels)
    severities(k) = localSeverityForLabel(labels(k));
end
rank = localSeverityRank(severities);
[~, idx] = max(rank);
label = labels(idx);
end

function severity = localWorstSeverity(labels)
labels = string(labels(:));
if isempty(labels)
    severity = "missing";
    return;
end
severities = strings(numel(labels), 1);
for k = 1:numel(labels)
    severities(k) = localSeverityForLabel(labels(k));
end
[~, idx] = max(localSeverityRank(severities));
severity = severities(idx);
end

function severity = localSeverityForLabel(label)
label = string(label);
missingLabels = ["telemetry_incomplete","logged_firmware_incomplete","replay_incomplete", ...
    "state_incomplete","covariance_incomplete","attitude_evidence_missing","missing", ...
    "actuator_telemetry_missing","actuator_unavailable"];
criticalLabels = ["nonmonotonic_phase","phase_evidence_mismatch","unexpected_phase_value", ...
    "logged_replay_divergent","truth_error_high","state_contract_delta","input_contract_delta", ...
    "timebase_mismatch","vertical_accel_disagreement","truth_accel_error_high"];
warningLabels = ["warning_active","firmware_warning_active","diagnostic_stale","sample_gap", ...
    "nis_gate_exceeded","innovation_outside_band","covariance_contract_delta", ...
    "logged_gravity_norm_bad","attitude_gravity_norm_bad","tilt_error_high", ...
    "gravity_residual_high","gps_rejected","gps_position_residual_high", ...
    "gps_velocity_residual_high","position_uncertainty_high","wind_uncertainty_high", ...
    "target_below_full_brake","invalid","stale","warning","actuator_policy_mismatch"];
noticeLabels = ["transition_observed","candidate_pending","dwell_met","latched_hold", ...
    "policy_invalid","phase_blocked","target_above_no_brake","brake_authorized", ...
    "inside_corridor_no_command","baro_rejected","trusted_update","replay_baro_rejected", ...
    "gravity_update_used","attitude_propagated","gps_update_used", ...
    "gps_measurement_not_used","valid_held","actuator_following_policy"];

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

function rank = localSeverityRank(severity)
severity = string(severity(:));
rank = zeros(numel(severity), 1);
for k = 1:numel(severity)
    switch severity(k)
        case "critical"
            rank(k) = 5;
        case "warning"
            rank(k) = 4;
        case "missing"
            rank(k) = 3;
        case "notice"
            rank(k) = 2;
        otherwise
            rank(k) = 1;
    end
end
end

function name = localPhaseName(phase)
if ~isfinite(phase)
    name = "UNKNOWN";
    return;
end
switch round(phase)
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

function node = localNode(nodeId, nodeLabel, nodeGroup, severity, statusLabel, valueText, rationale, sourceFields, t, x, y)
node = table(string(nodeId), string(nodeLabel), string(nodeGroup), string(severity), ...
    string(statusLabel), string(valueText), string(rationale), string(sourceFields), ...
    double(t), double(x), double(y), ...
    'VariableNames', {'node_id','node_label','node_group','severity', ...
    'status_label','value_text','rationale','source_fields','t','x','y'});
end

function edge = localEdge(edgeId, fromNode, toNode, edgeLabel, valueText, severity, rationale, sourceFields)
edge = table(string(edgeId), string(fromNode), string(toNode), string(edgeLabel), ...
    string(valueText), string(severity), string(rationale), string(sourceFields), ...
    'VariableNames', {'edge_id','from_node','to_node','edge_label', ...
    'value_text','severity','rationale','source_fields'});
end

function nodes = localEmptyNodeTable()
nodes = table('Size', [0 11], ...
    'VariableTypes', {'string','string','string','string','string','string','string','string','double','double','double'}, ...
    'VariableNames', {'node_id','node_label','node_group','severity', ...
    'status_label','value_text','rationale','source_fields','t','x','y'});
end

function edges = localEmptyEdgeTable()
edges = table('Size', [0 8], ...
    'VariableTypes', {'string','string','string','string','string','string','string','string'}, ...
    'VariableNames', {'edge_id','from_node','to_node','edge_label', ...
    'value_text','severity','rationale','source_fields'});
end

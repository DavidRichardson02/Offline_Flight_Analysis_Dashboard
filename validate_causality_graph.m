function validation = validate_causality_graph(options)
%VALIDATE_CAUSALITY_GRAPH Validate sensor-to-actuator causality snapshots.
%
% Validation exercises key mission times and degraded/fallback cases. The graph
% is static in this milestone; the node and edge tables are the primary
% reviewable contract, and the figure is the presentation artifact.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "causality_graph_validation")
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

caseDefs = localCaseDefinitions(options);
reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'selector', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'nodes', table(), ...
    'edges', table(), ...
    'snapshot', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseCaseResults, rows] = localRunCase(caseDefs(k), options);
    caseResults = [caseResults; caseCaseResults]; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "causality_graph_validation_report.csv");
writetable(reportTable, reportPath);

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.exportRoot = options.ExportRoot;
validation.reportPath = reportPath;
validation.caseResults = caseResults;
validation.reportTable = reportTable;
validation.overallPassed = all(reportTable.passed);

disp(reportTable(:, ["caseName","selector","scope","check","passed","actual","expected","notes"]));
if validation.overallPassed
    fprintf('Causality graph validation passed.\n');
else
    fprintf(2, 'Causality graph validation reported failures.\n');
end
end

function caseDefs = localCaseDefinitions(options)
caseDefs = [ ...
    struct('name', "latest_sd_fixture", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'seed', NaN, ...
        'useReplay', true, ...
        'mutation', "none"); ...
    struct('name', "latest_serial_fixture", ...
        'sourceKind', "serial", ...
        'sourcePath', options.SerialFixturePath, ...
        'seed', NaN, ...
        'useReplay', true, ...
        'mutation', "none"); ...
    struct('name', "generated_replay_contract_fixture", ...
        'sourceKind', "generated", ...
        'sourcePath', "", ...
        'seed', 71, ...
        'useReplay', true, ...
        'mutation', "none"); ...
    struct('name', "freshness_degraded_fixture", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'seed', NaN, ...
        'useReplay', true, ...
        'mutation', "freshness_degraded"); ...
    struct('name', "missing_replay_fallback", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'seed', NaN, ...
        'useReplay', false, ...
        'mutation', "none"); ...
    struct('name', "missing_firmware_fields_fallback", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'seed', NaN, ...
        'useReplay', false, ...
        'mutation', "missing_firmware_fields")];
end

function [caseResults, rows] = localRunCase(caseDef, options)
rows = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'selector', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'nodes', table(), ...
    'edges', table(), ...
    'snapshot', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

caseDir = fullfile(options.ExportRoot, caseDef.name);
if ~exist(caseDir, 'dir')
    mkdir(caseDir);
end

cfg = caelum.defaultConfig();
[inputPath, clean, importReport, cleanReport, truth] = localPrepareCleanCase(caseDef, caseDir, cfg);
clean = localApplyMutation(clean, caseDef.mutation);
events = caelum.detectEvents(clean, cfg);

if caseDef.useReplay
    replay = caelum.replayEstimator(clean, cfg);
else
    replay = table();
end

[eventIndex, auditBundle] = caelum.buildFlightEvidenceIndex(clean, events, replay, cfg, ...
    Report=importReport, Truth=truth);

selectors = localSelectorsForCase(caseDef);
for s = 1:numel(selectors)
    selector = selectors(s);
    snapshotTime = localResolveSelectorTime(selector, clean, events);

    [nodes, edges, snapshot] = caelum.buildCausalitySnapshotAudit(clean, events, replay, cfg, ...
        Time=snapshotTime, ...
        Selector=selector, ...
        EventIndex=eventIndex, ...
        AuditBundle=auditBundle, ...
        Report=importReport, ...
        Truth=truth);
    fig = caelum.plotCausalityGraph(nodes, edges, snapshot, ...
        Title="Causality Graph - " + caseDef.name + " - " + selector);

    results = struct();
    results.filename = localResultFilename(inputPath, caseDef, selector);
    results.causalityNodes = nodes;
    results.causalityEdges = edges;
    results.causalitySnapshot = snapshot;
    results.causalityGraphFigure = fig;
    exportInfo = caelum.exportFigures(results, caseDir);

    snapshotRows = localValidateSnapshot(caseDef, selector, clean, nodes, edges, snapshot, fig, exportInfo, ...
        localReportSummary(importReport, cleanReport));
    rows = [rows; snapshotRows]; %#ok<AGROW>

    caseResult = struct();
    caseResult.caseName = caseDef.name;
    caseResult.selector = selector;
    caseResult.sourceKind = caseDef.sourceKind;
    caseResult.sourcePath = inputPath;
    caseResult.nodes = nodes;
    caseResult.edges = edges;
    caseResult.snapshot = snapshot;
    caseResult.exportInfo = exportInfo;
    caseResult.passed = all(snapshotRows.passed);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>

    localCloseFigure(fig);
end
end

function rows = localValidateSnapshot(caseDef, selector, clean, nodes, edges, snapshot, fig, exportInfo, reportSummary)
rows = localEmptyValidationTable();
rows = [rows; localValidationRow(caseDef.name, selector, "execution", "snapshot_built", ...
    height(clean) > 0 && height(nodes) >= 9 && height(edges) >= 10 && isfinite(snapshot.t(1)), ...
    "clean=" + string(height(clean)) + ";nodes=" + string(height(nodes)) + ...
    ";edges=" + string(height(edges)) + ";t=" + string(snapshot.t(1)), ...
    "clean>0;nodes>=9;edges>=10;t finite", reportSummary)]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "schema", "node_required_columns_present", ...
    localNodeColumnsPresent(nodes), localMissingNodeColumns(nodes), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "schema", "edge_required_columns_present", ...
    localEdgeColumnsPresent(edges), localMissingEdgeColumns(edges), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "schema", "snapshot_required_columns_present", ...
    localSnapshotColumnsPresent(snapshot), localMissingSnapshotColumns(snapshot), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "coverage", "core_chain_nodes_present", ...
    all(ismember(["sensor_freshness","estimator_trust","apogee_prediction", ...
    "policy_decision","actuator_output"], string(nodes.node_id))), ...
    localMissingString(setdiff(["sensor_freshness","estimator_trust","apogee_prediction", ...
    "policy_decision","actuator_output"], string(nodes.node_id), 'stable')), ...
    "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "coverage", "core_chain_edges_present", ...
    all(ismember(["source_estimator","estimator_apogee","apogee_policy","policy_actuator"], string(edges.edge_id))), ...
    localMissingString(setdiff(["source_estimator","estimator_apogee","apogee_policy","policy_actuator"], ...
    string(edges.edge_id), 'stable')), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "classification", "node_labels_and_values_nonempty", ...
    all(nodes.status_label ~= "") && all(nodes.value_text ~= ""), ...
    "labels=" + string(nnz(nodes.status_label ~= "")) + ";values=" + string(nnz(nodes.value_text ~= "")), ...
    string(height(nodes)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "plot", "causality_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>

rows = [rows; localCaseSpecificRows(caseDef, selector, nodes)]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, selector, exportInfo)]; %#ok<AGROW>
end

function rows = localCaseSpecificRows(caseDef, selector, nodes)
rows = localEmptyValidationTable();
if ~caseDef.useReplay
    replayNode = nodes(nodes.node_id == "replay_contract", :);
    hasReplayFallback = ~isempty(replayNode) && ...
        (replayNode.severity == "missing" || replayNode.status_label == "replay_incomplete");
    rows = [rows; localValidationRow(caseDef.name, selector, "classification", ...
        "missing_replay_qualified", hasReplayFallback, localNodeSummary(nodes), ...
        "replay node missing or replay_incomplete", "")]; %#ok<AGROW>
end
if caseDef.mutation == "freshness_degraded"
    sensorNode = nodes(nodes.node_id == "sensor_freshness", :);
    hasFreshnessDegradation = ~isempty(sensorNode) && ...
        (sensorNode.severity == "warning" || sensorNode.severity == "missing");
    rows = [rows; localValidationRow(caseDef.name, selector, "classification", ...
        "freshness_degradation_visible", hasFreshnessDegradation, localNodeSummary(nodes), ...
        "sensor node warning or missing", "")]; %#ok<AGROW>
end
if caseDef.mutation == "missing_firmware_fields"
    impacted = nodes(ismember(nodes.node_id, ["apogee_prediction","policy_decision","actuator_output"]), :);
    hasMissing = ~isempty(impacted) && any(impacted.severity == "missing");
    rows = [rows; localValidationRow(caseDef.name, selector, "classification", ...
        "missing_firmware_fields_visible", hasMissing, localNodeSummary(nodes), ...
        "policy/apogee/actuator node missing", "")]; %#ok<AGROW>
end
end

function [inputPath, clean, importReport, cleanReport, truth] = localPrepareCleanCase(caseDef, caseDir, cfg)
truth = struct();
switch caseDef.sourceKind
    case "generated"
        inputPath = fullfile(caseDir, caseDef.name + ".csv");
        [~, truth] = caelum.generateTruthAwareCaelumLogV2(inputPath, seed=caseDef.seed);
        [raw, importReport] = caelum.importLog(inputPath);
    case "sd"
        inputPath = caseDef.sourcePath;
        if ~isfile(inputPath)
            error('validate_causality_graph:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
        [raw, importReport] = caelum.importLog(inputPath);
    case "serial"
        inputPath = caseDef.sourcePath;
        if ~isfile(inputPath)
            error('validate_causality_graph:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
        [raw, importReport] = caelum.importSerialTelemetry(inputPath);
    otherwise
        error('validate_causality_graph:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end

aligned = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);
end

function clean = localApplyMutation(clean, mutation)
vars = string(clean.Properties.VariableNames);
switch mutation
    case "freshness_degraded"
        n = height(clean);
        block = false(n, 1);
        block(max(1, round(0.25*n)):max(1, round(0.35*n))) = true;
        if ismember("baro_valid", vars)
            clean.baro_valid(block) = 0;
        end
        if ismember("imu_updated", vars)
            clean.imu_updated(block) = 0;
        end
        if ismember("phase_diag_age_ms", vars)
            clean.phase_diag_age_ms(block) = 1000;
        end
        if ismember("warn_mask", vars)
            clean.warn_mask(block) = 1;
        end
    case "missing_firmware_fields"
        removeFields = intersect(["phase","policy_valid","policy_cmd","actuator_us", ...
            "apogee_no_brake","apogee_full_brake","target_apogee","target_nominal", ...
            "target_effective","uncertainty_margin","warn_mask","phase_diag_valid", ...
            "phase_diag_updated","phase_diag_age_ms","phase_launch_latched", ...
            "phase_burnout_latched","phase_descent_latched","phase_brake_active"], vars, 'stable');
        if ~isempty(removeFields)
            clean(:, cellstr(removeFields)) = [];
        end
    otherwise
end
end

function selectors = localSelectorsForCase(caseDef)
switch caseDef.name
    case "latest_sd_fixture"
        selectors = ["launch","burnout","brake_start","max_command","apogee"];
    case "latest_serial_fixture"
        selectors = ["max_command","apogee"];
    case "generated_replay_contract_fixture"
        selectors = ["burnout","apogee"];
    case "freshness_degraded_fixture"
        selectors = "freshness_degraded_window";
    case "missing_replay_fallback"
        selectors = "max_command";
    case "missing_firmware_fields_fallback"
        selectors = "apogee";
    otherwise
        selectors = "default";
end
end

function t = localResolveSelectorTime(selector, T, events)
vars = string(T.Properties.VariableNames);
selector = string(selector);
switch selector
    case "launch"
        t = localEventTime(events, "launchTime_s");
    case "burnout"
        t = localEventTime(events, "burnoutTime_s");
    case "apogee"
        t = localEventTime(events, "apogeeTime_s");
    case "brake_start"
        t = localBrakeStartTime(T);
    case "max_command"
        t = localMaxCommandTime(T);
    case "freshness_degraded_window"
        if ismember("t", vars) && height(T) > 0
            idx = min(height(T), max(1, round(0.30 * height(T))));
            t = double(T.t(idx));
        else
            t = NaN;
        end
    otherwise
        t = NaN;
end

if ~isfinite(t)
    t = localDefaultTime(T, events);
end
end

function t = localEventTime(events, fieldName)
t = NaN;
if isstruct(events) && isfield(events, fieldName) && isfinite(events.(fieldName))
    t = events.(fieldName);
end
end

function t = localBrakeStartTime(T)
t = NaN;
vars = string(T.Properties.VariableNames);
if ismember("t", vars) && ismember("phase", vars)
    idx = find(isfinite(T.phase) & round(T.phase) == 3, 1, 'first');
    if ~isempty(idx)
        t = T.t(idx);
        return;
    end
end
if ismember("t", vars) && ismember("policy_cmd", vars)
    idx = find(isfinite(T.policy_cmd) & T.policy_cmd >= 0.05, 1, 'first');
    if ~isempty(idx)
        t = T.t(idx);
    end
end
end

function t = localMaxCommandTime(T)
t = NaN;
vars = string(T.Properties.VariableNames);
if ismember("t", vars) && ismember("policy_cmd", vars)
    valid = isfinite(T.t) & isfinite(T.policy_cmd);
    if any(valid)
        [~, idx] = max(T.policy_cmd(valid));
        validIdx = find(valid);
        t = T.t(validIdx(idx));
    end
end
end

function t = localDefaultTime(T, events)
t = localMaxCommandTime(T);
if isfinite(t)
    return;
end
t = localEventTime(events, "apogeeTime_s");
if isfinite(t)
    return;
end
vars = string(T.Properties.VariableNames);
if ismember("t", vars)
    tv = T.t(isfinite(T.t));
    if ~isempty(tv)
        t = median(tv, 'omitnan');
    end
end
end

function filename = localResultFilename(inputPath, caseDef, selector)
selector = regexprep(char(selector), '[^a-zA-Z0-9_-]', '_');
if caseDef.sourceKind == "generated"
    [folder, base, ext] = fileparts(inputPath);
else
    [folder, base, ext] = fileparts(caseDef.sourcePath);
end
if isempty(folder)
    folder = fileparts(inputPath);
end
filename = string(fullfile(folder, string(base) + "_" + string(caseDef.name) + "_" + string(selector) + string(ext)));
end

function rows = localArtifactRows(caseName, selector, exportInfo)
rows = localEmptyValidationTable();
required = ["causality_nodes_csv","causality_edges_csv","causality_snapshot_csv", ...
    "causality_graph_png","causality_graph_pdf","manifest_csv"];
for k = 1:numel(required)
    key = char(required(k));
    hasKey = isfield(exportInfo.files, key);
    if hasKey
        pathValue = string(exportInfo.files.(key));
        exists = isfile(pathValue);
        actual = pathValue;
    else
        exists = false;
        actual = "missing_export_key";
    end
    rows = [rows; localValidationRow(caseName, selector, "artifact", required(k) + "_written", ...
        exists, actual, "file_exists", "")]; %#ok<AGROW>
end
end

function tf = localNodeColumnsPresent(nodes)
tf = isempty(localMissingNodeColumnList(nodes));
end

function text = localMissingNodeColumns(nodes)
text = localMissingString(localMissingNodeColumnList(nodes));
end

function missing = localMissingNodeColumnList(nodes)
required = ["node_id","node_label","node_group","severity","status_label", ...
    "value_text","rationale","source_fields","t","x","y"];
missing = setdiff(required, string(nodes.Properties.VariableNames), 'stable');
end

function tf = localEdgeColumnsPresent(edges)
tf = isempty(localMissingEdgeColumnList(edges));
end

function text = localMissingEdgeColumns(edges)
text = localMissingString(localMissingEdgeColumnList(edges));
end

function missing = localMissingEdgeColumnList(edges)
required = ["edge_id","from_node","to_node","edge_label","value_text", ...
    "severity","rationale","source_fields"];
missing = setdiff(required, string(edges.Properties.VariableNames), 'stable');
end

function tf = localSnapshotColumnsPresent(snapshot)
tf = isempty(localMissingSnapshotColumnList(snapshot));
end

function text = localMissingSnapshotColumns(snapshot)
text = localMissingString(localMissingSnapshotColumnList(snapshot));
end

function missing = localMissingSnapshotColumnList(snapshot)
required = ["t","requested_t","selector","max_severity","most_important_node", ...
    "most_important_label","node_count","edge_count","event_count"];
missing = setdiff(required, string(snapshot.Properties.VariableNames), 'stable');
end

function text = localMissingString(missing)
missing = string(missing);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(missing, ",");
end
end

function text = localNodeSummary(nodes)
parts = strings(0, 1);
for k = 1:min(height(nodes), 10)
    parts(end+1) = nodes.node_id(k) + "=" + nodes.status_label(k); %#ok<AGROW>
end
if height(nodes) > 10
    parts(end+1) = "+" + string(height(nodes) - 10) + "_more"; %#ok<AGROW>
end
text = strjoin(parts, "; ");
end

function text = localReportSummary(importReport, cleanReport)
parts = strings(0, 1);
if isstruct(importReport) && isfield(importReport, 'schemaMode')
    parts(end+1) = "schema=" + string(importReport.schemaMode);
end
if isstruct(importReport) && isfield(importReport, 'validRowsImported')
    parts(end+1) = "imported=" + string(importReport.validRowsImported);
end
if isstruct(cleanReport) && isfield(cleanReport, 'rowsAfterCleaning')
    parts(end+1) = "clean=" + string(cleanReport.rowsAfterCleaning);
end
text = strjoin(parts, ";");
end

function row = localValidationRow(caseName, selector, scope, check, passed, actual, expected, notes)
row = table(string(caseName), string(selector), string(scope), string(check), logical(passed), ...
    string(actual), string(expected), string(notes), ...
    'VariableNames', {'caseName','selector','scope','check','passed','actual','expected','notes'});
end

function T = localEmptyValidationTable()
T = table('Size', [0 8], ...
    'VariableTypes', {'string','string','string','string','logical','string','string','string'}, ...
    'VariableNames', {'caseName','selector','scope','check','passed','actual','expected','notes'});
end

function localCloseFigure(fig)
if ~isempty(fig) && isgraphics(fig)
    close(fig);
end
end

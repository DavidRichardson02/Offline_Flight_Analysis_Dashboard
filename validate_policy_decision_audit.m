function validation = validate_policy_decision_audit(options)
%VALIDATE_POLICY_DECISION_AUDIT Validate the airbrake decision audit view.
%
% This validation consumes the latest checked-in SD and Serial fixtures,
% normalizes them through the dashboard import path, builds the policy audit
% table, renders the standalone audit figure, and exports review artifacts.
arguments
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
    options.ExportRoot (1,1) string = fullfile("exports", "policy_decision_audit_validation")
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

cfg = caelum.defaultConfig();
caseDefs = [ ...
    struct('name', "latest_sd_fixture", 'sourceKind', "sd", 'path', options.SdFixturePath); ...
    struct('name', "latest_serial_fixture", 'sourceKind', "serial", 'path', options.SerialFixturePath)];

reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'audit', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), cfg, options.ExportRoot);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "policy_decision_audit_validation_report.csv");
writetable(reportTable, reportPath);

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.exportRoot = options.ExportRoot;
validation.reportPath = reportPath;
validation.caseResults = caseResults;
validation.reportTable = reportTable;
validation.overallPassed = all(reportTable.passed);

disp(reportTable(:, ["caseName","scope","check","passed","actual","expected","notes"]));
if validation.overallPassed
    fprintf('Policy decision audit validation passed.\n');
else
    fprintf(2, 'Policy decision audit validation reported failures.\n');
end
end

function [caseResult, rows] = localRunCase(caseDef, cfg, exportRoot)
rows = localEmptyValidationTable();

if ~isfile(caseDef.path)
    error('validate_policy_decision_audit:MissingFixture', ...
        'Fixture not found: %s.', caseDef.path);
end

[clean, importReport, cleanReport] = localImportFixture(caseDef, cfg);
audit = caelum.buildPolicyDecisionAudit(clean, cfg);
fig = caelum.plotPolicyDecisionAudit(audit, cfg);

results = struct();
results.filename = caseDef.path;
results.policyAudit = audit;
results.policyAuditFigure = fig;

exportDir = fullfile(exportRoot, caseDef.name);
exportInfo = caelum.exportFigures(results, exportDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported", ...
    height(clean) > 0, string(height(clean)), ">0", ...
    "schema=" + string(importReport.schemaMode) + ";cleanRows=" + string(cleanReport.rowsAfterCleaning))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_required_columns_present", ...
    localRequiredAuditColumnsPresent(audit), localMissingAuditColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_row_count_matches_clean_log", ...
    height(audit) == height(clean), string(height(audit)), string(height(clean)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "math", "reachability_span_nonnegative", ...
    localFiniteSpansNonnegative(audit), string(min(audit.reachability_span_m, [], 'omitnan')), ">=0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "math", "corridor_demand_index_bounded", ...
    localDemandIndexBounded(audit), localDemandRangeText(audit), "[0,1]", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "decision_labels_nonempty", ...
    all(audit.decision_label ~= ""), string(nnz(audit.decision_label ~= "")), string(height(audit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "policy_evidence_not_all_incomplete", ...
    ~all(audit.decision_label == "telemetry_incomplete"), ...
    localLabelSummary(audit), "not_all_telemetry_incomplete", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "plot", "policy_audit_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>

rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = caseDef.path;
caseResult.audit = audit;
caseResult.exportInfo = exportInfo;
caseResult.passed = all(rows.passed);
end

function [clean, importReport, cleanReport] = localImportFixture(caseDef, cfg)
switch caseDef.sourceKind
    case "sd"
        [raw, importReport] = caelum.importLog(caseDef.path);
    case "serial"
        [raw, importReport] = caelum.importSerialTelemetry(caseDef.path);
    otherwise
        error('validate_policy_decision_audit:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end

aligned = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);
end

function tf = localRequiredAuditColumnsPresent(audit)
tf = isempty(localMissingAuditColumnList(audit));
end

function text = localMissingAuditColumns(audit)
missing = localMissingAuditColumnList(audit);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingAuditColumnList(audit)
required = [ ...
    "t", ...
    "phase", ...
    "phase_name", ...
    "policy_valid", ...
    "policy_cmd", ...
    "actuator_us", ...
    "apogee_no_brake_m", ...
    "apogee_full_brake_m", ...
    "target_selected_m", ...
    "reachability_low_m", ...
    "reachability_high_m", ...
    "reachability_span_m", ...
    "target_inside_corridor", ...
    "corridor_brake_demand_index", ...
    "policy_command_residual", ...
    "warning_active", ...
    "command_active", ...
    "decision_code", ...
    "decision_label", ...
    "decision_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
end

function tf = localFiniteSpansNonnegative(audit)
spans = audit.reachability_span_m(isfinite(audit.reachability_span_m));
tf = ~isempty(spans) && all(spans >= 0);
end

function tf = localDemandIndexBounded(audit)
values = audit.corridor_brake_demand_index(isfinite(audit.corridor_brake_demand_index));
tf = ~isempty(values) && all(values >= 0) && all(values <= 1);
end

function text = localDemandRangeText(audit)
values = audit.corridor_brake_demand_index(isfinite(audit.corridor_brake_demand_index));
if isempty(values)
    text = "no_finite_values";
else
    text = sprintf('[%.6g, %.6g]', min(values), max(values));
end
end

function text = localLabelSummary(audit)
labels = unique(audit.decision_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.decision_label == labels(k)));
end
text = strjoin(parts, ";");
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["policy_audit_csv","policy_audit_png","policy_audit_pdf","manifest_csv"];
manifestKeys = strings(0, 1);
manifestExists = false(0, 1);
if isfield(exportInfo, 'manifest') && istable(exportInfo.manifest) && ~isempty(exportInfo.manifest)
    manifestKeys = string(exportInfo.manifest.artifact);
    manifestExists = exportInfo.manifest.exists;
end

for k = 1:numel(requiredArtifacts)
    artifactKey = requiredArtifacts(k);
    idx = find(manifestKeys == artifactKey, 1, 'first');
    present = ~isempty(idx) && manifestExists(idx);
    rows = [rows; localValidationRow(caseName, "export", "artifact_" + artifactKey, ...
        present, string(present), "true", "")]; %#ok<AGROW>
end

hasErrors = isempty(fieldnames(exportInfo.errors));
rows = [rows; localValidationRow(caseName, "export", "export_errors_absent", ...
    hasErrors, string(~hasErrors), "false", "")]; %#ok<AGROW>
end

function rows = localEmptyValidationTable()
rows = table('Size', [0 7], ...
    'VariableTypes', {'string','string','string','logical','string','string','string'}, ...
    'VariableNames', {'caseName','scope','check','passed','actual','expected','notes'});
end

function row = localValidationRow(caseName, scope, check, passed, actual, expected, notes)
row = table(string(caseName), string(scope), string(check), logical(passed), ...
    string(actual), string(expected), string(notes), ...
    'VariableNames', {'caseName','scope','check','passed','actual','expected','notes'});
end

function localCloseFigure(fig)
if ~isempty(fig) && isgraphics(fig)
    close(fig);
end
end

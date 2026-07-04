function validation = validate_phase_state_machine_timeline(options)
%VALIDATE_PHASE_STATE_MACHINE_TIMELINE Validate phase evidence artifacts.
%
% The validation covers latest SD import, Serial HDR/TLM import, and a bounded
% live-buffer snapshot so both logged telemetry and live parser provenance paths
% exercise the same phase audit and plotting code.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "phase_state_machine_validation")
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
    options.BufferCapacity (1,1) double {mustBeInteger,mustBePositive} = 120
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

cfg = caelum.defaultConfig();
caseDefs = [ ...
    struct('name', "latest_sd_fixture", 'sourceKind', "sd", 'path', options.SdFixturePath); ...
    struct('name', "latest_serial_fixture", 'sourceKind', "serial", 'path', options.SerialFixturePath); ...
    struct('name', "latest_serial_live_buffer", 'sourceKind', "live_buffer", 'path', options.SerialFixturePath)];

reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'phaseStateAudit', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), cfg, options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "phase_state_machine_validation_report.csv");
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
    fprintf('Phase state-machine timeline validation passed.\n');
else
    fprintf(2, 'Phase state-machine timeline validation reported failures.\n');
end
end

function [caseResult, rows] = localRunCase(caseDef, cfg, options)
rows = localEmptyValidationTable();

if ~isfile(caseDef.path)
    error('validate_phase_state_machine_timeline:MissingFixture', ...
        'Fixture not found: %s.', caseDef.path);
end

[clean, report] = localImportCase(caseDef, cfg, options);
audit = caelum.buildPhaseStateMachineAudit(clean);
fig = caelum.plotPhaseStateMachineTimeline(audit);

results = struct();
results.filename = localResultFilename(caseDef);
results.phaseStateAudit = audit;
results.phaseStateFigure = fig;

exportDir = fullfile(options.ExportRoot, caseDef.name);
exportInfo = caelum.exportFigures(results, exportDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported", ...
    height(clean) > 0, string(height(clean)), ">0", localReportSummary(report))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "input_phase_field_present", ...
    ismember("phase", string(clean.Properties.VariableNames)), ...
    string(ismember("phase", string(clean.Properties.VariableNames))), "true", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_required_columns_present", ...
    localRequiredColumnsPresent(audit), localMissingColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_row_count_matches_samples", ...
    height(audit) == height(clean), string(height(audit)), string(height(clean)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "phase_labels_nonempty", ...
    all(audit.phase_name ~= ""), string(nnz(audit.phase_name ~= "")), string(height(audit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "phase_evidence_not_all_incomplete", ...
    ~all(audit.evidence_label == "telemetry_incomplete"), ...
    localLabelSummary(audit), "not_all_incomplete", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "expected_phase_evidence_available", ...
    any(isfinite(audit.expected_phase_from_evidence)), ...
    string(nnz(isfinite(audit.expected_phase_from_evidence))), ">0", "")]; %#ok<AGROW>

if caseDef.sourceKind ~= "live_buffer"
    rows = [rows; localValidationRow(caseDef.name, "transition", "phase_transitions_observed", ...
        nnz(audit.phase_changed) > 0, string(nnz(audit.phase_changed)), ">0", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "transition", "live_buffer_transition_check_relaxed", ...
        any(isfinite(audit.phase)), string(nnz(isfinite(audit.phase))), ">0 finite phases", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, "diagnostic", "phase_diag_fields_present", ...
    all(ismember(["phase_diag_valid","phase_diag_age_ms"], string(clean.Properties.VariableNames))), ...
    localDiagFieldText(clean), "phase_diag_valid,phase_diag_age_ms", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "plot", "phase_state_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = caseDef.path;
caseResult.phaseStateAudit = audit;
caseResult.exportInfo = exportInfo;
caseResult.passed = all(rows.passed);
end

function [clean, report] = localImportCase(caseDef, cfg, options)
switch caseDef.sourceKind
    case "sd"
        [raw, report] = caelum.importLog(caseDef.path);
        aligned = caelum.alignImportedSchema(raw, cfg);
        [clean, cleanReport] = caelum.cleanLog(aligned, cfg);
        report.cleanReport = cleanReport;
        report.rowsAfterCleaning = height(clean);
    case "serial"
        [raw, report] = caelum.importSerialTelemetry(caseDef.path);
        aligned = caelum.alignImportedSchema(raw, cfg);
        [clean, cleanReport] = caelum.cleanLog(aligned, cfg);
        report.cleanReport = cleanReport;
        report.rowsAfterCleaning = height(clean);
    case "live_buffer"
        rawLines = strip(readlines(caseDef.path));
        rawLines = rawLines(rawLines ~= "");
        buffer = caelum.createLiveTelemetryBuffer(Capacity=options.BufferCapacity, Config=cfg);
        buffer = caelum.appendLiveTelemetryBuffer(buffer, rawLines);
        [clean, report] = caelum.snapshotLiveTelemetryBuffer(buffer, Config=cfg);
    otherwise
        error('validate_phase_state_machine_timeline:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end
end

function filename = localResultFilename(caseDef)
[~, name, ~] = fileparts(caseDef.path);
filename = string(name) + "_" + caseDef.sourceKind + ".csv";
end

function text = localReportSummary(report)
parts = strings(0, 1);
if isfield(report, 'schemaMode')
    parts(end+1) = "schema=" + string(report.schemaMode);
end
if isfield(report, 'acceptedRows')
    parts(end+1) = "accepted=" + string(report.acceptedRows);
elseif isfield(report, 'validRowsImported')
    parts(end+1) = "accepted=" + string(report.validRowsImported);
end
if isfield(report, 'rowsAfterCleaning')
    parts(end+1) = "cleanRows=" + string(report.rowsAfterCleaning);
end
if isempty(parts)
    text = "";
else
    text = strjoin(parts, ";");
end
end

function tf = localRequiredColumnsPresent(audit)
tf = isempty(localMissingColumnList(audit));
end

function text = localMissingColumns(audit)
missing = localMissingColumnList(audit);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingColumnList(audit)
required = [ ...
    "t", ...
    "phase", ...
    "phase_name", ...
    "phase_changed", ...
    "transition_label", ...
    "phase_diag_valid", ...
    "phase_diag_updated", ...
    "phase_diag_age_ms", ...
    "phase_launch_latched", ...
    "phase_burnout_latched", ...
    "phase_descent_latched", ...
    "phase_launch_candidate", ...
    "phase_burnout_candidate", ...
    "phase_descent_candidate", ...
    "phase_boost_dwell_met", ...
    "phase_coast_dwell_met", ...
    "phase_brake_active", ...
    "expected_phase_from_evidence", ...
    "phase_evidence_mismatch", ...
    "evidence_code", ...
    "evidence_label", ...
    "evidence_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
end

function text = localLabelSummary(audit)
labels = unique(audit.evidence_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.evidence_label == labels(k)));
end
text = strjoin(parts, ";");
end

function text = localDiagFieldText(clean)
vars = string(clean.Properties.VariableNames);
present = ["phase_diag_valid","phase_diag_age_ms"];
text = strjoin(cellstr(present(ismember(present, vars))), ",");
if strlength(text) == 0
    text = "none";
end
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["phase_state_timeline_csv","phase_state_timeline_png","phase_state_timeline_pdf","manifest_csv"];
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

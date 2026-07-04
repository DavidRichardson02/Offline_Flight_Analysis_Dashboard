function validation = validate_replay_contract_diff_viewer(options)
%VALIDATE_REPLAY_CONTRACT_DIFF_VIEWER Validate replay contract diff artifacts.
%
% Cases cover deterministic generated logs, attitude-input replay mode, latest
% SD firmware fixtures, and latest Serial telemetry fixtures. The validation is
% artifact-oriented: it proves the diff tables and figure can be built for
% each source while preserving missing-field and divergence evidence.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "replay_contract_diff_validation")
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
    options.FieldContractPath (1,1) string = "vertical_replay_field_contract.csv"
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

fieldContract = caelum.getVerticalReplayFieldContract(options.FieldContractPath);
caseDefs = localCaseDefinitions(options);

reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'sampleAudit', table(), ...
    'fieldSummary', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), fieldContract, options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "replay_contract_diff_validation_report.csv");
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
    fprintf('Firmware-vs-MATLAB replay contract diff validation passed.\n');
else
    fprintf(2, 'Firmware-vs-MATLAB replay contract diff validation reported failures.\n');
end
end

function caseDefs = localCaseDefinitions(options)
caseDefs = [ ...
    struct( ...
        'name', "generated_legacy_contract", ...
        'sourceKind', "generated", ...
        'sourcePath', "", ...
        'generatorArgs', struct('seed', 42), ...
        'useAttitudeVerticalInput', false, ...
        'overwriteLoggedFirmware', true, ...
        'expectInputExact', true); ...
    struct( ...
        'name', "generated_attitude_contract", ...
        'sourceKind', "generated", ...
        'sourcePath', "", ...
        'generatorArgs', struct('seed', 43), ...
        'useAttitudeVerticalInput', true, ...
        'overwriteLoggedFirmware', true, ...
        'expectInputExact', false); ...
    struct( ...
        'name', "latest_sd_fixture", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'generatorArgs', struct(), ...
        'useAttitudeVerticalInput', false, ...
        'overwriteLoggedFirmware', false, ...
        'expectInputExact', false); ...
    struct( ...
        'name', "latest_serial_fixture", ...
        'sourceKind', "serial", ...
        'sourcePath', options.SerialFixturePath, ...
        'generatorArgs', struct(), ...
        'useAttitudeVerticalInput', false, ...
        'overwriteLoggedFirmware', false, ...
        'expectInputExact', false)];
end

function [caseResult, rows] = localRunCase(caseDef, fieldContract, options)
rows = localEmptyValidationTable();
caseDir = fullfile(options.ExportRoot, caseDef.name);
if ~exist(caseDir, 'dir')
    mkdir(caseDir);
end

cfg = caelum.defaultConfig();
cfg.useAttitudeVerticalInput = caseDef.useAttitudeVerticalInput;

[inputPath, clean, importReport, cleanReport] = localPrepareCleanCase(caseDef, caseDir, cfg);
if cfg.useAttitudeVerticalInput
    attitude = caelum.runAttitudeReplay(clean, cfg);
    [clean, attitude] = caelum.attachPhase1AttitudeFields(clean, attitude);
else
    attitude = table();
end
replay = caelum.replayEstimator(clean, cfg);
[sampleAudit, fieldSummary] = caelum.buildReplayContractDiffAudit(clean, replay, cfg, ...
    FieldContract=fieldContract);
fig = caelum.plotReplayContractDiffViewer(sampleAudit, fieldSummary);

results = struct();
results.filename = localResultFilename(inputPath, caseDef);
results.data = clean;
results.replay = replay;
results.attitude = attitude;
results.replayContractDiff = sampleAudit;
results.replayContractFieldSummary = fieldSummary;
results.replayContractDiffFigure = fig;

exportInfo = caelum.exportFigures(results, caseDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported_cleaned_and_replayed", ...
    height(clean) > 0 && height(replay) > 0, ...
    "clean=" + string(height(clean)) + ";replay=" + string(height(replay)), ...
    "clean>0;replay>0", localReportSummary(importReport, cleanReport))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "sample_audit_required_columns_present", ...
    localSampleAuditColumnsPresent(sampleAudit), localMissingSampleAuditColumns(sampleAudit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "field_summary_required_columns_present", ...
    localFieldSummaryColumnsPresent(fieldSummary), localMissingFieldSummaryColumns(fieldSummary), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "sample_audit_row_count_matches_clean_log", ...
    height(sampleAudit) == height(clean), string(height(sampleAudit)), string(height(clean)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "contract", "field_summary_has_comparable_fields", ...
    nnz(fieldSummary.samples_compared > 0) >= 3, ...
    string(nnz(fieldSummary.samples_compared > 0)), ">=3", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "contract", "finite_field_diffs_present", ...
    nnz(isfinite(fieldSummary.max_abs_diff)) > 0, ...
    string(nnz(isfinite(fieldSummary.max_abs_diff))), ">0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "contract_labels_nonempty", ...
    all(sampleAudit.contract_label ~= ""), ...
    string(nnz(sampleAudit.contract_label ~= "")), string(height(sampleAudit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "not_all_replay_incomplete", ...
    ~all(sampleAudit.contract_label == "replay_incomplete"), ...
    localLabelSummary(sampleAudit), "not_all_replay_incomplete", "")]; %#ok<AGROW>

if caseDef.expectInputExact
    inputRow = fieldSummary(fieldSummary.contract_field == "a_vertical_used", :);
    inputPass = ~isempty(inputRow) && inputRow.pass(1) && inputRow.match_rate(1) == 1;
    rows = [rows; localValidationRow(caseDef.name, "contract", "legacy_input_contract_exact", ...
        inputPass, localInputContractText(inputRow), "pass=true;match_rate=1", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "contract", "legacy_input_contract_exact_skipped", ...
        true, "not_required_for_case", "not_required_for_case", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, "plot", "replay_contract_diff_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = inputPath;
caseResult.sampleAudit = sampleAudit;
caseResult.fieldSummary = fieldSummary;
caseResult.exportInfo = exportInfo;
caseResult.passed = all(rows.passed);
end

function [inputPath, clean, importReport, cleanReport] = localPrepareCleanCase(caseDef, caseDir, cfg)
switch caseDef.sourceKind
    case "generated"
        inputPath = fullfile(caseDir, caseDef.name + ".csv");
        args = localStructToNameValue(caseDef.generatorArgs);
        [T, ~] = caelum.generateTruthAwareCaelumLogV2(inputPath, args{:});
        if caseDef.overwriteLoggedFirmware
            T = localOverwriteWithFirmwareLoggedFields(T, cfg);
            writetable(T, inputPath);
        end
        [raw, importReport] = caelum.importLog(inputPath);
    case "sd"
        inputPath = caseDef.sourcePath;
        if ~isfile(inputPath)
            error('validate_replay_contract_diff_viewer:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
        [raw, importReport] = caelum.importLog(inputPath);
    case "serial"
        inputPath = caseDef.sourcePath;
        if ~isfile(inputPath)
            error('validate_replay_contract_diff_viewer:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
        [raw, importReport] = caelum.importSerialTelemetry(inputPath);
    otherwise
        error('validate_replay_contract_diff_viewer:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end

aligned = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);
end

function args = localStructToNameValue(s)
names = fieldnames(s);
args = cell(1, 2 * numel(names));
for k = 1:numel(names)
    args{2 * k - 1} = names{k};
    args{2 * k} = s.(names{k});
end
end

function T = localOverwriteWithFirmwareLoggedFields(T, cfg)
aligned = caelum.alignImportedSchema(T, cfg);
firmware = caelum.runFirmwareVerticalEstimator(aligned, cfg);

T.g_bx = firmware.g_bx;
T.g_by = firmware.g_by;
T.g_bz = firmware.g_bz;
T.a_vertical = firmware.a_vertical;
T.kf_h = firmware.h;
T.kf_v = firmware.v;
T.P00 = firmware.P00;
T.P01 = firmware.P01;
T.P10 = firmware.P10;
T.P11 = firmware.P11;
end

function filename = localResultFilename(inputPath, caseDef)
[~, name, ~] = fileparts(inputPath);
filename = string(name) + "_" + caseDef.name + ".csv";
end

function text = localReportSummary(importReport, cleanReport)
parts = strings(0, 1);
if isfield(importReport, 'schemaMode')
    parts(end+1) = "schema=" + string(importReport.schemaMode);
end
if isfield(importReport, 'validRowsImported')
    parts(end+1) = "accepted=" + string(importReport.validRowsImported);
end
if isfield(cleanReport, 'rowsAfterCleaning')
    parts(end+1) = "cleanRows=" + string(cleanReport.rowsAfterCleaning);
end
if isempty(parts)
    text = "";
else
    text = strjoin(parts, ";");
end
end

function tf = localSampleAuditColumnsPresent(sampleAudit)
tf = isempty(localMissingSampleAuditColumnList(sampleAudit));
end

function text = localMissingSampleAuditColumns(sampleAudit)
missing = localMissingSampleAuditColumnList(sampleAudit);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingSampleAuditColumnList(sampleAudit)
required = [ ...
    "t", ...
    "logged_h_m", ...
    "replay_h_m", ...
    "delta_h_m", ...
    "logged_v_mps", ...
    "replay_v_mps", ...
    "delta_v_mps", ...
    "delta_a_vertical_mps2", ...
    "contract_code", ...
    "contract_label", ...
    "contract_rationale"];
missing = setdiff(required, string(sampleAudit.Properties.VariableNames), 'stable');
end

function tf = localFieldSummaryColumnsPresent(fieldSummary)
tf = isempty(localMissingFieldSummaryColumnList(fieldSummary));
end

function text = localMissingFieldSummaryColumns(fieldSummary)
missing = localMissingFieldSummaryColumnList(fieldSummary);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingFieldSummaryColumnList(fieldSummary)
required = [ ...
    "contract_field", ...
    "logged_field", ...
    "replay_field", ...
    "samples_compared", ...
    "match_rate", ...
    "max_abs_diff", ...
    "mean_abs_diff", ...
    "rmse_diff", ...
    "pass", ...
    "notes"];
missing = setdiff(required, string(fieldSummary.Properties.VariableNames), 'stable');
end

function text = localLabelSummary(sampleAudit)
labels = unique(sampleAudit.contract_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = string(labels(k)) + "=" + string(nnz(sampleAudit.contract_label == labels(k)));
end
text = strjoin(parts, ";");
end

function text = localInputContractText(inputRow)
if isempty(inputRow)
    text = "missing_a_vertical_used_row";
else
    text = "pass=" + string(inputRow.pass(1)) + ";match_rate=" + string(inputRow.match_rate(1));
end
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = [ ...
    "replay_contract_diff_png", ...
    "replay_contract_diff_pdf", ...
    "replay_contract_diff_csv", ...
    "replay_contract_field_summary_csv", ...
    "clean_csv", ...
    "replay_csv", ...
    "manifest_csv"];
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

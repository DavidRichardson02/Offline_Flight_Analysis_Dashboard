function validation = validate_attitude_gravity_provenance_view(options)
%VALIDATE_ATTITUDE_GRAVITY_PROVENANCE_VIEW Validate attitude/gravity artifacts.
%
% Cases cover generated truth-aware logs plus latest SD and Serial fixtures.
% The view is intentionally standalone so source semantics can stabilize before
% a compact version is added to the integrated dashboard.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "attitude_gravity_provenance_validation")
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
    options.MinimumFiniteFraction (1,1) double = 0.75
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

cfg = caelum.defaultConfig();
caseDefs = localCaseDefinitions(options);

reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'attitudeGravityAudit', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), cfg, options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "attitude_gravity_provenance_validation_report.csv");
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
    fprintf('Attitude / gravity provenance validation passed.\n');
else
    fprintf(2, 'Attitude / gravity provenance validation reported failures.\n');
end
end

function caseDefs = localCaseDefinitions(options)
caseDefs = [ ...
    struct( ...
        'name', "deterministic_truth_aware_v2", ...
        'sourceKind', "generated", ...
        'sourcePath', "", ...
        'generatorArgs', struct('seed', 42), ...
        'truthEnabled', true, ...
        'minimumFiniteFraction', 0.95); ...
    struct( ...
        'name', "degraded_truth_aware_v2", ...
        'sourceKind', "generated", ...
        'sourcePath', "", ...
        'generatorArgs', struct( ...
            'seed', 314, ...
            'addNaNs', true, ...
            'nanFraction', 0.01, ...
            'addDropouts', true, ...
            'dropoutFraction', 0.02, ...
            'addDuplicateTimestamps', true, ...
            'duplicateFraction', 0.01), ...
        'truthEnabled', true, ...
        'minimumFiniteFraction', options.MinimumFiniteFraction); ...
    struct( ...
        'name', "latest_sd_fixture", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'generatorArgs', struct(), ...
        'truthEnabled', false, ...
        'minimumFiniteFraction', 0.95); ...
    struct( ...
        'name', "latest_serial_fixture", ...
        'sourceKind', "serial", ...
        'sourcePath', options.SerialFixturePath, ...
        'generatorArgs', struct(), ...
        'truthEnabled', false, ...
        'minimumFiniteFraction', 0.95)];
end

function [caseResult, rows] = localRunCase(caseDef, cfg, options)
rows = localEmptyValidationTable();
caseDir = fullfile(options.ExportRoot, caseDef.name);
if ~exist(caseDir, 'dir')
    mkdir(caseDir);
end

[inputPath, truth] = localPrepareInput(caseDef, caseDir);
[clean, attitude, importReport, cleanReport] = localImportCleanAttitude(caseDef, inputPath, cfg);
audit = caelum.buildAttitudeGravityProvenanceAudit(clean, attitude, cfg, Truth=truth);
fig = caelum.plotAttitudeGravityProvenanceView(audit, cfg);

results = struct();
results.filename = inputPath;
results.attitudeGravityAudit = audit;
results.attitudeGravityFigure = fig;
results.attitude = attitude;

exportInfo = caelum.exportFigures(results, caseDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported_and_attitude_replayed", ...
    height(clean) > 0 && height(attitude) > 0, ...
    "clean=" + string(height(clean)) + ";attitude=" + string(height(attitude)), ...
    "clean>0;attitude>0", ...
    localReportSummary(importReport, cleanReport))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_required_columns_present", ...
    localRequiredColumnsPresent(audit), localMissingColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_row_count_matches_clean_log", ...
    height(audit) == height(clean), string(height(audit)), string(height(clean)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "finite", "vertical_sources_mostly_finite", ...
    localVerticalSourceFiniteFraction(audit) >= caseDef.minimumFiniteFraction, ...
    sprintf('%.6f', localVerticalSourceFiniteFraction(audit)), ...
    ">=" + string(caseDef.minimumFiniteFraction), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "gravity", "gravity_norm_evidence_present", ...
    nnz(isfinite(audit.logged_g_norm_mps2)) > 0 && nnz(isfinite(audit.attitude_g_norm_mps2)) > 0, ...
    sprintf('logged=%d;attitude=%d', nnz(isfinite(audit.logged_g_norm_mps2)), ...
        nnz(isfinite(audit.attitude_g_norm_mps2))), ...
    "logged>0;attitude>0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "update", "gravity_update_evidence_present", ...
    nnz(isfinite(audit.gravity_residual_mps2)) > 0 && nnz(isfinite(audit.tilt_error_deg)) > 0, ...
    sprintf('residual=%d;tilt=%d;updates=%d', nnz(isfinite(audit.gravity_residual_mps2)), ...
        nnz(isfinite(audit.tilt_error_deg)), nnz(audit.gravity_update_used)), ...
    "residual>0;tilt>0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "evidence_labels_nonempty", ...
    all(audit.evidence_label ~= ""), string(nnz(audit.evidence_label ~= "")), string(height(audit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "evidence_not_all_incomplete", ...
    ~all(audit.evidence_label == "telemetry_incomplete"), ...
    localLabelSummary(audit), "not_all_telemetry_incomplete", "")]; %#ok<AGROW>

if caseDef.truthEnabled
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_vertical_accel_error_present", ...
        nnz(isfinite(audit.attitude_truth_error_a_vertical_mps2)) > 0 && ...
            nnz(isfinite(audit.logged_truth_error_a_vertical_mps2)) > 0, ...
        localTruthMetricText(audit), "finite_truth_error_samples", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_check_skipped", ...
        true, "not_truth_enabled", "not_truth_enabled", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, "plot", "attitude_gravity_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = inputPath;
caseResult.attitudeGravityAudit = audit;
caseResult.exportInfo = exportInfo;
caseResult.passed = all(rows.passed);
end

function [inputPath, truth] = localPrepareInput(caseDef, caseDir)
truth = struct();
switch caseDef.sourceKind
    case "generated"
        inputPath = fullfile(caseDir, caseDef.name + ".csv");
        args = localStructToNameValue(caseDef.generatorArgs);
        [~, truth] = caelum.generateTruthAwareCaelumLogV2(inputPath, args{:});
    case {"sd","serial"}
        inputPath = caseDef.sourcePath;
        if ~isfile(inputPath)
            error('validate_attitude_gravity_provenance_view:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
    otherwise
        error('validate_attitude_gravity_provenance_view:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end
end

function args = localStructToNameValue(s)
names = fieldnames(s);
args = cell(1, 2 * numel(names));
for k = 1:numel(names)
    args{2 * k - 1} = names{k};
    args{2 * k} = s.(names{k});
end
end

function [clean, attitude, importReport, cleanReport] = localImportCleanAttitude(caseDef, inputPath, cfg)
switch caseDef.sourceKind
    case {"generated","sd"}
        [raw, importReport] = caelum.importLog(inputPath);
    case "serial"
        [raw, importReport] = caelum.importSerialTelemetry(inputPath);
    otherwise
        error('validate_attitude_gravity_provenance_view:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end

aligned = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);
attitude = caelum.runAttitudeReplay(clean, cfg);
[clean, attitude] = caelum.attachPhase1AttitudeFields(clean, attitude);
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
    "ax_mps2", ...
    "ay_mps2", ...
    "az_mps2", ...
    "accel_norm_mps2", ...
    "gyro_norm_rps", ...
    "logged_g_norm_mps2", ...
    "attitude_g_norm_mps2", ...
    "logged_a_vertical_mps2", ...
    "smoothed_a_vertical_mps2", ...
    "gravity_projected_a_vertical_mps2", ...
    "attitude_a_vertical_mps2", ...
    "logged_minus_attitude_a_vertical_mps2", ...
    "projected_minus_logged_a_vertical_mps2", ...
    "gravity_update_used", ...
    "gravity_innovation", ...
    "gravity_residual_mps2", ...
    "tilt_error_deg", ...
    "truth_a_vertical_mps2", ...
    "attitude_truth_error_a_vertical_mps2", ...
    "evidence_code", ...
    "evidence_label", ...
    "evidence_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
end

function fraction = localVerticalSourceFiniteFraction(audit)
fields = ["logged_a_vertical_mps2","gravity_projected_a_vertical_mps2","attitude_a_vertical_mps2"];
fractions = nan(numel(fields), 1);
for k = 1:numel(fields)
    values = audit.(char(fields(k)));
    fractions(k) = mean(isfinite(values));
end
fraction = min(fractions);
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

function text = localTruthMetricText(audit)
loggedSamples = nnz(isfinite(audit.logged_truth_error_a_vertical_mps2));
attitudeSamples = nnz(isfinite(audit.attitude_truth_error_a_vertical_mps2));
loggedRmse = sqrt(mean(audit.logged_truth_error_a_vertical_mps2.^2, 'omitnan'));
attitudeRmse = sqrt(mean(audit.attitude_truth_error_a_vertical_mps2.^2, 'omitnan'));
text = sprintf('loggedSamples=%d;attitudeSamples=%d;loggedRmse=%.6g;attitudeRmse=%.6g', ...
    loggedSamples, attitudeSamples, loggedRmse, attitudeRmse);
end

function text = localLabelSummary(audit)
labels = unique(audit.evidence_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.evidence_label == labels(k)));
end
text = strjoin(parts, ";");
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["attitude_gravity_provenance_csv", ...
    "attitude_gravity_provenance_png", ...
    "attitude_gravity_provenance_pdf", ...
    "attitude_csv", ...
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

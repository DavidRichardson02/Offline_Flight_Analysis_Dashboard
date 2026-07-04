function validation = validate_estimator_trust_dashboard(options)
%VALIDATE_ESTIMATOR_TRUST_DASHBOARD Validate estimator trust review artifacts.
%
% The validation covers generated truth-aware cases plus latest SD and Serial
% fixtures. It proves that replay trust evidence can be built, plotted, and
% exported without relying on the integrated dashboard.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "estimator_trust_validation")
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
    'estimatorTrust', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), cfg, options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "estimator_trust_validation_report.csv");
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
    fprintf('Estimator trust dashboard validation passed.\n');
else
    fprintf(2, 'Estimator trust dashboard validation reported failures.\n');
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
[clean, replay, importReport, cleanReport] = localImportCleanReplay(caseDef, inputPath, cfg);
audit = caelum.buildEstimatorTrustAudit(clean, replay, cfg, Truth=truth);
fig = caelum.plotEstimatorTrustDashboard(audit, cfg);

results = struct();
results.filename = inputPath;
results.estimatorTrust = audit;
results.estimatorTrustFigure = fig;

exportInfo = caelum.exportFigures(results, caseDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported_and_replayed", ...
    height(clean) > 0 && height(replay) > 0, ...
    "clean=" + string(height(clean)) + ";replay=" + string(height(replay)), ...
    "clean>0;replay>0", ...
    "schema=" + string(importReport.schemaMode) + ";cleanRows=" + string(cleanReport.rowsAfterCleaning))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_required_columns_present", ...
    localRequiredColumnsPresent(audit), localMissingColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_row_count_matches_clean_log", ...
    height(audit) == height(clean), string(height(audit)), string(height(clean)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "finite", "state_fields_mostly_finite", ...
    localStateFiniteFraction(audit) >= caseDef.minimumFiniteFraction, ...
    sprintf('%.6f', localStateFiniteFraction(audit)), ...
    ">=" + string(caseDef.minimumFiniteFraction), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "innovation", "innovation_samples_present", ...
    nnz(isfinite(audit.innovation_nis)) > 0, ...
    string(nnz(isfinite(audit.innovation_nis))), ">0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "innovation", "nis_nonnegative", ...
    localNisNonnegative(audit), localNisRangeText(audit), ">=0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "trust_labels_nonempty", ...
    all(audit.trust_label ~= ""), string(nnz(audit.trust_label ~= "")), string(height(audit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "trust_evidence_not_all_incomplete", ...
    ~all(audit.trust_label == "replay_incomplete"), ...
    localLabelSummary(audit), "not_all_replay_incomplete", "")]; %#ok<AGROW>

if caseDef.truthEnabled
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_error_present", ...
        nnz(isfinite(audit.replay_truth_error_h_m)) > 0 && nnz(isfinite(audit.replay_truth_error_v_mps)) > 0, ...
        localTruthMetricText(audit), "finite_truth_error_samples", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_check_skipped", ...
        true, "not_truth_enabled", "not_truth_enabled", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, "plot", "estimator_trust_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = inputPath;
caseResult.estimatorTrust = audit;
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
            error('validate_estimator_trust_dashboard:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
    otherwise
        error('validate_estimator_trust_dashboard:UnknownSourceKind', ...
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

function [clean, replay, importReport, cleanReport] = localImportCleanReplay(caseDef, inputPath, cfg)
switch caseDef.sourceKind
    case {"generated","sd"}
        [raw, importReport] = caelum.importLog(inputPath);
    case "serial"
        [raw, importReport] = caelum.importSerialTelemetry(inputPath);
    otherwise
        error('validate_estimator_trust_dashboard:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end

aligned = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);
replay = caelum.replayEstimator(clean, cfg);
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
    "baro_alt_m", ...
    "logged_h_m", ...
    "logged_v_mps", ...
    "logged_sigma_h_m", ...
    "logged_sigma_v_mps", ...
    "replay_h_m", ...
    "replay_v_mps", ...
    "replay_sigma_h_m", ...
    "replay_sigma_v_mps", ...
    "innovation_h_m", ...
    "innovation_sigma_h_m", ...
    "innovation_z_h", ...
    "innovation_nis", ...
    "baro_used", ...
    "baro_rejected", ...
    "logged_minus_replay_h_m", ...
    "logged_minus_replay_v_mps", ...
    "replay_b_a_mps2", ...
    "replay_beta", ...
    "trust_code", ...
    "trust_label", ...
    "trust_rationale"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
end

function fraction = localStateFiniteFraction(audit)
fields = ["replay_h_m","replay_v_mps","replay_sigma_h_m","replay_sigma_v_mps"];
fractions = nan(numel(fields), 1);
for k = 1:numel(fields)
    values = audit.(char(fields(k)));
    fractions(k) = mean(isfinite(values));
end
fraction = min(fractions);
end

function tf = localNisNonnegative(audit)
values = audit.innovation_nis(isfinite(audit.innovation_nis));
tf = ~isempty(values) && all(values >= 0);
end

function text = localNisRangeText(audit)
values = audit.innovation_nis(isfinite(audit.innovation_nis));
if isempty(values)
    text = "no_finite_values";
else
    text = sprintf('[%.6g, %.6g]', min(values), max(values));
end
end

function text = localTruthMetricText(audit)
hSamples = nnz(isfinite(audit.replay_truth_error_h_m));
vSamples = nnz(isfinite(audit.replay_truth_error_v_mps));
hRmse = sqrt(mean(audit.replay_truth_error_h_m.^2, 'omitnan'));
vRmse = sqrt(mean(audit.replay_truth_error_v_mps.^2, 'omitnan'));
text = sprintf('hSamples=%d;vSamples=%d;hRmse=%.6g;vRmse=%.6g', ...
    hSamples, vSamples, hRmse, vRmse);
end

function text = localLabelSummary(audit)
labels = unique(audit.trust_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.trust_label == labels(k)));
end
text = strjoin(parts, ";");
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["estimator_trust_csv","estimator_trust_png","estimator_trust_pdf","manifest_csv"];
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

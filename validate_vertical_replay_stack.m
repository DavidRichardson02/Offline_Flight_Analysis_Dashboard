function validation = validate_vertical_replay_stack(options)
%VALIDATE_VERTICAL_REPLAY_STACK Prove the replay stack is operational, inspectable, and exportable.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "vertical_replay_validation")
    options.BaselinePath (1,1) string = "vertical_replay_baseline.csv"
    options.FieldContractPath (1,1) string = "vertical_replay_field_contract.csv"
    options.NumericTolerance (1,1) double = 1e-3
    options.GenerateBaseline (1,1) logical = false
    options.MonteCarloSeeds (1,:) double = [100 101 102]
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

fieldContract = caelum.getVerticalReplayFieldContract(options.FieldContractPath);
firmwareSchema = caelum.getFirmwareSdlogSchema();
baselineTable = localReadBaseline(options.BaselinePath);
caseDefs = localBuildCaseDefinitions();
modeDefs = localBuildModeDefinitions();

caseResults = repmat(struct( ...
    'caseName', "", ...
    'modeName', "", ...
    'exportDir', "", ...
    'passed', false, ...
    'validationSummary', table(), ...
    'baselineMetrics', table(), ...
    'exportInfo', struct(), ...
    'parity', table(), ...
    'filename', ""), 0, 1);

reportTable = localEmptyValidationTable();
baselineMetricsAll = localEmptyMetricTable();

for caseIdx = 1:numel(caseDefs)
    caseDef = caseDefs(caseIdx);
    for modeIdx = 1:numel(modeDefs)
        modeDef = modeDefs(modeIdx);
        [caseResult, caseReportRows] = localRunValidationCase( ...
            caseDef, modeDef, fieldContract, firmwareSchema, baselineTable, options);
        caseResults(end+1, 1) = caseResult; %#ok<AGROW>
        reportTable = [reportTable; caseReportRows]; %#ok<AGROW>
        baselineMetricsAll = [baselineMetricsAll; caseResult.baselineMetrics]; %#ok<AGROW>
    end
end

[mcResult, mcReportRows, mcBaselineMetrics] = localRunMonteCarloSmoke(modeDefs, options);
reportTable = [reportTable; mcReportRows]; %#ok<AGROW>
baselineMetricsAll = [baselineMetricsAll; mcBaselineMetrics]; %#ok<AGROW>

if options.GenerateBaseline
    writetable(baselineMetricsAll, options.BaselinePath);
end

reportPath = fullfile(options.ExportRoot, "vertical_replay_validation_report.csv");
writetable(reportTable, reportPath);

overallMask = reportTable.severity ~= "info";
if any(overallMask)
    overallPassed = all(reportTable.passed(overallMask));
else
    overallPassed = true;
end

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.exportRoot = options.ExportRoot;
validation.reportPath = reportPath;
validation.caseResults = caseResults;
validation.monteCarlo = mcResult;
validation.reportTable = reportTable;
validation.overallPassed = overallPassed;

disp(reportTable(:, ["caseName","modeName","scope","check","passed","notes"]));
if overallPassed
    fprintf('Vertical replay validation passed.\n');
else
    fprintf(2, 'Vertical replay validation reported failures.\n');
end
end

function caseDefs = localBuildCaseDefinitions()
caseDefs = repmat(struct( ...
    'name', "", ...
    'sourceType', "", ...
    'sourcePath', "", ...
    'generatedFilename', "", ...
    'generatorArgs', struct(), ...
    'truthEnabled', false, ...
    'runParity', false, ...
    'runBaselineCompare', false, ...
    'makePlots', false, ...
    'makeDashboard', false, ...
    'compatibilityOnly', false, ...
    'finiteFractionThreshold', NaN, ...
    'firmwareConsistentLoggedFields', false, ...
    'requireDuplicateRemoval', false), 3, 1);

caseDefs(1).name = "deterministic_truth_aware_v2";
caseDefs(1).sourceType = "generated";
caseDefs(1).generatedFilename = "deterministic_truth_aware_v2.csv";
caseDefs(1).generatorArgs = struct('seed', 42);
caseDefs(1).truthEnabled = true;
caseDefs(1).runParity = true;
caseDefs(1).runBaselineCompare = true;
caseDefs(1).makePlots = true;
caseDefs(1).makeDashboard = true;
caseDefs(1).compatibilityOnly = false;
caseDefs(1).finiteFractionThreshold = 0.95;
caseDefs(1).firmwareConsistentLoggedFields = true;

caseDefs(2).name = "degraded_truth_aware_v2";
caseDefs(2).sourceType = "generated";
caseDefs(2).generatedFilename = "degraded_truth_aware_v2.csv";
caseDefs(2).generatorArgs = struct( ...
        'seed', 314, ...
        'addNaNs', true, ...
        'nanFraction', 0.01, ...
        'addDropouts', true, ...
        'dropoutFraction', 0.02, ...
        'addDuplicateTimestamps', true, ...
        'duplicateFraction', 0.01);
caseDefs(2).truthEnabled = true;
caseDefs(2).runParity = true;
caseDefs(2).runBaselineCompare = false;
caseDefs(2).makePlots = false;
caseDefs(2).makeDashboard = false;
caseDefs(2).compatibilityOnly = false;
caseDefs(2).finiteFractionThreshold = 0.75;
caseDefs(2).firmwareConsistentLoggedFields = true;
caseDefs(2).requireDuplicateRemoval = true;

caseDefs(3).name = "drop1_minimal";
caseDefs(3).sourceType = "existing";
caseDefs(3).sourcePath = "Drop1.csv";
caseDefs(3).truthEnabled = false;
caseDefs(3).runParity = false;
caseDefs(3).runBaselineCompare = false;
caseDefs(3).makePlots = true;
caseDefs(3).makeDashboard = true;
caseDefs(3).compatibilityOnly = true;
caseDefs(3).finiteFractionThreshold = NaN;
end

function modeDefs = localBuildModeDefinitions()
modeDefs = repmat(struct('name', "", 'useAttitudeVerticalInput', false), 2, 1);
modeDefs(1).name = "legacy";
modeDefs(1).useAttitudeVerticalInput = false;
modeDefs(2).name = "attitude";
modeDefs(2).useAttitudeVerticalInput = true;
end

function [caseResult, reportRows] = localRunValidationCase(caseDef, modeDef, fieldContract, firmwareSchema, baselineTable, options)
cfg = caelum.defaultConfig();
cfg.useAttitudeVerticalInput = modeDef.useAttitudeVerticalInput;

exportDir = fullfile(options.ExportRoot, caseDef.name, modeDef.name);
if ~exist(exportDir, 'dir')
    mkdir(exportDir);
end

inputInfo = localPrepareCaseInput(caseDef, exportDir);
coreRows = localEmptyValidationTable();

results = caelum.analyzeLog(inputInfo.filename, ...
    MakePlots=caseDef.makePlots, ...
    ReplayEstimator=true, ...
    Config=cfg, ...
    MakeDashboard=caseDef.makeDashboard, ...
    Truth=inputInfo.truth, ...
    ExportFigures=false);

results.fieldContract = fieldContract;
results.parity = localSkippedParityTable("Parity not required for this case.");

coreRows = [coreRows; localValidationRow(caseDef.name, modeDef.name, ...
    "execution", "analyzeLog_completed", true, "gate", "completed", "completed", NaN, "")]; %#ok<AGROW>
coreRows = [coreRows; localFirmwareInputSchemaRows(caseDef, modeDef, inputInfo, firmwareSchema)]; %#ok<AGROW>
coreRows = [coreRows; localFirmwareFieldCoverageRows(caseDef.name, modeDef.name, results, fieldContract)]; %#ok<AGROW>
coreRows = [coreRows; localPresenceAndFiniteRows(caseDef, modeDef, results)]; %#ok<AGROW>

if caseDef.truthEnabled
    coreRows = [coreRows; localTruthRows(caseDef.name, modeDef.name, results)]; %#ok<AGROW>
    coreRows = [coreRows; localBaroAcceptanceRows(caseDef.name, modeDef.name, results)]; %#ok<AGROW>
end

if caseDef.requireDuplicateRemoval
    coreRows = [coreRows; localDuplicateRemovalRows(caseDef.name, modeDef.name, results.cleanReport)]; %#ok<AGROW>
end

if caseDef.runParity
    sampleStruct = localTableToSamples(inputInfo.sampleTable);
    onboard = caelum.runRealtimeOnboard(sampleStruct, cfg);
    coreRows = [coreRows; localFirmwareLogParityRows(caseDef, modeDef, results, onboard.verticalHistory, options.NumericTolerance)]; %#ok<AGROW>
    [parityTable, parityRows] = localBuildParityEvidence( ...
        caseDef.name, modeDef.name, results.replay, onboard.verticalHistory, options.NumericTolerance);
    results.parity = parityTable;
    coreRows = [coreRows; parityRows]; %#ok<AGROW>
else
    coreRows = [coreRows; localValidationRow(caseDef.name, modeDef.name, ...
        "parity", "parity_skipped", true, "info", "not_applicable", "not_applicable", NaN, ...
        "Compatibility-only case; parity export retained with a not-applicable row.")]; %#ok<AGROW>
end

results.validationSummary = coreRows;
exportInfo = caelum.exportFigures(results, exportDir);

artifactRows = localArtifactRows(caseDef, modeDef, exportInfo);
baselineMetrics = localCollectBaselineMetrics(caseDef.name, modeDef.name, results, exportInfo);
baselineRows = localBaselineRows(caseDef, modeDef, baselineMetrics, baselineTable, options.NumericTolerance);

reportRows = [coreRows; artifactRows; baselineRows]; %#ok<AGROW>
reportRows = [reportRows; localValidationRow(caseDef.name, modeDef.name, ...
    "export", "artifact_bundle_dir", true, "info", exportDir, exportDir, NaN, "")]; %#ok<AGROW>
results.validationSummary = reportRows;

exportInfo = caelum.exportFigures(results, exportDir);
artifactRows = localArtifactRows(caseDef, modeDef, exportInfo);
baselineMetrics = localCollectBaselineMetrics(caseDef.name, modeDef.name, results, exportInfo);
baselineRows = localBaselineRows(caseDef, modeDef, baselineMetrics, baselineTable, options.NumericTolerance);
reportRows = [coreRows; artifactRows; baselineRows]; %#ok<AGROW>
reportRows = [reportRows; localValidationRow(caseDef.name, modeDef.name, ...
    "export", "artifact_bundle_dir", true, "info", exportDir, exportDir, NaN, "")]; %#ok<AGROW>
results.validationSummary = reportRows;
exportInfo = caelum.exportFigures(results, exportDir);
localCloseResultFigures(results);

nonInfoMask = reportRows.severity ~= "info";
if any(nonInfoMask)
    passed = all(reportRows.passed(nonInfoMask));
else
    passed = true;
end

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.modeName = modeDef.name;
caseResult.exportDir = exportDir;
caseResult.passed = passed;
caseResult.validationSummary = reportRows;
caseResult.baselineMetrics = baselineMetrics;
caseResult.exportInfo = exportInfo;
caseResult.parity = results.parity;
caseResult.filename = string(inputInfo.filename);
end

function inputInfo = localPrepareCaseInput(caseDef, exportDir)
inputInfo = struct();
inputInfo.truth = struct();
inputInfo.sampleTable = table();

switch caseDef.sourceType
    case "generated"
        inputPath = fullfile(exportDir, caseDef.generatedFilename);
        args = localStructToNameValue(caseDef.generatorArgs);
        [T, truth] = caelum.generateTruthAwareCaelumLogV2(inputPath, args{:});
        if caseDef.firmwareConsistentLoggedFields
            T = localOverwriteWithFirmwareLoggedFields(T);
            writetable(T, inputPath);
        end
        inputInfo.filename = string(inputPath);
        inputInfo.truth = truth;
        inputInfo.sampleTable = T;
    case "existing"
        inputInfo.filename = caseDef.sourcePath;
    otherwise
        error('validate_vertical_replay_stack:UnknownSourceType', ...
            'Unhandled case source type: %s', caseDef.sourceType);
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

function T = localOverwriteWithFirmwareLoggedFields(T)
aligned = caelum.alignImportedSchema(T, caelum.defaultConfig());
firmware = caelum.runFirmwareVerticalEstimator(aligned, caelum.defaultConfig());

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

function rows = localFirmwareInputSchemaRows(caseDef, modeDef, inputInfo, firmwareSchema)
rows = localEmptyValidationTable();
if caseDef.sourceType ~= "generated"
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "firmware_input", "sdlog_schema_check_skipped", true, "info", ...
        "not_generated_case", "not_generated_case", NaN, "")]; %#ok<AGROW>
    return;
end

requiredFields = string(firmwareSchema.field(firmwareSchema.required));
actualFields = string(inputInfo.sampleTable.Properties.VariableNames);
missing = setdiff(requiredFields, actualFields);

rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
    "firmware_input", "required_sdlog_fields_present", isempty(missing), "gate", ...
    localMissingString(missing), "none_missing", NaN, ...
    "Checked against the checked-in firmware SD logger schema.")]; %#ok<AGROW>
end

function rows = localFirmwareFieldCoverageRows(caseName, modeName, results, fieldContract)
rows = localEmptyValidationTable();
requiredRows = fieldContract(fieldContract.required_for_firmware, :);
missing = strings(0, 1);

for k = 1:height(requiredRows)
    domain = string(requiredRows.domain(k));
    fieldName = string(requiredRows.source_name(k));
    switch domain
        case "vertical_replay"
            targetTable = results.replay;
        case "attitude_replay"
            targetTable = results.attitude;
        otherwise
            targetTable = table();
    end

    if ~istable(targetTable) || ~ismember(fieldName, string(targetTable.Properties.VariableNames))
        missing(end+1, 1) = domain + "." + fieldName; %#ok<AGROW>
    end
end

if isempty(missing)
    actual = "all_required_fields_present";
    notes = "";
    passed = true;
else
    actual = strjoin(missing, ";");
    notes = "Missing required firmware-alignment fields.";
    passed = false;
end

rows = [rows; localValidationRow(caseName, modeName, ...
    "field_contract", "required_firmware_fields_present", passed, "gate", actual, ...
    "all_required_fields_present", NaN, notes)]; %#ok<AGROW>
end

function rows = localPresenceAndFiniteRows(caseDef, modeDef, results)
rows = localEmptyValidationTable();

requiredReplayColumns = ["t","h","v","b_a","beta","sigma_h","sigma_v", ...
    "innovation_h","innovation_nis","baro_used","baro_rejected", ...
    "vertical_input_mode","a_vertical_used","attitude_fallback_used"];
requiredAttitudeColumns = ["t","q_w","q_x","q_y","q_z","a_vertical_attitude", ...
    "gravity_update_used","gravity_innovation","gravity_residual", ...
    "tilt_error_deg","b_gx","b_gy","b_gz"];

replayMissing = setdiff(requiredReplayColumns, string(results.replay.Properties.VariableNames));
attitudeMissing = setdiff(requiredAttitudeColumns, string(results.attitude.Properties.VariableNames));

rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
    "schema", "required_replay_columns_present", isempty(replayMissing), "gate", ...
    localMissingString(replayMissing), "none_missing", NaN, "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
    "schema", "required_attitude_columns_present", isempty(attitudeMissing), "gate", ...
    localMissingString(attitudeMissing), "none_missing", NaN, "")]; %#ok<AGROW>

if ~isnan(caseDef.finiteFractionThreshold)
    replayFiniteFields = ["h","v","b_a","beta","sigma_h","sigma_v","innovation_h","innovation_nis","a_vertical_used"];
    attitudeFiniteFields = ["q_w","q_x","q_y","q_z","a_vertical_attitude","gravity_innovation","gravity_residual","tilt_error_deg","b_gx","b_gy","b_gz"];

    replayFinite = localMinimumFiniteFraction(results.replay, replayFiniteFields);
    attitudeFinite = localMinimumFiniteFraction(results.attitude, attitudeFiniteFields);

    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "inspectability", "replay_fields_mostly_finite", replayFinite >= caseDef.finiteFractionThreshold, "gate", ...
        num2str(replayFinite, '%.6f'), ">=" + string(caseDef.finiteFractionThreshold), NaN, "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "inspectability", "attitude_fields_mostly_finite", attitudeFinite >= caseDef.finiteFractionThreshold, "gate", ...
        num2str(attitudeFinite, '%.6f'), ">=" + string(caseDef.finiteFractionThreshold), NaN, "")]; %#ok<AGROW>
end
end

function rows = localTruthRows(caseName, modeName, results)
rows = localEmptyValidationTable();
hasTruth = isfield(results, 'truthMetrics') && isfield(results.truthMetrics, 'rmse_h_replay') ...
    && isfield(results.truthMetrics, 'rmse_v_replay') ...
    && isfinite(results.truthMetrics.rmse_h_replay) ...
    && isfinite(results.truthMetrics.rmse_v_replay);

rows = [rows; localValidationRow(caseName, modeName, ...
    "truth", "replay_truth_metrics_present", hasTruth, "gate", ...
    localTruthMetricString(results.truthMetrics), "finite_rmse_h_replay_and_rmse_v_replay", NaN, "")]; %#ok<AGROW>
end

function rows = localBaroAcceptanceRows(caseName, modeName, results)
rows = localEmptyValidationTable();
accepted = 0;
if isfield(results, 'replay') && istable(results.replay) && ismember("baro_used", string(results.replay.Properties.VariableNames))
    accepted = nnz(results.replay.baro_used);
end
rows = [rows; localValidationRow(caseName, modeName, ...
    "health", "accepted_baro_updates_present", accepted > 0, "gate", ...
    string(accepted), ">0", NaN, "")]; %#ok<AGROW>
end

function rows = localDuplicateRemovalRows(caseName, modeName, cleanReport)
rows = localEmptyValidationTable();
rows = [rows; localValidationRow(caseName, modeName, ...
    "robustness", "rows_after_cleaning_positive", cleanReport.rowsAfterCleaning > 0, "gate", ...
    string(cleanReport.rowsAfterCleaning), ">0", NaN, "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, modeName, ...
    "robustness", "duplicate_timestamps_removed", cleanReport.duplicateTimestampsRemoved > 0, "gate", ...
    string(cleanReport.duplicateTimestampsRemoved), ">0", NaN, "")]; %#ok<AGROW>
end

function [parityTable, rows] = localBuildParityEvidence(caseName, modeName, replay, verticalHistory, tolerance)
rows = localEmptyValidationTable();
[fieldMap, gateMask] = localReplayFirmwareParityMap(modeName);

[offlineAligned, onboardAligned, notes] = localAlignTablesOnTime(replay, verticalHistory);
if isempty(offlineAligned) || isempty(onboardAligned)
    parityTable = localSkippedParityTable("No common replay samples available for parity.");
    rows = [rows; localValidationRow(caseName, modeName, ...
        "parity", "timebase_alignment", false, "gate", "0", ">0", tolerance, notes)]; %#ok<AGROW>
    return;
end

rows = [rows; localValidationRow(caseName, modeName, ...
    "parity", "timebase_alignment", true, "gate", string(height(offlineAligned)), ">0", tolerance, notes)]; %#ok<AGROW>

parityTable = table('Size', [size(fieldMap, 1) 9], ...
    'VariableTypes', {'string','double','double','double','double','double','string','logical','string'}, ...
    'VariableNames', {'field','samplesCompared','samplesMatching','matchRate','maxAbsDiff','meanAbsDiff','comparison','pass','notes'});

for k = 1:size(fieldMap, 1)
    replayField = fieldMap(k, 1);
    firmwareField = fieldMap(k, 2);
    parityTable.field(k) = replayField + "->" + firmwareField;

    if ~ismember(replayField, string(offlineAligned.Properties.VariableNames)) || ...
            ~ismember(firmwareField, string(onboardAligned.Properties.VariableNames))
        parityTable.samplesCompared(k) = 0;
        parityTable.samplesMatching(k) = 0;
        parityTable.matchRate(k) = NaN;
        parityTable.maxAbsDiff(k) = NaN;
        parityTable.meanAbsDiff(k) = NaN;
        parityTable.comparison(k) = "missing";
        parityTable.pass(k) = false;
        parityTable.notes(k) = "Field missing in replay or firmware estimator.";
        rows = [rows; localValidationRow(caseName, modeName, ...
            "parity", "match_" + replayField, false, localParitySeverity(gateMask(k)), ...
            "missing_field", "present_in_both_tables", tolerance, parityTable.notes(k))]; %#ok<AGROW>
        continue;
    end

    a = offlineAligned.(char(replayField));
    b = onboardAligned.(char(firmwareField));
    if islogical(a) || islogical(b)
        matches = double(a == b);
        parityTable.samplesCompared(k) = numel(matches);
        parityTable.samplesMatching(k) = sum(matches);
        parityTable.matchRate(k) = mean(matches);
        parityTable.maxAbsDiff(k) = NaN;
        parityTable.meanAbsDiff(k) = NaN;
        parityTable.comparison(k) = "exact";
        parityTable.pass(k) = all(matches);
        parityTable.notes(k) = "";
        actual = sprintf('%.6f', parityTable.matchRate(k));
        expected = "1.0";
    else
        valid = isfinite(a) & isfinite(b);
        diffs = abs(a(valid) - b(valid));
        if isempty(diffs)
            parityTable.samplesCompared(k) = 0;
            parityTable.samplesMatching(k) = 0;
            parityTable.matchRate(k) = NaN;
            parityTable.maxAbsDiff(k) = NaN;
            parityTable.meanAbsDiff(k) = NaN;
            parityTable.comparison(k) = "numeric";
            parityTable.pass(k) = false;
            parityTable.notes(k) = "No overlapping finite samples.";
        else
            parityTable.samplesCompared(k) = numel(diffs);
            parityTable.samplesMatching(k) = sum(diffs <= tolerance);
            parityTable.matchRate(k) = mean(diffs <= tolerance);
            parityTable.maxAbsDiff(k) = max(diffs);
            parityTable.meanAbsDiff(k) = mean(diffs);
            parityTable.comparison(k) = "numeric";
            parityTable.pass(k) = all(diffs <= tolerance);
            parityTable.notes(k) = "";
        end
        actual = sprintf('%.6g', parityTable.maxAbsDiff(k));
        expected = "<=" + string(tolerance);
    end

    rows = [rows; localValidationRow(caseName, modeName, ...
        "parity", "match_" + replayField, parityTable.pass(k), localParitySeverity(gateMask(k)), ...
        actual, expected, tolerance, parityTable.notes(k))]; %#ok<AGROW>
end
end

function [AAligned, BAligned, notes] = localAlignTablesOnTime(A, B)
notes = "";
if ~istable(A) || ~istable(B) || isempty(A) || isempty(B)
    AAligned = table();
    BAligned = table();
    notes = "Replay or onboard vertical history is empty.";
    return;
end

keyA = int64(round(A.t * 1e9));
keyB = int64(round(B.t * 1e9));
[~, ia, ib] = intersect(keyA, keyB, 'stable');
AAligned = A(ia, :);
BAligned = B(ib, :);
if isempty(AAligned)
    notes = "No common timestamps found.";
else
    notes = sprintf('Aligned %d samples on time.', height(AAligned));
end
end

function rows = localFirmwareLogParityRows(caseDef, modeDef, results, firmwareHistory, tolerance)
rows = localEmptyValidationTable();
if ~isfield(results, 'importReport') || ~isfield(results.importReport, 'schemaMode') || ...
        string(results.importReport.schemaMode) ~= "full"
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "firmware_log", "logged_field_parity_skipped", true, "info", ...
        "non_full_schema_log", "full_schema_log", tolerance, "")]; %#ok<AGROW>
    return;
end

[loggedAligned, firmwareAligned, notes] = localAlignTablesOnTime( ...
    localLoggedFirmwareTable(results.data), firmwareHistory);
if isempty(loggedAligned) || isempty(firmwareAligned)
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "firmware_log", "timebase_alignment", false, "gate", ...
        "0", ">0", tolerance, notes)]; %#ok<AGROW>
    return;
end

rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
    "firmware_log", "timebase_alignment", true, "gate", ...
    string(height(loggedAligned)), ">0", tolerance, notes)]; %#ok<AGROW>

fieldMap = [ ...
    "g_bx","g_bx"; ...
    "g_by","g_by"; ...
    "g_bz","g_bz"; ...
    "a_vertical","a_vertical"; ...
    "kf_h","h"; ...
    "kf_v","v"; ...
    "P00","P00"; ...
    "P01","P01"; ...
    "P10","P10"; ...
    "P11","P11"];

for k = 1:size(fieldMap, 1)
    loggedField = fieldMap(k, 1);
    firmwareField = fieldMap(k, 2);
    a = loggedAligned.(char(loggedField));
    b = firmwareAligned.(char(firmwareField));
    valid = isfinite(a) & isfinite(b);
    diffs = abs(a(valid) - b(valid));
    passed = ~isempty(diffs) && all(diffs <= tolerance);
    if isempty(diffs)
        actual = "no_finite_overlap";
        notesField = "No overlapping finite samples.";
    else
        actual = sprintf('%.6g', max(diffs));
        notesField = "";
    end

    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "firmware_log", "match_" + loggedField, passed, "gate", ...
        actual, "<=" + string(tolerance), tolerance, notesField)]; %#ok<AGROW>
end
end

function T = localLoggedFirmwareTable(cleanData)
T = table();
T.t = cleanData.t;
T.g_bx = cleanData.g_bx;
T.g_by = cleanData.g_by;
T.g_bz = cleanData.g_bz;
T.a_vertical = cleanData.a_vertical;
T.kf_h = cleanData.kf_h;
T.kf_v = cleanData.kf_v;
T.P00 = cleanData.P00;
T.P01 = cleanData.P01;
T.P10 = cleanData.P10;
T.P11 = cleanData.P11;
end

function [fieldMap, gateMask] = localReplayFirmwareParityMap(modeName)
fieldMap = [ ...
    "a_vertical_used","a_vertical"; ...
    "h","h"; ...
    "v","v"; ...
    "sigma_h","sigma_h"; ...
    "sigma_v","sigma_v"; ...
    "baro_used","baro_used"];

gateMask = true(size(fieldMap, 1), 1);
if string(modeName) == "attitude"
    gateMask(1) = false;
end
end

function severity = localParitySeverity(isGate)
if isGate
    severity = "gate";
else
    severity = "info";
end
end

function rows = localArtifactRows(caseDef, modeDef, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["summary_csv","import_report_csv","clean_csv","attitude_csv", ...
    "replay_csv","parity_csv","field_contract_csv","validation_summary_csv","manifest_csv"];
if caseDef.truthEnabled
    requiredArtifacts = [requiredArtifacts, "truth_metrics_csv", "consistency_metrics_csv"];
end
if caseDef.makeDashboard
    requiredArtifacts = [requiredArtifacts, "dashboard_png", "dashboard_pdf"];
end

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
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "export", "artifact_" + artifactKey, present, "gate", ...
        string(present), "true", NaN, "")]; %#ok<AGROW>
end

hasErrors = isempty(fieldnames(exportInfo.errors));
rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
    "export", "export_errors_absent", hasErrors, "gate", ...
    string(~hasErrors), "false", NaN, "")]; %#ok<AGROW>
end

function metrics = localCollectBaselineMetrics(caseName, modeName, results, exportInfo)
metrics = localEmptyMetricTable();

if isfield(results, 'summaryTable') && istable(results.summaryTable)
    for k = 1:height(results.summaryTable)
        metricName = "summary." + string(results.summaryTable.Metric(k));
        metricValue = localCellToString(results.summaryTable.Value{k});
        metrics = [metrics; localMetricRow(caseName, modeName, metricName, metricValue)]; %#ok<AGROW>
    end
end

if isfield(results, 'parity') && istable(results.parity) && ~isempty(results.parity)
    for k = 1:height(results.parity)
        fieldName = string(results.parity.field(k));
        metrics = [metrics; localMetricRow(caseName, modeName, ...
            "parity." + fieldName + ".pass", string(results.parity.pass(k)))]; %#ok<AGROW>
        metrics = [metrics; localMetricRow(caseName, modeName, ...
            "parity." + fieldName + ".matchRate", string(results.parity.matchRate(k)))]; %#ok<AGROW>
        metrics = [metrics; localMetricRow(caseName, modeName, ...
            "parity." + fieldName + ".maxAbsDiff", string(results.parity.maxAbsDiff(k)))]; %#ok<AGROW>
    end
end

if isfield(exportInfo, 'manifest') && istable(exportInfo.manifest)
    for k = 1:height(exportInfo.manifest)
        artifactKey = string(exportInfo.manifest.artifact(k));
        metrics = [metrics; localMetricRow(caseName, modeName, ...
            "artifact." + artifactKey + ".exists", string(exportInfo.manifest.exists(k)))]; %#ok<AGROW>
    end
end
end

function rows = localBaselineRows(caseDef, modeDef, metrics, baselineTable, tolerance)
rows = localEmptyValidationTable();

if ~caseDef.runBaselineCompare
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "baseline", "baseline_compare_skipped", true, "info", ...
        "not_enabled_for_case", "not_enabled_for_case", tolerance, "")]; %#ok<AGROW>
    return;
end

if isempty(baselineTable)
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "baseline", "baseline_compare_skipped", true, "info", ...
        "baseline_file_empty", "baseline_rows_present", tolerance, ...
        "Populate vertical_replay_baseline.csv from a reviewed MATLAB run.")]; %#ok<AGROW>
    return;
end

subset = baselineTable(baselineTable.case == caseDef.name & baselineTable.mode == modeDef.name, :);
if isempty(subset)
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "baseline", "baseline_compare_skipped", true, "info", ...
        "no_case_rows", "baseline_rows_present", tolerance, ...
        "Populate vertical_replay_baseline.csv from a reviewed MATLAB run.")]; %#ok<AGROW>
    return;
end

for k = 1:height(subset)
    metricName = string(subset.metric(k));
    baselineValue = string(subset.value(k));
    idx = find(metrics.metric == metricName, 1, 'first');
    if isempty(idx)
        rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
            "baseline", "baseline_metric_" + metricName, false, "baseline", ...
            "missing_actual_metric", baselineValue, tolerance, "")]; %#ok<AGROW>
        continue;
    end

    actualValue = string(metrics.value(idx));
    [passed, notes] = localCompareBaselineValue(actualValue, baselineValue, tolerance);
    rows = [rows; localValidationRow(caseDef.name, modeDef.name, ...
        "baseline", "baseline_metric_" + metricName, passed, "baseline", ...
        actualValue, baselineValue, tolerance, notes)]; %#ok<AGROW>
end
end

function [passed, notes] = localCompareBaselineValue(actualValue, baselineValue, tolerance)
notes = "";
if any(strcmpi(actualValue, ["true","false"])) || any(strcmpi(baselineValue, ["true","false"]))
    passed = strcmpi(actualValue, baselineValue);
    return;
end

actualNumeric = str2double(actualValue);
baselineNumeric = str2double(baselineValue);
if isfinite(actualNumeric) && isfinite(baselineNumeric)
    passed = abs(actualNumeric - baselineNumeric) <= tolerance;
    if ~passed
        notes = sprintf('abs diff %.6g exceeded %.6g', abs(actualNumeric - baselineNumeric), tolerance);
    end
else
    passed = strcmp(actualValue, baselineValue);
end
end

function baselineTable = localReadBaseline(baselinePath)
if ~isfile(baselinePath)
    baselineTable = localEmptyMetricTable();
    return;
end

opts = detectImportOptions(baselinePath, 'Delimiter', ',', 'VariableNamingRule', 'preserve');
baselineTable = readtable(baselinePath, opts);
if ~all(ismember(["case","mode","metric","value"], string(baselineTable.Properties.VariableNames)))
    error('validate_vertical_replay_stack:InvalidBaseline', ...
        'Baseline file must contain case, mode, metric, and value columns.');
end
baselineTable.case = string(baselineTable.case);
baselineTable.mode = string(baselineTable.mode);
baselineTable.metric = string(baselineTable.metric);
baselineTable.value = string(baselineTable.value);
end

function sampleStruct = localTableToSamples(T)
n = height(T);
sampleStruct = repmat(struct(), n, 1);
fields = string(T.Properties.VariableNames);
for k = 1:n
    sampleStruct(k).t = double(T.t_us(k)) * 1e-6;
    for j = 1:numel(fields)
        fieldName = fields(j);
        if fieldName == "t_us"
            continue;
        end
        sampleStruct(k).(char(fieldName)) = T.(char(fieldName))(k);
    end
end
end

function [mcResult, reportRows, baselineMetrics] = localRunMonteCarloSmoke(modeDefs, options)
reportRows = localEmptyValidationTable();
baselineMetrics = localEmptyMetricTable();

mcResult = struct();
mcResult.byMode = repmat(struct('modeName', "", 'seedResults', table(), 'successRate', NaN), numel(modeDefs), 1);

for modeIdx = 1:numel(modeDefs)
    modeDef = modeDefs(modeIdx);
    cfg = caelum.defaultConfig();
    cfg.useAttitudeVerticalInput = modeDef.useAttitudeVerticalInput;

    seedResults = table('Size', [numel(options.MonteCarloSeeds) 5], ...
        'VariableTypes', {'double','logical','string','double','string'}, ...
        'VariableNames', {'seed','success','status','gpsAcceptanceRate','failureDir'});

    for seedIdx = 1:numel(options.MonteCarloSeeds)
        seed = options.MonteCarloSeeds(seedIdx);
        seedResults.seed(seedIdx) = seed;
        seedResults.failureDir(seedIdx) = "";

        runtimeDir = fullfile(options.ExportRoot, "monte_carlo", modeDef.name, "runtime");
        if ~exist(runtimeDir, 'dir')
            mkdir(runtimeDir);
        end
        filename = fullfile(runtimeDir, sprintf('mc_seed_%03d.csv', seed));

        try
            [~, truth] = caelum.generateTruthAwareCaelumLogV2(filename, seed=seed);
            results = caelum.analyzeLog(filename, ...
                MakePlots=false, ...
                ReplayEstimator=true, ...
                Config=cfg, ...
                MakeDashboard=false, ...
                ExportFigures=false, ...
                Truth=truth);
            seedResults.success(seedIdx) = true;
            seedResults.status(seedIdx) = "ok";
            if istable(results.est3d) && ~isempty(results.est3d) && ismember("gps_used", string(results.est3d.Properties.VariableNames))
                seedResults.gpsAcceptanceRate(seedIdx) = mean(double(results.est3d.gps_used), 'omitnan');
            else
                seedResults.gpsAcceptanceRate(seedIdx) = NaN;
            end
        catch ME
            failureDir = fullfile(options.ExportRoot, "monte_carlo", modeDef.name, sprintf('seed_%03d', seed));
            if ~exist(failureDir, 'dir')
                mkdir(failureDir);
            end
            if isfile(filename)
                copyfile(filename, fullfile(failureDir, sprintf('mc_seed_%03d.csv', seed)));
            end
            failureRows = localEmptyValidationTable();
            failureRows = [failureRows; localValidationRow("monte_carlo", modeDef.name, ...
                "execution", "seed_" + string(seed), false, "gate", ...
                string(ME.identifier), "ok", options.NumericTolerance, string(ME.message))]; %#ok<AGROW>
            writetable(failureRows, fullfile(failureDir, "seed_failure_report.csv"));

            seedResults.success(seedIdx) = false;
            seedResults.status(seedIdx) = string(ME.identifier);
            seedResults.gpsAcceptanceRate(seedIdx) = NaN;
            seedResults.failureDir(seedIdx) = failureDir;
        end
    end

    successRate = mean(double(seedResults.success));
    mcResult.byMode(modeIdx).modeName = modeDef.name;
    mcResult.byMode(modeIdx).seedResults = seedResults;
    mcResult.byMode(modeIdx).successRate = successRate;

    reportRows = [reportRows; localValidationRow("monte_carlo", modeDef.name, ...
        "smoke", "success_rate", successRate == 1, "gate", ...
        string(successRate), "1", NaN, "")]; %#ok<AGROW>
    reportRows = [reportRows; localValidationRow("monte_carlo", modeDef.name, ...
        "smoke", "num_failed_seeds", nnz(~seedResults.success) == 0, "gate", ...
        string(nnz(~seedResults.success)), "0", NaN, "")]; %#ok<AGROW>

    baselineMetrics = [baselineMetrics; localMetricRow("monte_carlo", modeDef.name, ...
        "success_rate", string(successRate))]; %#ok<AGROW>
end

summaryPath = fullfile(options.ExportRoot, "monte_carlo_summary.csv");
summaryTable = table();
summaryTable.mode = string({mcResult.byMode.modeName}).';
summaryTable.successRate = [mcResult.byMode.successRate].';
writetable(summaryTable, summaryPath);
end

function rows = localEmptyValidationTable()
rows = table('Size', [0 10], ...
    'VariableTypes', {'string','string','string','string','logical','string','string','string','double','string'}, ...
    'VariableNames', {'caseName','modeName','scope','check','passed','severity','actual','expected','tolerance','notes'});
end

function row = localValidationRow(caseName, modeName, scope, check, passed, severity, actual, expected, tolerance, notes)
row = table( ...
    string(caseName), string(modeName), string(scope), string(check), logical(passed), ...
    string(severity), string(actual), string(expected), double(tolerance), string(notes), ...
    'VariableNames', {'caseName','modeName','scope','check','passed','severity','actual','expected','tolerance','notes'});
end

function metrics = localEmptyMetricTable()
metrics = table('Size', [0 4], ...
    'VariableTypes', {'string','string','string','string'}, ...
    'VariableNames', {'case','mode','metric','value'});
end

function row = localMetricRow(caseName, modeName, metric, value)
row = table(string(caseName), string(modeName), string(metric), string(value), ...
    'VariableNames', {'case','mode','metric','value'});
end

function minimumFraction = localMinimumFiniteFraction(T, fields)
fractions = nan(numel(fields), 1);
for k = 1:numel(fields)
    fieldName = fields(k);
    if ~ismember(fieldName, string(T.Properties.VariableNames))
        fractions(k) = 0;
        continue;
    end
    values = T.(char(fieldName));
    fractions(k) = mean(isfinite(values));
end
minimumFraction = min(fractions);
end

function s = localMissingString(missing)
if isempty(missing)
    s = "none_missing";
else
    s = strjoin(missing, ";");
end
end

function s = localTruthMetricString(truthMetrics)
if isfield(truthMetrics, 'rmse_h_replay') && isfield(truthMetrics, 'rmse_v_replay')
    s = "rmse_h_replay=" + string(truthMetrics.rmse_h_replay) + ...
        ";rmse_v_replay=" + string(truthMetrics.rmse_v_replay);
else
    s = "missing_truth_metrics";
end
end

function value = localCellToString(v)
if isstring(v)
    value = v;
elseif ischar(v)
    value = string(v);
else
    value = string(v);
end
end

function parityTable = localSkippedParityTable(message)
parityTable = table( ...
    "not_applicable", 0, 0, NaN, NaN, NaN, "skipped", true, string(message), ...
    'VariableNames', {'field','samplesCompared','samplesMatching','matchRate','maxAbsDiff','meanAbsDiff','comparison','pass','notes'});
end

function localCloseResultFigures(results)
localCloseFigureHandle(results, 'dashboardFigure');
localCloseFigureArray(results, 'figures');
localCloseFigureArray(results, 'figures3D');
end

function localCloseFigureHandle(results, fieldName)
if isfield(results, fieldName)
    fig = results.(fieldName);
    if ~isempty(fig) && all(isgraphics(fig))
        close(fig);
    end
end
end

function localCloseFigureArray(results, fieldName)
if ~isfield(results, fieldName)
    return;
end

figs = results.(fieldName);
if isempty(figs)
    return;
end

for k = 1:numel(figs)
    if isgraphics(figs(k))
        close(figs(k));
    end
end
end

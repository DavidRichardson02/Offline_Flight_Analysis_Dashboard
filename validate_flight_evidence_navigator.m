function validation = validate_flight_evidence_navigator(options)
%VALIDATE_FLIGHT_EVIDENCE_NAVIGATOR Validate flight evidence navigator artifacts.
%
% The navigator is intentionally static in this milestone. Validation proves
% that the shared event index and standalone figure can be built across normal,
% degraded, and missing-evidence cases without requiring firmware changes.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "flight_evidence_navigator_validation")
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
    'sourceKind', "", ...
    'sourcePath', "", ...
    'eventIndex', table(), ...
    'auditBundle', struct(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "flight_evidence_navigator_validation_report.csv");
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
    fprintf('Flight evidence navigator validation passed.\n');
else
    fprintf(2, 'Flight evidence navigator validation reported failures.\n');
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
        'seed', 51, ...
        'useReplay', true, ...
        'mutation', "none"); ...
    struct('name', "freshness_degraded_fixture", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'seed', NaN, ...
        'useReplay', true, ...
        'mutation', "freshness_degraded"); ...
    struct('name', "phase_evidence_fixture", ...
        'sourceKind', "sd", ...
        'sourcePath', options.SdFixturePath, ...
        'seed', NaN, ...
        'useReplay', true, ...
        'mutation', "phase_focus"); ...
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

function [caseResult, rows] = localRunCase(caseDef, options)
rows = localEmptyValidationTable();
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
fig = caelum.plotFlightEvidenceNavigator(eventIndex, clean, events, cfg, ...
    Title="Flight Evidence Navigator - " + caseDef.name);

results = struct();
results.filename = localResultFilename(inputPath, caseDef);
results.data = clean;
results.replay = replay;
results.flightEvidenceIndex = eventIndex;
results.flightEvidenceNavigatorFigure = fig;

exportInfo = caelum.exportFigures(results, caseDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported_cleaned_and_indexed", ...
    height(clean) > 0 && height(eventIndex) > 0, ...
    "clean=" + string(height(clean)) + ";events=" + string(height(eventIndex)), ...
    "clean>0;events>0", localReportSummary(importReport, cleanReport))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "event_index_required_columns_present", ...
    localEventColumnsPresent(eventIndex), localMissingEventColumns(eventIndex), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "labels_and_rationales_nonempty", ...
    all(eventIndex.label ~= "") && all(eventIndex.rationale ~= ""), ...
    "labels=" + string(nnz(eventIndex.label ~= "")) + ";rationales=" + string(nnz(eventIndex.rationale ~= "")), ...
    string(height(eventIndex)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "coverage", "mission_events_indexed", ...
    nnz(eventIndex.event_type == "mission_event") >= 3, ...
    string(nnz(eventIndex.event_type == "mission_event")), ">=3", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "coverage", "multiple_sources_indexed", ...
    numel(unique(eventIndex.source_view)) >= 4, ...
    string(numel(unique(eventIndex.source_view))), ">=4", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "plot", "navigator_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>

rows = [rows; localCaseSpecificRows(caseDef, eventIndex)]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = inputPath;
caseResult.eventIndex = eventIndex;
caseResult.auditBundle = auditBundle;
caseResult.exportInfo = exportInfo;
caseResult.passed = all(rows.passed);
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
            error('validate_flight_evidence_navigator:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
        [raw, importReport] = caelum.importLog(inputPath);
    case "serial"
        inputPath = caseDef.sourcePath;
        if ~isfile(inputPath)
            error('validate_flight_evidence_navigator:MissingFixture', ...
                'Fixture not found: %s.', inputPath);
        end
        [raw, importReport] = caelum.importSerialTelemetry(inputPath);
    otherwise
        error('validate_flight_evidence_navigator:UnknownSourceKind', ...
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
    case "phase_focus"
        if ismember("phase_diag_age_ms", vars)
            clean.phase_diag_age_ms(:) = min(clean.phase_diag_age_ms(:), 10);
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

function rows = localCaseSpecificRows(caseDef, eventIndex)
rows = localEmptyValidationTable();
labels = string(eventIndex.label);
sources = string(eventIndex.source_view);
switch caseDef.mutation
    case "freshness_degraded"
        hasFreshnessProblem = any(startsWith(sources, "telemetry_freshness") & ...
            ismember(labels, ["invalid","stale","warning_active","valid_held"]));
        rows = [rows; localValidationRow(caseDef.name, "classification", "freshness_degradation_indexed", ...
            hasFreshnessProblem, localLabelSummary(eventIndex), ...
            "freshness invalid/stale/warn/held present", "")]; %#ok<AGROW>
    case "missing_firmware_fields"
        hasMissing = any(eventIndex.severity == "missing");
        rows = [rows; localValidationRow(caseDef.name, "classification", "missing_firmware_fields_indexed", ...
            hasMissing, localLabelSummary(eventIndex), "severity includes missing", "")]; %#ok<AGROW>
end

if ~caseDef.useReplay
    hasReplayFallback = any(sources == "replay_contract" & labels == "replay_incomplete") || ...
        any(sources == "estimator_trust" & labels == "replay_incomplete");
    rows = [rows; localValidationRow(caseDef.name, "classification", "missing_replay_fallback_indexed", ...
        hasReplayFallback, localLabelSummary(eventIndex), ...
        "replay_incomplete from replay_contract or estimator_trust", "")]; %#ok<AGROW>
end

if string(caseDef.name) == "phase_evidence_fixture"
    hasPhaseEvent = any(sources == "phase_state_machine" & labels == "transition_observed");
    rows = [rows; localValidationRow(caseDef.name, "classification", "phase_transition_indexed", ...
        hasPhaseEvent, localLabelSummary(eventIndex), "transition_observed present", "")]; %#ok<AGROW>
end
end

function tf = localEventColumnsPresent(eventIndex)
tf = isempty(localMissingEventColumnList(eventIndex));
end

function text = localMissingEventColumns(eventIndex)
missing = localMissingEventColumnList(eventIndex);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(missing, ",");
end
end

function missing = localMissingEventColumnList(eventIndex)
required = ["t_start","t_end","t_mid","event_type","severity","source_view", ...
    "label","rationale","confidence","field_names"];
missing = setdiff(required, string(eventIndex.Properties.VariableNames), 'stable');
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
required = ["flight_evidence_index_csv","flight_evidence_navigator_png", ...
    "flight_evidence_navigator_pdf","manifest_csv"];
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
    rows = [rows; localValidationRow(caseName, "artifact", required(k) + "_written", ...
        exists, actual, "file_exists", "")]; %#ok<AGROW>
end
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

function text = localLabelSummary(eventIndex)
labels = unique(string(eventIndex.label), 'stable');
parts = strings(0, 1);
for k = 1:min(numel(labels), 12)
    parts(end+1) = labels(k) + "=" + string(nnz(eventIndex.label == labels(k))); %#ok<AGROW>
end
if numel(labels) > 12
    parts(end+1) = "+" + string(numel(labels) - 12) + "_more"; %#ok<AGROW>
end
text = strjoin(parts, "; ");
end

function filename = localResultFilename(inputPath, caseDef)
if caseDef.sourceKind == "generated"
    filename = string(inputPath);
else
    [~, base, ext] = fileparts(inputPath);
    filename = string(fullfile(fileparts(inputPath), string(base) + "_" + string(caseDef.name) + string(ext)));
end
end

function row = localValidationRow(caseName, scope, check, passed, actual, expected, notes)
row = table(string(caseName), string(scope), string(check), logical(passed), ...
    string(actual), string(expected), string(notes), ...
    'VariableNames', {'caseName','scope','check','passed','actual','expected','notes'});
end

function T = localEmptyValidationTable()
T = table('Size', [0 7], ...
    'VariableTypes', {'string','string','string','logical','string','string','string'}, ...
    'VariableNames', {'caseName','scope','check','passed','actual','expected','notes'});
end

function localCloseFigure(fig)
if ~isempty(fig) && isgraphics(fig)
    close(fig);
end
end

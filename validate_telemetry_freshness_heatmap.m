function validation = validate_telemetry_freshness_heatmap(options)
%VALIDATE_TELEMETRY_FRESHNESS_HEATMAP Validate source freshness artifacts.
%
% The validation exercises latest SD import, Serial HDR/TLM import, and a live
% buffer snapshot built from the Serial fixture so parser/ring-buffer counters
% are represented in the exported audit table.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "telemetry_freshness_validation")
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
    'telemetryFreshness', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), cfg, options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "telemetry_freshness_validation_report.csv");
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
    fprintf('Telemetry freshness heatmap validation passed.\n');
else
    fprintf(2, 'Telemetry freshness heatmap validation reported failures.\n');
end
end

function [caseResult, rows] = localRunCase(caseDef, cfg, options)
rows = localEmptyValidationTable();

if ~isfile(caseDef.path)
    error('validate_telemetry_freshness_heatmap:MissingFixture', ...
        'Fixture not found: %s.', caseDef.path);
end

[clean, report] = localImportCase(caseDef, cfg, options);
audit = caelum.buildTelemetryFreshnessAudit(clean, Report=report);
fig = caelum.plotTelemetryFreshnessHeatmap(audit);
[compactFig, compactAudit] = localCreateCompactPanel(clean, report);

results = struct();
results.filename = localResultFilename(caseDef);
results.telemetryFreshness = audit;
results.telemetryFreshnessFigure = fig;

exportDir = fullfile(options.ExportRoot, caseDef.name);
exportInfo = caelum.exportFigures(results, exportDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported", ...
    height(clean) > 0, string(height(clean)), ">0", localReportSummary(report))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_required_columns_present", ...
    localRequiredColumnsPresent(audit), localMissingColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "expected_source_domains_present", ...
    localExpectedDomainsPresent(audit), localMissingDomains(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_row_count_matches_sources_times_samples", ...
    height(audit) == localExpectedAuditRows(audit, clean), ...
    string(height(audit)), string(localExpectedAuditRows(audit, clean)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "status_labels_nonempty", ...
    all(audit.status_label ~= ""), string(nnz(audit.status_label ~= "")), string(height(audit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "status_evidence_not_all_missing", ...
    ~all(audit.status_label == "missing"), localLabelSummary(audit), "not_all_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "freshness", "valid_updated_or_held_present", ...
    any(audit.status_label == "valid_updated" | audit.status_label == "valid_held"), ...
    localLabelSummary(audit), "valid_updated_or_valid_held", "")]; %#ok<AGROW>

if caseDef.sourceKind == "live_buffer"
    rows = [rows; localValidationRow(caseDef.name, "parser", "live_buffer_counters_present", ...
        localFirstFinite(audit.report_accepted_rows) > 0 && ...
        isfinite(localFirstFinite(audit.report_dropped_nonmonotonic_rows)), ...
        localParserCounterText(audit), "accepted>0;counters_finite", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "parser", "live_buffer_counter_check_skipped", ...
        true, "not_live_buffer_case", "not_live_buffer_case", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, "plot", "telemetry_freshness_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "plot", "compact_freshness_panel_created", ...
    ~isempty(compactFig) && isgraphics(compactFig) && istable(compactAudit) && height(compactAudit) > 0, ...
    sprintf('figure=%d;rows=%d', ~isempty(compactFig) && isgraphics(compactFig), height(compactAudit)), ...
    "figure=1;rows>0", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);
localCloseFigure(compactFig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = caseDef.path;
caseResult.telemetryFreshness = audit;
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
        error('validate_telemetry_freshness_heatmap:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end
end

function filename = localResultFilename(caseDef)
[~, name, ~] = fileparts(caseDef.path);
filename = string(name) + "_" + caseDef.sourceKind + ".csv";
end

function [fig, audit] = localCreateCompactPanel(clean, report)
fig = figure('Visible', 'off', 'Color', [0.07 0.08 0.09]);
ax = axes('Parent', fig);
audit = caelum.plotCompactTelemetryFreshness(ax, clean, ...
    Report=report, ...
    MaxSamples=240, ...
    Title="Telemetry Freshness Compact");
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
    "sample_index", ...
    "t", ...
    "source", ...
    "source_label", ...
    "valid", ...
    "updated", ...
    "seq", ...
    "seq_delta", ...
    "age_ms", ...
    "status_code", ...
    "status_label", ...
    "status_rationale", ...
    "report_accepted_rows", ...
    "report_dropped_malformed_rows", ...
    "report_dropped_non_numeric_rows", ...
    "report_dropped_nonmonotonic_rows", ...
    "report_dropped_capacity_rows"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
end

function tf = localExpectedDomainsPresent(audit)
tf = isempty(localMissingDomainList(audit));
end

function text = localMissingDomains(audit)
missing = localMissingDomainList(audit);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingDomainList(audit)
expected = ["barometer","imu","aux_accel","attitude","vertical_accel","estimator","phase_diag","policy","warning"];
missing = setdiff(expected, unique(string(audit.source), 'stable'), 'stable');
end

function expectedRows = localExpectedAuditRows(audit, clean)
sourceCount = numel(unique(string(audit.source), 'stable'));
expectedRows = sourceCount * height(clean);
end

function text = localLabelSummary(audit)
labels = unique(audit.status_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.status_label == labels(k)));
end
text = strjoin(parts, ";");
end

function value = localFirstFinite(values)
idx = find(isfinite(values), 1, 'first');
if isempty(idx)
    value = NaN;
else
    value = values(idx);
end
end

function text = localParserCounterText(audit)
text = sprintf('accepted=%.0f;malformed=%.0f;non_numeric=%.0f;nonmonotonic=%.0f;capacity=%.0f', ...
    localFirstFinite(audit.report_accepted_rows), ...
    localFirstFinite(audit.report_dropped_malformed_rows), ...
    localFirstFinite(audit.report_dropped_non_numeric_rows), ...
    localFirstFinite(audit.report_dropped_nonmonotonic_rows), ...
    localFirstFinite(audit.report_dropped_capacity_rows));
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["telemetry_freshness_csv","telemetry_freshness_png","telemetry_freshness_pdf","manifest_csv"];
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

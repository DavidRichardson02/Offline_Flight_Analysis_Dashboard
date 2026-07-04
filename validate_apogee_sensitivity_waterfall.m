function validation = validate_apogee_sensitivity_waterfall(options)
%VALIDATE_APOGEE_SENSITIVITY_WATERFALL Validate apogee authority decomposition.
%
% This validation checks both logged corridor authority and finite-difference
% model perturbations around the replayed vertical state.
arguments
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
    options.ExportRoot (1,1) string = fullfile("exports", "apogee_sensitivity_validation")
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

cfg = caelum.defaultConfig();
caseDefs = [ ...
    struct('name', "latest_sd_fixture", 'sourceKind', "sd", ...
        'path', options.SdFixturePath, 'mutation', "none", ...
        'selectors', ["max_command","apogee"]); ...
    struct('name', "latest_serial_fixture", 'sourceKind', "serial", ...
        'path', options.SerialFixturePath, 'mutation', "none", ...
        'selectors', ["max_command","apogee"]); ...
    struct('name', "missing_firmware_fields_fallback", 'sourceKind', "sd", ...
        'path', options.SdFixturePath, 'mutation', "missing_firmware_fields", ...
        'selectors', "max_command")];

reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'selector', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'audit', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseCaseResults, rows] = localRunCase(caseDefs(k), cfg, options.ExportRoot);
    caseResults = [caseResults; caseCaseResults]; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "apogee_sensitivity_validation_report.csv");
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
    fprintf('Apogee sensitivity waterfall validation passed.\n');
else
    fprintf(2, 'Apogee sensitivity waterfall validation reported failures.\n');
end
end

function [caseResults, rows] = localRunCase(caseDef, cfg, exportRoot)
rows = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'selector', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'audit', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

if ~isfile(caseDef.path)
    error('validate_apogee_sensitivity_waterfall:MissingFixture', ...
        'Fixture not found: %s.', caseDef.path);
end

[clean, importReport, cleanReport] = localImportFixture(caseDef, cfg);
clean = localApplyMutation(clean, caseDef.mutation);
replay = localBuildReplay(clean, cfg);

caseDir = fullfile(exportRoot, caseDef.name);
if ~exist(caseDir, 'dir')
    mkdir(caseDir);
end

selectors = string(caseDef.selectors);
for s = 1:numel(selectors)
    selector = selectors(s);
    audit = caelum.buildApogeeSensitivityAudit(clean, cfg, Selector=selector, Replay=replay);
    fig = caelum.plotApogeeSensitivityWaterfall(audit, cfg);

    results = struct();
    results.filename = localResultFilename(caseDef.path, caseDef.name, selector);
    results.apogeeSensitivity = audit;
    results.apogeeSensitivityFigure = fig;
    exportInfo = caelum.exportFigures(results, caseDir);

    snapshotRows = localValidateSnapshot(caseDef, selector, clean, audit, fig, exportInfo, ...
        "schema=" + string(importReport.schemaMode) + ";cleanRows=" + string(cleanReport.rowsAfterCleaning));
    rows = [rows; snapshotRows]; %#ok<AGROW>

    caseResult = struct();
    caseResult.caseName = caseDef.name;
    caseResult.selector = selector;
    caseResult.sourceKind = caseDef.sourceKind;
    caseResult.sourcePath = caseDef.path;
    caseResult.audit = audit;
    caseResult.exportInfo = exportInfo;
    caseResult.passed = all(snapshotRows.passed);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>

    localCloseFigure(fig);
end
end

function replay = localBuildReplay(clean, cfg)
try
    replay = caelum.replayEstimator(clean, cfg);
catch
    replay = table();
end
end

function [clean, importReport, cleanReport] = localImportFixture(caseDef, cfg)
switch caseDef.sourceKind
    case "sd"
        [raw, importReport] = caelum.importLog(caseDef.path);
    case "serial"
        [raw, importReport] = caelum.importSerialTelemetry(caseDef.path);
    otherwise
        error('validate_apogee_sensitivity_waterfall:UnknownSourceKind', ...
            'Unhandled source kind: %s.', caseDef.sourceKind);
end
aligned = caelum.alignImportedSchema(raw, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);
end

function clean = localApplyMutation(clean, mutation)
vars = string(clean.Properties.VariableNames);
switch mutation
    case "missing_firmware_fields"
        removeFields = intersect(["policy_valid","policy_cmd","actuator_us", ...
            "apogee_no_brake","apogee_full_brake","target_apogee", ...
            "target_nominal","target_effective","uncertainty_margin"], vars, 'stable');
        if ~isempty(removeFields)
            clean(:, cellstr(removeFields)) = [];
        end
    otherwise
end
end

function rows = localValidateSnapshot(caseDef, selector, clean, audit, fig, exportInfo, reportSummary)
rows = localEmptyValidationTable();
rows = [rows; localValidationRow(caseDef.name, selector, "execution", "audit_built", ...
    height(clean) > 0 && height(audit) >= 13, ...
    "clean=" + string(height(clean)) + ";audit=" + string(height(audit)), ...
    "clean>0;audit>=13", reportSummary)]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "schema", "required_columns_present", ...
    localRequiredColumnsPresent(audit), localMissingColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, selector, "classification", "labels_nonempty", ...
    all(audit.audit_label ~= "") && all(audit.severity ~= ""), ...
    "labels=" + string(nnz(audit.audit_label ~= "")), string(height(audit)), "")]; %#ok<AGROW>

if caseDef.mutation == "missing_firmware_fields"
    rows = [rows; localValidationRow(caseDef.name, selector, "fallback", "missing_firmware_fields_visible", ...
        any(audit.severity == "missing"), localLabelSummary(audit), "missing severity present", "")]; %#ok<AGROW>
elseif ~localHasFiniteAuthority(audit)
    rows = [rows; localValidationRow(caseDef.name, selector, "fallback", "authority_unavailable_visible", ...
        any(ismember(audit.audit_label, ["telemetry_incomplete","authority_unavailable","target_unavailable"])), ...
        localLabelSummary(audit), "missing authority classified", ...
        "The selected review time has no finite logged apogee corridor, so missing authority is expected evidence.")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, selector, "math", "authority_span_nonnegative", ...
        localAuthoritySpanNonnegative(audit), localAuthorityText(audit), "span>=0", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, selector, "math", "no_brake_not_below_full_brake", ...
        localNoBrakeNotBelowFullBrake(audit), localAuthorityText(audit), "high>=low", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, selector, "math", "corridor_demand_bounded", ...
        localDemandBounded(audit), localDemandText(audit), "[0,1]", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, selector, "math", "command_projections_inside_authority", ...
        localProjectionsInsideAuthority(audit), localProjectionText(audit), "inside [low,high]", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, selector, "finite_difference", "fd_terms_present", ...
        localFiniteDifferenceTermsPresent(audit), localFiniteDifferenceText(audit), ...
        "base+h+v+cmd finite", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, selector, "finite_difference", "fd_directionality", ...
        localFiniteDifferenceDirectionality(audit), localFiniteDifferenceText(audit), ...
        "dh>0;dv>0;du<=0", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, selector, "plot", "waterfall_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, selector, exportInfo)]; %#ok<AGROW>
end

function tf = localHasFiniteAuthority(audit)
low = localFirstFinite(audit.authority_low_m);
high = localFirstFinite(audit.authority_high_m);
span = localFirstFinite(audit.authority_span_m);
tf = isfinite(low) && isfinite(high) && isfinite(span) && span > 0;
end

function tf = localFiniteDifferenceTermsPresent(audit)
required = ["replay_model_base","fd_altitude_step","fd_velocity_step","fd_command_step"];
if ~all(ismember(required, string(audit.component)))
    tf = false;
    return;
end
tf = true;
for k = 1:numel(required)
    row = audit(audit.component == required(k), :);
    tf = tf && ~isempty(row) && isfinite(row.value(1));
end
end

function tf = localFiniteDifferenceDirectionality(audit)
h = localComponentRow(audit, "fd_altitude_step");
v = localComponentRow(audit, "fd_velocity_step");
u = localComponentRow(audit, "fd_command_step");
tf = ~isempty(h) && ~isempty(v) && ~isempty(u) && ...
    isfinite(h.delta_value(1)) && isfinite(v.delta_value(1)) && isfinite(u.delta_value(1)) && ...
    h.delta_value(1) > 0 && v.delta_value(1) > 0 && u.delta_value(1) <= 1.0e-9;
end

function text = localFiniteDifferenceText(audit)
components = ["replay_model_base","fd_altitude_step","fd_velocity_step","fd_command_step"];
parts = strings(numel(components), 1);
for k = 1:numel(components)
    row = localComponentRow(audit, components(k));
    if isempty(row)
        parts(k) = components(k) + "=missing";
    else
        parts(k) = components(k) + "=" + string(sprintf('value %.6g delta %.6g slope %.6g', ...
            row.value(1), row.delta_value(1), row.normalized_value(1)));
    end
end
text = strjoin(parts, ";");
end

function row = localComponentRow(audit, component)
row = audit(audit.component == component, :);
if height(row) > 1
    row = row(1, :);
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
required = ["t","selector","component","component_label","value","unit", ...
    "reference_value","delta_value","normalized_value","authority_low_m", ...
    "authority_high_m","authority_span_m","target_selected_m","policy_cmd", ...
    "actuator_position_norm","actuator_tracking_error","decision_label", ...
    "severity","audit_label","rationale","source_fields"];
missing = setdiff(required, string(audit.Properties.VariableNames), 'stable');
end

function tf = localAuthoritySpanNonnegative(audit)
span = audit.authority_span_m(isfinite(audit.authority_span_m));
tf = ~isempty(span) && all(span >= 0);
end

function tf = localNoBrakeNotBelowFullBrake(audit)
low = localFirstFinite(audit.authority_low_m);
high = localFirstFinite(audit.authority_high_m);
tf = isfinite(low) && isfinite(high) && high >= low;
end

function tf = localDemandBounded(audit)
row = audit(audit.component == "demand_from_corridor", :);
tf = ~isempty(row) && isfinite(row.value(1)) && row.value(1) >= 0 && row.value(1) <= 1;
end

function tf = localProjectionsInsideAuthority(audit)
low = localFirstFinite(audit.authority_low_m);
high = localFirstFinite(audit.authority_high_m);
if ~isfinite(low) || ~isfinite(high)
    tf = false;
    return;
end
rows = audit(ismember(audit.component, ["policy_command_projection","actuator_projection"]), :);
values = rows.value(isfinite(rows.value));
tf = ~isempty(values) && all(values >= low - 1.0e-9) && all(values <= high + 1.0e-9);
end

function text = localAuthorityText(audit)
text = sprintf('[%.6g, %.6g] span=%.6g', ...
    localFirstFinite(audit.authority_low_m), ...
    localFirstFinite(audit.authority_high_m), ...
    localFirstFinite(audit.authority_span_m));
end

function text = localDemandText(audit)
row = audit(audit.component == "demand_from_corridor", :);
if isempty(row)
    text = "missing";
else
    text = sprintf('%.6g', row.value(1));
end
end

function text = localProjectionText(audit)
rows = audit(ismember(audit.component, ["policy_command_projection","actuator_projection"]), :);
parts = strings(height(rows), 1);
for k = 1:height(rows)
    parts(k) = rows.component(k) + "=" + string(sprintf('%.6g', rows.value(k)));
end
text = strjoin(parts, ";");
end

function value = localFirstFinite(values)
values = values(isfinite(values));
if isempty(values)
    value = NaN;
else
    value = values(1);
end
end

function text = localLabelSummary(audit)
labels = unique(audit.audit_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(audit.audit_label == labels(k)));
end
text = strjoin(parts, ";");
end

function filename = localResultFilename(sourcePath, caseName, selector)
[folder, base, ext] = fileparts(sourcePath);
selector = regexprep(char(selector), '[^a-zA-Z0-9_-]', '_');
filename = string(fullfile(folder, string(base) + "_" + string(caseName) + "_" + string(selector) + string(ext)));
end

function rows = localArtifactRows(caseName, selector, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["apogee_sensitivity_csv","apogee_sensitivity_png", ...
    "apogee_sensitivity_pdf","manifest_csv"];
for k = 1:numel(requiredArtifacts)
    key = char(requiredArtifacts(k));
    if isfield(exportInfo.files, key)
        pathValue = string(exportInfo.files.(key));
        exists = isfile(pathValue);
        actual = pathValue;
    else
        exists = false;
        actual = "missing_export_key";
    end
    rows = [rows; localValidationRow(caseName, selector, "artifact", requiredArtifacts(k) + "_written", ...
        exists, actual, "file_exists", "")]; %#ok<AGROW>
end
end

function row = localValidationRow(caseName, selector, scope, check, passed, actual, expected, notes)
row = table(string(caseName), string(selector), string(scope), string(check), logical(passed), ...
    string(actual), string(expected), string(notes), ...
    'VariableNames', {'caseName','selector','scope','check','passed','actual','expected','notes'});
end

function rows = localEmptyValidationTable()
rows = table('Size', [0 8], ...
    'VariableTypes', {'string','string','string','string','logical','string','string','string'}, ...
    'VariableNames', {'caseName','selector','scope','check','passed','actual','expected','notes'});
end

function localCloseFigure(fig)
if ~isempty(fig) && isgraphics(fig)
    close(fig);
end
end

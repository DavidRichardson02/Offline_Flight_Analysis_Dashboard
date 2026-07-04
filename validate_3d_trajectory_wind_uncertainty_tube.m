function validation = validate_3d_trajectory_wind_uncertainty_tube(options)
%VALIDATE_3D_TRAJECTORY_WIND_UNCERTAINTY_TUBE Validate 3D/wind tube artifacts.
%
% Cases cover a truth-aware synthetic GPS/wind log, the latest SD fixture, and
% the latest Serial fixture. The Serial case intentionally validates graceful
% inertial-only behavior when GPS fields are absent.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "trajectory_wind_tube_validation")
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

cfg = caelum.localResolve3DConfig(caelum.defaultConfig());
caseDefs = [ ...
    struct('name', "truth_aware_synthetic", 'sourceKind', "truth_synthetic", ...
        'path', fullfile(options.ExportRoot, "truth_aware_synthetic", "Synthetic_TruthAware_3DWind.csv"), ...
        'expectGps', true, 'expectTruth', true); ...
    struct('name', "latest_sd_fixture", 'sourceKind', "sd", ...
        'path', options.SdFixturePath, 'expectGps', true, 'expectTruth', false); ...
    struct('name', "latest_serial_fixture", 'sourceKind', "serial", ...
        'path', options.SerialFixturePath, 'expectGps', false, 'expectTruth', false)];

reportTable = localEmptyValidationTable();
caseResults = repmat(struct( ...
    'caseName', "", ...
    'sourceKind', "", ...
    'sourcePath', "", ...
    'trajectoryWindAudit', table(), ...
    'exportInfo', struct(), ...
    'passed', false), 0, 1);

for k = 1:numel(caseDefs)
    [caseResult, rows] = localRunCase(caseDefs(k), cfg, options);
    caseResults(end+1, 1) = caseResult; %#ok<AGROW>
    reportTable = [reportTable; rows]; %#ok<AGROW>
end

reportPath = fullfile(options.ExportRoot, "trajectory_wind_tube_validation_report.csv");
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
    fprintf('3D trajectory / wind uncertainty tube validation passed.\n');
else
    fprintf(2, '3D trajectory / wind uncertainty tube validation reported failures.\n');
end
end

function [caseResult, rows] = localRunCase(caseDef, cfg, options)
rows = localEmptyValidationTable();

[clean, truth, report] = localImportCase(caseDef, cfg);
est3d = caelum.run3DEKF(clean, cfg);
audit = caelum.build3DTrajectoryWindAudit(est3d, clean, Truth=truth);
fig = caelum.plot3DTrajectoryWindUncertaintyTube(audit);

results = struct();
results.filename = localResultFilename(caseDef);
results.trajectoryWindAudit = audit;
results.trajectoryWindFigure = fig;
results.est3d = est3d;
results.wind = caelum.estimateWind(est3d);

exportDir = fullfile(options.ExportRoot, caseDef.name);
exportInfo = caelum.exportFigures(results, exportDir);

rows = [rows; localValidationRow(caseDef.name, "execution", "fixture_imported", ...
    height(clean) > 0, string(height(clean)), ">0", localReportSummary(report))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "est3d_required_columns_present", ...
    localEst3DColumnsPresent(est3d), localMissingEst3DColumns(est3d), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_required_columns_present", ...
    localAuditColumnsPresent(audit), localMissingAuditColumns(audit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "schema", "audit_row_count_matches_est3d", ...
    height(audit) == height(est3d), string(height(audit)), string(height(est3d)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "geometry", "tube_geometry_has_finite_samples", ...
    nnz(isfinite(audit.display_tube_radius_m) & isfinite(audit.display_tube_vertical_half_width_m)) > 1, ...
    string(nnz(isfinite(audit.display_tube_radius_m) & isfinite(audit.display_tube_vertical_half_width_m))), ...
    ">1", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseDef.name, "classification", "evidence_labels_nonempty", ...
    all(audit.evidence_label ~= ""), string(nnz(audit.evidence_label ~= "")), string(height(audit)), "")]; %#ok<AGROW>

if caseDef.expectGps
    rows = [rows; localValidationRow(caseDef.name, "gps", "gps_measurements_present", ...
        nnz(audit.gps_measurement_available) > 0, string(nnz(audit.gps_measurement_available)), ">0", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, "gps", "gps_updates_or_rejections_observed", ...
        nnz(audit.gps_used | audit.gps_rejected) > 0, ...
        sprintf('used=%d;rejected=%d', nnz(audit.gps_used), nnz(audit.gps_rejected)), ...
        "used_or_rejected>0", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "gps", "gps_absent_case_classified", ...
        nnz(audit.gps_measurement_available) == 0 && any(audit.evidence_label == "inertial_propagation_only"), ...
        sprintf('gps_samples=%d;labels=%s', nnz(audit.gps_measurement_available), localLabelSummary(audit)), ...
        "gps_samples=0;inertial_label_present", "")]; %#ok<AGROW>
end

if caseDef.expectTruth
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_position_error_available", ...
        nnz(isfinite(audit.truth_position_error_norm_m)) > 0, ...
        string(nnz(isfinite(audit.truth_position_error_norm_m))), ">0", "")]; %#ok<AGROW>
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_wind_error_available", ...
        nnz(isfinite(audit.truth_wind_error_norm_mps)) > 0, ...
        string(nnz(isfinite(audit.truth_wind_error_norm_mps))), ">0", "")]; %#ok<AGROW>
else
    rows = [rows; localValidationRow(caseDef.name, "truth", "truth_check_skipped", ...
        true, "not_truth_case", "not_truth_case", "")]; %#ok<AGROW>
end

rows = [rows; localValidationRow(caseDef.name, "plot", "trajectory_wind_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseDef.name, exportInfo)]; %#ok<AGROW>

localCloseFigure(fig);

caseResult = struct();
caseResult.caseName = caseDef.name;
caseResult.sourceKind = caseDef.sourceKind;
caseResult.sourcePath = caseDef.path;
caseResult.trajectoryWindAudit = audit;
caseResult.exportInfo = exportInfo;
caseResult.passed = all(rows.passed);
end

function [clean, truth, report] = localImportCase(caseDef, cfg)
truth = struct();
switch caseDef.sourceKind
    case "truth_synthetic"
        outDir = fileparts(caseDef.path);
        if ~exist(outDir, 'dir')
            mkdir(outDir);
        end
        [~, truth] = caelum.generateTruthAwareCaelumLogV2(caseDef.path, ...
            seed=55, gpsRateHz=10, windXYZ=[1.7 -0.9 0.25]);
        [raw, report] = caelum.importLog(caseDef.path);
        aligned = caelum.alignImportedSchema(raw, cfg);
        [clean, cleanReport] = caelum.cleanLog(aligned, cfg);
        report.cleanReport = cleanReport;
        report.rowsAfterCleaning = height(clean);
    case "sd"
        if ~isfile(caseDef.path)
            error('validate_3d_trajectory_wind_uncertainty_tube:MissingFixture', ...
                'Fixture not found: %s.', caseDef.path);
        end
        [raw, report] = caelum.importLog(caseDef.path);
        aligned = caelum.alignImportedSchema(raw, cfg);
        [clean, cleanReport] = caelum.cleanLog(aligned, cfg);
        report.cleanReport = cleanReport;
        report.rowsAfterCleaning = height(clean);
    case "serial"
        if ~isfile(caseDef.path)
            error('validate_3d_trajectory_wind_uncertainty_tube:MissingFixture', ...
                'Fixture not found: %s.', caseDef.path);
        end
        [raw, report] = caelum.importSerialTelemetry(caseDef.path);
        aligned = caelum.alignImportedSchema(raw, cfg);
        [clean, cleanReport] = caelum.cleanLog(aligned, cfg);
        report.cleanReport = cleanReport;
        report.rowsAfterCleaning = height(clean);
    otherwise
        error('validate_3d_trajectory_wind_uncertainty_tube:UnknownSourceKind', ...
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
if isfield(report, 'validRowsImported')
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

function tf = localEst3DColumnsPresent(est3d)
tf = isempty(localMissingEst3DColumnList(est3d));
end

function text = localMissingEst3DColumns(est3d)
missing = localMissingEst3DColumnList(est3d);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingEst3DColumnList(est3d)
required = ["t","px","py","pz","vx","vy","vz","wx","wy","wz", ...
    "sigma_px","sigma_py","sigma_pz","sigma_wx","sigma_wy","sigma_wz", ...
    "gps_used","gps_rejected","innovation_pos_norm","innovation_vel_norm"];
missing = setdiff(required, string(est3d.Properties.VariableNames), 'stable');
end

function tf = localAuditColumnsPresent(audit)
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
    "px_m", ...
    "py_m", ...
    "pz_m", ...
    "wx_mps", ...
    "wy_mps", ...
    "wz_mps", ...
    "position_sigma_norm_m", ...
    "wind_sigma_norm_mps", ...
    "tube_radius_m", ...
    "display_tube_radius_m", ...
    "gps_measurement_available", ...
    "gps_position_residual_norm_m", ...
    "gps_velocity_residual_norm_mps", ...
    "truth_position_error_norm_m", ...
    "truth_wind_error_norm_mps", ...
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

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = ["trajectory_wind_tube_csv","trajectory_wind_tube_png", ...
    "trajectory_wind_tube_pdf","est3d_csv","wind_summary_csv","manifest_csv"];
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

function validation = validate_monte_carlo_mission_envelope_board(options)
%VALIDATE_MONTE_CARLO_MISSION_ENVELOPE_BOARD Validate Monte Carlo board artifacts.
%
% The validation generates a deterministic designed Monte Carlo set, derives
% the mission-envelope audit, plots the sensitivity board, and exports the
% figure and CSV artifacts used for review.
arguments
    options.ExportRoot (1,1) string = fullfile("exports", "monte_carlo_mission_envelope_validation")
    options.NumRuns (1,1) double {mustBeInteger,mustBePositive} = 12
    options.Seed (1,1) double = 900
    options.MinimumSuccessRate (1,1) double {mustBeNonnegative} = 0.75
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~exist(options.ExportRoot, 'dir')
    mkdir(options.ExportRoot);
end

cfg = caelum.localResolve3DConfig(caelum.defaultConfig());
caseName = "designed_synthetic";
caseDir = fullfile(options.ExportRoot, caseName);
logsDir = fullfile(caseDir, "logs");
if ~exist(caseDir, 'dir')
    mkdir(caseDir);
end

mc = caelum.runMonteCarloMissionEnvelope(logsDir, ...
    NumRuns=options.NumRuns, ...
    Seed=options.Seed, ...
    SaveLogs=true, ...
    MakePlots=false, ...
    MakeDashboard=false, ...
    Config=cfg);

fig = caelum.plotMonteCarloMissionEnvelopeBoard(mc.envelopeAudit, mc.sensitivity, cfg);

results = struct();
results.filename = fullfile(caseDir, "designed_synthetic_monte_carlo.csv");
results.monteCarloFigure = fig;
results.monteCarloEnvelope = mc.envelopeAudit;
results.monteCarloSensitivity = mc.sensitivity;
results.monteCarloRunMetrics = mc.runMetrics;

exportInfo = caelum.exportFigures(results, caseDir);

rows = localEmptyValidationTable();
rows = [rows; localValidationRow(caseName, "execution", "requested_run_count_generated", ...
    height(mc.runMetrics) == options.NumRuns, ...
    string(height(mc.runMetrics)), string(options.NumRuns), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "execution", "success_rate_above_threshold", ...
    localSuccessRate(mc.runMetrics) >= options.MinimumSuccessRate, ...
    sprintf('%.3f', localSuccessRate(mc.runMetrics)), ...
    ">=" + string(options.MinimumSuccessRate), localStatusSummary(mc.runMetrics))]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "schema", "envelope_required_columns_present", ...
    localEnvelopeColumnsPresent(mc.envelopeAudit), ...
    localMissingEnvelopeColumns(mc.envelopeAudit), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "schema", "sensitivity_required_columns_present", ...
    localSensitivityColumnsPresent(mc.sensitivity), ...
    localMissingSensitivityColumns(mc.sensitivity), "none_missing", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "schema", "envelope_row_count_matches_runs", ...
    height(mc.envelopeAudit) == height(mc.runMetrics), ...
    string(height(mc.envelopeAudit)), string(height(mc.runMetrics)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "classification", "labels_nonempty", ...
    all(mc.envelopeAudit.envelope_label ~= ""), ...
    string(nnz(mc.envelopeAudit.envelope_label ~= "")), string(height(mc.envelopeAudit)), "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "classification", "not_all_runs_failed", ...
    ~all(mc.envelopeAudit.envelope_label == "run_failed"), ...
    localLabelSummary(mc.envelopeAudit), "not_all_run_failed", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "sensitivity", "finite_correlations_present", ...
    nnz(isfinite(mc.sensitivity.correlation)) > 0, ...
    string(nnz(isfinite(mc.sensitivity.correlation))), ">0", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "sensitivity", "sensitivity_rank_is_monotonic", ...
    isequal(mc.sensitivity.rank(:), (1:height(mc.sensitivity)).'), ...
    localRankText(mc.sensitivity), "1:N", "")]; %#ok<AGROW>
rows = [rows; localValidationRow(caseName, "plot", "monte_carlo_figure_created", ...
    ~isempty(fig) && isgraphics(fig), string(~isempty(fig) && isgraphics(fig)), "true", "")]; %#ok<AGROW>
rows = [rows; localArtifactRows(caseName, exportInfo)]; %#ok<AGROW>

reportPath = fullfile(options.ExportRoot, "monte_carlo_mission_envelope_validation_report.csv");
writetable(rows, reportPath);

localCloseFigure(fig);

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.exportRoot = options.ExportRoot;
validation.reportPath = reportPath;
validation.monteCarlo = mc;
validation.exportInfo = exportInfo;
validation.reportTable = rows;
validation.overallPassed = all(rows.passed);

disp(rows(:, ["caseName","scope","check","passed","actual","expected","notes"]));
if validation.overallPassed
    fprintf('Monte Carlo mission envelope / sensitivity board validation passed.\n');
else
    fprintf(2, 'Monte Carlo mission envelope / sensitivity board validation reported failures.\n');
end
end

function rate = localSuccessRate(runMetrics)
if isempty(runMetrics)
    rate = NaN;
else
    rate = mean(double(runMetrics.success), 'omitnan');
end
end

function tf = localEnvelopeColumnsPresent(envelope)
tf = isempty(localMissingEnvelopeColumnList(envelope));
end

function text = localMissingEnvelopeColumns(envelope)
missing = localMissingEnvelopeColumnList(envelope);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingEnvelopeColumnList(envelope)
required = [ ...
    "runIndex", ...
    "success", ...
    "truth_peak_altitude_m", ...
    "logged_peak_altitude_m", ...
    "peak_altitude_abs_error_m", ...
    "rmse_h_m", ...
    "rmse_pz_m", ...
    "gpsAcceptanceRate", ...
    "windError_mps", ...
    "data_loss_fraction", ...
    "composite_error_score", ...
    "envelope_code", ...
    "envelope_label", ...
    "envelope_rationale"];
missing = setdiff(required, string(envelope.Properties.VariableNames), 'stable');
end

function tf = localSensitivityColumnsPresent(sensitivity)
tf = isempty(localMissingSensitivityColumnList(sensitivity));
end

function text = localMissingSensitivityColumns(sensitivity)
missing = localMissingSensitivityColumnList(sensitivity);
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

function missing = localMissingSensitivityColumnList(sensitivity)
required = [ ...
    "input_name", ...
    "output_name", ...
    "correlation", ...
    "abs_correlation", ...
    "slope", ...
    "valid_runs", ...
    "rank"];
missing = setdiff(required, string(sensitivity.Properties.VariableNames), 'stable');
end

function text = localStatusSummary(runMetrics)
labels = unique(runMetrics.status, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(runMetrics.status == labels(k)));
end
text = strjoin(parts, ";");
end

function text = localLabelSummary(envelope)
labels = unique(envelope.envelope_label, 'stable');
parts = strings(numel(labels), 1);
for k = 1:numel(labels)
    parts(k) = labels(k) + "=" + string(nnz(envelope.envelope_label == labels(k)));
end
text = strjoin(parts, ";");
end

function text = localRankText(sensitivity)
if isempty(sensitivity)
    text = "empty";
else
    text = sprintf('%d:%d', min(sensitivity.rank), max(sensitivity.rank));
end
end

function rows = localArtifactRows(caseName, exportInfo)
rows = localEmptyValidationTable();
requiredArtifacts = [ ...
    "monte_carlo_mission_envelope_png", ...
    "monte_carlo_mission_envelope_pdf", ...
    "monte_carlo_envelope_csv", ...
    "monte_carlo_sensitivity_csv", ...
    "monte_carlo_run_metrics_csv", ...
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

function exportInfo = exportFigures(results, exportDir)
%EXPORTFIGURES Export figures and evidence tables for offline analysis and validation.
arguments
    results struct
    exportDir (1,1) string = "exports"
end

if ~exist(exportDir, "dir")
    mkdir(exportDir);
end

baseName = localBaseName(results.filename);
exportInfo = struct();
exportInfo.exportDir = exportDir;
exportInfo.baseName = baseName;
exportInfo.files = struct();
exportInfo.warnings = strings(0,1);
exportInfo.errors = struct();
exportInfo.manifest = table();

if isfield(results, "dashboardFigure") && ~isempty(results.dashboardFigure) && isgraphics(results.dashboardFigure)
    pngPath = fullfile(exportDir, baseName + "_dashboard.png");
    pdfPath = fullfile(exportDir, baseName + "_dashboard.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.dashboardFigure, pngPath, "png", "dashboard_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.dashboardFigure, pdfPath, "pdf", "dashboard_pdf");
end

if isfield(results, "auxiliaryDashboardFigure") && ~isempty(results.auxiliaryDashboardFigure) && isgraphics(results.auxiliaryDashboardFigure)
    pngPath = fullfile(exportDir, baseName + "_auxiliary_dashboard.png");
    pdfPath = fullfile(exportDir, baseName + "_auxiliary_dashboard.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.auxiliaryDashboardFigure, pngPath, "png", "auxiliary_dashboard_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.auxiliaryDashboardFigure, pdfPath, "pdf", "auxiliary_dashboard_pdf");
end

if isfield(results, "policyAuditFigure") && ~isempty(results.policyAuditFigure) && isgraphics(results.policyAuditFigure)
    pngPath = fullfile(exportDir, baseName + "_policy_audit.png");
    pdfPath = fullfile(exportDir, baseName + "_policy_audit.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.policyAuditFigure, pngPath, "png", "policy_audit_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.policyAuditFigure, pdfPath, "pdf", "policy_audit_pdf");
end

if isfield(results, "estimatorTrustFigure") && ~isempty(results.estimatorTrustFigure) && isgraphics(results.estimatorTrustFigure)
    pngPath = fullfile(exportDir, baseName + "_estimator_trust.png");
    pdfPath = fullfile(exportDir, baseName + "_estimator_trust.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.estimatorTrustFigure, pngPath, "png", "estimator_trust_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.estimatorTrustFigure, pdfPath, "pdf", "estimator_trust_pdf");
end

if isfield(results, "telemetryFreshnessFigure") && ~isempty(results.telemetryFreshnessFigure) && isgraphics(results.telemetryFreshnessFigure)
    pngPath = fullfile(exportDir, baseName + "_telemetry_freshness.png");
    pdfPath = fullfile(exportDir, baseName + "_telemetry_freshness.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.telemetryFreshnessFigure, pngPath, "png", "telemetry_freshness_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.telemetryFreshnessFigure, pdfPath, "pdf", "telemetry_freshness_pdf");
end

if isfield(results, "phaseStateFigure") && ~isempty(results.phaseStateFigure) && isgraphics(results.phaseStateFigure)
    pngPath = fullfile(exportDir, baseName + "_phase_state_timeline.png");
    pdfPath = fullfile(exportDir, baseName + "_phase_state_timeline.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.phaseStateFigure, pngPath, "png", "phase_state_timeline_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.phaseStateFigure, pdfPath, "pdf", "phase_state_timeline_pdf");
end

if isfield(results, "trajectoryWindFigure") && ~isempty(results.trajectoryWindFigure) && isgraphics(results.trajectoryWindFigure)
    pngPath = fullfile(exportDir, baseName + "_trajectory_wind_tube.png");
    pdfPath = fullfile(exportDir, baseName + "_trajectory_wind_tube.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.trajectoryWindFigure, pngPath, "png", "trajectory_wind_tube_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.trajectoryWindFigure, pdfPath, "pdf", "trajectory_wind_tube_pdf");
end

if isfield(results, "attitudeGravityFigure") && ~isempty(results.attitudeGravityFigure) && isgraphics(results.attitudeGravityFigure)
    pngPath = fullfile(exportDir, baseName + "_attitude_gravity_provenance.png");
    pdfPath = fullfile(exportDir, baseName + "_attitude_gravity_provenance.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.attitudeGravityFigure, pngPath, "png", "attitude_gravity_provenance_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.attitudeGravityFigure, pdfPath, "pdf", "attitude_gravity_provenance_pdf");
end

if isfield(results, "monteCarloFigure") && ~isempty(results.monteCarloFigure) && isgraphics(results.monteCarloFigure)
    pngPath = fullfile(exportDir, baseName + "_monte_carlo_mission_envelope.png");
    pdfPath = fullfile(exportDir, baseName + "_monte_carlo_mission_envelope.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.monteCarloFigure, pngPath, "png", "monte_carlo_mission_envelope_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.monteCarloFigure, pdfPath, "pdf", "monte_carlo_mission_envelope_pdf");
end

if isfield(results, "replayContractDiffFigure") && ~isempty(results.replayContractDiffFigure) && isgraphics(results.replayContractDiffFigure)
    pngPath = fullfile(exportDir, baseName + "_replay_contract_diff.png");
    pdfPath = fullfile(exportDir, baseName + "_replay_contract_diff.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.replayContractDiffFigure, pngPath, "png", "replay_contract_diff_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.replayContractDiffFigure, pdfPath, "pdf", "replay_contract_diff_pdf");
end

if isfield(results, "flightEvidenceNavigatorFigure") && ~isempty(results.flightEvidenceNavigatorFigure) && isgraphics(results.flightEvidenceNavigatorFigure)
    pngPath = fullfile(exportDir, baseName + "_flight_evidence_navigator.png");
    pdfPath = fullfile(exportDir, baseName + "_flight_evidence_navigator.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.flightEvidenceNavigatorFigure, pngPath, "png", "flight_evidence_navigator_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.flightEvidenceNavigatorFigure, pdfPath, "pdf", "flight_evidence_navigator_pdf");
end

if isfield(results, "causalityGraphFigure") && ~isempty(results.causalityGraphFigure) && isgraphics(results.causalityGraphFigure)
    pngPath = fullfile(exportDir, baseName + "_causality_graph.png");
    pdfPath = fullfile(exportDir, baseName + "_causality_graph.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.causalityGraphFigure, pngPath, "png", "causality_graph_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.causalityGraphFigure, pdfPath, "pdf", "causality_graph_pdf");
end

if isfield(results, "apogeeSensitivityFigure") && ~isempty(results.apogeeSensitivityFigure) && isgraphics(results.apogeeSensitivityFigure)
    pngPath = fullfile(exportDir, baseName + "_apogee_sensitivity_waterfall.png");
    pdfPath = fullfile(exportDir, baseName + "_apogee_sensitivity_waterfall.pdf");
    exportInfo = localExportFigureArtifact(exportInfo, results.apogeeSensitivityFigure, pngPath, "png", "apogee_sensitivity_png");
    exportInfo = localExportFigureArtifact(exportInfo, results.apogeeSensitivityFigure, pdfPath, "pdf", "apogee_sensitivity_pdf");
end

if isfield(results, "figures") && ~isempty(results.figures)
    exportInfo = localExportFigureArray(exportInfo, results.figures, baseName, exportDir, "overview");
end

if isfield(results, "figures3D") && ~isempty(results.figures3D)
    exportInfo = localExportFigureArray(exportInfo, results.figures3D, baseName, exportDir, "gps3d");
end

if isfield(results, "summaryTable") && istable(results.summaryTable) && ~isempty(results.summaryTable)
    csvPath = fullfile(exportDir, baseName + "_summary.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.summaryTable, csvPath, "summary_csv");
end

if isfield(results, "importReport") && ~isempty(results.importReport)
    csvPath = fullfile(exportDir, baseName + "_import_report.csv");
    importTable = struct2table(results.importReport, "AsArray", true);
    exportInfo = localWriteTableArtifact(exportInfo, importTable, csvPath, "import_report_csv");
end

if isfield(results, "truthMetrics") && isstruct(results.truthMetrics) && ~isempty(fieldnames(results.truthMetrics))
    csvPath = fullfile(exportDir, baseName + "_truth_metrics.csv");
    truthTable = struct2table(results.truthMetrics, "AsArray", true);
    exportInfo = localWriteTableArtifact(exportInfo, truthTable, csvPath, "truth_metrics_csv");
end

if isfield(results, "consistencyMetrics") && isstruct(results.consistencyMetrics) && ~isempty(fieldnames(results.consistencyMetrics))
    csvPath = fullfile(exportDir, baseName + "_consistency_metrics.csv");
    consistencyTable = struct2table(results.consistencyMetrics, "AsArray", true);
    exportInfo = localWriteTableArtifact(exportInfo, consistencyTable, csvPath, "consistency_metrics_csv");
end

if isfield(results, "data") && istable(results.data) && ~isempty(results.data)
    csvPath = fullfile(exportDir, baseName + "_clean.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.data, csvPath, "clean_csv");
end

if isfield(results, "policyAudit") && istable(results.policyAudit) && ~isempty(results.policyAudit)
    csvPath = fullfile(exportDir, baseName + "_policy_audit.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.policyAudit, csvPath, "policy_audit_csv");
end

if isfield(results, "estimatorTrust") && istable(results.estimatorTrust) && ~isempty(results.estimatorTrust)
    csvPath = fullfile(exportDir, baseName + "_estimator_trust.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.estimatorTrust, csvPath, "estimator_trust_csv");
end

if isfield(results, "telemetryFreshness") && istable(results.telemetryFreshness) && ~isempty(results.telemetryFreshness)
    csvPath = fullfile(exportDir, baseName + "_telemetry_freshness.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.telemetryFreshness, csvPath, "telemetry_freshness_csv");
end

if isfield(results, "phaseStateAudit") && istable(results.phaseStateAudit) && ~isempty(results.phaseStateAudit)
    csvPath = fullfile(exportDir, baseName + "_phase_state_timeline.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.phaseStateAudit, csvPath, "phase_state_timeline_csv");
end

if isfield(results, "trajectoryWindAudit") && istable(results.trajectoryWindAudit) && ~isempty(results.trajectoryWindAudit)
    csvPath = fullfile(exportDir, baseName + "_trajectory_wind_tube.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.trajectoryWindAudit, csvPath, "trajectory_wind_tube_csv");
end

if isfield(results, "attitudeGravityAudit") && istable(results.attitudeGravityAudit) && ~isempty(results.attitudeGravityAudit)
    csvPath = fullfile(exportDir, baseName + "_attitude_gravity_provenance.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.attitudeGravityAudit, csvPath, "attitude_gravity_provenance_csv");
end

if isfield(results, "monteCarloEnvelope") && istable(results.monteCarloEnvelope) && ~isempty(results.monteCarloEnvelope)
    csvPath = fullfile(exportDir, baseName + "_monte_carlo_envelope.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.monteCarloEnvelope, csvPath, "monte_carlo_envelope_csv");
end

if isfield(results, "monteCarloSensitivity") && istable(results.monteCarloSensitivity) && ~isempty(results.monteCarloSensitivity)
    csvPath = fullfile(exportDir, baseName + "_monte_carlo_sensitivity.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.monteCarloSensitivity, csvPath, "monte_carlo_sensitivity_csv");
end

if isfield(results, "monteCarloRunMetrics") && istable(results.monteCarloRunMetrics) && ~isempty(results.monteCarloRunMetrics)
    csvPath = fullfile(exportDir, baseName + "_monte_carlo_run_metrics.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.monteCarloRunMetrics, csvPath, "monte_carlo_run_metrics_csv");
end

if isfield(results, "replayContractDiff") && istable(results.replayContractDiff) && ~isempty(results.replayContractDiff)
    csvPath = fullfile(exportDir, baseName + "_replay_contract_diff.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.replayContractDiff, csvPath, "replay_contract_diff_csv");
end

if isfield(results, "replayContractFieldSummary") && istable(results.replayContractFieldSummary) && ~isempty(results.replayContractFieldSummary)
    csvPath = fullfile(exportDir, baseName + "_replay_contract_field_summary.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.replayContractFieldSummary, csvPath, "replay_contract_field_summary_csv");
end

if isfield(results, "flightEvidenceIndex") && istable(results.flightEvidenceIndex) && ~isempty(results.flightEvidenceIndex)
    csvPath = fullfile(exportDir, baseName + "_flight_evidence_index.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.flightEvidenceIndex, csvPath, "flight_evidence_index_csv");
end

if isfield(results, "causalityNodes") && istable(results.causalityNodes) && ~isempty(results.causalityNodes)
    csvPath = fullfile(exportDir, baseName + "_causality_nodes.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.causalityNodes, csvPath, "causality_nodes_csv");
end

if isfield(results, "causalityEdges") && istable(results.causalityEdges) && ~isempty(results.causalityEdges)
    csvPath = fullfile(exportDir, baseName + "_causality_edges.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.causalityEdges, csvPath, "causality_edges_csv");
end

if isfield(results, "causalitySnapshot") && istable(results.causalitySnapshot) && ~isempty(results.causalitySnapshot)
    csvPath = fullfile(exportDir, baseName + "_causality_snapshot.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.causalitySnapshot, csvPath, "causality_snapshot_csv");
end

if isfield(results, "apogeeSensitivity") && istable(results.apogeeSensitivity) && ~isempty(results.apogeeSensitivity)
    csvPath = fullfile(exportDir, baseName + "_apogee_sensitivity.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.apogeeSensitivity, csvPath, "apogee_sensitivity_csv");
end

if isfield(results, "attitude") && istable(results.attitude) && ~isempty(results.attitude)
    csvPath = fullfile(exportDir, baseName + "_attitude.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.attitude, csvPath, "attitude_csv");
end

if isfield(results, "replay") && istable(results.replay) && ~isempty(results.replay)
    csvPath = fullfile(exportDir, baseName + "_replay.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.replay, csvPath, "replay_csv");
end

if isfield(results, "parity") && istable(results.parity) && ~isempty(results.parity)
    csvPath = fullfile(exportDir, baseName + "_parity.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.parity, csvPath, "parity_csv");
end

if isfield(results, "fieldContract") && istable(results.fieldContract) && ~isempty(results.fieldContract)
    csvPath = fullfile(exportDir, baseName + "_field_contract.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.fieldContract, csvPath, "field_contract_csv");
end

if isfield(results, "validationSummary") && istable(results.validationSummary) && ~isempty(results.validationSummary)
    csvPath = fullfile(exportDir, baseName + "_validation_summary.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.validationSummary, csvPath, "validation_summary_csv");
end

if isfield(results, "est3d") && istable(results.est3d) && ~isempty(results.est3d)
    csvPath = fullfile(exportDir, baseName + "_est3d.csv");
    exportInfo = localWriteTableArtifact(exportInfo, results.est3d, csvPath, "est3d_csv");
end

if isfield(results, "wind") && isstruct(results.wind)
    csvPath = fullfile(exportDir, baseName + "_wind_summary.csv");
    windTable = struct2table(results.wind, "AsArray", true);
    exportInfo = localWriteTableArtifact(exportInfo, windTable, csvPath, "wind_summary_csv");
end

manifestPath = fullfile(exportDir, baseName + "_manifest.csv");
exportInfo.files.manifest_csv = manifestPath;
localWriteManifest(localBuildManifest(exportInfo), manifestPath);
exportInfo.manifest = localBuildManifest(exportInfo);
localWriteManifest(exportInfo.manifest, manifestPath);
end

function exportInfo = localExportFigureArray(exportInfo, figs, baseName, exportDir, prefix)
for k = 1:numel(figs)
    fig = figs(k);
    if ~isgraphics(fig)
        continue;
    end
    tag = prefix + "_" + string(k);
    pngPath = fullfile(exportDir, baseName + "_" + tag + ".png");
    pdfPath = fullfile(exportDir, baseName + "_" + tag + ".pdf");
    exportInfo = localExportFigureArtifact(exportInfo, fig, pngPath, "png", char(tag + "_png"));
    exportInfo = localExportFigureArtifact(exportInfo, fig, pdfPath, "pdf", char(tag + "_pdf"));
end
end

function exportInfo = localExportFigureArtifact(exportInfo, fig, outputPath, format, key)
[ok, note] = localExportFigure(fig, outputPath, format);
if ok
    exportInfo.files.(key) = outputPath;
    if note ~= ""
        exportInfo.warnings(end+1) = string(key) + ": " + note;
    end
else
    exportInfo.errors.(key) = note;
end
end

function exportInfo = localWriteTableArtifact(exportInfo, T, outputPath, key)
try
    writetable(T, outputPath);
    exportInfo.files.(key) = outputPath;
catch ME
    exportInfo.errors.(key) = string(ME.message);
end
end

function manifest = localBuildManifest(exportInfo)
fileKeys = string(fieldnames(exportInfo.files));
errorKeys = string(fieldnames(exportInfo.errors));
nRows = numel(fileKeys) + numel(errorKeys);
manifest = table('Size', [nRows 5], ...
    'VariableTypes', {'string','string','logical','double','string'}, ...
    'VariableNames', {'artifact','path','exists','bytes','status'});

row = 0;
for i = 1:numel(fileKeys)
    row = row + 1;
    key = fileKeys(i);
    pathValue = string(exportInfo.files.(char(key)));
    manifest.artifact(row) = key;
    manifest.path(row) = pathValue;
    manifest.exists(row) = isfile(pathValue);
    if manifest.exists(row)
        info = dir(char(pathValue));
        manifest.bytes(row) = info.bytes;
        manifest.status(row) = "written";
    else
        manifest.bytes(row) = NaN;
        manifest.status(row) = "missing";
    end
end

for i = 1:numel(errorKeys)
    row = row + 1;
    key = errorKeys(i);
    manifest.artifact(row) = key;
    manifest.path(row) = "";
    manifest.exists(row) = false;
    manifest.bytes(row) = NaN;
    manifest.status(row) = "error: " + string(exportInfo.errors.(char(key)));
end
end

function localWriteManifest(manifest, manifestPath)
try
    writetable(manifest, manifestPath);
catch ME
    error('caelum:exportFigures:ManifestWriteFailed', ...
        'Failed to write manifest %s: %s', manifestPath, ME.message);
end
end

function baseName = localBaseName(filename)
[~, name, ~] = fileparts(char(filename));
baseName = string(name);
baseName = regexprep(baseName, "[^a-zA-Z0-9_-]", "_");
end

function [ok, note] = localExportFigure(fig, outputPath, format)
ok = false;
note = "";

try
    switch format
        case "png"
            exportgraphics(fig, outputPath, "Resolution", 300);
        case "pdf"
            exportgraphics(fig, outputPath, "ContentType", "vector");
        otherwise
            error('caelum:exportFigures:UnsupportedFormat', ...
                'Unsupported export format: %s', format);
    end
    ok = true;
    return;
catch ME
    note = "exportgraphics failed, used fallback";
    try
        switch format
            case "png"
                print(fig, char(outputPath), "-dpng", "-r300");
            case "pdf"
                print(fig, char(outputPath), "-dpdf", "-painters");
        end
        ok = true;
        return;
    catch
        try
            saveas(fig, char(outputPath));
            ok = true;
            note = "exportgraphics/print failed, used saveas fallback";
            return;
        catch ME3
            note = string(ME.message) + " | fallback failed: " + string(ME3.message);
            ok = false;
        end
    end
end
end

function validation = validate_caelum_release(options)
%VALIDATE_CAELUM_RELEASE Run the release-facing vertical replay validation workflow.
arguments
    options.MakeDashboards (1,1) logical = true
    options.DashboardFixture (1,1) string = ""
    options.ExportDashboardFigures (1,1) logical = false
    options.DashboardExportDir (1,1) string = "exports/release_validation_dashboards"
end

addpath(genpath(fileparts(mfilename('fullpath'))));

fprintf('--- Caelum patched release validation ---\n');

releaseDashboard = localRenderReleaseDashboards(options);

try
    firmwareDashboardValidation = validate_firmware_dashboard_alignment();
    disp(firmwareDashboardValidation.reportTable(:, ["scope","check","passed","notes"]));

    verticalValidation = validate_vertical_replay_stack(RenderDiagnosticFigures=false);
    disp(verticalValidation.reportTable(:, ["caseName","modeName","check","passed","notes"]));

    irecMissionProfileValidation = validate_irec_mission_profile();
    disp(irecMissionProfileValidation.reportTable(:, ["scope","check","passed","notes"]));

    liveTelemetryValidation = validate_live_telemetry_import();
    disp(liveTelemetryValidation.reportTable(:, ["scope","check","passed","notes"]));
catch ME
    fprintf(2, 'Caelum release validation failed:\n%s\n', getReport(ME, 'extended'));
    rethrow(ME);
end

validation = verticalValidation;
validation.firmwareDashboardAlignment = firmwareDashboardValidation;
validation.irecMissionProfile = irecMissionProfileValidation;
validation.liveTelemetryImport = liveTelemetryValidation;
validation.overallPassed = firmwareDashboardValidation.overallPassed && ...
    verticalValidation.overallPassed && ...
    irecMissionProfileValidation.overallPassed && ...
    liveTelemetryValidation.overallPassed;

validation.dashboardResults = releaseDashboard.dashboardResults;
validation.dashboardFigure = releaseDashboard.dashboardFigure;
validation.auxiliaryDashboardFigure = releaseDashboard.auxiliaryDashboardFigure;
validation.dashboardRenderErrorIdentifier = releaseDashboard.errorIdentifier;
validation.dashboardRenderErrorMessage = releaseDashboard.errorMessage;

if localIsLiveFigure(validation.dashboardFigure) || localIsLiveFigure(validation.auxiliaryDashboardFigure)
    localShowFigure(validation.dashboardFigure);
    localShowFigure(validation.auxiliaryDashboardFigure);
    fprintf('--- Dashboard windows: main=%s | auxiliary=%s ---\n', ...
        localFigureStatus(validation.dashboardFigure), ...
        localFigureStatus(validation.auxiliaryDashboardFigure));
end

if validation.overallPassed
    fprintf('--- Validation passed ---\n');
else
    error('caelum:validate_caelum_release:ValidationFailed', ...
        'Caelum release validation reported one or more failures.');
end
end

function releaseDashboard = localRenderReleaseDashboards(options)
releaseDashboard = struct();
releaseDashboard.dashboardResults = struct();
releaseDashboard.dashboardFigure = gobjects(0, 1);
releaseDashboard.auxiliaryDashboardFigure = gobjects(0, 1);
releaseDashboard.errorIdentifier = "";
releaseDashboard.errorMessage = "";

if ~options.MakeDashboards
    return;
end

try
    dashboardFixture = localReleaseDashboardFixture(options.DashboardFixture);
    fprintf('--- Rendering release dashboard windows from %s ---\n', char(dashboardFixture));
    dashboardResults = caelum.analyzeLog(dashboardFixture, ...
        MakePlots=false, ...
        ReplayEstimator=true, ...
        MakeDashboard=true, ...
        MakeAuxiliaryDashboard=true, ...
        ExportFigures=options.ExportDashboardFigures, ...
        ExportDir=options.DashboardExportDir);
    releaseDashboard.dashboardResults = dashboardResults;
    releaseDashboard.dashboardFigure = dashboardResults.dashboardFigure;
    releaseDashboard.auxiliaryDashboardFigure = dashboardResults.auxiliaryDashboardFigure;

    if ~localIsLiveFigure(releaseDashboard.auxiliaryDashboardFigure)
        warning('caelum:validate_caelum_release:AuxiliaryDashboardMissing', ...
            'analyzeLog returned no live auxiliary dashboard figure; rendering it directly from dashboardResults.');
        releaseDashboard.auxiliaryDashboardFigure = caelum.plotAuxiliaryDashboard( ...
            dashboardResults.data, ...
            dashboardResults.events, ...
            dashboardResults.replay, ...
            dashboardResults.config, ...
            Est3D=dashboardResults.est3d);
        releaseDashboard.dashboardResults.auxiliaryDashboardFigure = releaseDashboard.auxiliaryDashboardFigure;
    end

    localShowFigure(releaseDashboard.dashboardFigure);
    localShowFigure(releaseDashboard.auxiliaryDashboardFigure);
    fprintf('--- Dashboard windows: main=%s | auxiliary=%s ---\n', ...
        localFigureStatus(releaseDashboard.dashboardFigure), ...
        localFigureStatus(releaseDashboard.auxiliaryDashboardFigure));
catch ME
    releaseDashboard.errorIdentifier = string(ME.identifier);
    releaseDashboard.errorMessage = string(ME.message);
    warning('caelum:validate_caelum_release:DashboardRenderFailed', ...
        'Release dashboard rendering failed before validation: %s', ME.message);
end
end

function fixture = localReleaseDashboardFixture(requestedFixture)
rootDir = fileparts(mfilename('fullpath'));

if strlength(requestedFixture) > 0
    candidate = requestedFixture;
    if ~isfile(candidate)
        candidate = string(fullfile(rootDir, requestedFixture));
    end
    if ~isfile(candidate)
        error('caelum:validate_caelum_release:DashboardFixtureMissing', ...
            'Requested dashboard fixture was not found: %s', char(requestedFixture));
    end
    fixture = candidate;
    return;
end

candidates = [ ...
    string(fullfile(rootDir, "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")); ...
    string(fullfile(rootDir, "Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")); ...
    string(fullfile(rootDir, "Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")); ...
    string(fullfile(rootDir, "Documents and Tools", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt"))];

for k = 1:numel(candidates)
    if isfile(candidates(k))
        fixture = candidates(k);
        return;
    end
end

error('caelum:validate_caelum_release:DashboardFixtureMissing', ...
    'No release dashboard fixture was found under %s.', rootDir);
end

function tf = localIsLiveFigure(fig)
tf = ~isempty(fig) && isscalar(fig) && isgraphics(fig, 'figure');
end

function localShowFigure(fig)
if ~localIsLiveFigure(fig)
    return;
end
try
    set(fig, 'Visible', 'on', 'WindowStyle', 'normal');
    figure(fig);
    shg;
    drawnow;
catch
end
end

function status = localFigureStatus(fig)
if localIsLiveFigure(fig)
    try
        status = sprintf('figure %d visible=%s', double(fig.Number), char(string(fig.Visible)));
    catch
        status = "live figure";
    end
else
    status = "missing";
end
end

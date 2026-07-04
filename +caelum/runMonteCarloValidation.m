function mc = runMonteCarloValidation(outputDir, options)
%RUNMONTECARLOVALIDATION Canonical V3 Monte Carlo validation with native GPS/3D support.
arguments
    outputDir (1,1) string = "mc_logs"
    options.NumRuns (1,1) double = 30
    options.MakePlots (1,1) logical = false
    options.MakeDashboard (1,1) logical = false
    options.SaveLogs (1,1) logical = true
    options.Seed (1,1) double = 100
end

if options.SaveLogs && ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

varNames = {'runIndex','success','status','logPath','rmse_pz','rmse_vz','gpsAcceptanceRate','windError','analysisTime_s'};
varTypes = {'double','logical','string','string','double','double','double','double','double'};
runMetrics = table('Size', [options.NumRuns numel(varNames)], 'VariableTypes', varTypes, 'VariableNames', varNames);

for k = 1:options.NumRuns
    file = fullfile(outputDir, sprintf('MC_LOG_%03d.csv', k));
    startedAt = tic;
    try
        [~, truth] = caelum.generateTruthAwareCaelumLogV2(file, seed=options.Seed + k - 1);
        results = caelum.analyzeLog(file, MakePlots=options.MakePlots, MakeDashboard=options.MakeDashboard);
        runMetrics.runIndex(k) = k;
        runMetrics.success(k) = true;
        runMetrics.status(k) = "ok";
        runMetrics.logPath(k) = string(file);

        if istable(results.est3d) && ~isempty(results.est3d)
            zErr = results.est3d.pz - truth.z_true;
            vzErr = results.est3d.vz - truth.v_true;
            runMetrics.rmse_pz(k) = sqrt(mean(zErr.^2, 'omitnan'));
            runMetrics.rmse_vz(k) = sqrt(mean(vzErr.^2, 'omitnan'));
            runMetrics.gpsAcceptanceRate(k) = mean(double(results.est3d.gps_used), 'omitnan');
            if isfield(results, 'wind') && isfield(results.wind, 'final')
                runMetrics.windError(k) = norm(results.wind.final - truth.wind_true(end,:));
            end
        end
    catch ME
        runMetrics.runIndex(k) = k;
        runMetrics.success(k) = false;
        runMetrics.status(k) = string(ME.identifier);
        runMetrics.logPath(k) = string(file);
    end
    runMetrics.analysisTime_s(k) = toc(startedAt);
    if ~options.SaveLogs && isfile(file)
        delete(file);
    end
end

mc = struct();
mc.outputDir = outputDir;
mc.runMetrics = runMetrics;
mc.aggregate = struct();
mc.aggregate.successRate = mean(double(runMetrics.success), 'omitnan');
mc.aggregate.mean_rmse_pz = mean(runMetrics.rmse_pz(runMetrics.success), 'omitnan');
mc.aggregate.mean_rmse_vz = mean(runMetrics.rmse_vz(runMetrics.success), 'omitnan');
mc.aggregate.mean_gps_acceptance_rate = mean(runMetrics.gpsAcceptanceRate(runMetrics.success), 'omitnan');
mc.aggregate.mean_wind_error = mean(runMetrics.windError(runMetrics.success), 'omitnan');
end

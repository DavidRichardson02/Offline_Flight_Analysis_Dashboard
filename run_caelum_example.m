function results = run_caelum_example(filename)
%RUN_CAELUM_EXAMPLE Example entry point for the canonical Caelum V3 package.

arguments
    filename (1,1) string = "Drop1.csv"
end

results = caelum.analyzeLog(filename, ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true, ...
    ExportFigures=true);

disp(results.summaryTable);

if isfield(results, "wind") && isstruct(results.wind)
    disp(results.wind);
end

if ~isempty(results.importReport)
    disp(results.importReport);
end
end

function exportSummary(results, filename)
%EXPORTSUMMARY Export summary table to CSV.

arguments
    results struct
    filename (1,1) string = "summary_metrics.csv"
end

if ~isfield(results, 'summaryTable') || isempty(results.summaryTable)
    error('caelum:exportSummary:NoSummary', 'results.summaryTable is missing or empty.');
end

writetable(results.summaryTable, filename);
end

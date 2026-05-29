function summaryTable = makeSummaryTable(summary)
%MAKESUMMARYTABLE Convert summary struct to a compact table.

arguments
    summary struct
end

names = string(fieldnames(summary));
values = cell(numel(names), 1);

for k = 1:numel(names)
    v = summary.(names(k));
    if isscalar(v) && (isnumeric(v) || islogical(v))
        values{k} = v;
    elseif isstring(v) || ischar(v)
        values{k} = string(v);
    else
        values{k} = string(mat2str(v));
    end
end

summaryTable = table(names, values, 'VariableNames', {'Metric','Value'});
end

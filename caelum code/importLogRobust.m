function [T, report] = importLogRobust(filename)
%IMPORTLOGROBUST Salvage import for damaged Caelum CSV files with canonical GPS support.
arguments
    filename (1,1) string
end

if ~isfile(filename)
    error('caelum:importLogRobust:FileNotFound', ...
        'File not found: %s', filename);
end

raw = readlines(filename);
raw = strip(raw);

report = struct();
report.importMode = "robust";
report.totalRawLines = numel(raw);
report.commentLinesRemoved = nnz(startsWith(raw, "#"));
report.emptyLinesRemoved = nnz(raw == "");
report.repeatedHeadersRemoved = 0;
report.droppedMalformedRows = 0;
report.validRowsImported = 0;
report.schemaMode = "dynamic";
report.gpsChannelsPresent = 0;

keep = raw ~= "" & ~startsWith(raw, "#");
raw = raw(keep);

if isempty(raw)
    error('caelum:importLogRobust:EmptyFile', ...
        'No usable lines found in %s', filename);
end

header = string(strip(split(raw(1), ","))).';
dataLines = raw(2:end);
isRepeatedHeader = dataLines == strjoin(header, ",");
report.repeatedHeadersRemoved = nnz(isRepeatedHeader);
dataLines = dataLines(~isRepeatedHeader);

nCols = numel(header);
parsed = nan(numel(dataLines), nCols);
goodRow = false(numel(dataLines), 1);

for i = 1:numel(dataLines)
    parts = string(strip(split(dataLines(i), ","))).';
    if numel(parts) ~= nCols
        report.droppedMalformedRows = report.droppedMalformedRows + 1;
        continue;
    end

    vals = nan(1, nCols);
    rowOk = true;
    for j = 1:nCols
        token = parts(j);
        if token == "" || strcmpi(token, "NaN")
            vals(j) = NaN;
            continue;
        end
        v = str2double(token);
        if isnan(v) && ~strcmpi(token, "NaN")
            rowOk = false;
            break;
        end
        vals(j) = v;
    end

    if rowOk
        parsed(i, :) = vals;
        goodRow(i) = true;
    else
        report.droppedMalformedRows = report.droppedMalformedRows + 1;
    end
end

parsed = parsed(goodRow, :);
report.validRowsImported = size(parsed, 1);

if isempty(parsed)
    error('caelum:importLogRobust:NoValidRows', ...
        'No valid numeric rows could be salvaged from %s', filename);
end

T = array2table(parsed, 'VariableNames', cellstr(header));

gpsSet = ["gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"];
vars = string(T.Properties.VariableNames);
for k = 1:numel(gpsSet)
    if ~ismember(gpsSet(k), vars)
        T.(char(gpsSet(k))) = nan(height(T), 1);
    end
end
report.gpsChannelsPresent = sum(ismember(gpsSet, vars));
end

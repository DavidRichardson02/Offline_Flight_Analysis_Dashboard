function buffer = appendLiveTelemetryBuffer(buffer, lines)
%APPENDLIVETELEMETRYBUFFER Append HDR/TLM serial lines to a live ring buffer.
%
% The parser is conservative by construction:
% - HDR defines the payload order.
% - TLM rows must match the active header width.
% - Non-numeric payloads are dropped and counted.
% - Nonmonotonic timestamps are dropped by default to preserve a time-ordered
%   buffer.
% - Capacity overflow drops the oldest accepted rows.
arguments
    buffer struct
    lines
end

buffer = localEnsureBuffer(buffer);
rawLines = strip(string(lines(:)));

for lineIdx = 1:numel(rawLines)
    line = rawLines(lineIdx);
    buffer.counters.totalLinesSeen = buffer.counters.totalLinesSeen + 1;

    if line == ""
        buffer.counters.emptyLinesSkipped = buffer.counters.emptyLinesSkipped + 1;
        continue;
    end

    if startsWith(line, "#")
        buffer.counters.commentLinesSkipped = buffer.counters.commentLinesSkipped + 1;
        continue;
    end

    parts = string(strip(split(line, ","))).';
    if isempty(parts)
        buffer.counters.emptyLinesSkipped = buffer.counters.emptyLinesSkipped + 1;
        continue;
    end

    tag = upper(parts(1));
    switch tag
        case "HDR"
            buffer = localAcceptHeader(buffer, parts(2:end));

        case "TLM"
            buffer = localAcceptTelemetryRow(buffer, parts(2:end));

        otherwise
            buffer.counters.ignoredNonTelemetryLines = buffer.counters.ignoredNonTelemetryLines + 1;
    end
end
end

function buffer = localEnsureBuffer(buffer)
if isfield(buffer, 'kind') && string(buffer.kind) == "caelum-live-telemetry-buffer"
    return;
end

error('caelum:appendLiveTelemetryBuffer:InvalidBuffer', ...
    'Buffer must be created with caelum.createLiveTelemetryBuffer.');
end

function buffer = localAcceptHeader(buffer, header)
buffer.counters.headerLinesSeen = buffer.counters.headerLinesSeen + 1;
[isValid, errorText] = localValidateHeader(header);
if ~isValid
    buffer.counters.invalidHeaders = buffer.counters.invalidHeaders + 1;
    buffer.counters.lastErrorMessage = errorText;
    return;
end

if isempty(buffer.header)
    buffer.header = header;
elseif isequal(buffer.header, header)
    buffer.counters.repeatedHeadersRemoved = buffer.counters.repeatedHeadersRemoved + 1;
elseif buffer.counters.acceptedRows == 0
    buffer.header = header;
    buffer.counters.headerChanges = buffer.counters.headerChanges + 1;
else
    buffer.counters.headerChanges = buffer.counters.headerChanges + 1;
    buffer.counters.rejectedHeaderChanges = buffer.counters.rejectedHeaderChanges + 1;
    buffer.counters.lastErrorMessage = ...
        "Rejected in-stream HDR change after telemetry rows were accepted.";
end
end

function buffer = localAcceptTelemetryRow(buffer, tokens)
buffer.counters.tlmLinesSeen = buffer.counters.tlmLinesSeen + 1;
if isempty(buffer.header)
    buffer.counters.droppedBeforeHeaderRows = buffer.counters.droppedBeforeHeaderRows + 1;
    return;
end

if numel(tokens) ~= numel(buffer.header)
    buffer.counters.droppedMalformedRows = buffer.counters.droppedMalformedRows + 1;
    return;
end

[values, rowOk] = localParseNumericRow(tokens);
if ~rowOk
    buffer.counters.droppedNonNumericRows = buffer.counters.droppedNonNumericRows + 1;
    return;
end

row = array2table(values, 'VariableNames', cellstr(buffer.header));
row = localAttachTimestampAlias(row);
row.host_rx_datenum = now;
row.host_line_seq = buffer.counters.totalLinesSeen;

if localIsNonmonotonic(buffer, row)
    buffer.counters.droppedNonmonotonicRows = buffer.counters.droppedNonmonotonicRows + 1;
    return;
end

buffer.raw = localAppendRow(buffer.raw, row);
buffer.counters.acceptedRows = buffer.counters.acceptedRows + 1;
buffer.lastAcceptedHostDatenum = row.host_rx_datenum(1);
if ismember("t_us", string(row.Properties.VariableNames)) && isfinite(row.t_us(1))
    buffer.lastAcceptedT_us = row.t_us(1);
end

buffer = localEnforceCapacity(buffer);
end

function [isValid, errorText] = localValidateHeader(header)
isValid = true;
errorText = "";

if isempty(header)
    isValid = false;
    errorText = "HDR record does not contain payload fields.";
    return;
end

if any(header == "")
    isValid = false;
    errorText = "HDR record contains an empty field name.";
    return;
end

validNames = string(matlab.lang.makeValidName(cellstr(header)));
if any(validNames ~= header)
    invalid = header(validNames ~= header);
    isValid = false;
    errorText = "HDR record contains invalid MATLAB field names: " + ...
        strjoin(cellstr(invalid), ", ");
    return;
end

if numel(unique(header, 'stable')) ~= numel(header)
    isValid = false;
    errorText = "HDR record contains duplicate field names.";
end
end

function [values, rowOk] = localParseNumericRow(tokens)
values = nan(1, numel(tokens));
rowOk = true;

for k = 1:numel(tokens)
    token = tokens(k);
    if token == "" || strcmpi(token, "NaN")
        values(k) = NaN;
        continue;
    end

    value = str2double(token);
    if isnan(value) && ~strcmpi(token, "NaN")
        rowOk = false;
        return;
    end
    values(k) = value;
end
end

function T = localAttachTimestampAlias(T)
vars = string(T.Properties.VariableNames);
if ismember("t_us", vars)
    return;
end

aliasNames = [ ...
    "time_us", ...
    "timestamp_us", ...
    "t_ms", ...
    "time_ms", ...
    "timestamp_ms", ...
    "t_s", ...
    "time_s", ...
    "timestamp_s", ...
    "t"];
aliasScales = [1.0, 1.0, 1000.0, 1000.0, 1000.0, 1.0e6, 1.0e6, 1.0e6, 1.0e6];

for k = 1:numel(aliasNames)
    name = aliasNames(k);
    if ismember(name, vars)
        T.t_us = T.(char(name)) .* aliasScales(k);
        return;
    end
end
end

function tf = localIsNonmonotonic(buffer, row)
tf = false;
if ~buffer.requireMonotonicTimestamps
    return;
end

rowVars = string(row.Properties.VariableNames);
if ~ismember("t_us", rowVars) || ~isfinite(row.t_us(1)) || ~isfinite(buffer.lastAcceptedT_us)
    return;
end

tf = row.t_us(1) <= buffer.lastAcceptedT_us;
end

function raw = localAppendRow(raw, row)
if isempty(raw)
    raw = row;
    return;
end

rawVars = string(raw.Properties.VariableNames);
rowVars = string(row.Properties.VariableNames);

for k = 1:numel(rowVars)
    name = rowVars(k);
    if ~ismember(name, rawVars)
        raw.(char(name)) = nan(height(raw), 1);
    end
end

rawVars = string(raw.Properties.VariableNames);
for k = 1:numel(rawVars)
    name = rawVars(k);
    if ~ismember(name, rowVars)
        row.(char(name)) = NaN;
    end
end

row = row(:, raw.Properties.VariableNames);
raw = [raw; row]; %#ok<AGROW>
end

function buffer = localEnforceCapacity(buffer)
overflow = height(buffer.raw) - buffer.capacity;
if overflow <= 0
    return;
end

buffer.raw = buffer.raw(overflow + 1:end, :);
buffer.counters.droppedRowsFromCapacity = ...
    buffer.counters.droppedRowsFromCapacity + overflow;
end

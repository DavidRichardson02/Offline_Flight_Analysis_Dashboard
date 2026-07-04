function [T, report] = importSerialTelemetry(source)
%IMPORTSERIALTELEMETRY Parse firmware HDR/TLM serial telemetry CSV streams.
%
% The firmware live stream is self-describing: an HDR record defines the field
% order, and subsequent TLM records carry numeric payloads in that exact order.
% This importer is deliberately header-driven so serial-only observability
% fields remain available to the dashboard instead of being down-converted to
% the SD logger schema. Malformed telemetry rows are counted and dropped rather
% than shifted into the wrong columns.
arguments
    source
end

[raw, sourceKind, sourceName] = localReadSource(source);
raw = strip(string(raw(:)));

report = struct();
report.importMode = "serial-telemetry";
report.sourceKind = sourceKind;
report.sourceName = sourceName;
report.totalRawLines = numel(raw);
report.commentLinesRemoved = nnz(startsWith(raw, "#"));
report.emptyLinesRemoved = nnz(raw == "");
report.ignoredNonTelemetryLines = 0;
report.headersSeen = 0;
report.repeatedHeadersRemoved = 0;
report.headerChanges = 0;
report.tlmLinesSeen = 0;
report.droppedBeforeHeaderRows = 0;
report.droppedMalformedRows = 0;
report.droppedNonNumericRows = 0;
report.validRowsImported = 0;
report.schemaMode = "serial-telemetry";
report.serialRecordWidth = 0;
report.serialPayloadFields = 0;
report.header = strings(1, 0);

usable = raw ~= "" & ~startsWith(raw, "#");
lines = raw(usable);

header = strings(1, 0);
rowValues = cell(0, 1);
dataAcceptedUnderHeader = false;

for lineIdx = 1:numel(lines)
    parts = string(strip(split(lines(lineIdx), ","))).';
    if isempty(parts)
        continue;
    end

    tag = upper(parts(1));
    switch tag
        case "HDR"
            report.headersSeen = report.headersSeen + 1;
            nextHeader = localValidateHeader(parts(2:end), lineIdx);

            if isempty(header)
                header = nextHeader;
                dataAcceptedUnderHeader = false;
            elseif isequal(header, nextHeader)
                report.repeatedHeadersRemoved = report.repeatedHeadersRemoved + 1;
            elseif dataAcceptedUnderHeader
                error('caelum:importSerialTelemetry:HeaderChangedAfterData', ...
                    ['Serial telemetry header changed after data rows were accepted. ' ...
                     'A live dashboard cannot preserve column meaning across an in-stream schema change.']);
            else
                report.headerChanges = report.headerChanges + 1;
                header = nextHeader;
            end

        case "TLM"
            report.tlmLinesSeen = report.tlmLinesSeen + 1;
            if isempty(header)
                report.droppedBeforeHeaderRows = report.droppedBeforeHeaderRows + 1;
                continue;
            end

            tokens = parts(2:end);
            if numel(tokens) ~= numel(header)
                report.droppedMalformedRows = report.droppedMalformedRows + 1;
                continue;
            end

            [values, rowOk] = localParseNumericRow(tokens);
            if ~rowOk
                report.droppedNonNumericRows = report.droppedNonNumericRows + 1;
                continue;
            end

            rowValues{end + 1, 1} = values; %#ok<AGROW>
            dataAcceptedUnderHeader = true;

        otherwise
            report.ignoredNonTelemetryLines = report.ignoredNonTelemetryLines + 1;
    end
end

if isempty(header)
    error('caelum:importSerialTelemetry:MissingHeader', ...
        'No HDR record was found in the serial telemetry source.');
end

if isempty(rowValues)
    error('caelum:importSerialTelemetry:NoValidRows', ...
        'No valid TLM rows were parsed from the serial telemetry source.');
end

parsed = vertcat(rowValues{:});
T = array2table(parsed, 'VariableNames', cellstr(header));
T = localAttachTimestampAlias(T);

report.validRowsImported = height(T);
report.serialRecordWidth = numel(header) + 1;
report.serialPayloadFields = numel(header);
report.header = header;
report.schemaMode = localSchemaMode(T);
end

function [raw, sourceKind, sourceName] = localReadSource(source)
sourceKind = "lines";
sourceName = "";

if isstring(source) && isscalar(source)
    if isfile(source)
        raw = readlines(source);
        sourceKind = "file";
        sourceName = source;
    else
        raw = splitlines(source);
        sourceKind = "text";
    end
elseif ischar(source)
    sourceText = string(source);
    if isfile(sourceText)
        raw = readlines(sourceText);
        sourceKind = "file";
        sourceName = sourceText;
    else
        raw = splitlines(sourceText);
        sourceKind = "text";
    end
elseif isstring(source)
    raw = source(:);
elseif iscellstr(source)
    raw = string(source(:));
else
    error('caelum:importSerialTelemetry:InvalidSource', ...
        'Source must be a filename, text block, string array, or cell array of character vectors.');
end
end

function header = localValidateHeader(header, lineIdx)
if isempty(header)
    error('caelum:importSerialTelemetry:EmptyHeader', ...
        'HDR record on parsed line %d does not contain payload fields.', lineIdx);
end

if any(header == "")
    error('caelum:importSerialTelemetry:EmptyHeaderField', ...
        'HDR record on parsed line %d contains an empty field name.', lineIdx);
end

validNames = string(matlab.lang.makeValidName(cellstr(header)));
if any(validNames ~= header)
    invalid = header(validNames ~= header);
    error('caelum:importSerialTelemetry:InvalidHeaderField', ...
        'HDR record contains field names that are not valid MATLAB identifiers: %s', ...
        strjoin(cellstr(invalid), ', '));
end

if numel(unique(header, 'stable')) ~= numel(header)
    error('caelum:importSerialTelemetry:DuplicateHeaderField', ...
        'HDR record contains duplicate field names.');
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

function mode = localSchemaMode(T)
vars = string(T.Properties.VariableNames);
latestSdSchema = string(caelum.getFirmwareSdlogSchema().field).';
latestSerialSchema = string(caelum.getFirmwareSerialTelemetrySchema().field).';

if all(ismember(latestSerialSchema, vars))
    mode = "latest-firmware-serial";
elseif all(ismember(latestSdSchema, vars))
    if numel(vars) > numel(latestSdSchema)
        mode = "latest-firmware-sd-plus-serial-extras";
    else
        mode = "latest-firmware-sd-compatible-serial";
    end
else
    mode = "serial-telemetry-dynamic";
end
end

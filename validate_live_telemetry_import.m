function validation = validate_live_telemetry_import(options)
%VALIDATE_LIVE_TELEMETRY_IMPORT Validate firmware HDR/TLM parsing and buffering.
%
% This check consumes a Serial-style fixture whose HDR payload matches
% telemetry_print_header(). It proves that the live-ingest boundary preserves
% firmware field order, normalizes abbreviated update metadata, retains phase
% and policy observability fields, counts malformed rows, and feeds the existing
% schema-alignment and clean-log stages.
arguments
    options.SourcePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
    options.NumericTolerance (1,1) double = 1e-9
end

addpath(genpath(fileparts(mfilename('fullpath'))));

if ~isfile(options.SourcePath)
    error('validate_live_telemetry_import:MissingFixture', ...
        'Fixture not found: %s', options.SourcePath);
end

raw = strip(readlines(options.SourcePath));
raw = raw(raw ~= "");
usable = raw(~startsWith(raw, "#"));
if numel(usable) < 2
    error('validate_live_telemetry_import:EmptyFixture', ...
        'Fixture does not contain an HDR line and at least one TLM row: %s', options.SourcePath);
end

headerLines = usable(startsWith(usable, "HDR,"));
if isempty(headerLines)
    error('validate_live_telemetry_import:MissingHeader', ...
        'Fixture does not contain an HDR line: %s', options.SourcePath);
end

headerLine = erase(headerLines(1), "HDR,");
expectedFields = string(split(headerLine, ",")).';
expectedValidRows = localCountValidTelemetryRows(usable, numel(expectedFields));

[T, importReport] = caelum.importSerialTelemetry(raw);
cfg = caelum.defaultConfig();
aligned = caelum.alignImportedSchema(T, cfg);
[clean, cleanReport] = caelum.cleanLog(aligned, cfg);

tlmLines = usable(startsWith(usable, "TLM,"));
bufferCapacity = min(120, expectedValidRows);
ringLines = [raw; tlmLines(1)];
buffer = caelum.createLiveTelemetryBuffer(Capacity=bufferCapacity, Config=cfg);
buffer = caelum.appendLiveTelemetryBuffer(buffer, ringLines);
[bufferSnapshot, bufferReport, buffer] = caelum.snapshotLiveTelemetryBuffer(buffer, Config=cfg);

reportTable = localEmptyValidationTable();

reportTable = [reportTable; localValidationRow("parser", "valid_rows_imported", ...
    importReport.validRowsImported == expectedValidRows, ...
    string(importReport.validRowsImported), string(expectedValidRows), "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("parser", "repeated_header_counted", ...
    importReport.repeatedHeadersRemoved == max(0, numel(headerLines) - 1), ...
    string(importReport.repeatedHeadersRemoved), string(max(0, numel(headerLines) - 1)), "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("parser", "malformed_tlm_counted", ...
    importReport.droppedMalformedRows >= 1, string(importReport.droppedMalformedRows), ">=1", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("parser", "status_line_ignored", ...
    importReport.ignoredNonTelemetryLines >= 1, string(importReport.ignoredNonTelemetryLines), ">=1", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("parser", "schema_mode_latest_serial", ...
    string(importReport.schemaMode) == "latest-firmware-serial", ...
    string(importReport.schemaMode), "latest-firmware-serial", "")]; %#ok<AGROW>

actualFields = string(T.Properties.VariableNames);
payloadFields = actualFields(1:numel(expectedFields));
fieldOrderPreserved = isequal(payloadFields, expectedFields);
reportTable = [reportTable; localValidationRow("schema", "hdr_field_order_preserved", ...
    fieldOrderPreserved, localJoin(payloadFields), localJoin(expectedFields), "")]; %#ok<AGROW>

standardMetadataFields = [ ...
    "baro_updated", ...
    "imu_updated", ...
    "aux_updated", ...
    "att_updated", ...
    "auxvz_updated", ...
    "est_updated"];
missingMetadataAliases = setdiff(standardMetadataFields, string(aligned.Properties.VariableNames));
reportTable = [reportTable; localValidationRow("schema", "serial_update_aliases_normalized", ...
    isempty(missingMetadataAliases), localMissingString(missingMetadataAliases), "none_missing", "")]; %#ok<AGROW>

diagFields = [ ...
    "phase_diag_valid", ...
    "phase_diag_updated", ...
    "phase_diag_seq", ...
    "phase_diag_t_ms", ...
    "phase_diag_age_ms", ...
    "phase_launch_latched", ...
    "phase_burnout_latched", ...
    "phase_descent_latched", ...
    "policy_valid", ...
    "policy_cmd", ...
    "target_nominal", ...
    "target_effective", ...
    "uncertainty_margin", ...
    "warn_mask"];
missingDiag = setdiff(diagFields, string(clean.Properties.VariableNames));
reportTable = [reportTable; localValidationRow("schema", "phase_policy_observability_present", ...
    isempty(missingDiag), localMissingString(missingDiag), "none_missing", "")]; %#ok<AGROW>

reportTable = [reportTable; localValidationRow("cleaning", "clean_log_completed", ...
    height(clean) == expectedValidRows, string(height(clean)), string(expectedValidRows), ...
    "duplicate/nonmonotonic removal was not expected for this synthetic capture.")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("cleaning", "no_timestamp_rows_removed", ...
    cleanReport.rowsRemovedMissingTimestamp == 0, string(cleanReport.rowsRemovedMissingTimestamp), "0", "")]; %#ok<AGROW>

reportTable = [reportTable; localValidationRow("ring_buffer", "accepted_rows_counted", ...
    bufferReport.acceptedRows == expectedValidRows, string(bufferReport.acceptedRows), string(expectedValidRows), "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("ring_buffer", "nonmonotonic_row_dropped", ...
    bufferReport.droppedNonmonotonicRows == 1, string(bufferReport.droppedNonmonotonicRows), "1", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("ring_buffer", "capacity_overflow_counted", ...
    bufferReport.droppedRowsFromCapacity == max(0, expectedValidRows - bufferCapacity), ...
    string(bufferReport.droppedRowsFromCapacity), string(max(0, expectedValidRows - bufferCapacity)), "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("ring_buffer", "snapshot_capacity_bounded", ...
    height(bufferSnapshot) == bufferCapacity, string(height(bufferSnapshot)), string(bufferCapacity), "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("ring_buffer", "snapshot_phase_policy_present", ...
    all(ismember(["phase","policy_cmd","phase_diag_valid","target_effective"], string(bufferSnapshot.Properties.VariableNames))), ...
    localMissingString(setdiff(["phase","policy_cmd","phase_diag_valid","target_effective"], string(bufferSnapshot.Properties.VariableNames))), ...
    "none_missing", "")]; %#ok<AGROW>

compareFields = ["t_us","phase_diag_seq","phase","policy_cmd","target_effective","warn_mask"];
for k = 1:numel(compareFields)
    fieldName = compareFields(k);
    if ~ismember(fieldName, string(T.Properties.VariableNames)) || ...
            ~ismember(fieldName, string(bufferSnapshot.Properties.VariableNames))
        reportTable = [reportTable; localValidationRow("parity", "buffer_preserves_" + fieldName, ...
            false, "missing_field", "<=" + string(options.NumericTolerance), "")]; %#ok<AGROW>
        continue;
    end

    tail = T(end - height(bufferSnapshot) + 1:end, :);
    diffValue = max(abs(tail.(char(fieldName)) - bufferSnapshot.(char(fieldName))), [], 'omitnan');
    passed = isfinite(diffValue) && diffValue <= options.NumericTolerance;
    reportTable = [reportTable; localValidationRow("parity", "buffer_preserves_" + fieldName, ...
        passed, string(diffValue), "<=" + string(options.NumericTolerance), "")]; %#ok<AGROW>
end

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.sourcePath = options.SourcePath;
validation.importReport = importReport;
validation.cleanReport = cleanReport;
validation.buffer = buffer;
validation.bufferReport = bufferReport;
validation.reportTable = reportTable;
validation.overallPassed = all(reportTable.passed);

disp(reportTable(:, ["scope","check","passed","actual","expected","notes"]));
if validation.overallPassed
    fprintf('Live telemetry import validation passed.\n');
else
    fprintf(2, 'Live telemetry import validation reported failures.\n');
end
end

function count = localCountValidTelemetryRows(lines, expectedWidth)
count = 0;
for k = 1:numel(lines)
    line = lines(k);
    if ~startsWith(line, "TLM,")
        continue;
    end

    tokens = string(strip(split(line, ","))).';
    payload = tokens(2:end);
    if numel(payload) ~= expectedWidth
        continue;
    end

    rowOk = true;
    for j = 1:numel(payload)
        token = payload(j);
        if token == "" || strcmpi(token, "NaN")
            continue;
        end
        value = str2double(token);
        if isnan(value) && ~strcmpi(token, "NaN")
            rowOk = false;
            break;
        end
    end
    if rowOk
        count = count + 1;
    end
end
end

function rows = localEmptyValidationTable()
rows = table('Size', [0 6], ...
    'VariableTypes', {'string','string','logical','string','string','string'}, ...
    'VariableNames', {'scope','check','passed','actual','expected','notes'});
end

function row = localValidationRow(scope, check, passed, actual, expected, notes)
row = table(string(scope), string(check), logical(passed), ...
    string(actual), string(expected), string(notes), ...
    'VariableNames', {'scope','check','passed','actual','expected','notes'});
end

function text = localJoin(values)
if isempty(values)
    text = "";
else
    text = strjoin(cellstr(values), ",");
end
end

function text = localMissingString(missing)
if isempty(missing)
    text = "none_missing";
else
    text = strjoin(cellstr(missing), ",");
end
end

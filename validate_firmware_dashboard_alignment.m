function validation = validate_firmware_dashboard_alignment(options)
%VALIDATE_FIRMWARE_DASHBOARD_ALIGNMENT Validate MATLAB contracts against firmware sources.
%
% This gate treats the Arduino firmware headers as the source of truth for the
% dashboard import contracts. It checks the checked-in schema files, synthetic
% SD and Serial fixtures, Serial metadata aliases, and the deliberate separation
% between firmware policy target and IREC scoring target.
arguments
    options.FirmwareRoot (1,1) string = "/Users/98dav/MATLAB/Projects/Offline_Flight_Analysis_Dashboard/CaelumSufflamen"
    options.SdFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv")
    options.SerialFixturePath (1,1) string = fullfile("Flight Data", "Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt")
end

addpath(genpath(fileparts(mfilename('fullpath'))));

sdLoggerPath = fullfile(options.FirmwareRoot, "sd_logger.cpp");
telemetryPath = fullfile(options.FirmwareRoot, "telemetry.cpp");
configPath = fullfile(options.FirmwareRoot, "config.h");

sdSchema = caelum.getFirmwareSdlogSchema();
serialSchema = caelum.getFirmwareSerialTelemetrySchema();

firmwareSdFields = localExtractSdHeaderFields(sdLoggerPath);
[firmwareSerialFields, serialTag] = localExtractSerialHeaderFields(telemetryPath);

reportTable = localEmptyValidationTable();

sdSchemaFields = string(sdSchema.field).';
serialSchemaFields = string(serialSchema.field).';

reportTable = [reportTable; localValidationRow("schema", "sd_contract_matches_firmware_header", ...
    isequal(sdSchemaFields, firmwareSdFields), ...
    localSchemaSummary(sdSchemaFields, firmwareSdFields), "exact_order_match", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("schema", "sd_contract_field_count", ...
    numel(sdSchemaFields) == 79, string(numel(sdSchemaFields)), "79", "")]; %#ok<AGROW>

reportTable = [reportTable; localValidationRow("schema", "serial_header_tag_is_hdr", ...
    serialTag == "HDR", serialTag, "HDR", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("schema", "serial_contract_matches_firmware_header", ...
    isequal(serialSchemaFields, firmwareSerialFields), ...
    localSchemaSummary(serialSchemaFields, firmwareSerialFields), "exact_order_match", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("schema", "serial_contract_field_count", ...
    numel(serialSchemaFields) == 76, string(numel(serialSchemaFields)), "76", "")]; %#ok<AGROW>

[sdHeader, sdLineCount] = localReadCsvHeader(options.SdFixturePath);
sdPrefixOk = numel(sdHeader) >= numel(sdSchemaFields) && ...
    isequal(sdHeader(1:numel(sdSchemaFields)), sdSchemaFields);
gpsExtras = ["gps_x","gps_y","gps_z","gps_vx","gps_vy","gps_vz"];
sdExtras = sdHeader(numel(sdSchemaFields) + 1:end);
reportTable = [reportTable; localValidationRow("fixture", "sd_fixture_prefix_matches_contract", ...
    sdPrefixOk, localSchemaSummary(sdHeader(1:min(numel(sdHeader), numel(sdSchemaFields))), sdSchemaFields), ...
    "sd_schema_prefix", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("fixture", "sd_fixture_gps_extras_present", ...
    isequal(sdExtras, gpsExtras), localJoin(sdExtras), localJoin(gpsExtras), "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("fixture", "sd_fixture_has_rows", ...
    sdLineCount > 1, string(max(0, sdLineCount - 1)), ">0", "")]; %#ok<AGROW>

[Tsd, sdImportReport] = caelum.importLog(options.SdFixturePath);
alignedSd = caelum.alignImportedSchema(Tsd, caelum.defaultConfig());
[cleanSd, cleanSdReport] = caelum.cleanLog(alignedSd, caelum.defaultConfig());
reportTable = [reportTable; localValidationRow("import", "sd_import_schema_mode", ...
    string(sdImportReport.schemaMode) == "latest-firmware-sd", ...
    string(sdImportReport.schemaMode), "latest-firmware-sd", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("import", "sd_clean_log_completed", ...
    height(cleanSd) > 0 && cleanSdReport.rowsRemovedMissingTimestamp == 0, ...
    "rows=" + string(height(cleanSd)) + ";missing_t=" + string(cleanSdReport.rowsRemovedMissingTimestamp), ...
    "rows>0;missing_t=0", "")]; %#ok<AGROW>

[serialHeader, serialLineCount] = localReadSerialHeader(options.SerialFixturePath);
reportTable = [reportTable; localValidationRow("fixture", "serial_fixture_matches_contract", ...
    isequal(serialHeader, serialSchemaFields), localSchemaSummary(serialHeader, serialSchemaFields), ...
    "exact_order_match", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("fixture", "serial_fixture_has_rows", ...
    serialLineCount > 1, string(max(0, serialLineCount - 1)), ">0", "")]; %#ok<AGROW>

[Tserial, serialImportReport] = caelum.importSerialTelemetry(options.SerialFixturePath);
alignedSerial = caelum.alignImportedSchema(Tserial, caelum.defaultConfig());
[cleanSerial, cleanSerialReport] = caelum.cleanLog(alignedSerial, caelum.defaultConfig());
reportTable = [reportTable; localValidationRow("import", "serial_import_schema_mode", ...
    string(serialImportReport.schemaMode) == "latest-firmware-serial", ...
    string(serialImportReport.schemaMode), "latest-firmware-serial", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("import", "serial_aliases_normalized", ...
    all(ismember(["baro_updated","imu_updated","aux_updated","att_updated","auxvz_updated","est_updated"], ...
        string(alignedSerial.Properties.VariableNames))), ...
    localMissingString(setdiff(["baro_updated","imu_updated","aux_updated","att_updated","auxvz_updated","est_updated"], ...
        string(alignedSerial.Properties.VariableNames))), "none_missing", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("import", "serial_clean_log_completed", ...
    height(cleanSerial) > 0 && cleanSerialReport.rowsRemovedMissingTimestamp == 0, ...
    "rows=" + string(height(cleanSerial)) + ";missing_t=" + string(cleanSerialReport.rowsRemovedMissingTimestamp), ...
    "rows>0;missing_t=0", "")]; %#ok<AGROW>

serialLines = strip(readlines(options.SerialFixturePath));
serialLines = serialLines(serialLines ~= "");
buffer = caelum.createLiveTelemetryBuffer(Capacity=120, Config=caelum.defaultConfig());
buffer = caelum.appendLiveTelemetryBuffer(buffer, serialLines);
[bufferSnapshot, bufferReport] = caelum.snapshotLiveTelemetryBuffer(buffer, Config=caelum.defaultConfig());
reportTable = [reportTable; localValidationRow("live_buffer", "serial_buffer_snapshot_completed", ...
    height(bufferSnapshot) > 0 && bufferReport.acceptedRows == serialImportReport.validRowsImported, ...
    "snapshot_rows=" + string(height(bufferSnapshot)) + ";accepted=" + string(bufferReport.acceptedRows), ...
    "snapshot_rows>0;accepted=valid_rows", "")]; %#ok<AGROW>

firmwarePolicyTarget_m = localExtractFirmwarePolicyTarget(configPath);
mission = caelum.irecMissionProfile(TargetApogee_ft=10000);
reportTable = [reportTable; localValidationRow("target_semantics", "firmware_policy_target_detected", ...
    isfinite(firmwarePolicyTarget_m), string(firmwarePolicyTarget_m), "finite", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("target_semantics", "mission_scoring_target_detected", ...
    isfinite(mission.targetApogee_m) && abs(mission.targetApogee_m - 3048.0) < 1e-9, ...
    string(mission.targetApogee_m), "3048.0", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("target_semantics", "firmware_target_matches_irec_10k", ...
    isfinite(firmwarePolicyTarget_m) && abs(firmwarePolicyTarget_m - mission.targetApogee_m) < 1e-6, ...
    "firmware=" + string(firmwarePolicyTarget_m) + ";mission=" + string(mission.targetApogee_m), ...
    "3048.0", ...
    "Firmware control target is deliberately aligned to the IREC 10,000 ft mission.")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("target_semantics", "targets_reported_separately", ...
    isfinite(firmwarePolicyTarget_m) && isfinite(mission.targetApogee_m), ...
    "firmware=" + string(firmwarePolicyTarget_m) + ";mission=" + string(mission.targetApogee_m), ...
    "separate_fields", ...
    "The numeric targets now match, but recorded firmware target and scoring target remain distinct evidence fields.")]; %#ok<AGROW>

requiredTargetFields = ["target_apogee","target_nominal","target_effective","uncertainty_margin"];
reportTable = [reportTable; localValidationRow("target_semantics", "sd_target_fields_present", ...
    all(ismember(requiredTargetFields, string(cleanSd.Properties.VariableNames))), ...
    localMissingString(setdiff(requiredTargetFields, string(cleanSd.Properties.VariableNames))), ...
    "none_missing", "")]; %#ok<AGROW>
reportTable = [reportTable; localValidationRow("target_semantics", "serial_target_fields_present", ...
    all(ismember(requiredTargetFields, string(cleanSerial.Properties.VariableNames))), ...
    localMissingString(setdiff(requiredTargetFields, string(cleanSerial.Properties.VariableNames))), ...
    "none_missing", "")]; %#ok<AGROW>

validation = struct();
validation.generatedAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
validation.firmwareRoot = options.FirmwareRoot;
validation.sdFixturePath = options.SdFixturePath;
validation.serialFixturePath = options.SerialFixturePath;
validation.firmwarePolicyTarget_m = firmwarePolicyTarget_m;
validation.missionTargetApogee_m = mission.targetApogee_m;
validation.reportTable = reportTable;
validation.overallPassed = all(reportTable.passed);

disp(reportTable(:, ["scope","check","passed","actual","expected","notes"]));
if validation.overallPassed
    fprintf('Firmware/dashboard alignment validation passed.\n');
else
    fprintf(2, 'Firmware/dashboard alignment validation reported failures.\n');
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

function fields = localExtractSdHeaderFields(sourcePath)
sourceText = fileread(sourcePath);
tokens = regexp(sourceText, ...
    '(?s)static\s+void\s+sd_write_header\(File\s*&f\)\s*\{.*?f\.println\(\s*(.*?)\s*\);\s*\}', ...
    'tokens', 'once');
if isempty(tokens)
    error('validate_firmware_dashboard_alignment:MissingSdHeader', ...
        'Could not extract SD header from %s.', sourcePath);
end
fields = string(split(localJoinStringLiterals(tokens{1}), ",")).';
end

function [fields, tag] = localExtractSerialHeaderFields(sourcePath)
sourceText = fileread(sourcePath);
tokens = regexp(sourceText, ...
    '(?s)void\s+telemetry_print_header\(void\)\s*\{.*?Serial\.println\(\s*F\(\s*(.*?)\s*\)\s*\);\s*\}', ...
    'tokens', 'once');
if isempty(tokens)
    error('validate_firmware_dashboard_alignment:MissingSerialHeader', ...
        'Could not extract Serial telemetry header from %s.', sourcePath);
end
headerTokens = string(split(localJoinStringLiterals(tokens{1}), ",")).';
tag = headerTokens(1);
fields = headerTokens(2:end);
end

function text = localJoinStringLiterals(block)
parts = regexp(block, '"([^"]*)"', 'tokens');
if isempty(parts)
    error('validate_firmware_dashboard_alignment:MissingStringLiteral', ...
        'Could not extract string literals from firmware header block.');
end
literalStrings = strings(1, numel(parts));
for k = 1:numel(parts)
    literalStrings(k) = string(parts{k}{1});
end
text = strjoin(literalStrings, "");
end

function [header, lineCount] = localReadCsvHeader(filename)
if ~isfile(filename)
    error('validate_firmware_dashboard_alignment:MissingFixture', ...
        'Fixture file not found: %s.', filename);
end
raw = strip(readlines(filename));
raw = raw(raw ~= "" & ~startsWith(raw, "#"));
if isempty(raw)
    error('validate_firmware_dashboard_alignment:EmptyFixture', ...
        'Fixture file has no usable lines: %s.', filename);
end
header = string(split(raw(1), ",")).';
lineCount = numel(raw);
end

function [header, lineCount] = localReadSerialHeader(filename)
if ~isfile(filename)
    error('validate_firmware_dashboard_alignment:MissingSerialFixture', ...
        'Serial fixture file not found: %s.', filename);
end
raw = strip(readlines(filename));
raw = raw(raw ~= "" & ~startsWith(raw, "#"));
headerLine = raw(startsWith(raw, "HDR,"));
if isempty(headerLine)
    error('validate_firmware_dashboard_alignment:MissingSerialFixtureHeader', ...
        'Serial fixture does not contain an HDR line: %s.', filename);
end
tokens = string(split(headerLine(1), ",")).';
header = tokens(2:end);
lineCount = numel(raw);
end

function value = localExtractFirmwarePolicyTarget(configPath)
sourceText = fileread(configPath);
tokens = regexp(sourceText, ...
    'POLICY_TARGET_APOGEE_M\s*=\s*([0-9.+\-eEfF]+)', ...
    'tokens', 'once');
if isempty(tokens)
    value = NaN;
    return;
end
valueText = erase(string(tokens{1}), ["f","F"]);
value = str2double(valueText);
end

function text = localSchemaSummary(actual, expected)
if isequal(actual, expected)
    text = "count=" + string(numel(actual)) + ";order=match";
    return;
end
missing = setdiff(expected, actual, 'stable');
extra = setdiff(actual, expected, 'stable');
firstMismatch = "";
limit = min(numel(actual), numel(expected));
for k = 1:limit
    if actual(k) ~= expected(k)
        firstMismatch = "index " + string(k) + ": actual=" + actual(k) + ";expected=" + expected(k);
        break;
    end
end
if firstMismatch == "" && numel(actual) ~= numel(expected)
    firstMismatch = "length actual=" + string(numel(actual)) + ";expected=" + string(numel(expected));
end
text = "missing=" + localMissingString(missing) + ...
    ";extra=" + localMissingString(extra) + ...
    ";first_mismatch=" + firstMismatch;
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

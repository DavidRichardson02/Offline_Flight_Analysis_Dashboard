function audit = buildTelemetryFreshnessAudit(T, options)
%BUILDTELEMETRYFRESHNESSAUDIT Derive source freshness/provenance evidence.
%
% The output is a long table: each row is one source domain at one sample.
% Status labels are display evidence derived from telemetry validity, update,
% sequence, age, and warning fields; they do not replace firmware state.
arguments
    T table
    options.Report struct = struct()
    options.MaxAge_ms (1,1) double = 500
end

n = height(T);
vars = string(T.Properties.VariableNames);
t = localColumn(T, vars, "t", n, NaN);
sampleIndex = (1:n).';

domains = localDomainDefinitions();
audit = table();

for k = 1:numel(domains)
    domain = domains(k);
    row = table();
    row.sample_index = sampleIndex;
    row.t = t;
    row.source = repmat(domain.name, n, 1);
    row.source_label = repmat(domain.label, n, 1);

    [validFlag, hasValid] = localOptionalLogical(T, vars, domain.validField, n);
    [updatedFlag, hasUpdated] = localOptionalLogical(T, vars, domain.updatedField, n);
    [seqValue, hasSeq] = localOptionalNumeric(T, vars, domain.seqField, n);
    [ageMs, hasAge] = localOptionalNumeric(T, vars, domain.ageField, n);

    row.valid = validFlag;
    row.updated = updatedFlag;
    row.seq = seqValue;
    row.seq_delta = localSeqDelta(seqValue);
    row.seq_changed = isfinite(row.seq_delta) & row.seq_delta > 0;
    row.age_ms = ageMs;
    row.has_valid_field = repmat(hasValid, n, 1);
    row.has_updated_field = repmat(hasUpdated, n, 1);
    row.has_seq_field = repmat(hasSeq, n, 1);
    row.has_age_field = repmat(hasAge, n, 1);
    row.warn_mask = localColumn(T, vars, "warn_mask", n, NaN);

    [row.status_code, row.status_label, row.status_rationale] = ...
        localClassifyStatus(row, domain, hasValid, hasUpdated, hasSeq, hasAge, options.MaxAge_ms);

    audit = [audit; row]; %#ok<AGROW>
end

acceptedRows = localReportValue(options.Report, "acceptedRows", NaN);
if ~isfinite(acceptedRows)
    acceptedRows = localReportValue(options.Report, "validRowsImported", NaN);
end

audit.report_total_lines_seen = repmat(localReportValue(options.Report, "totalLinesSeen", NaN), height(audit), 1);
audit.report_accepted_rows = repmat(acceptedRows, height(audit), 1);
audit.report_dropped_malformed_rows = repmat(localReportValue(options.Report, "droppedMalformedRows", NaN), height(audit), 1);
audit.report_dropped_non_numeric_rows = repmat(localReportValue(options.Report, "droppedNonNumericRows", NaN), height(audit), 1);
audit.report_dropped_nonmonotonic_rows = repmat(localReportValue(options.Report, "droppedNonmonotonicRows", NaN), height(audit), 1);
audit.report_dropped_capacity_rows = repmat(localReportValue(options.Report, "droppedRowsFromCapacity", NaN), height(audit), 1);
audit.report_ignored_nontelemetry_lines = repmat(localReportValue(options.Report, "ignoredNonTelemetryLines", NaN), height(audit), 1);
audit.report_repeated_headers_removed = repmat(localReportValue(options.Report, "repeatedHeadersRemoved", NaN), height(audit), 1);
audit.report_snapshot_stale = repmat(logical(localReportValue(options.Report, "snapshotStale", false)), height(audit), 1);
audit.report_latest_age_s = repmat(localReportValue(options.Report, "latestAge_s", NaN), height(audit), 1);
end

function domains = localDomainDefinitions()
domains = [ ...
    struct('name', "barometer", 'label', "Barometer", ...
        'validField', "baro_valid", 'updatedField', "baro_updated", 'seqField', "baro_seq", 'ageField', ""); ...
    struct('name', "imu", 'label', "IMU", ...
        'validField', "imu_valid", 'updatedField', "imu_updated", 'seqField', "imu_seq", 'ageField', ""); ...
    struct('name', "aux_accel", 'label', "Aux accel", ...
        'validField', "aux_valid", 'updatedField', "aux_updated", 'seqField', "aux_seq", 'ageField', ""); ...
    struct('name', "attitude", 'label', "Attitude", ...
        'validField', "att_valid", 'updatedField', "att_updated", 'seqField', "att_seq", 'ageField', ""); ...
    struct('name', "vertical_accel", 'label', "Vertical accel", ...
        'validField', "auxvz_valid", 'updatedField', "auxvz_updated", 'seqField', "auxvz_seq", 'ageField', ""); ...
    struct('name', "estimator", 'label', "Estimator", ...
        'validField', "est_valid", 'updatedField', "est_updated", 'seqField', "est_seq", 'ageField', ""); ...
    struct('name', "phase_diag", 'label', "Phase diag", ...
        'validField', "phase_diag_valid", 'updatedField', "phase_diag_updated", 'seqField', "phase_diag_seq", 'ageField', "phase_diag_age_ms"); ...
    struct('name', "policy", 'label', "Policy", ...
        'validField', "policy_valid", 'updatedField', "", 'seqField', "", 'ageField', ""); ...
    struct('name', "warning", 'label', "Warning mask", ...
        'validField', "", 'updatedField', "", 'seqField', "", 'ageField', "")];
end

function values = localColumn(T, vars, fieldName, n, defaultValue)
if fieldName ~= "" && ismember(fieldName, vars)
    values = double(T.(char(fieldName)));
else
    values = repmat(defaultValue, n, 1);
end
values = values(:);
end

function [values, present] = localOptionalNumeric(T, vars, fieldName, n)
present = fieldName ~= "" && ismember(fieldName, vars);
if present
    values = double(T.(char(fieldName)));
else
    values = nan(n, 1);
end
values = values(:);
end

function [values, present] = localOptionalLogical(T, vars, fieldName, n)
present = fieldName ~= "" && ismember(fieldName, vars);
if present
    numeric = double(T.(char(fieldName)));
    values = isfinite(numeric) & numeric > 0.5;
else
    values = false(n, 1);
end
values = values(:);
end

function delta = localSeqDelta(seqValue)
delta = [NaN; diff(seqValue)];
delta(~isfinite(seqValue)) = NaN;
delta([false; ~isfinite(seqValue(1:end-1))]) = NaN;
end

function [code, label, rationale] = localClassifyStatus(row, domain, hasValid, hasUpdated, hasSeq, hasAge, maxAgeMs)
n = height(row);
code = zeros(n, 1);
label = strings(n, 1);
rationale = strings(n, 1);

for k = 1:n
    if domain.name == "warning"
        if isfinite(row.warn_mask(k)) && row.warn_mask(k) ~= 0
            code(k) = 5;
            label(k) = "warning_active";
            rationale(k) = "Firmware warning mask is nonzero.";
        elseif isfinite(row.warn_mask(k))
            code(k) = 4;
            label(k) = "valid_updated";
            rationale(k) = "Firmware warning mask is present and clear.";
        else
            code(k) = 0;
            label(k) = "missing";
            rationale(k) = "Warning mask field is unavailable.";
        end
        continue;
    end

    hasAnyEvidence = hasValid || hasUpdated || hasSeq || hasAge;
    if ~hasAnyEvidence
        code(k) = 0;
        label(k) = "missing";
        rationale(k) = "No validity, update, sequence, or age field is available for this source.";
    elseif hasValid && ~row.valid(k)
        code(k) = 1;
        label(k) = "invalid";
        rationale(k) = "Source validity flag is false.";
    elseif hasAge && isfinite(row.age_ms(k)) && row.age_ms(k) > maxAgeMs
        code(k) = 2;
        label(k) = "stale";
        rationale(k) = "Source diagnostic age exceeds the configured freshness threshold.";
    elseif hasUpdated && ~row.updated(k)
        code(k) = 3;
        label(k) = "valid_held";
        rationale(k) = "Source remains valid but did not publish an update this sample.";
    elseif hasUpdated && row.updated(k)
        code(k) = 4;
        label(k) = "valid_updated";
        rationale(k) = "Source validity and update evidence are both affirmative.";
    elseif hasSeq && row.seq_changed(k)
        code(k) = 4;
        label(k) = "valid_updated";
        rationale(k) = "Source sequence counter advanced.";
    elseif hasSeq && ~row.seq_changed(k)
        code(k) = 3;
        label(k) = "valid_held";
        rationale(k) = "Source sequence counter did not advance.";
    else
        code(k) = 3;
        label(k) = "valid_held";
        rationale(k) = "Source evidence is present, but no per-sample update flag is available.";
    end
end
end

function value = localReportValue(report, fieldName, defaultValue)
name = char(fieldName);
if isstruct(report) && isfield(report, name) && ~isempty(report.(name))
    value = report.(name);
else
    value = defaultValue;
end

if islogical(value)
    value = double(value);
elseif isstring(value) || ischar(value)
    value = defaultValue;
end
end

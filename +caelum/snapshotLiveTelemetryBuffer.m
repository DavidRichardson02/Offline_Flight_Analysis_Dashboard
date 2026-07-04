function [T, report, buffer] = snapshotLiveTelemetryBuffer(buffer, options)
%SNAPSHOTLIVETELEMETRYBUFFER Return a normalized snapshot of live buffer data.
%
% By default, the snapshot is aligned and cleaned into the same table contract
% used by analyzeLog and playLiveFlight. Set Normalize=false to inspect the raw
% accepted serial rows plus host receive metadata.
arguments
    buffer struct
    options.Normalize (1,1) logical = true
    options.Config struct = struct()
end

buffer = localEnsureBuffer(buffer);
report = buffer.counters;
report.rowsInBuffer = height(buffer.raw);
report.capacity = buffer.capacity;
report.bufferUtilization = report.rowsInBuffer / buffer.capacity;
report.latestAge_s = localLatestAgeSeconds(buffer);
report.snapshotStale = isfinite(report.latestAge_s) && report.latestAge_s > buffer.staleAge_s;
report.normalized = options.Normalize;

if report.snapshotStale
    buffer.counters.staleSnapshots = buffer.counters.staleSnapshots + 1;
    report.staleSnapshots = buffer.counters.staleSnapshots;
end

if isempty(buffer.raw)
    T = table();
    return;
end

if ~options.Normalize
    T = buffer.raw;
    return;
end

cfg = localResolveConfig(buffer, options.Config);
aligned = caelum.alignImportedSchema(buffer.raw, cfg);
[T, cleanReport] = caelum.cleanLog(aligned, cfg);
report.cleanReport = cleanReport;
report.rowsAfterCleaning = height(T);
end

function buffer = localEnsureBuffer(buffer)
if isfield(buffer, 'kind') && string(buffer.kind) == "caelum-live-telemetry-buffer"
    return;
end

error('caelum:snapshotLiveTelemetryBuffer:InvalidBuffer', ...
    'Buffer must be created with caelum.createLiveTelemetryBuffer.');
end

function cfg = localResolveConfig(buffer, optionConfig)
if ~isempty(fieldnames(optionConfig))
    cfg = optionConfig;
elseif isfield(buffer, 'config') && ~isempty(fieldnames(buffer.config))
    cfg = buffer.config;
else
    cfg = caelum.defaultConfig();
end
end

function age_s = localLatestAgeSeconds(buffer)
if ~isfield(buffer, 'lastAcceptedHostDatenum') || ~isfinite(buffer.lastAcceptedHostDatenum)
    age_s = NaN;
else
    age_s = (now - buffer.lastAcceptedHostDatenum) * 86400.0;
end
end

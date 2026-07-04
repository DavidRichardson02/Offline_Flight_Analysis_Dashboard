function buffer = createLiveTelemetryBuffer(options)
%CREATELIVETELEMETRYBUFFER Create a bounded serial telemetry ring buffer.
%
% The live buffer owns only ingestion state: the current HDR schema, accepted raw
% rows, host receive metadata, and counters for dropped or suspect input. It does
% not run estimator logic. Use snapshotLiveTelemetryBuffer to convert the current
% buffer contents into the normalized dashboard table contract.
arguments
    options.Capacity (1,1) double {mustBeInteger,mustBePositive} = 2000
    options.Config struct = caelum.defaultConfig()
    options.RequireMonotonicTimestamps (1,1) logical = true
    options.StaleAge_s (1,1) double {mustBeNonnegative} = 1.0
end

buffer = struct();
buffer.kind = "caelum-live-telemetry-buffer";
buffer.capacity = options.Capacity;
buffer.config = options.Config;
buffer.requireMonotonicTimestamps = options.RequireMonotonicTimestamps;
buffer.staleAge_s = options.StaleAge_s;
buffer.header = strings(1, 0);
buffer.raw = table();
buffer.lastAcceptedT_us = NaN;
buffer.lastAcceptedHostDatenum = NaN;
buffer.createdAt = string(datetime("now", "TimeZone", "local", "Format", "yyyy-MM-dd HH:mm:ss Z"));
buffer.counters = localInitialCounters();
end

function counters = localInitialCounters()
counters = struct();
counters.totalLinesSeen = 0;
counters.commentLinesSkipped = 0;
counters.emptyLinesSkipped = 0;
counters.ignoredNonTelemetryLines = 0;
counters.headerLinesSeen = 0;
counters.repeatedHeadersRemoved = 0;
counters.headerChanges = 0;
counters.rejectedHeaderChanges = 0;
counters.invalidHeaders = 0;
counters.tlmLinesSeen = 0;
counters.acceptedRows = 0;
counters.droppedBeforeHeaderRows = 0;
counters.droppedMalformedRows = 0;
counters.droppedNonNumericRows = 0;
counters.droppedNonmonotonicRows = 0;
counters.droppedRowsFromCapacity = 0;
counters.serialReadErrors = 0;
counters.staleSnapshots = 0;
counters.lastErrorMessage = "";
end

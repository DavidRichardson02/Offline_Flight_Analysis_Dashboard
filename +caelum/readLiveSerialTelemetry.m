function [snapshot, report, buffer, serialObj] = readLiveSerialTelemetry(port, baud, options)
%READLIVESERIALTELEMETRY Read live firmware HDR/TLM telemetry from serialport.
%
% Example:
%   [T, report, buffer] = caelum.readLiveSerialTelemetry("/dev/cu.usbmodem101", 115200, Duration_s=10);
%   pb = caelum.playLiveFlight(T, PlaybackRate=1.0);
%
% The reader is intentionally bounded by Duration_s and/or MaxRows so the same
% function can be used for flight-test captures, bench smoke tests, and CI-style
% manual validation without requiring an asynchronous UI callback.
arguments
    port (1,1) string
    baud (1,1) double {mustBePositive} = 115200
    options.Duration_s (1,1) double {mustBeNonnegative} = 10
    options.MaxRows (1,1) double {mustBeNonnegative} = Inf
    options.Capacity (1,1) double {mustBeInteger,mustBePositive} = 2000
    options.Timeout_s (1,1) double {mustBePositive} = 1.0
    options.PollInterval_s (1,1) double {mustBePositive} = 0.01
    options.Terminator (1,1) string = "LF"
    options.FlushOnStart (1,1) logical = true
    options.NormalizeSnapshot (1,1) logical = true
    options.Config struct = caelum.defaultConfig()
    options.ExistingBuffer struct = struct()
end

if strlength(port) == 0
    available = serialportlist("available");
    error('caelum:readLiveSerialTelemetry:MissingPort', ...
        'Provide a serial port name. Available ports: %s', strjoin(cellstr(string(available)), ', '));
end

if isempty(fieldnames(options.ExistingBuffer))
    buffer = caelum.createLiveTelemetryBuffer( ...
        Capacity=options.Capacity, ...
        Config=options.Config);
else
    buffer = options.ExistingBuffer;
end

serialObj = serialport(port, baud, "Timeout", options.Timeout_s);
configureTerminator(serialObj, options.Terminator);
if options.FlushOnStart
    flush(serialObj);
end

startTic = tic;
acceptedAtStart = buffer.counters.acceptedRows;
while localShouldContinue(startTic, buffer, acceptedAtStart, options)
    if serialObj.NumBytesAvailable > 0
        try
            line = readline(serialObj);
            buffer = caelum.appendLiveTelemetryBuffer(buffer, line);
        catch ME
            buffer.counters.serialReadErrors = buffer.counters.serialReadErrors + 1;
            buffer.counters.lastErrorMessage = string(ME.message);
            pause(options.PollInterval_s);
        end
    else
        pause(options.PollInterval_s);
    end
end

[snapshot, report, buffer] = caelum.snapshotLiveTelemetryBuffer( ...
    buffer, Normalize=options.NormalizeSnapshot, Config=options.Config);
report.port = port;
report.baud = baud;
report.durationRequested_s = options.Duration_s;
report.durationElapsed_s = toc(startTic);
report.maxRowsRequested = options.MaxRows;

if nargout < 4
    clear serialObj;
end
end

function tf = localShouldContinue(startTic, buffer, acceptedAtStart, options)
durationActive = isinf(options.Duration_s) || toc(startTic) < options.Duration_s;
rowsAccepted = buffer.counters.acceptedRows - acceptedAtStart;
rowsActive = isinf(options.MaxRows) || rowsAccepted < options.MaxRows;
tf = durationActive && rowsActive;
end

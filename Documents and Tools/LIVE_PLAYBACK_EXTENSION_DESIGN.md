# Caelum Live Playback Extension Design

## Purpose

Extend the offline MATLAB dashboard so the same engineering review surface can
support:

1. Post-flight playback from SD CSV logs.
2. Near-real-time playback from a buffered serial telemetry stream.
3. Review of position, firmware flight phase, airbrake policy state, actuator
   command, and warning telemetry on a synchronized time base.

The first implemented step is `+caelum/playLiveFlight.m`. It reuses the offline
CSV import, schema alignment, cleaning, and optional 3D replay pipeline, then
renders a live-style playback cursor across position, altitude, phase, policy,
and apogee-prediction panels.

The next implemented step is `+caelum/importSerialTelemetry.m`. It parses
firmware `HDR`/`TLM` serial telemetry captures into a numeric table while
preserving the firmware-published field order. `playLiveFlight` now detects
serial capture files or in-memory serial lines and routes them through this
parser before using the existing normalization and rendering path.

The current live-ingest step adds a bounded serial telemetry buffer, a blocking
`serialport` reader, and a callback-driven dashboard session:

- `+caelum/createLiveTelemetryBuffer.m` initializes the buffer, schema state,
  capacity, freshness threshold, and counters.
- `+caelum/appendLiveTelemetryBuffer.m` appends `HDR`/`TLM` lines, rejects
  malformed/non-numeric/nonmonotonic rows, and drops the oldest rows on capacity
  overflow.
- `+caelum/snapshotLiveTelemetryBuffer.m` returns a normalized dashboard table
  snapshot from the current buffer contents.
- `+caelum/readLiveSerialTelemetry.m` opens a MATLAB `serialport`, ingests live
  lines for a bounded duration or row count, and returns the snapshot, counters,
  and buffer.
- `+caelum/startLiveSerialDashboard.m` opens a MATLAB `serialport`, attaches a
  terminator callback that appends each `HDR`/`TLM` line into the ring buffer,
  and uses a UI timer to snapshot the buffer into live trajectory, altitude,
  phase, policy, apogee, and parser-health panels. Pause/resume and scrub
  controls operate on buffered samples without stopping serial ingestion.

## Data Contract

The current Teensy 4.1 SD logger source of truth is:

`C:\Users\98dav\Documents\CaelumSufflamen\utils\sd_logger.cpp`

The checked-in dashboard schema now mirrors that 56-column SD CSV order in:

`firmware_sdlog_schema.csv`

The live serial telemetry source of truth is:

`C:\Users\98dav\Documents\CaelumSufflamen\utils\telemetry.cpp`

As of this integration pass, `telemetry_print_header()` emits a 77-field
`HDR,...` line including the leading record tag. Compared with the SD log, the
serial stream also carries source validity/update metadata, estimator seeded
state, `target_nominal`, `target_effective`, `uncertainty_margin`,
`sea_level_hpa`, and `baro_baseline_hpa`. The future serial parser should retain
those fields instead of down-converting the stream to the SD-only schema.

The dashboard normalizes current firmware names into the older analysis names:

| Firmware field | Dashboard analysis field | Meaning |
| --- | --- | --- |
| `est_h` | `kf_h` | Firmware vertical altitude estimate |
| `est_v` | `kf_v` | Firmware vertical velocity estimate |
| `est_a` | `kf_a` | Firmware estimator acceleration input |
| `q0,q1,q2,q3` | `q_w,q_x,q_y,q_z` | Firmware attitude quaternion |
| `phase` | `phase`, `phase_name` | Firmware flight-phase enum and label |
| `policy_cmd` | `policy_cmd`, `policy_cmd_percent` | Normalized airbrake command |
| `target_effective` | `target_effective` | Live serial effective target after uncertainty margin |
| `uncertainty_margin` | `uncertainty_margin` | Live serial covariance-aware policy margin |

Older Monte Carlo and synthetic dashboard logs remain supported. Missing gravity
vector fields are reconstructed by `alignImportedSchema`, and missing relative
altitude is derived from the first finite `bmp_alt` sample.

## Mission Scoring Profile

For this project use-case, the IREC scoring target is the 10,000 ft AGL class.
`+caelum/irecMissionProfile.m` encodes this as:

- `targetApogee_ft = 10000`
- `targetApogee_m = 3048.0`
- scoring-window fraction `0.30`, yielding 7,000 ft to 13,000 ft for the
  altitude-accuracy scoring band
- official altitude source: COTS barometric pressure altimeter with on-board
  storage, per the IREC rules

The mission profile is loaded by `caelum.defaultConfig()` as `cfg.mission`.
This deliberately remains separate from firmware telemetry fields:

| Field or config item | Role |
| --- | --- |
| `cfg.mission.targetApogee_m` | Competition scoring target, fixed at 3048 m for the 10,000 ft AGL class |
| `target_apogee` | Firmware policy target recorded in telemetry |
| `target_nominal` | Firmware nominal target before live policy adjustment |
| `target_effective` | Firmware effective target after uncertainty margin or policy adjustment |

The attached firmware checkout now deliberately defines `POLICY_TARGET_APOGEE_M`
as `3048.0 m` in `utils/config.h`, matching the IREC 10,000 ft AGL mission
target. The dashboard still reports the firmware target fields and the IREC
scoring target as separate quantities because one is recorded flight-computer
evidence and the other is the mission/scoring contract.

Dashboards and playback views report the IREC target in the summary and overlay
the reference line on apogee panels only when it is within the plotted data
scale, avoiding distortion of low-altitude synthetic fixtures. Integrated
dashboard summaries also gate competition-error text: legacy/drop-test logs that
remain far below competition altitude and do not carry a matching firmware target
show the 10,000 ft target as a reference only, rather than reporting a
misleading score-like error.

## Playback Architecture

The live extension should remain split into four stages:

1. Ingest
   - Offline: CSV file or `analyzeLog` result struct.
   - Live: `serialport` reader that parses `HDR` and `TLM` lines from the
     Teensy telemetry stream.

2. Normalize
   - Convert source-specific field names into the dashboard analysis contract.
   - Preserve validity, update, sequence, age, phase, policy, and warning fields.
   - Reject or quarantine malformed rows without shifting column meaning.

3. Buffer
   - Maintain a timestamp-ordered ring buffer.
   - Keep payload fields adjacent to validity/freshness metadata.
   - Track dropped rows, repeated headers, nonmonotonic timestamps, and parse
     failures as first-class diagnostics.

4. Render
   - Update trajectory, altitude, phase, policy command, apogee prediction, and
     warning panels from the normalized buffer.
   - Drive all panels from one time cursor so policy decisions can be compared
     against position and flight phase.

## Current Entry Point

Examples:

```matlab
% Replay a latest-format Teensy SD log.
pb = caelum.playLiveFlight("LOG000.CSV", PlaybackRate=2.0);

% Replay an existing analysis result without re-importing.
results = caelum.analyzeLog("LOG000.CSV");
pb = caelum.playLiveFlight(results, PlaybackRate=1.0, PositionSource="auto");

% Force vertical-only playback when GPS or 3D replay is unavailable.
pb = caelum.playLiveFlight("LOG000.CSV", PositionSource="vertical");

% Parse a captured serial HDR/TLM stream and replay it through the same surface.
[Tserial, report] = caelum.importSerialTelemetry("telemetry_capture.txt");
pb = caelum.playLiveFlight(Tserial, PlaybackRate=1.0, PositionSource="auto");

% Or let playLiveFlight detect a serial capture file directly.
pb = caelum.playLiveFlight("telemetry_capture.txt", PlaybackRate=1.0);

% Build a deterministic buffer from captured lines.
buffer = caelum.createLiveTelemetryBuffer(Capacity=2000);
buffer = caelum.appendLiveTelemetryBuffer(buffer, readlines("telemetry_capture.txt"));
[Tlive, liveReport, buffer] = caelum.snapshotLiveTelemetryBuffer(buffer);
pb = caelum.playLiveFlight(buffer, PlaybackRate=1.0);

% Read directly from a Teensy serial stream for 10 seconds.
[Tlive, liveReport, buffer] = caelum.readLiveSerialTelemetry( ...
    "/dev/cu.usbmodem101", 115200, Duration_s=10, Capacity=2000);
pb = caelum.playLiveFlight(Tlive, PlaybackRate=1.0);

% Start the true live dashboard. Use the pause button to freeze the cursor and
% the scrub slider to inspect earlier samples while serial ingestion continues.
session = caelum.startLiveSerialDashboard( ...
    "/dev/cu.usbmodem101", 115200, Capacity=2000, RefreshPeriod_s=0.25);

% Inspect the current normalized snapshot and parser diagnostics.
[Tlive, liveReport, buffer] = session.snapshot();

% Stop callbacks, the refresh timer, and the serial object when the bench run is
% complete.
session.stop();
```

## Recommended Next Development Steps

1. Bench-test `readLiveSerialTelemetry` and `startLiveSerialDashboard` against
   the Teensy port for short captures, recording parser counters, stale-snapshot
   behavior, and whether the serial callback remains responsive while paused.
2. Confirm the bench-loaded firmware build still carries the same 10,000 ft AGL
   policy target (`3048.0 m`) before flight testing.
3. Add a raw serial capture/export option to the live dashboard session so every
   bench run can be replayed through `importSerialTelemetry` and `playLiveFlight`.
4. Add exported playback snapshots for reports so the live view can produce
   reviewable artifacts after a flight test.
5. Consider adding the same pause/resume/scrub controls to `playLiveFlight` if
   offline review needs interactive control instead of deterministic playback.
6. Rerun `validate_firmware_dashboard_alignment` after any firmware target
   change so the dashboard evidence continues to distinguish firmware control
   target from scoring target.

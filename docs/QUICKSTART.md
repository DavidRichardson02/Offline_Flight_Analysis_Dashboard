# Quickstart

This guide gets the Offline Flight Analysis Dashboard running from a fresh checkout.

## Requirements

Required:

- MATLAB with support for modern `table` workflows, `arguments` blocks, `tiledlayout`, standard plotting, and numeric analysis.

Optional:

- Serial hardware access for live telemetry workflows using MATLAB `serialport`.
- Arduino CLI and Teensy 4.1 board support if you also validate or rebuild the firmware reference under `CaelumSufflamen/`.

No mandatory third-party MATLAB toolbox dependency is documented for the repository.

## 1. Open the Repository in MATLAB

From the repository root:

```matlab
addpath(genpath(pwd));
```

If MATLAB was already open before cloning or switching branches, run `rehash toolboxcache` or restart MATLAB if package functions are not discovered.

## 2. Run the Release Gate

```matlab
validation = validate_caelum_release;
```

The release gate renders release dashboards when configured, then runs the release-facing validators:

- `validate_firmware_dashboard_alignment`
- `validate_vertical_replay_stack`
- `validate_irec_mission_profile`
- `validate_live_telemetry_import`

The returned struct contains `overallPassed`. The validator raises an error if any required release check fails.

To run without dashboard windows:

```matlab
validation = validate_caelum_release(MakeDashboards=false);
```

To export release dashboard figures:

```matlab
validation = validate_caelum_release( ...
    ExportDashboardFigures=true, ...
    DashboardExportDir="exports/release_validation_dashboards");
```

`exports/` is ignored by Git by default. Commit exported products only when intentionally promoting them into documentation or a release artifact.

## 3. Analyze an Offline SD CSV Log

```matlab
results = caelum.analyzeLog("Flight Data/Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv", ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true, ...
    MakeAuxiliaryDashboard=true, ...
    ExportFigures=false);
```

Important result fields:

| Result field | Meaning |
| --- | --- |
| `results.raw` | Imported table after strict or robust import and schema alignment. |
| `results.data` | Cleaned dashboard contract table. |
| `results.events` | Detected launch, burnout, apogee, landing, or other review events. |
| `results.replay` | Vertical estimator replay table when enabled. |
| `results.attitude` | Attitude replay table when enabled in config. |
| `results.summary` / `results.summaryTable` | Human-review summary metrics. |
| `results.est3d` | Optional 3D/GPS replay table. |
| `results.wind` | Wind estimate summary from the 3D replay layer. |
| `results.dashboardFigure` | Main integrated dashboard figure. |
| `results.auxiliaryDashboardFigure` | Auxiliary evidence dashboard figure when requested. |
| `results.importReport` / `results.cleanReport` | Import and cleaning diagnostics. |
| `results.consistencyMetrics` | Replay consistency, innovation, covariance, attitude, and gating metrics. |

## 4. Import and Replay Serial Telemetry

For a captured firmware serial text file containing `HDR,...` and `TLM,...` lines:

```matlab
[Tserial, report] = caelum.importSerialTelemetry("Flight Data/Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt");
pb = caelum.playLiveFlight(Tserial, PlaybackRate=1.0, PositionSource="auto");
```

The parser preserves field order from the firmware `HDR` line and reports malformed rows, repeated headers, nonnumeric payloads, and timestamp issues.

## 5. Use the Live Telemetry Buffer

A deterministic buffer can be built from captured lines:

```matlab
buffer = caelum.createLiveTelemetryBuffer(Capacity=2000);
buffer = caelum.appendLiveTelemetryBuffer(buffer, readlines("Flight Data/Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt"));
[Tlive, liveReport, buffer] = caelum.snapshotLiveTelemetryBuffer(buffer);
pb = caelum.playLiveFlight(buffer, PlaybackRate=1.0);
```

To read from a real serial device for a bounded duration:

```matlab
[Tlive, liveReport, buffer] = caelum.readLiveSerialTelemetry( ...
    "/dev/cu.usbmodem101", 115200, Duration_s=10, Capacity=2000);
```

To start the callback-driven live dashboard:

```matlab
session = caelum.startLiveSerialDashboard( ...
    "/dev/cu.usbmodem101", 115200, Capacity=2000, RefreshPeriod_s=0.25);

% Later, inspect the snapshot or stop the session.
[Tlive, liveReport, buffer] = session.snapshot();
session.stop();
```

Use the correct port name for the host system. Windows ports normally look like `COM7`; macOS/Linux ports usually look like `/dev/cu.*`, `/dev/tty.*`, or `/dev/ttyACM*`.

## 6. Common Focused Validators

```matlab
validate_firmware_dashboard_alignment
validate_vertical_replay_stack
validate_irec_mission_profile
validate_live_telemetry_import
validate_replay_contract_diff_viewer
validate_flight_evidence_navigator
validate_telemetry_freshness_heatmap
validate_causality_graph
validate_phase_state_machine_timeline
validate_policy_decision_audit
validate_estimator_trust_dashboard
validate_attitude_gravity_provenance_view
validate_3d_trajectory_wind_uncertainty_tube
validate_apogee_sensitivity_waterfall
validate_monte_carlo_mission_envelope_board
```

See [Validation Guide](VALIDATION.md) for when to use each check.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| `Undefined function or variable 'caelum.*'` | MATLAB path not initialized. | Run `addpath(genpath(pwd));` from the repo root. |
| `File not found` for a fixture | MATLAB current folder is not the repository root, or the fixture path is wrong. | Use an absolute path or `fullfile(pwd, ...)`. |
| Strict import fails | Log does not match a known schema. | Let `analyzeLog` use robust import fallback, then inspect `results.importReport`. |
| Serial replay has missing fields | Capture lacks a valid `HDR` line or firmware schema changed. | Update `firmware_serial_telemetry_schema.csv`, fixtures, import logic, and validators together. |
| Dashboard windows do not appear | Headless MATLAB, visibility settings, or `MakeDashboards=false`. | Run with dashboard options enabled on a local MATLAB desktop. |
| Validation generated files appear in Git status | Generated output directories are ignored by policy but may be intentionally created locally. | Do not commit generated `exports/`, screenshots, or `.mat` workspaces unless intentionally promoted. |

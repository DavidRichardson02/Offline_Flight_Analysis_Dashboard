# Offline Flight Analysis Dashboard

MATLAB offline flight-analysis and validation environment for Caelum rocket telemetry. The project imports SD-card and serial telemetry logs, normalizes firmware schemas into a MATLAB analysis contract, replays estimator behavior, renders engineering dashboards, validates firmware/dashboard alignment, and supports live-style telemetry playback from captured or real serial streams.

This repository is the canonical Caelum V3 analysis/refactor package with the integrated V4 dashboard surface.

## What This Project Does

The dashboard is designed for post-flight engineering review and firmware contract validation. It provides:

- strict and robust Caelum telemetry import paths for SD CSV logs and firmware `HDR`/`TLM` serial captures
- schema alignment between latest Teensy firmware telemetry fields and MATLAB dashboard field names
- cleaned telemetry tables with timestamp, sensor, estimator, attitude, GPS, phase, policy, and target metadata
- vertical estimator replay with innovation, covariance, bias, beta, and gating diagnostics
- optional attitude replay, gravity provenance, 3D/GPS EKF replay, and wind estimation
- integrated dashboard rendering for altitude, velocity, acceleration, sensor health, estimator uncertainty, GPS, 3D trajectory, wind, phase, policy, provenance, and summary review
- focused diagnostic boards for replay contracts, policy decisions, telemetry freshness, causality, phase timelines, estimator trust, attitude/gravity provenance, 3D trajectory/wind uncertainty, and Monte Carlo mission envelopes
- firmware/dashboard contract validation against the checked CaelumSufflamen firmware reference
- local release validation through `validate_caelum_release.m`

## Documentation

Start with the documentation hub:

| Document | Purpose |
| --- | --- |
| [docs/README.md](docs/README.md) | Documentation index and maintenance rules. |
| [docs/QUICKSTART.md](docs/QUICKSTART.md) | Fresh-clone MATLAB setup, release validation, offline analysis, and live playback examples. |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Package architecture, dataflow, module ownership, and result struct contract. |
| [docs/TELEMETRY_SCHEMA.md](docs/TELEMETRY_SCHEMA.md) | SD CSV and serial `HDR`/`TLM` firmware schema contracts. |
| [docs/VALIDATION.md](docs/VALIDATION.md) | Release gate, focused validators, and evidence expectations. |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | GitHub release, handoff, dashboard, and documentation checklist. |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution and validation rules. |

Detailed live playback design notes are maintained in [`Documents and Tools/LIVE_PLAYBACK_EXTENSION_DESIGN.md`](Documents%20and%20Tools/LIVE_PLAYBACK_EXTENSION_DESIGN.md).

## Current Release Entry Point

From the repository root in MATLAB:

```matlab
addpath(genpath(pwd));
validation = validate_caelum_release;
```

`validate_caelum_release.m` renders release dashboard windows when requested, then runs the release-facing validation gates:

- `validate_firmware_dashboard_alignment`
- `validate_vertical_replay_stack`
- `validate_irec_mission_profile`
- `validate_live_telemetry_import`

The validator reports an `overallPassed` result and throws an error if any required release gate fails.

For headless validation:

```matlab
validation = validate_caelum_release(MakeDashboards=false);
```

## Quick Offline Analysis Workflow

```matlab
results = caelum.analyzeLog("Flight Data/Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv", ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true, ...
    MakeAuxiliaryDashboard=true, ...
    ExportFigures=false);
```

At a high level, `caelum.analyzeLog` performs:

1. strict import with robust-import fallback
2. firmware schema alignment into the dashboard contract
3. telemetry cleaning and event detection
4. attitude replay and vertical estimator replay when enabled
5. truth and consistency metric calculation when truth data is available
6. optional 3D/GPS replay and wind estimation
7. overview/dashboard rendering
8. optional figure and CSV export

## Live and Serial Telemetry Support

The live-playback extension lets the same engineering review surface support:

- post-flight playback from SD CSV logs
- captured serial telemetry replay from firmware `HDR`/`TLM` text logs
- bounded live serial ingestion through MATLAB `serialport`
- ring-buffer snapshots for live dashboard updates
- pause/resume and scrub-style inspection of buffered telemetry samples

Relevant entry points include:

```matlab
% Replay a logged SD or serial capture file.
pb = caelum.playLiveFlight("Flight Data/Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt");

% Parse a captured serial HDR/TLM stream.
[Tserial, report] = caelum.importSerialTelemetry("Flight Data/Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt");

% Build and snapshot a deterministic telemetry buffer.
buffer = caelum.createLiveTelemetryBuffer(Capacity=2000);
buffer = caelum.appendLiveTelemetryBuffer(buffer, readlines("Flight Data/Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt"));
[Tlive, liveReport, buffer] = caelum.snapshotLiveTelemetryBuffer(buffer);

% Start a true live serial dashboard.
session = caelum.startLiveSerialDashboard("/dev/cu.usbmodem101", 115200, ...
    Capacity=2000, RefreshPeriod_s=0.25);
```

See [docs/QUICKSTART.md](docs/QUICKSTART.md) for Windows/macOS/Linux serial-port notes and live buffer examples.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `+caelum/` | Main MATLAB package for import, schema alignment, cleaning, event detection, estimator replay, 3D/GPS replay, wind estimation, dashboards, live playback, buffering, and export utilities. |
| `validate_*.m` | Release and feature-specific validation scripts for firmware alignment, replay contracts, live telemetry import, policy audits, phase timelines, causality, telemetry freshness, estimator trust, trajectory/wind evidence, and mission envelopes. |
| `docs/` | GitHub-facing documentation hub. |
| `Flight Data/` | Representative SD and serial fixtures used by validators. Generated Monte Carlo logs are intentionally ignored. |
| `firmware_sdlog_schema.csv` | Checked SD-card logger schema contract mirrored from the firmware reference. |
| `firmware_serial_telemetry_schema.csv` | Checked serial `HDR`/`TLM` telemetry schema contract mirrored from the firmware reference. |
| `vertical_replay_*.csv` | Vertical replay field contract and baseline fixtures. |
| `Documents and Tools/` | Release notes, design documentation, manuscript/source notes, MATLAB project metadata, and supporting non-generated project documents. |
| `CaelumSufflamen/` | Firmware reference checkout and firmware-side validation context used to keep dashboard contracts aligned. |
| `exports/` | Regenerated figures, CSVs, and PDFs. Ignored by Git. |
| `Screen Captures/` | Local screenshots and manual review captures. Ignored by Git. |

## Validation Commands

Run the full release gate:

```matlab
validate_caelum_release
```

Run focused validators as needed:

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

Most validation products are regenerated into ignored output folders such as `exports/` and should not be committed unless a specific artifact is intentionally promoted into documentation.

See [docs/VALIDATION.md](docs/VALIDATION.md) for a validation matrix by change type.

## Firmware and Mission Contract

The repository tracks both MATLAB analysis code and firmware-facing telemetry contracts. The validation workflow checks that:

- `firmware_sdlog_schema.csv` matches the SD logger field order from the firmware reference
- `firmware_serial_telemetry_schema.csv` matches the serial telemetry `HDR` payload order
- latest SD and serial fixtures can be imported, aligned, cleaned, and buffered
- firmware policy target fields remain separate from the IREC mission scoring target
- the IREC 10,000 ft AGL mission profile is encoded as a 3048.0 m target apogee

The default configuration loads the IREC mission profile through `caelum.defaultConfig()`.

## Requirements

Required:

- MATLAB with support for modern table workflows, `arguments` blocks, `tiledlayout`, standard plotting, and numeric analysis

Optional:

- serial hardware access for live telemetry workflows using MATLAB `serialport`
- Arduino CLI and Teensy 4.1 board support for firmware-reference build workflows under `CaelumSufflamen/`

No mandatory third-party MATLAB toolbox dependency is documented in this repository.

## Data and Source-Control Policy

Tracked source-of-truth files include:

- MATLAB source and validation scripts
- telemetry schema contracts
- representative validation fixtures
- firmware reference source and documentation
- release notes and project documentation

Ignored/generated files include:

- `exports/` render products
- `Screen Captures/` local screenshots
- generated Monte Carlo logs
- MATLAB autosaves and binary workspaces
- Python bytecode and caches
- Arduino/Teensy build products
- local IDE files, OS metadata, credentials, tokens, keys, and environment files

## Typical Development Loop

1. Update firmware schema, MATLAB import logic, replay logic, dashboard logic, fixtures, or documentation.
2. Run the focused validator for the changed subsystem.
3. Run `validate_caelum_release` before release or handoff.
4. Review regenerated figures/CSVs under ignored output directories.
5. Commit only source, fixtures, schemas, and documentation that are intended to be permanent repository inputs.

## GitHub Metadata

Suggested GitHub description:

```text
MATLAB offline flight-analysis dashboard for Caelum telemetry, estimator replay, firmware contract validation, live serial playback, and mission evidence review.
```

Suggested GitHub topics:

```text
matlab, flight-analysis, telemetry, rocket, aerospace, sensor-fusion, estimator-replay, kalman-filter, gps, serial-telemetry, teensy, firmware-validation, monte-carlo, dashboard, validation, caelum
```

## License

This repository is publicly visible for portfolio, academic, review, and demonstration purposes only. Reuse, redistribution, modification, sublicensing, commercial exploitation, or incorporation into another project requires prior written permission from the copyright holder. See [`LICENSE`](LICENSE) for the governing terms.

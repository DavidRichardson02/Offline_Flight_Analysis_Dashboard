# Documentation Index

This folder is the GitHub-facing documentation hub for the **Offline Flight Analysis Dashboard**. The codebase is MATLAB-first and is organized around telemetry import, firmware/dashboard schema alignment, estimator replay, engineering dashboards, live-style playback, and release validation.

## Start Here

| Document | Use it when you need to... |
| --- | --- |
| [Quickstart](QUICKSTART.md) | Open the project in MATLAB, run the release validator, analyze a sample log, or replay serial telemetry. |
| [Architecture](ARCHITECTURE.md) | Understand the package pipeline, data ownership boundaries, dashboard outputs, and major MATLAB modules. |
| [Telemetry Schema](TELEMETRY_SCHEMA.md) | Understand SD log fields, serial `HDR`/`TLM` fields, schema-normalization rules, and firmware/dashboard contract updates. |
| [Validation Guide](VALIDATION.md) | Choose the right `validate_*` script and understand what the release gate checks. |
| [Release Checklist](RELEASE_CHECKLIST.md) | Prepare a reviewable GitHub release or portfolio handoff. |
| [Live Playback Extension Design](../Documents%20and%20Tools/LIVE_PLAYBACK_EXTENSION_DESIGN.md) | Review the detailed serial/live playback design notes already maintained with the project. |
| [Contributing](../CONTRIBUTING.md) | Follow repository contribution, validation, and source-control rules. |
| [License](../LICENSE) | Review repository visibility and reuse restrictions. |

## Repository in One Paragraph

The Offline Flight Analysis Dashboard converts Caelum flight-computer telemetry into engineering evidence. It imports SD CSV logs and serial `HDR`/`TLM` captures, aligns firmware field names to MATLAB analysis names, cleans timestamps and malformed rows, detects flight events, replays attitude and vertical estimator behavior, optionally fuses GPS/3D state, estimates wind, renders dashboard figures, and runs validators that check firmware/dashboard contract consistency.

## Primary MATLAB Entry Points

```matlab
addpath(genpath(pwd));

% Full release-facing validation gate.
validation = validate_caelum_release;

% Typical offline log analysis.
results = caelum.analyzeLog("Flight Data/Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv", ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true, ...
    MakeAuxiliaryDashboard=true, ...
    ExportFigures=false);

% Serial capture import and live-style playback.
[Tserial, report] = caelum.importSerialTelemetry("Flight Data/Synthetic_LatestFirmware_PracticalFlight_HDRTLM.txt");
pb = caelum.playLiveFlight(Tserial, PlaybackRate=1.0, PositionSource="auto");
```

## Documentation Maintenance Rules

When code, fixtures, schemas, or firmware contracts change, update documentation in the same pull request. At minimum:

1. Update `README.md` for user-facing workflow or repository metadata changes.
2. Update `docs/TELEMETRY_SCHEMA.md` when SD, serial, or aligned-dashboard fields change.
3. Update `docs/VALIDATION.md` when validation gates, fixture names, or release checks change.
4. Update `docs/ARCHITECTURE.md` when package flow, major modules, or dashboard responsibilities change.
5. Keep generated outputs such as `exports/` and `Screen Captures/` out of source control unless a specific artifact is intentionally promoted into documentation.

## Evidence Boundary

The documentation describes repository contracts and workflows. It does not claim a physical flight result unless the corresponding log, fixture, validation report, manifest, or exported evidence artifact is committed or otherwise referenced in a review package.

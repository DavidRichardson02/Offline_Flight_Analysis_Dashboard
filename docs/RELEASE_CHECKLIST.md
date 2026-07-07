# Release and Handoff Checklist

Use this checklist before presenting the repository as complete on GitHub, opening a release PR, or handing the dashboard to another reviewer.

## 1. Repository Hygiene

- [ ] Working branch contains only intended source, fixture, schema, and documentation changes.
- [ ] Generated products remain untracked unless intentionally promoted.
- [ ] No local credentials, tokens, `.env` files, private serial-port settings, `.mat` workspaces, or IDE metadata are committed.
- [ ] `README.md` describes the current entry points and points to `docs/`.
- [ ] `LICENSE` and README license language agree.
- [ ] `CONTRIBUTING.md` matches the current validation workflow.

## 2. MATLAB Path and Environment

From the repository root:

```matlab
addpath(genpath(pwd));
```

Record the MATLAB version and operating system when preparing formal release notes.

- [ ] MATLAB can discover `+caelum` package functions.
- [ ] Representative fixtures under `Flight Data/` are accessible from the current checkout.
- [ ] Dashboard windows are available if the release requires screenshots or visual review.

## 3. Schema and Firmware Contract Review

- [ ] `firmware_sdlog_schema.csv` matches the intended SD CSV firmware field order.
- [ ] `firmware_serial_telemetry_schema.csv` matches the intended serial `HDR`/`TLM` field order.
- [ ] `+caelum/alignImportedSchema.m` maps firmware fields into dashboard names explicitly.
- [ ] Firmware policy target fields remain separate from IREC mission target/scoring fields.
- [ ] Validity, update, timestamp, sequence, phase, policy, and warning fields remain preserved through import and cleaning.
- [ ] New telemetry fields are documented in [Telemetry Schema](TELEMETRY_SCHEMA.md).

## 4. Focused Validation

Run the focused validators for any changed subsystem.

| Changed area | Minimum focused check |
| --- | --- |
| Firmware schema or fixtures | `validate_firmware_dashboard_alignment` |
| Vertical replay | `validate_vertical_replay_stack` |
| Mission target/profile | `validate_irec_mission_profile` |
| Serial import/live buffer | `validate_live_telemetry_import` |
| Policy dashboard/audit | `validate_policy_decision_audit` |
| Phase timeline | `validate_phase_state_machine_timeline` |
| Estimator trust | `validate_estimator_trust_dashboard` |
| 3D/GPS/wind | `validate_3d_trajectory_wind_uncertainty_tube` |
| Monte Carlo envelope | `validate_monte_carlo_mission_envelope_board` |

For each validator:

- [ ] Command was run from a clean MATLAB path.
- [ ] Pass/fail status is recorded.
- [ ] Any warnings or skipped cases are documented.
- [ ] Generated artifacts are reviewed locally.

## 5. Full Release Gate

Run:

```matlab
validation = validate_caelum_release;
```

Or, for headless checks:

```matlab
validation = validate_caelum_release(MakeDashboards=false);
```

- [ ] `validation.overallPassed == true`.
- [ ] Firmware/dashboard alignment check passed.
- [ ] Vertical replay stack check passed.
- [ ] IREC mission profile check passed.
- [ ] Live telemetry import check passed.
- [ ] Dashboard rendering errors, if any, are understood and documented.

## 6. Dashboard Review

For at least one representative fixture:

- [ ] Main dashboard renders.
- [ ] Auxiliary dashboard renders when requested.
- [ ] Altitude, vertical speed, estimator uncertainty, phase, policy, target, and warning panels are readable.
- [ ] Low-altitude fixtures do not display misleading IREC score-like claims.
- [ ] 3D/GPS/wind panels are present only when supported by available fields.
- [ ] Figure exports, if generated, include enough context to identify fixture, branch, and settings.

## 7. Live Playback Review

For serial/live workflows:

- [ ] `caelum.importSerialTelemetry` imports a representative `HDR`/`TLM` capture.
- [ ] Parser diagnostics report malformed rows, repeated headers, nonmonotonic timestamps, and dropped rows clearly.
- [ ] `caelum.playLiveFlight` can replay the imported serial table.
- [ ] `createLiveTelemetryBuffer`, `appendLiveTelemetryBuffer`, and `snapshotLiveTelemetryBuffer` preserve ordering and capacity behavior.
- [ ] Real serial use cases document port name, baud rate, firmware build, and capture duration.

## 8. Documentation Review

- [ ] README quickstart is accurate.
- [ ] [Quickstart](QUICKSTART.md) runs from a fresh clone.
- [ ] [Architecture](ARCHITECTURE.md) matches the current package flow.
- [ ] [Telemetry Schema](TELEMETRY_SCHEMA.md) matches schema CSVs.
- [ ] [Validation Guide](VALIDATION.md) lists the current release and focused validators.
- [ ] Any known limitations are documented rather than implied to be complete.

## 9. GitHub Presentation

Recommended repository About description:

```text
MATLAB offline flight-analysis dashboard for Caelum telemetry, estimator replay, firmware contract validation, live serial playback, and mission evidence review.
```

Recommended topics:

```text
matlab, flight-analysis, telemetry, rocket, aerospace, sensor-fusion, estimator-replay, kalman-filter, gps, serial-telemetry, teensy, firmware-validation, monte-carlo, dashboard, validation, caelum
```

Optional GitHub assets to add later:

- pinned dashboard screenshot or GIF in README
- a short demo section with one fixture and expected outputs
- release artifact package containing selected plots and validation summary
- GitHub Pages site generated from `docs/`

## 10. Pull Request Summary Template

```markdown
## Summary
- Added/updated ...
- Documented ...
- Preserved ...

## Validation
- [ ] `validate_firmware_dashboard_alignment`
- [ ] `validate_vertical_replay_stack`
- [ ] `validate_irec_mission_profile`
- [ ] `validate_live_telemetry_import`
- [ ] `validate_caelum_release`

## Generated Artifacts
- `exports/` generated locally only / promoted intentionally: ...

## Known Limitations
- ...
```

## Done Definition

A repository documentation pass is complete when a new reviewer can land on GitHub, understand what the project does, run the primary MATLAB workflows, find schema and validation contracts, and distinguish implemented evidence from generated/local outputs.

# Validation Guide

Validation is the repository's evidence chain. The goal is not only to make plots render; the goal is to prove that firmware telemetry, MATLAB import, replay logic, dashboards, and mission-profile assumptions remain aligned.

## Full Release Gate

Run from the repository root in MATLAB:

```matlab
addpath(genpath(pwd));
validation = validate_caelum_release;
```

The release gate runs these release-facing checks:

| Check | Purpose |
| --- | --- |
| `validate_firmware_dashboard_alignment` | Confirms firmware schemas, dashboard names, and checked fixtures remain aligned. |
| `validate_vertical_replay_stack` | Exercises vertical replay contracts, estimator behavior, covariance/innovation outputs, and fixtures. |
| `validate_irec_mission_profile` | Confirms the IREC 10,000 ft AGL mission profile and target separation rules. |
| `validate_live_telemetry_import` | Validates serial `HDR`/`TLM` import, buffering, and live-playback contract behavior. |

The returned struct includes:

- `overallPassed`
- `firmwareDashboardAlignment`
- `irecMissionProfile`
- `liveTelemetryImport`
- `dashboardResults`
- `dashboardFigure`
- `auxiliaryDashboardFigure`
- dashboard render error metadata, if a dashboard could not be rendered

The script throws an error when `overallPassed` is false.

## Useful Release-Gate Variants

```matlab
% Run validation without opening dashboard figures.
validation = validate_caelum_release(MakeDashboards=false);

% Use a specific dashboard fixture.
validation = validate_caelum_release( ...
    DashboardFixture="Flight Data/Synthetic_LatestFirmware_PracticalFlight_WithGPS.csv");

% Export dashboard figures into the ignored exports directory.
validation = validate_caelum_release( ...
    ExportDashboardFigures=true, ...
    DashboardExportDir="exports/release_validation_dashboards");
```

## Focused Validators by Change Type

| Change type | Recommended checks |
| --- | --- |
| Firmware telemetry fields or schema CSVs | `validate_firmware_dashboard_alignment` |
| SD CSV import behavior | `validate_firmware_dashboard_alignment`, then `validate_caelum_release` |
| Serial `HDR`/`TLM` parsing or live buffer logic | `validate_live_telemetry_import` |
| Vertical estimator replay | `validate_vertical_replay_stack` |
| Replay contract comparison tools | `validate_replay_contract_diff_viewer` |
| IREC target, scoring semantics, or mission profile | `validate_irec_mission_profile` |
| Policy decision/audit panels | `validate_policy_decision_audit` |
| Phase state-machine timeline panels | `validate_phase_state_machine_timeline` |
| Freshness/age heatmaps | `validate_telemetry_freshness_heatmap` |
| Causality/evidence graph | `validate_causality_graph` |
| Estimator trust dashboard | `validate_estimator_trust_dashboard` |
| Attitude and gravity provenance | `validate_attitude_gravity_provenance_view` |
| 3D trajectory, GPS, wind, or uncertainty tube | `validate_3d_trajectory_wind_uncertainty_tube` |
| Apogee sensitivity board | `validate_apogee_sensitivity_waterfall` |
| Monte Carlo mission envelope board | `validate_monte_carlo_mission_envelope_board` |
| Cross-cutting release or handoff | `validate_caelum_release` |

## What a Good Validation Report Should Include

For a pull request or release handoff, report:

1. MATLAB version and operating system, if relevant.
2. Repository branch and commit.
3. Exact commands run.
4. Whether dashboard figures were rendered or suppressed.
5. Fixture names used.
6. `overallPassed` and focused validator pass/fail status.
7. Any warnings, skipped checks, or dashboard rendering errors.
8. Whether generated outputs were committed intentionally or left ignored.

Example pull request validation block:

```text
Validation:
- MATLAB R20xx, local desktop session
- addpath(genpath(pwd))
- validate_firmware_dashboard_alignment: passed
- validate_live_telemetry_import: passed
- validate_caelum_release(MakeDashboards=false): passed

Generated artifacts:
- exports/ created locally only; not committed
```

## Fixtures and Generated Artifacts

Tracked fixtures under `Flight Data/` are repository inputs. They should remain small enough to review and stable enough to reproduce validation behavior.

Ignored/generated outputs include:

- `exports/`
- `Screen Captures/`
- generated Monte Carlo logs
- MATLAB `.mat` files and autosaves
- local screenshots

Generated outputs should be committed only when a specific figure, CSV, or report is intentionally promoted into documentation or release evidence.

## Schema Validation Expectations

Schema validation should prove that:

- SD logger schema files match expected firmware fields.
- Serial `HDR` payload fields match the checked serial telemetry schema.
- Importers do not silently shift field meanings after malformed rows or repeated headers.
- Dashboard aliases such as `est_h` -> `kf_h` and `q0` -> `q_w` are deliberate and tested.
- Policy target fields remain separate from IREC mission/scoring target fields.

## Dashboard Validation Expectations

Dashboard validation should prove that:

- Figures render without errors for representative fixtures.
- Panels use cleaned and aligned telemetry, not raw unvetted columns.
- Validity, freshness, warning, phase, policy, and estimator status are visible or auditable.
- Low-altitude/drop-test fixtures do not produce misleading competition-score claims.
- 3D/GPS/wind panels degrade gracefully when GPS fields are absent or invalid.

## Live Telemetry Validation Expectations

Live telemetry validation should prove that:

- The parser accepts well-formed `HDR`/`TLM` captures.
- Malformed rows are counted and reported.
- Repeated headers are handled deliberately.
- Nonmonotonic timestamps are rejected, quarantined, or reported.
- The ring buffer preserves order and drops old rows on capacity overflow.
- `playLiveFlight` can consume serial tables and buffers through the same review surface as offline logs.

## Failure Triage

| Failure | First place to inspect |
| --- | --- |
| Missing columns | `firmware_sdlog_schema.csv`, `firmware_serial_telemetry_schema.csv`, `+caelum/alignImportedSchema.m` |
| Strict import error | `+caelum/importLog.m`, fixture header, delimiter, repeated headers, malformed rows |
| Dashboard render error | `results.dashboardRenderErrorIdentifier`, `results.dashboardRenderErrorMessage`, panel-specific validator |
| Replay mismatch | `validate_vertical_replay_stack`, `+caelum/replayEstimator.m`, covariance/gating settings in `defaultConfig` |
| Mission target mismatch | `+caelum/irecMissionProfile.m`, `+caelum/defaultConfig.m`, firmware target telemetry fields |
| Serial parser mismatch | `+caelum/importSerialTelemetry.m`, serial schema CSV, captured `HDR` line |

## Release Readiness Standard

A repository state is release-ready when:

- `validate_caelum_release` passes.
- Changed subsystems have focused validator coverage.
- README and docs match the current workflows.
- Schema CSVs and fixtures match firmware telemetry contracts.
- Generated artifacts are either ignored or intentionally promoted.
- Known limitations are documented instead of hidden.

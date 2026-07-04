# Contributing

Thank you for contributing to the Offline Flight Analysis Dashboard. This project is a MATLAB-based engineering analysis environment for Caelum telemetry, estimator replay, firmware/dashboard contract validation, and live telemetry review.

## Development Principles

Please keep changes aligned with these priorities:

1. Preserve telemetry contract correctness.
2. Keep firmware schema, fixtures, import logic, validators, and documentation synchronized.
3. Treat generated plots, exports, screenshots, logs, and build outputs as reproducible artifacts rather than source files.
4. Prefer focused validators for subsystem changes and `validate_caelum_release` for release/handoff checks.

## Before Making Changes

From the repository root in MATLAB:

```matlab
addpath(genpath(pwd));
```

For a full release-facing check, run:

```matlab
validate_caelum_release
```

## Recommended Validation by Change Type

| Change Type | Recommended Checks |
| --- | --- |
| Firmware telemetry fields or schema contracts | `validate_firmware_dashboard_alignment` |
| Vertical replay, replay fixtures, estimator contracts | `validate_vertical_replay_stack`, `validate_replay_contract_diff_viewer` |
| Mission target or scoring semantics | `validate_irec_mission_profile`, `validate_policy_decision_audit` |
| Serial telemetry parsing or live buffer logic | `validate_live_telemetry_import`, `validate_telemetry_freshness_heatmap` |
| Dashboard evidence panels | relevant `validate_*` script for the panel plus `validate_caelum_release` |
| 3D/GPS, trajectory, wind, or attitude provenance | `validate_3d_trajectory_wind_uncertainty_tube`, `validate_attitude_gravity_provenance_view` |

## Source-Control Policy

Commit source-of-truth inputs such as:

- MATLAB source files
- validation scripts
- firmware schema CSVs
- representative fixtures
- documentation
- release notes
- firmware reference source required for contract validation

Do not commit regenerated or local-only outputs such as:

- `exports/`
- `Screen Captures/`
- generated Monte Carlo logs
- MATLAB autosaves or `.mat` workspaces
- Python caches
- Arduino/Teensy build outputs
- local IDE metadata
- OS metadata
- credentials, tokens, keys, certificates, or local environment files

## Pull Request Checklist

Before opening or merging a pull request, confirm:

- [ ] The changed files match the intended scope.
- [ ] Generated outputs remain untracked unless intentionally promoted into documentation.
- [ ] Relevant focused validators were run.
- [ ] `validate_caelum_release` was run for release-facing or cross-cutting changes.
- [ ] README, release notes, schemas, fixtures, and firmware notes were updated together when telemetry contracts changed.
- [ ] Any validation failures or skipped checks are documented in the pull request.

## Firmware Contract Changes

When firmware telemetry changes, update all affected layers together:

1. firmware source/header definition
2. `firmware_sdlog_schema.csv` and/or `firmware_serial_telemetry_schema.csv`
3. representative fixtures under `Flight Data/`
4. MATLAB import and schema alignment logic
5. relevant validators
6. README and release notes

The goal is for MATLAB dashboard behavior to remain traceable to the firmware telemetry contract.

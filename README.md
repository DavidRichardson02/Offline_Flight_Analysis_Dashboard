# Offline Flight Analysis Dashboard

MATLAB analysis and validation tools for Caelum flight telemetry, estimator replay, phase-state evidence, airbrake policy review, telemetry freshness, and generated engineering figures.

The repository is structured as a reviewable offline analysis environment. It keeps firmware telemetry contracts, replay logic, validation entry points, and representative fixtures under version control while excluding regenerated plots, PDFs, caches, build outputs, and local machine metadata.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `+caelum/` | MATLAB package code for import, schema alignment, cleaning, replay, estimation, audits, plotting, and live-buffer utilities. |
| `validate_*.m` | Focused validation entry points for dashboard alignment, replay contracts, telemetry freshness, causality graphs, phase timelines, policy audits, and trajectory/wind evidence. |
| `Flight Data/` | Representative SD/serial fixtures and small flight-log inputs used by validators. Generated Monte Carlo logs are intentionally ignored. |
| `firmware_*_schema.csv` | Checked telemetry schema contracts for SD-card and serial firmware outputs. |
| `vertical_replay_*.csv` | Vertical replay field contract and baseline fixtures. |
| `Documents and Tools/` | Release notes, design documentation, manuscript source, MATLAB project metadata, and supporting non-generated inputs. |
| `CaelumSufflamen/` | Nested firmware reference checkout and firmware-side validation context used to keep dashboard contracts aligned. |
| `exports/` | Regenerated validation figures, CSVs, and PDFs. This directory is ignored by Git. |
| `Screen Captures/` | Local screenshots and manual review captures. This directory is ignored by Git. |

## Requirements

- MATLAB with table, plotting, and standard numeric workflow support.
- Optional serial hardware access for live telemetry workflows that use `serialport`.
- Optional Arduino CLI and Teensy 4.1 board support for the nested `CaelumSufflamen` firmware build path.

The offline validators are designed to run from the repository root after MATLAB can see the package directory.

## Quick Start

Open the project root in MATLAB, then run:

```matlab
addpath(genpath(pwd));
validation = validate_caelum_release;
```

For focused checks, run individual validators:

```matlab
validate_firmware_dashboard_alignment
validate_replay_contract_diff_viewer
validate_flight_evidence_navigator
validate_telemetry_freshness_heatmap
validate_causality_graph
```

Most validators write regenerated artifacts under `exports/`. Those outputs are intentionally reproducible review products, not source files.

## Data And Contract Policy

The checked CSV and serial fixtures are part of the reproducible validation contract. Generated artifacts are not.

Tracked inputs include:

- MATLAB source and validation scripts.
- Firmware telemetry schema CSVs.
- Representative SD and serial telemetry fixtures in `Flight Data/`.
- Release notes and engineering design documentation.
- Firmware reference source and documentation under `CaelumSufflamen/`.

Ignored outputs include:

- `exports/` render products.
- `Screen Captures/` screenshots.
- MATLAB autosaves and binary workspaces.
- Python bytecode and caches.
- Arduino/Teensy build products.
- Generated Monte Carlo run logs.
- Local environment and credential files.

## Firmware Reference

The nested `CaelumSufflamen/` directory provides firmware-side context for the dashboard contract. Its build notes are in `CaelumSufflamen/Documentation/BUILDING.md`. The dashboard schema files at the repository root mirror firmware SD and serial telemetry fields so replay and visualization remain tied to the flight-computer data contract.

## Validation Notes

`validate_caelum_release.m` is the release-facing validation entry point. It runs the dashboard alignment checks, vertical replay stack, IREC mission profile validation, and live telemetry import validation. Focused validators provide narrower evidence for individual views and contracts.

When changing telemetry fields, update the firmware schema CSVs, import alignment, fixtures, validators, and documentation together. The validation outputs should be regenerated locally, reviewed, and left untracked unless a specific artifact is intentionally promoted into documentation.

## License

No open-source license has been selected for this project. For a private repository, that means reuse rights are not granted by default. Add an explicit license only after choosing the intended distribution model.

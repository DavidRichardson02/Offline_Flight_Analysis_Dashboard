# Telemetry Schema and Firmware Contract

The dashboard is only useful when every plotted value can be traced back to a stable firmware field contract. This document explains how the repository treats SD CSV logs, serial `HDR`/`TLM` telemetry, normalized MATLAB table fields, and firmware/dashboard compatibility checks.

## Source-of-Truth Files

| File | Purpose |
| --- | --- |
| `firmware_sdlog_schema.csv` | Checked SD-card CSV logger field contract. |
| `firmware_serial_telemetry_schema.csv` | Checked serial `HDR`/`TLM` payload field contract. |
| `+caelum/getFirmwareSdlogSchema.m` | MATLAB accessor for the SD schema contract. |
| `+caelum/getFirmwareSerialTelemetrySchema.m` | MATLAB accessor for the serial schema contract, if present in the current checkout. |
| `+caelum/importLog.m` | Strict SD CSV importer for known Caelum schemas. |
| `+caelum/importLogRobust.m` | Robust fallback importer for imperfect or legacy CSV logs. |
| `+caelum/importSerialTelemetry.m` | Serial `HDR`/`TLM` parser. |
| `+caelum/alignImportedSchema.m` | Field-name normalization layer. |
| `validate_firmware_dashboard_alignment.m` | Validator that checks firmware/dashboard schema compatibility. |

## Contract Rules

1. Do not reorder committed schema fields casually. Field order is part of the parser contract.
2. Prefer appending new fields over inserting fields in the middle of a firmware stream.
3. Preserve validity, update, sequence, timestamp, phase, policy, and warning fields with the payload they describe.
4. Keep SD and serial contracts separate; serial telemetry may include runtime fields that SD logs do not, and vice versa.
5. When firmware telemetry changes, update schema CSVs, fixtures, import logic, validators, and docs together.
6. When a field is reconstructed for legacy logs, document the reconstruction and keep it out of control-critical claims unless verified.

## SD CSV Log Contract

The SD schema is maintained in `firmware_sdlog_schema.csv` with columns:

| Schema column | Meaning |
| --- | --- |
| `field` | Firmware field name as emitted into the CSV. |
| `units` | Engineering unit or type-like unit such as `bool`, `enum`, or `bitmask`. |
| `type` | Expected MATLAB/import type. |
| `required` | Whether the field is required for the checked latest-firmware contract. |
| `notes` | Human-readable contract note. |

Major SD field groups:

| Group | Representative fields |
| --- | --- |
| Row and time | `row_seq`, `t_us` |
| Barometer | `baro_valid`, `baro_updated`, `baro_seq`, `bmp_T`, `bmp_P`, `bmp_alt` |
| IMU | `imu_valid`, `imu_updated`, `imu_seq`, `ax`, `ay`, `az`, `gx`, `gy`, `gz` |
| Auxiliary acceleration | `aux_valid`, `aux_updated`, `aux_seq`, `lis_ax`, `lis_ay`, `lis_az` |
| Attitude | `att_valid`, `att_updated`, `att_seq`, `q0`, `q1`, `q2`, `q3` |
| Vertical acceleration | `auxvz_valid`, `auxvz_updated`, `auxvz_seq`, `a_vertical` |
| Estimator | `est_valid`, `est_updated`, `est_seeded`, `est_seq`, `est_h`, `est_v`, `est_a`, `P00`, `P01`, `P10`, `P11` |
| Arming and phase | `arm_state`, `policy_runtime_enabled`, `software_arm_token`, `phase`, `actuator_us` |
| Phase diagnostics | `phase_diag_valid`, `phase_diag_updated`, `phase_launch_latched`, `phase_burnout_latched`, `phase_descent_latched`, dwell and confirm timers |
| Policy | `policy_valid`, `policy_cmd`, `apogee_no_brake`, `apogee_full_brake`, `target_apogee`, `apogee_error`, `target_nominal`, `target_effective`, `uncertainty_margin` |
| Health | `warn_mask` |

## Serial `HDR`/`TLM` Contract

The serial schema is maintained in `firmware_serial_telemetry_schema.csv`. Serial telemetry starts with a header line that gives field order, followed by `TLM` rows carrying numeric payloads.

Major serial-only or serial-emphasized fields include:

| Field | Purpose |
| --- | --- |
| `t_ms` | Firmware `millis()` timestamp for serial telemetry. |
| `baro_upd`, `imu_upd`, `aux_upd`, `att_upd`, `auxvz_upd`, `est_upd` | Update flags using compact serial naming. |
| `sea_level_hpa` | Sea-level pressure reference used by firmware altitude conversion. |
| `baro_baseline_hpa` | Captured pressure baseline for local altitude reference. |

Serial parser responsibilities:

- Preserve the field order declared by `HDR`.
- Reject or report malformed `TLM` rows without shifting column meanings.
- Track repeated headers, nonnumeric payloads, nonmonotonic timestamps, dropped rows, and parser counters.
- Normalize names into the same dashboard analysis contract used by SD logs.

## Firmware to Dashboard Name Mapping

The dashboard keeps compatibility with earlier analysis names while accepting latest firmware fields.

| Firmware field | Dashboard analysis field | Meaning |
| --- | --- | --- |
| `est_h` | `kf_h` | Firmware vertical altitude estimate. |
| `est_v` | `kf_v` | Firmware vertical velocity estimate. |
| `est_a` | `kf_a` | Firmware estimator acceleration input. |
| `q0`, `q1`, `q2`, `q3` | `q_w`, `q_x`, `q_y`, `q_z` | Firmware attitude quaternion. |
| `phase` | `phase`, `phase_name` | Firmware phase enum and dashboard label. |
| `policy_cmd` | `policy_cmd`, `policy_cmd_percent` | Normalized airbrake policy command. |
| `target_effective` | `target_effective` | Effective target after uncertainty margin. |
| `uncertainty_margin` | `uncertainty_margin` | Covariance-aware policy margin. |

## Enumerations and Semantics

### `arm_state`

| Value | Meaning |
| --- | --- |
| `0` | `DISARMED` |
| `1` | `SAFE` |
| `2` | `ARMED` |

### `phase`

| Value | Meaning |
| --- | --- |
| `0` | `IDLE` |
| `1` | `BOOST` |
| `2` | `COAST` |
| `3` | `BRAKE` |
| `4` | `DESCENT` |

### Policy fields

| Field | Interpretation |
| --- | --- |
| `policy_valid` | Firmware policy considers the nonzero command meaningful; final actuator safety gates still matter. |
| `policy_cmd` | Normalized deployment intent in `[0, 1]`. |
| `actuator_us` | Post-safety pulse-equivalent actuator command. |
| `apogee_no_brake` | Predicted apogee with retracted brakes. |
| `apogee_full_brake` | Predicted apogee with maximum deployment. |
| `target_nominal` | Configured firmware target before uncertainty margin. |
| `target_effective` | Target after subtracting uncertainty margin. |
| `uncertainty_margin` | Altitude-covariance-derived target reduction. |

## Updating the Schema Safely

When adding, removing, or renaming telemetry fields:

1. Update the firmware logger or telemetry emitter.
2. Update `firmware_sdlog_schema.csv` and/or `firmware_serial_telemetry_schema.csv`.
3. Update representative fixtures under `Flight Data/`.
4. Update import and normalization code in `+caelum/`.
5. Update validators, especially `validate_firmware_dashboard_alignment` and `validate_live_telemetry_import`.
6. Update dashboard panels if the visible evidence contract changed.
7. Update this document and the README if user workflow changes.
8. Run the focused validator and then `validate_caelum_release`.

## Review Checklist for Telemetry Changes

- [ ] Field order is intentionally preserved or intentionally migrated.
- [ ] Units are documented.
- [ ] Boolean, enum, and bitmask semantics are documented.
- [ ] Validity/update/sequence/timestamp fields remain adjacent to their payload domain where practical.
- [ ] Legacy fixtures still import or fail with a clear diagnostic.
- [ ] The dashboard does not silently reinterpret stale or invalid data as fresh data.
- [ ] The parser reports malformed rows and repeated headers.
- [ ] Firmware policy target fields remain separate from IREC mission scoring fields.
- [ ] Validation scripts pass or documented failures are understood.

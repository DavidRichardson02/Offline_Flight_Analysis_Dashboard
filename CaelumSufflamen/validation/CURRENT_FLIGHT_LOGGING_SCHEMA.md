# Current-Flight Logging Schema for Aerodynamic Coefficient Identification

This document defines the recommended current-flight logging schema for identifying the aerodynamic coefficients used by the Caelum Sufflamen airbrake policy:

```text
POLICY_CDA_BODY_M2
POLICY_CDA_BRAKE_M2
```

The schema is designed for real current-branch Teensy 4.1 flights. It is not a replacement for flight-test review, but it defines the minimum evidence needed to make a later coefficient update traceable, reproducible, and reviewable.

## 1. Objective

The current policy model uses:

```text
k(u) = rho * (CDA_body + u*CDA_brake) / (2*m)
```

where:

| Symbol | Meaning |
| --- | --- |
| `rho` | Air density assumption in kg/m^3. |
| `m` | Vehicle mass in kg. |
| `CDA_body` | Effective drag area of the vehicle with airbrakes retracted. |
| `CDA_brake` | Additional effective drag area at normalized full airbrake deployment. |
| `u` | Normalized deployment command or measured normalized deployment in `[0,1]`. |

The log schema must allow a reviewer to reconstruct:

1. What the vehicle state estimate was during coast.
2. What phase the firmware believed it was in.
3. What command the airbrake policy requested.
4. What actuator pulse the firmware actually sent.
5. What brake position was physically achieved, if measured.
6. What apogee was observed.
7. What configuration, mass, and atmospheric assumptions were used.
8. Which samples are valid enough to use for coefficient fitting.

## 2. Current Repository Status

The existing SD logger already records many required fields:

| Existing field group | Examples |
| --- | --- |
| Time | `t_us` |
| Barometer | `bmp_T`, `bmp_P`, `bmp_alt` |
| IMU | `ax`, `ay`, `az`, `gx`, `gy`, `gz` |
| Attitude | `q0`, `q1`, `q2`, `q3` |
| Vertical state | `a_vertical`, `est_h`, `est_v`, `est_a` |
| Covariance | `P00`, `P01`, `P10`, `P11` |
| Authority gates | `arm_state`, `policy_runtime_enabled`, `software_arm_token` |
| Phase | `phase` and phase diagnostic fields |
| Policy | `policy_valid`, `policy_cmd`, `apogee_no_brake`, `apogee_full_brake`, `target_apogee`, `apogee_error` |
| Actuator | `actuator_us` |
| Health | `warn_mask` |

Important missing or weak evidence for high-confidence identification:

| Gap | Why it matters |
| --- | --- |
| Flight-level metadata is not embedded in a structured file. | Mass, motor, configuration, pressure reference, and density assumptions are required for repeatability. |
| Actual brake position is not logged. | Servo command may not equal physical airbrake deployment. |
| Command provenance is incomplete. | It is useful to distinguish raw solved command, slew-limited command, and applied actuator command. |
| Loop timing and row sequence are limited. | Identification benefits from explicit row order, loop period, and dropped-row checks. |
| Independent apogee marker is absent. | Fitting currently infers apogee from estimator altitude; external or post-processed apogee improves confidence. |

## 3. File Set Per Flight

Each flight used for coefficient identification should be committed under:

```text
validation/data/<flight_id>/
```

Required files:

| File | Required | Purpose |
| --- | --- | --- |
| `LOG###.CSV` | Yes | Raw or minimally processed SD log emitted by the firmware. |
| `flight_metadata.json` | Yes | Vehicle, environment, configuration, sensor, actuator, and review metadata. |
| `events.csv` | Recommended | Human or post-processed markers for launch, burnout, apogee, landing, and anomalies. |
| `README.md` | Recommended | Short flight note with provenance, known anomalies, and whether the data may be used for coefficient fitting. |
| `fit_result.json` | Produced later | Output from coefficient fitting script. Store under `validation/results/` unless the result is flight-local only. |

Recommended directory example:

```text
validation/data/flight_2026_001/
|- LOG000.CSV
|- flight_metadata.json
|- events.csv
`- README.md
```

## 4. Schema Version

Use this schema identifier for current planning:

```text
CS_AERO_ID_LOG_V1
```

The schema version should appear in `flight_metadata.json`. If firmware later embeds comment-style metadata lines into SD logs, the same identifier should appear there as well:

```text
#SCHEMA,CS_AERO_ID_LOG_V1
```

## 5. Primary SD Log Row Schema

The primary log should remain CSV because it is easy to inspect, replay, and process with existing host scripts. The recommended header groups are below.

### 5.1 Timing and Row Integrity

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `schema_version` | none | Recommended | firmware constant or metadata join | Allows future scripts to reject incompatible logs. |
| `flight_id` | none | Recommended | firmware metadata or metadata join | Prevents mixing rows from different flights. |
| `row_seq` | count | Yes | logger | Detects dropped or duplicated rows. |
| `loop_seq` | count | Recommended | scheduler | Correlates log rows with control-loop passes. |
| `t_us` | us | Yes | `micros()` | Primary timebase for fitting and replay. |
| `t_ms` | ms | Recommended | `millis()` | Easier human diagnostics and freshness checks. |
| `dt_loop_us` | us | Recommended | scheduler | Identifies timing jitter that may corrupt estimation. |
| `dt_imu_us` | us | Recommended | estimator | Confirms measured IMU integration interval. |
| `log_rate_hz` | Hz | Recommended | config or metadata join | Confirms expected sampling rate. |

Minimum acceptable current firmware substitute:

```text
t_us
```

Preferred future addition:

```text
row_seq,loop_seq,t_ms,dt_loop_us,dt_imu_us
```

### 5.2 Raw Sensor and Sensor Validity

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `baro_valid` | bool | Yes | barometer snapshot | Rejects invalid altitude measurements. |
| `baro_updated` | bool | Recommended | barometer snapshot | Shows whether pressure was fresh this pass. |
| `baro_seq` | count | Recommended | barometer snapshot | Detects repeated barometer data. |
| `bmp_T` | deg C | Yes | BMP5xx | Supports density and sensor sanity review. |
| `bmp_P` | hPa | Yes | BMP5xx | Pressure source for altitude. |
| `bmp_alt` | m | Yes | BMP5xx | Raw barometric altitude before estimator fusion. |
| `imu_valid` | bool | Yes | BMI088 snapshot | Rejects invalid acceleration/gyro samples. |
| `imu_updated` | bool | Recommended | BMI088 snapshot | Shows fresh IMU publication. |
| `imu_seq` | count | Recommended | BMI088 snapshot | Detects repeated IMU data. |
| `ax` | m/s^2 | Yes | BMI088 | Acceleration evidence for phase and estimator review. |
| `ay` | m/s^2 | Yes | BMI088 | Acceleration evidence for phase and estimator review. |
| `az` | m/s^2 | Yes | BMI088 | Acceleration evidence for phase and estimator review. |
| `gx` | rad/s | Yes | BMI088 | Attitude propagation evidence. |
| `gy` | rad/s | Yes | BMI088 | Attitude propagation evidence. |
| `gz` | rad/s | Yes | BMI088 | Attitude propagation evidence. |
| `a_norm` | m/s^2 | Recommended | firmware | Launch/burnout phase evidence. |
| `aux_valid` | bool | Recommended | auxiliary accelerometer snapshot | Secondary acceleration health. |
| `lis_ax` | m/s^2 | Recommended | LIS2DU12 or LIS3DH auxiliary accelerometer | Cross-check acceleration. |
| `lis_ay` | m/s^2 | Recommended | LIS2DU12 or LIS3DH auxiliary accelerometer | Cross-check acceleration. |
| `lis_az` | m/s^2 | Recommended | LIS2DU12 or LIS3DH auxiliary accelerometer | Cross-check acceleration. |
| `pmod_accel_valid` | bool | Recommended | Pmod ACL/ACL2 snapshot | Optional independent acceleration health. |
| `pmod_accel_updated` | bool | Recommended | Pmod ACL/ACL2 snapshot | Shows fresh optional acceleration publication. |
| `pmod_accel_seq` | count | Recommended | Pmod ACL/ACL2 snapshot | Detects repeated optional acceleration data. |
| `pmod_accel_kind` | enum | Recommended | Pmod ACL/ACL2 snapshot | Distinguishes disabled, ACL2 ADXL362, and ACL ADXL345 backends. |
| `pmod_raw_x` | count | Recommended | Pmod ACL/ACL2 | Raw optional X-axis acceleration count. |
| `pmod_raw_y` | count | Recommended | Pmod ACL/ACL2 | Raw optional Y-axis acceleration count. |
| `pmod_raw_z` | count | Recommended | Pmod ACL/ACL2 | Raw optional Z-axis acceleration count. |
| `pmod_ax` | m/s^2 | Recommended | Pmod ACL/ACL2 | Optional independent acceleration cross-check. |
| `pmod_ay` | m/s^2 | Recommended | Pmod ACL/ACL2 | Optional independent acceleration cross-check. |
| `pmod_az` | m/s^2 | Recommended | Pmod ACL/ACL2 | Optional independent acceleration cross-check. |
| `pmod_a_norm` | m/s^2 | Recommended | Pmod ACL/ACL2 | Optional acceleration norm for sensor comparison. |
| `mag_valid` | bool | Recommended | Pmod CMPS2 snapshot | Rejects invalid magnetometer samples. |
| `mag_updated` | bool | Recommended | Pmod CMPS2 snapshot | Shows fresh magnetometer publication. |
| `mag_seq` | count | Recommended | Pmod CMPS2 snapshot | Detects repeated magnetometer samples. |
| `mag_raw_x` | count | Recommended | Pmod CMPS2 | Raw X-axis magnetic output count. |
| `mag_raw_y` | count | Recommended | Pmod CMPS2 | Raw Y-axis magnetic output count. |
| `mag_raw_z` | count | Recommended | Pmod CMPS2 | Raw Z-axis magnetic output count. |
| `mag_x_uT` | uT | Recommended | Pmod CMPS2 | Calibrated X-axis magnetic observability. |
| `mag_y_uT` | uT | Recommended | Pmod CMPS2 | Calibrated Y-axis magnetic observability. |
| `mag_z_uT` | uT | Recommended | Pmod CMPS2 | Calibrated Z-axis magnetic observability. |
| `mag_norm_uT` | uT | Recommended | Pmod CMPS2 | Magnetic norm and interference screening. |
| `mag_heading_deg` | deg | Recommended | Pmod CMPS2 | Uncalibrated heading observability only. |
| `mag_interference` | bool | Recommended | Pmod CMPS2 | Excludes magnetically contaminated intervals. |

### 5.3 Attitude and Vertical Acceleration

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `att_valid` | bool | Yes | attitude snapshot | Rejects invalid frame rotation. |
| `att_updated` | bool | Recommended | attitude snapshot | Shows fresh quaternion solution. |
| `att_seq` | count | Recommended | attitude snapshot | Detects repeated attitude state. |
| `q0` | none | Yes | attitude snapshot | Body-to-world rotation. |
| `q1` | none | Yes | attitude snapshot | Body-to-world rotation. |
| `q2` | none | Yes | attitude snapshot | Body-to-world rotation. |
| `q3` | none | Yes | attitude snapshot | Body-to-world rotation. |
| `auxvz_valid` | bool | Yes | vertical acceleration snapshot | Rejects invalid acceleration projection. |
| `a_vertical` | m/s^2 | Yes | attitude/IMU projection | Supports estimator and residual analysis. |

### 5.4 Estimated Vertical State

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `est_valid` | bool | Yes | estimator | Rejects unusable state samples. |
| `est_updated` | bool | Recommended | estimator | Shows fresh estimator publication. |
| `est_seeded` | bool | Recommended | estimator | Confirms reference frame has been established. |
| `est_seq` | count | Recommended | estimator | Detects repeated estimator state. |
| `est_h` | m | Yes | estimator | Primary altitude for fitting. |
| `est_v` | m/s | Yes | estimator | Primary vertical speed for fitting. |
| `est_a` | m/s^2 | Yes | estimator | Acceleration input used by estimator. |
| `P00` | m^2 | Yes | estimator covariance | Altitude uncertainty and quality filtering. |
| `P01` | m^2/s | Recommended | estimator covariance | State covariance review. |
| `P10` | m^2/s | Recommended | estimator covariance | State covariance review. |
| `P11` | m^2/s^2 | Recommended | estimator covariance | Vertical-speed uncertainty review. |
| `est_age_ms` | ms | Recommended | firmware | Rejects stale estimates. |

### 5.5 Flight Phase and Phase Diagnostics

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `phase` | enum | Yes | phase detector | Selects coast/brake fit windows. |
| `phase_diag_valid` | bool | Recommended | phase detector | Confirms diagnostic freshness. |
| `phase_launch_latched` | bool | Recommended | phase detector | Verifies launch event. |
| `phase_burnout_latched` | bool | Recommended | phase detector | Verifies coast eligibility. |
| `phase_descent_latched` | bool | Recommended | phase detector | Identifies post-apogee region. |
| `phase_boost_dwell_met` | bool | Recommended | phase detector | Explains transition timing. |
| `phase_coast_dwell_met` | bool | Recommended | phase detector | Explains descent gating. |
| `phase_brake_active` | bool | Recommended | phase detector | Identifies active braking classification. |
| `phase_since_launch_ms` | ms | Recommended | phase detector | Aligns events. |
| `phase_since_burnout_ms` | ms | Recommended | phase detector | Aligns coast window. |

Phase enum contract:

| Value | Name | Fit use |
| --- | --- | --- |
| `0` | `IDLE` | Exclude. |
| `1` | `BOOST` | Exclude from coast drag fit; useful for event context. |
| `2` | `COAST` | Primary body-drag and low-command fit region. |
| `3` | `BRAKE` | Primary brake-effect fit region. |
| `4` | `DESCENT` | Exclude from upward-coast model; useful to locate observed apogee. |

### 5.6 Policy, Prediction, and Command Provenance

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `policy_valid` | bool | Yes | policy | Confirms command was meaningful and authorized for consideration. |
| `policy_cmd` | normalized | Yes | policy | Current fitter uses this as deployment command. |
| `policy_cmd_desired` | normalized | Recommended | policy | Raw solver output before slew limiting. |
| `policy_cmd_slewed` | normalized | Recommended | policy | Command after slew limiting. |
| `policy_cmd_applied` | normalized | Recommended | top-level actuator decision | Command that actually reached actuator after safety gates. |
| `apogee_no_brake` | m | Yes | policy | Model prediction with `u=0`. |
| `apogee_full_brake` | m | Yes | policy | Model prediction with `u=max`. |
| `target_apogee` | m | Yes | policy | Effective target used by policy. |
| `apogee_error` | m | Yes | policy | Predicted overshoot/undershoot. |
| `target_nominal` | m | Recommended | policy | Configured target before uncertainty margin. |
| `target_effective` | m | Recommended | policy | Target after uncertainty margin. |
| `uncertainty_margin` | m | Recommended | policy | Covariance-derived target reduction. |
| `policy_min_alt_m` | m | Recommended metadata | config | Documents policy gates. |
| `policy_min_vz_mps` | m/s | Recommended metadata | config | Documents policy gates. |

The distinction between `policy_cmd`, `policy_cmd_desired`, `policy_cmd_slewed`, and `policy_cmd_applied` is important. Coefficient fitting should prefer measured brake position when available. If measured position is unavailable, it should use the applied command, not merely the raw model request.

### 5.7 Arming, Safety, and Actuator Output

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `arm_state` | enum | Yes | system state | Confirms command authority. |
| `policy_runtime_enabled` | bool | Yes | system state | Confirms runtime policy gate. |
| `software_arm_token` | bool | Yes | system state | Confirms explicit arming path. |
| `safety_runtime_ok` | bool | Recommended | safety | Explains why command may or may not reach actuator. |
| `safety_allows_actuation` | bool | Recommended | safety | Final non-idle actuation permission. |
| `actuation_enabled_compile` | bool | Recommended metadata | build/config | Confirms firmware image can actuate. |
| `actuator_us` | us | Yes | actuator | Pulse actually requested by firmware. |
| `servo_us_min` | us | Recommended metadata | config | Converts pulse to normalized command. |
| `servo_us_max` | us | Recommended metadata | config | Converts pulse to normalized command. |
| `servo_us_idle` | us | Recommended metadata | config | Identifies fail-idle output. |
| `brake_pos_valid` | bool | Strongly recommended | position sensor or test fixture | Confirms measured deployment state. |
| `brake_pos01_meas` | normalized | Strongly recommended | position sensor or calibrated mechanism | Best value for identifying `CDA_brake`. |
| `brake_pos_source` | enum/string | Recommended metadata | metadata | Distinguishes measured, calibrated, inferred, or unavailable position. |

If `brake_pos01_meas` is unavailable, coefficient updates should be labeled lower confidence because the analysis assumes commanded pulse maps to actual airbrake geometry.

### 5.8 Health, Quality, and Rejection Flags

| Column | Unit | Required | Source | Identification role |
| --- | --- | --- | --- | --- |
| `warn_mask` | bitmask | Yes | telemetry | Compact health filtering. |
| `sd_runtime_failed` | bool | Recommended | logger | Excludes incomplete logs. |
| `sensor_saturation_mask` | bitmask | Recommended | sensors | Rejects saturated IMU/barometer intervals. |
| `motion_bad` | bool | Recommended | sensors | Rejects corrupted motion windows. |
| `fit_exclude` | bool | Optional post-process | analysis | Allows curated exclusion without deleting raw rows. |
| `fit_exclude_reason` | string | Optional post-process | analysis | Documents anomaly handling. |

Raw firmware logs should not silently delete bad samples. Use validity and rejection fields instead.

## 6. Companion Metadata Schema

`flight_metadata.json` should contain information that does not need to be repeated on every row.

Recommended structure:

```json
{
  "schema_version": "CS_AERO_ID_LOG_V1",
  "flight_id": "flight_2026_001",
  "date_utc": "2026-00-00T00:00:00Z",
  "vehicle": {
    "name": "Caelum Sufflamen test vehicle",
    "configuration_id": "config_001",
    "mass_kg": 2.5,
    "cg_m": null,
    "diameter_m": null,
    "airbrake_geometry_revision": "rev_a"
  },
  "motor": {
    "designation": null,
    "thrust_curve_source": null,
    "burnout_time_s_expected": null
  },
  "environment": {
    "launch_site": null,
    "pad_altitude_m": null,
    "temperature_c": null,
    "pressure_hpa": null,
    "humidity_percent": null,
    "wind_speed_mps": null,
    "wind_direction_deg": null,
    "rho_assumed_kgpm3": 1.225
  },
  "firmware": {
    "board": "Teensy 4.1",
    "commit_or_build_id": null,
    "arduino_fqbn": "teensy:avr:teensy41",
    "policy_target_apogee_m": 300.0,
    "policy_cda_body_m2_config": 0.004,
    "policy_cda_brake_m2_config": 0.02
  },
  "actuator": {
    "servo_us_min": 1000,
    "servo_us_max": 2000,
    "servo_us_idle": 1000,
    "position_feedback_available": false,
    "brake_position_calibration": null
  },
  "data_quality": {
    "usable_for_body_cda_fit": false,
    "usable_for_brake_cda_fit": false,
    "review_status": "unreviewed",
    "notes": []
  }
}
```

Use `null` for unknown values. Do not invent values.

## 7. Event Marker Schema

`events.csv` should be optional but strongly recommended.

Recommended columns:

| Column | Unit | Required | Description |
| --- | --- | --- | --- |
| `event_name` | none | Yes | `launch`, `burnout`, `coast_start`, `brake_start`, `brake_end`, `apogee`, `descent_start`, `landing`, `anomaly`. |
| `t_us` | us | Yes | Event timestamp in firmware log timebase when available. |
| `source` | none | Yes | `firmware`, `postprocess`, `video`, `external_altimeter`, `manual_review`. |
| `confidence` | none | Yes | `low`, `medium`, `high`. |
| `est_h_m` | m | Optional | Estimated altitude at event. |
| `est_v_mps` | m/s | Optional | Estimated vertical speed at event. |
| `notes` | none | Optional | Short explanation. |

The event file should not replace raw data. It should document review decisions.

## 8. Minimum Identification Datasets

### 8.1 Body Drag Only

Minimum for `POLICY_CDA_BODY_M2`:

1. A valid boost-to-coast-to-apogee flight.
2. Reliable `est_h` and `est_v` during upward coast.
3. No airbrake deployment or confirmed `brake_pos01_meas` near zero.
4. Known vehicle mass.
5. Known density assumption.
6. Observed apogee from estimator and preferably independent reference.

Required row filters:

```text
phase == COAST
est_valid == 1
warn_mask has no estimator/sensor validity faults
est_v >= POLICY_MIN_VZ_MPS or analysis-defined fit threshold
brake_pos01_meas <= closed threshold, or policy_cmd/applied command <= closed threshold
```

### 8.2 Brake Drag Authority

Minimum for `POLICY_CDA_BRAKE_M2`:

1. All body-drag requirements.
2. A known nonzero brake deployment interval during upward coast.
3. Logged `policy_cmd_applied` or `actuator_us`.
4. Preferably measured `brake_pos01_meas`.
5. Observed apogee after deployment.
6. Enough command variation to separate brake drag from body drag.

Required row filters:

```text
phase in {COAST, BRAKE}
est_valid == 1
policy_valid == 1 or policy_cmd_applied > 0
brake_pos01_meas >= open threshold, if available
est_v > 0 during fitted rows
observed apogee available later in same flight
```

### 8.3 High-Confidence Identification

High-confidence coefficient updates should use:

1. Multiple flights.
2. At least one mostly retracted coast flight.
3. At least one controlled deployment flight.
4. Independent apogee reference if available.
5. Known vehicle mass for each flight.
6. Consistent vehicle configuration.
7. Held-out replay validation showing reduced prediction error.

## 9. Firmware Logging Implementation Status

The current logger now emits the P0 identification fields needed to filter SD
rows by row continuity, snapshot validity, estimator publication metadata, and
policy target provenance.

Implemented P0 fields:

| Priority | Field | Reason |
| --- | --- | --- |
| P0 | `row_seq` | Detect dropped or duplicated SD rows. |
| P0 | `baro_valid`, `baro_updated`, `baro_seq` | Filter and audit pressure-derived altitude evidence. |
| P0 | `imu_valid`, `imu_updated`, `imu_seq` | Filter and audit acceleration/gyro evidence. |
| P0 | `aux_valid`, `aux_updated`, `aux_seq` | Preserve auxiliary acceleration evidence quality. |
| P0 | `pmod_accel_valid`, `pmod_accel_updated`, `pmod_accel_seq`, `pmod_accel_kind` | Preserve optional Pmod ACL/ACL2 acceleration evidence without making it control-critical. |
| P0 | `mag_valid`, `mag_updated`, `mag_seq`, `mag_interference` | Preserve optional CMPS2 magnetic-field evidence and interference screening. |
| P0 | `att_valid`, `att_updated`, `att_seq` | Filter and audit quaternion frame-rotation evidence. |
| P0 | `auxvz_valid`, `auxvz_updated`, `auxvz_seq` | Filter and audit vertical-acceleration projection evidence. |
| P0 | `est_valid`, `est_updated`, `est_seeded`, `est_seq` | Filter and audit altitude/vertical-speed estimator evidence. |
| P0 | `target_nominal`, `target_effective`, `uncertainty_margin` in SD log | Serial has these policy fields; SD should carry the same policy context. |

Remaining recommended additions:

| Priority | Field | Reason |
| --- | --- | --- |
| P1 | `policy_cmd_desired`, `policy_cmd_slewed`, `policy_cmd_applied` | Separates solver output from gated hardware output. |
| P1 | `safety_runtime_ok`, `safety_allows_actuation` | Explains applied command decisions. |
| P1 | `dt_loop_us`, `dt_imu_us` | Supports timing-quality checks. |
| P1 | `a_norm` | Supports phase review without recomputing. |
| P2 | `brake_pos_valid`, `brake_pos01_meas` | Required for high-confidence brake coefficient identification. |
| P2 | `schema_version` or boot metadata marker | Allows scripts to reject incompatible logs. |

Do not remove existing columns casually. Extend schemas in a backward-compatible way and update host tests when the logger changes.

## 10. Analysis Acceptance Checks

A coefficient-identification result should not be accepted unless these checks pass:

| Check | Required outcome |
| --- | --- |
| Schema check | Required columns exist and header/row counts match. |
| Time check | `t_us` is monotonic within the flight window. |
| Validity check | Fitted rows have valid estimator, attitude, IMU, and barometer evidence or documented exceptions. |
| Phase check | Fitted rows are in `COAST` or `BRAKE`, not boost or descent. |
| Command check | Brake-fit rows have nonzero applied or measured deployment. |
| Apogee check | Observed apogee occurs after fitted coast/brake rows. |
| Physical check | Fitted `CDA_body` and `CDA_brake` are finite, non-negative, and plausible for the vehicle. |
| Residual check | Fitted constants reduce prediction bias/RMSE against held-out or cross-validated flights. |
| Provenance check | Metadata records mass, density assumption, firmware build, actuator calibration, and anomalies. |

## 11. Example Target Header

This is the long-term target header. It includes the implemented P0 fields plus
remaining P1/P2 identification-focused additions.

```csv
schema_version,flight_id,row_seq,loop_seq,t_us,t_ms,dt_loop_us,dt_imu_us,baro_valid,baro_updated,baro_seq,bmp_T,bmp_P,bmp_alt,imu_valid,imu_updated,imu_seq,ax,ay,az,gx,gy,gz,a_norm,aux_valid,aux_updated,aux_seq,lis_ax,lis_ay,lis_az,pmod_accel_valid,pmod_accel_updated,pmod_accel_seq,pmod_accel_kind,pmod_raw_x,pmod_raw_y,pmod_raw_z,pmod_ax,pmod_ay,pmod_az,pmod_a_norm,mag_valid,mag_updated,mag_seq,mag_raw_x,mag_raw_y,mag_raw_z,mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,att_valid,att_updated,att_seq,q0,q1,q2,q3,auxvz_valid,auxvz_updated,auxvz_seq,a_vertical,est_valid,est_updated,est_seeded,est_seq,est_h,est_v,est_a,P00,P01,P10,P11,est_age_ms,arm_state,policy_runtime_enabled,software_arm_token,phase,phase_diag_valid,phase_diag_updated,phase_diag_seq,phase_diag_t_ms,phase_diag_age_ms,phase_launch_latched,phase_burnout_latched,phase_descent_latched,phase_launch_candidate,phase_burnout_candidate,phase_descent_candidate,phase_boost_dwell_met,phase_coast_dwell_met,phase_brake_active,phase_launch_confirm_ms,phase_burnout_confirm_ms,phase_descent_confirm_ms,phase_since_launch_ms,phase_since_burnout_ms,policy_valid,policy_cmd,policy_cmd_desired,policy_cmd_slewed,policy_cmd_applied,apogee_no_brake,apogee_full_brake,target_apogee,apogee_error,target_nominal,target_effective,uncertainty_margin,safety_runtime_ok,safety_allows_actuation,actuator_us,brake_pos_valid,brake_pos01_meas,warn_mask,sd_runtime_failed
```

The existing fitter can continue to use the subset:

```text
t_us, phase, est_h, est_v, policy_cmd, policy_valid
```

but future identification should prefer the richer command and validity fields.

## 12. Recommended Next Engineering Actions

With the P0 SD logger fields and host validation scaffolding implemented, the
next validation and development steps are:

1. Collect current-schema SD logs that include phase, policy command, actuator pulse, estimator state, covariance, warning mask, and observed coast-through-apogee behavior.
2. Run `tests/host/policy_aero_identification_report.py` on real current-flight logs and commit the Markdown/JSON report with the source logs.
3. Run `tests/host/heldout_replay_validation.py` using separate fit and held-out flights before changing aerodynamic constants.
4. Use `tests/host/firmware_in_loop_shim.py` with deterministic command/sensor rows to exercise estimator, phase, command, and policy interactions before target-board tests.
5. Validate Teensy 4.1 servo pulse width with an oscilloscope or logic analyzer and commit the result as a test artifact.
6. Extend simulation from a coast-only analytical model toward a repeatable plant model with sensor noise, actuator dynamics, and fault injection.
7. Build a C++ firmware-in-the-loop target that compiles production modules against Arduino, Serial, SD, sensor, and time mocks.

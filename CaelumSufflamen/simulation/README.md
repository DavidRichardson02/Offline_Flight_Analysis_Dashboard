# Simulation and Hardware-in-the-Loop Plan

This repository currently includes analytical host-side policy simulation, SD-log replay validation, and a deterministic firmware-loop host shim. It does not yet include a full C++ firmware-in-the-loop build or hardware-in-the-loop simulation environment.

## Current Level

| Level | Artifact | Status | Purpose |
| --- | --- | --- | --- |
| 0 | `SIM_APOGEE` Serial command | committed | On-target closed-form policy probe |
| 1 | `tests/host/policy_coast_sim.py` | committed | 1D analytical coast simulation with policy command shaping |
| 2 | `tests/host/replay_policy_validation.py` | committed | Replay SD-style logs against the configured apogee model |
| 3 | `tests/host/firmware_in_loop_shim.py` | committed | Replay deterministic rows through command, estimator, phase, and policy host shims |
| 4 | firmware-in-the-loop C++ build with mocked Arduino/sensor APIs | planned | Compile policy, phase, parser, estimator, and logger code into a host test binary |
| 5 | Teensy 4.1 hardware-in-the-loop rig | planned | Exercise real scheduler timing, Serial commands, SD logging, servo pulse output, and sensor input emulation |

## Repeatable Control-Law Evaluation Path

1. Use `policy_coast_sim.py` to sweep initial altitude, vertical speed, and target apogee.
2. Use `replay_policy_validation.py` to replay real SD logs and report prediction bias/RMSE.
3. Use `heldout_replay_validation.py` to fit on training flights and compare apogee prediction error against held-out flights.
4. Use `firmware_in_loop_shim.py` to replay deterministic command/sensor rows through host shims before moving to target hardware.
5. Promote real flight logs into `validation/data/<flight_id>/` and generated summaries into `validation/results/`.
6. Build a C++ firmware-in-the-loop target by replacing Arduino timing, Serial, SD, and sensor APIs with deterministic host shims.
7. Build a Teensy 4.1 HIL rig that feeds repeatable sensor traces and captures servo pulse widths, Serial telemetry, and SD output.

## Firmware-Loop Shim Input

`tests/host/firmware_in_loop_shim.py` accepts a CSV with deterministic replay rows. The preferred columns are:

| Column | Required | Meaning |
| --- | --- | --- |
| `t_ms` or `t_us` | Yes | Replay timestamp. |
| `serial` | Optional | Serial bytes injected before that row's estimator/phase/policy pass. |
| `est_h`, `est_v` | Recommended | Recorded or synthetic estimator state used directly by the shim. |
| `baro_alt_m` | Optional | Barometric altitude used when `est_h`/`est_v` are not supplied. |
| `imu_a_norm` | Yes for phase | Acceleration norm used by the phase detector shim. |
| `est_a` or `a_vertical_mps2` | Optional | Vertical acceleration observability passed through the estimator shim. |

The shim output records command responses, estimator state, phase, policy validity, command, and predicted apogee fields. It is a deterministic integration harness for recorded inputs, not a substitute for compiling the production C++ firmware against Arduino mocks.

## Proposed HIL Interfaces

| Interface | Injection or capture method | Required evidence |
| --- | --- | --- |
| Barometer | pressure/temperature replay stream | estimator altitude matches replay contract |
| IMU | accel/gyro replay stream | attitude and vertical acceleration remain bounded |
| Serial | scripted command source and captured output | arming and policy gates follow expected command sequence |
| SD card | real card or emulated storage | logged rows preserve schema and warning semantics |
| Servo | pulse-width capture on `PIN_AIRBRAKE_SERVO` | commanded microseconds match actuator contract |
| Time | deterministic replay clock for host, measured Teensy clock for HIL | loop cadence and freshness gates are observable |

## Acceptance Criteria

- replay tests include no-command, partial-command, full-command, stale-estimator, and descending cases
- fitted constants are traceable to committed data and result artifacts
- firmware-loop shim tests run without target hardware
- C++ firmware-in-the-loop tests compile production modules against deterministic host mocks
- HIL captures prove command gating before validating closed-loop performance
- real-flight claims are separated from bench-only evidence

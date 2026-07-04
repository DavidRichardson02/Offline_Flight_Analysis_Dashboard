# Validation Results

This directory stores generated analysis outputs.

The current `coefficient_report.*` and `heldout_replay.json` files may be
generated from synthetic fixtures under `validation/data/flight_2026_001` through
`validation/data/flight_2026_003` when no real SD logs are available. Those
fixtures are theoretical tool-check data only. They must not be used as evidence
for changing `POLICY_CDA_BODY_M2` or `POLICY_CDA_BRAKE_M2`.

For aerodynamic coefficient updates, commit real current-branch SD logs,
metadata, event notes, coefficient reports, and held-out replay summaries with
clear provenance.

`render_all_views.ps1` renders the apogee evidence, apogee prediction residual
timeline, estimator-policy causal phase-space, raw-vs-filtered provenance, EKF innovation/covariance, temporal
freshness/latency, aerodynamic coefficient observability, wind-relative landing
footprint/uncertainty cone, onboard minimal science HUD pages, energy-state
phase, phase timeline, health dashboard, orientation-vector,
magnetic-field-quality, gravity-norm stability, sensor-frame alignment verifier,
readiness-gate, tilt-compensated heading
demonstrator, and heading
sign/calibration validator SVG/JSON views from one current-schema SD CSV. With
no `-InputCsv`, it first generates a
deterministic synthetic plant-simulation log and writes
`synthetic_nonflight_visual_*` outputs. Those files are non-flight tool-check
artifacts only and must not be used as flight evidence or coefficient evidence.

Example synthetic checkout:

```powershell
powershell -ExecutionPolicy Bypass -File .\validation\results\render_all_views.ps1
```

Example real-log rendering:

```powershell
powershell -ExecutionPolicy Bypass -File .\validation\results\render_all_views.ps1 `
  -InputCsv .\validation\data\flight_001\LOG000.CSV `
  -Prefix flight_001
```

Bench serial captures are kept separate from synthetic outputs. Keep live
`PLOT APOGEE`, `PLOT PROVENANCE`, `PLOT ENERGY`, `PLOT PHASE`, `PLOT HEALTH`,
`PLOT ORIENT`, `PLOT ESTIMATOR`, estimator-policy phase-space, EKF
innovation/covariance, temporal freshness/latency, aerodynamic coefficient
observability, wind-relative landing footprint, magnetic field quality, gravity
norm stability, onboard HUD pages, sensor-frame alignment, tilt-compensated
heading, heading sign/calibration validator, and readiness gate artifacts under
`bench_*` names and record the capture commands, port, sample counts, installed
profile, and renderer summaries in a bench manifest.

The tilt-compensated heading demonstrator is an offline analysis view. It uses
logged attitude quaternion, LIS3DH gravity-stability, CMPS2 magnetic-vector
quality, and warning-mask evidence to decide whether a computed heading sample is
ready. It does not imply that magnetometer heading is part of the flight-control
path.

The heading sign/calibration validator is a second-stage offline analysis view.
It consumes the tilt-compensated heading JSON, segments controlled bench
roll/pitch poses, and reports whether the capture supports tilt-compensation
sign convention and CMPS2 heading-bin calibration coverage.

The sensor-frame alignment verifier is a controlled-pose bench view. It consumes
current-schema SD rows, captured `PLOT ORIENT` text, or orientation JSON, then
checks six-face gravity-axis coverage, accelerometer roll/pitch recomputation,
gravity norm consistency, optional expected face order, and CMPS2 validity.

The estimator-policy causal phase-space display consumes current-schema SD rows
or captured `PLOT APOGEE` text. It overlays estimator altitude/velocity state,
no-brake and full-brake apogee predictions, effective target, phase, policy
gates, command, actuator response, freshness, and warnings so blocked or
authorized policy decisions can be traced to their telemetry causes.

The apogee prediction residual timeline consumes current-schema SD rows or
captured `PLOT APOGEE` text. It back-labels no-brake, full-brake, and
selected-command apogee predictions against observed apogee, either supplied
with `--observed-apogee-m` or inferred from maximum logged estimator altitude.
Rows that require host-model fallback or host selected-command reconstruction
are marked as model-assisted rather than pure firmware-prediction evidence.

The EKF innovation/covariance dashboard consumes current-schema SD rows or
captured `PLOT ESTIMATOR` text. Firmware currently publishes post-update
estimator state and covariance, not the exact pre-update Kalman innovation `y`
and innovation covariance `S`, so the dashboard labels normalized innovation as
a residual proxy using `est_h - baro_alt` and `sqrt(P00 + kR)`. It is still a
useful consistency instrument for stale inputs, residual excursions, covariance
symmetry, positive-semidefinite behavior, and published sigma contracts.

The temporal freshness/latency oscilloscope consumes current-schema SD rows or
captured `PLOT HEALTH` text. It uses SD update flags and sequence counters to
derive channel ages when explicit age fields are unavailable, then reports
sample-period jitter, row continuity, per-channel sequence gaps, stale windows,
warning-mask evidence, and SD runtime failure intervals.

The aerodynamic coefficient observability map consumes current-schema SD rows.
It is a pre-fit display that checks whether body/brake drag coefficients are
observable before running coefficient identification: phase gates, estimator
state, warning-free windows, velocity and apogee leverage, closed-command body
baseline samples, open-command brake excitation, command span, design-matrix
conditioning, and measured-vs-proxy deployment evidence. A command-only result
is lower confidence than measured `brake_pos01_meas` evidence.

The wind-relative landing footprint / uncertainty cone consumes CSV logs with
horizontal position and ground-velocity fields plus wind metadata or CLI wind
overrides. It decomposes the projected landing displacement into ground-relative
motion, air-relative no-wind motion, wind drift, descent-time evidence, and a
2-sigma uncertainty ellipse. Projection uses the latest finite horizontal state
only while it is inside the configured freshness limit. Current vertical-only SD
logs are expected to render `horizontal_state_unavailable`; that is an
observability result, not a plotting failure.

The onboard minimal science HUD pages view consumes current-schema SD rows or
captured `PLOT HUD` text. It mirrors the firmware's compact onboard page
contract: flight state, apogee/control, attitude/field, and readiness/safety.
Each page is backed by explicit validity, freshness, warning, safety, and SD
evidence rather than presentation-only status text.

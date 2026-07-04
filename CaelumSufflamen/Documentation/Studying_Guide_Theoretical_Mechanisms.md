# Caelum Sufflamen Theoretical Mechanisms Studying Guide

This document is an extended theory companion to `Studying_Guide.md`. The original study guide explains how to move through the repository. This guide explains the theoretical mechanisms behind the firmware: why each subsystem exists, what physical or mathematical model it assumes, what evidence would validate it, and what failure modes a reviewer should look for.

The guide is intentionally conservative. It explains the implemented mechanisms and the intended physics, but it does not claim that the current aerodynamic constants are vehicle-identified or that the system is flight-ready.

## 1. Reading Contract

Use this guide when you want to answer mechanism-level questions such as:

| Question | Mechanism area |
| --- | --- |
| Why does the firmware need attitude estimation? | Body-frame acceleration must be rotated into a vertical world-frame estimate. |
| Why does the estimator combine IMU and barometer data? | IMU acceleration gives short-term dynamics; barometer altitude bounds drift. |
| Why does the policy only act in coast-like phases? | The apogee predictor assumes upward coast dynamics, not powered boost or descent. |
| Why does the policy solve with bisection? | Predicted apogee decreases monotonically with command in the implemented drag model. |
| Why do telemetry rows include validity and update flags? | A numerical value is not meaningful unless its freshness and validity are known. |
| Why are the aerodynamic constants still placeholders? | Current committed previous-year logs do not contain enough deployment and apogee evidence to identify them. |

Treat this file as a bridge between code review, flight dynamics, estimation theory, and validation planning.

## 2. Evidence Boundary

The repository supports these mechanism claims:

| Mechanism claim | Status |
| --- | --- |
| The firmware implements a deterministic Teensy 4.1 scheduler. | Supported by source and build documentation. |
| The firmware publishes validity-qualified sensor and estimator snapshots. | Supported by `include/data_types.h`, sensor modules, telemetry, and SD logger. |
| The firmware estimates altitude and vertical speed with a two-state Kalman filter. | Supported by `src/estimation.cpp` and `src/kalman_alt2.cpp`. |
| The firmware computes an airbrake command from a closed-form quadratic-drag coast model. | Supported by `src/airbrake_policy.cpp`. |
| The policy command is gated by arming, phase, estimator freshness, altitude, speed, and safety checks. | Supported by command, policy, safety, and actuator modules. |
| The aerodynamic constants are identified for this vehicle. | Not supported. |
| The committed previous-year data is sufficient to update airbrake drag coefficients. | Not supported by the audit artifact. |
| Full simulation, firmware-in-the-loop, and hardware-in-the-loop evaluation are complete. | Not supported. |

When presenting the project, use this wording:

```text
The repository contains a reviewable airbrake-control firmware architecture and host-side validation tools. The aerodynamic constants are explicitly placeholders until vehicle-specific identification data is collected and committed.
```

Do not use this wording:

```text
The controller has been aerodynamically validated for flight.
```

## 3. Whole-System Mechanism Map

The control chain is:

```text
pressure, acceleration, angular rate
-> validity-qualified sensor snapshots
-> attitude estimate
-> vertical acceleration estimate
-> altitude and vertical-speed estimate
-> flight-phase classification
-> apogee prediction and command solve
-> runtime policy gate
-> safety gate
-> servo pulse command or forced idle
-> telemetry and SD evidence
```

The theoretical idea is not simply "read sensors and move servo." The actual design is a sequence of contracts:

| Contract | Question answered |
| --- | --- |
| Sensor validity | Did this measurement exist and have finite physical units? |
| Attitude validity | Can body-frame acceleration be interpreted in a world vertical frame? |
| Estimator validity | Is altitude and vertical speed seeded, finite, and fresh? |
| Phase validity | Is the vehicle in a context where the policy model is appropriate? |
| Policy validity | Does the model request a positive non-idle command under all gates? |
| Safety validity | Is it still safe to let any non-idle command reach hardware? |
| Log validity | Does the recorded row preserve enough metadata to reconstruct the decision? |

## 4. Deterministic Embedded Control Theory

### 4.1 Determinism

A deterministic embedded control loop has bounded work, predictable ordering, and explicit state ownership. In this repository, that appears as:

| Design element | Theoretical reason |
| --- | --- |
| Fixed 50 Hz scheduler | Gives the control stack a known nominal update cadence. |
| Non-blocking command parser | Prevents operator input from delaying sensor and actuator work. |
| One sensor acquisition attempt per poll | Bounds runtime sensor work and keeps timing analyzable. |
| Fixed-count policy bisection | Prevents a variable-time numerical solver from entering flight loop timing. |
| Explicit fail-idle actuator path | Makes the safe output the default result of uncertainty or invalid state. |

The important theoretical principle is bounded response:

```text
For each scheduler pass, every subsystem should have a known maximum amount of work.
```

This is why the code avoids unbounded retries, dynamic allocation, and waiting for new serial input inside the control path.

### 4.2 Scheduler Period

The configured loop rate is:

```text
LOOP_HZ = 50
LOOP_PERIOD_US = 1000000 / LOOP_HZ = 20000 us
```

At 50 Hz, the nominal control period is 20 ms. The estimator does not blindly assume this value for IMU propagation. It uses measured IMU timestamp differences and rejects unrealistic intervals with:

```text
EST_MIN_IMU_DT_S = 0.0005
EST_MAX_IMU_DT_S = 0.1000
```

The theoretical reason is that numerical integration error and covariance propagation depend on the actual elapsed time:

```text
h_next = h + v*dt + 0.5*a*dt^2
v_next = v + a*dt
```

A corrupted `dt` can create a physically impossible state jump. The code therefore treats time as a measured input that must be validated.

## 5. Snapshot Semantics as Information Theory

The project uses snapshots with fields such as:

```text
valid
updated
t_ms
t_us
seq
payload...
```

These fields encode information quality.

| Field | Theory-level meaning |
| --- | --- |
| `valid` | The payload is semantically usable. |
| `updated` | The owning module published fresh data during the latest service pass. |
| `t_ms` | Millisecond timestamp for freshness checks and human diagnostics. |
| `t_us` | Microsecond timestamp for sensor timing and log ordering. |
| `seq` | Monotonic publication count for detecting repeated or missing publications. |

The distinction between `valid` and `updated` is critical.

```text
valid == true
```

means the current payload can be interpreted.

```text
updated == true
```

means this scheduler pass produced a fresh publication.

A valid old estimate may still become unsafe if its age exceeds a freshness threshold. This is why safety and policy use timestamp age, not only validity.

## 6. Sensor Measurement Theory

### 6.1 Barometer

The BMP5xx barometer provides pressure and temperature. The firmware converts pressure to altitude using a standard-atmosphere relationship through `pressure_to_altitude_m(...)`.

The theoretical relationship is:

```text
pressure decreases with altitude
```

so the firmware can infer altitude from pressure if a reference pressure is known. The project uses two pressure references:

| Reference | Meaning |
| --- | --- |
| `sea_level_hpa` | Standard-atmosphere reference used by the pressure-to-altitude conversion. |
| `baro_baseline_hpa` | Local pad baseline pressure captured before flight, when available. |

The estimator works in a relative altitude frame. If a local baseline exists, the baseline pressure is converted to a baseline altitude and subtracted:

```text
h_relative = h_current_standard_atmosphere - h_baseline_standard_atmosphere
```

If no explicit baseline exists, the estimator captures the first valid barometric altitude as its live zero reference.

### 6.2 IMU

The BMI088 provides:

```text
ax, ay, az in m/s^2
gx, gy, gz in rad/s
```

The accelerometer does not directly measure "vehicle acceleration" in the simple Newtonian sense. It measures specific force: the non-gravitational acceleration experienced by the sensor. Interpreting that measurement requires knowing sensor orientation.

The gyroscope measures angular rate. Gyro data can be integrated to update attitude, but integration drifts. Accelerometer data gives a gravity-direction reference during low-disturbance periods, but rocket acceleration can temporarily corrupt the gravity assumption. The Madgwick filter blends these information sources through a correction gain.

### 6.3 Auxiliary Accelerometer

The LIS2DU12 auxiliary accelerometer is logged and validity-qualified. In the current active estimator path, BMI088 acceleration and gyro drive attitude and vertical acceleration. The auxiliary stream remains useful for comparison, diagnostics, and future redundancy.

## 7. Pressure-to-Altitude Mechanism

The barometric altitude calculation depends on assumptions:

| Assumption | Practical implication |
| --- | --- |
| Atmosphere approximates a standard pressure-altitude relationship. | Weather and launch-site pressure errors can bias altitude. |
| Local pressure baseline is captured before flight. | Relative altitude is more meaningful than sea-level absolute altitude for apogee targeting. |
| Pressure port dynamics are acceptable. | Transient pressure disturbances can appear as altitude noise. |

The firmware handles baseline selection this way:

```text
if baro_baseline_hpa is finite and positive:
    use configured pressure baseline
else:
    capture first trusted live altitude as zero
```

The theoretical tradeoff is:

| Method | Advantage | Risk |
| --- | --- | --- |
| Captured pressure baseline | Better pad-relative altitude frame. | Requires reliable preflight calibration. |
| First valid live altitude | Automatic fallback. | Can capture a bad zero if first sample is disturbed. |

## 8. Attitude Theory

### 8.1 Why Attitude Exists

The airbrake policy needs vertical speed and altitude. The Kalman predictor needs vertical acceleration. The IMU measures acceleration in the body frame:

```text
a_body = [ax, ay, az]
```

But the estimator needs acceleration in the world vertical direction:

```text
a_world_z
```

If the rocket tilts, body `z` is no longer the same as world vertical. Without attitude compensation, a tilted but accelerating rocket can be interpreted incorrectly.

### 8.2 Quaternion Representation

The firmware stores attitude as a unit quaternion:

```text
q = [q0, q1, q2, q3]
```

A quaternion is used instead of Euler angles because:

| Quaternion benefit | Why it matters |
| --- | --- |
| No gimbal lock in the represented orientation. | Rocket attitude can pass through steep angles. |
| Compact rotation operator. | Efficient for embedded math. |
| Easy normalization. | Unit-length enforcement keeps rotations physically meaningful. |

The code normalizes the quaternion after integration. This is not cosmetic. A non-unit quaternion no longer represents a pure rotation and can scale or distort vectors.

### 8.3 Madgwick Update

The implemented attitude update combines:

```text
gyro integration term
- beta * accelerometer correction gradient
```

The gyro term follows rigid-body kinematics:

```text
q_dot_gyro = 0.5 * q * omega
```

The accelerometer correction tries to align the quaternion-implied gravity direction with the measured acceleration direction after normalization.

The gain:

```text
MADGWICK_BETA = 0.1
```

controls how aggressively the filter corrects orientation drift from accelerometer information.

| Higher beta | Lower beta |
| --- | --- |
| Faster roll/pitch correction. | Less acceleration disturbance injected into attitude. |
| More sensitivity to high-dynamic acceleration. | More gyro drift between corrections. |

For rockets, the beta tradeoff is important because boost acceleration is not gravity. During high acceleration, the accelerometer direction can be a poor gravity reference.

## 9. Vertical Acceleration Projection

After attitude is valid, the firmware computes the world vertical acceleration component from the body-frame acceleration vector and quaternion rotation.

The implemented projection uses the third row of the body-to-world rotation matrix:

```text
a_world_z =
  2*(q1*q3 - q0*q2)*ax
+ 2*(q0*q1 + q2*q3)*ay
+ (q0*q0 - q1*q1 - q2*q2 + q3*q3)*az
```

Then the firmware adds gravity:

```text
a_vertical = a_world_z + g
```

under the validated sign convention in this branch.

The important study point is that the sign convention is part of the implementation contract. If sensor orientation, mounting, or axis sign changes, this projection must be revalidated. A sign error here can invert acceleration, corrupt velocity, and cause phase and policy errors.

## 10. State-Space Estimation Theory

The altitude estimator uses a two-state model:

```text
x = [h, v]^T
```

where:

```text
h = altitude in meters
v = vertical speed in m/s
```

The input is vertical acceleration:

```text
a = a_vertical
```

The discrete-time prediction is:

```text
h_next = h + v*dt + 0.5*a*dt^2
v_next = v + a*dt
```

The barometric measurement is:

```text
z = h + measurement_noise
```

This is a good minimal estimator for a resource-constrained embedded controller because:

| Feature | Benefit |
| --- | --- |
| Two states | Simple, reviewable, low computation. |
| IMU prediction | Captures short-term vertical dynamics. |
| Baro correction | Bounds drift in integrated acceleration. |
| Covariance output | Gives downstream policy a measure of altitude uncertainty. |

It is not a complete vehicle navigation filter. It does not estimate lateral motion, full aerodynamic state, sensor biases, or atmospheric model errors.

## 11. Kalman Filter Mechanism

### 11.1 Prediction

The prediction step propagates the state and covariance:

```text
x_pred = F*x + B*a
P_pred = F*P*F^T + Q
```

For this model:

```text
F = [[1, dt],
     [0,  1]]
```

and the acceleration input affects the state as:

```text
B = [0.5*dt^2,
     dt]
```

The process-noise covariance is discretized from acceleration uncertainty:

```text
Q00 = kSigmaA2 * dt^4 / 4
Q01 = kSigmaA2 * dt^3 / 2
Q11 = kSigmaA2 * dt^2
```

The theory is:

```text
larger dt -> more uncertainty growth
larger acceleration uncertainty -> more uncertainty growth
```

### 11.2 Measurement Update

The measurement is altitude only:

```text
z = h
H = [1, 0]
```

The innovation is:

```text
y = z_meas - h_pred
```

The innovation variance is:

```text
S = P00 + R
```

The Kalman gain is:

```text
K = P*H^T / S
K0 = P00 / S
K1 = P10 / S
```

The state correction is:

```text
h = h + K0*y
v = v + K1*y
```

Even though the barometer measures only altitude, vertical velocity can still be corrected because covariance couples altitude and velocity. If the filter believes altitude and velocity errors are correlated, an altitude innovation can inform velocity.

### 11.3 Joseph-Form Covariance Update

The code uses Joseph form:

```text
P = (I - K*H) * P * (I - K*H)^T + K*R*K^T
```

Theoretical benefit:

| Simplified update | Joseph-form update |
| --- | --- |
| Less arithmetic. | More numerically robust. |
| Easier to write incorrectly under finite precision. | Better preserves positive-semidefinite covariance. |

This matters on microcontrollers because floating-point roundoff and repeated updates can slowly damage covariance consistency.

## 12. Covariance as Control Evidence

The estimator publishes:

```text
P00, P01, P10, P11
```

The altitude variance is:

```text
P00
```

The one-sigma altitude uncertainty estimate is:

```text
sigma_h = sqrt(P00)
```

The policy uses this to make the effective target more conservative:

```text
uncertainty_margin = POLICY_SIGMA_MARGIN_N * sqrt(P00)
target_effective = POLICY_TARGET_APOGEE_M - uncertainty_margin
```

The margin is bounded by:

```text
POLICY_MAX_UNCERTAINTY_MARGIN_M
```

The theory is risk-sensitive control:

```text
When altitude uncertainty is higher, aim lower to reduce overshoot risk.
```

This does not prove the estimator covariance is statistically calibrated. It only means the architecture exposes covariance and uses it in a conservative direction. Actual calibration requires comparing estimated uncertainty to observed errors.

## 13. Flight-Phase State Machine Theory

The phase detector implements a conservative finite-state machine:

```text
IDLE -> BOOST -> COAST -> BRAKE -> DESCENT
```

`BRAKE` is not a permanently latched phase. It reflects active policy command intent after burnout and before descent.

The detector uses three techniques:

| Technique | Purpose |
| --- | --- |
| Latches | Prevent the system from forgetting major flight milestones. |
| Dwell timers | Prevent one noisy sample from causing a phase transition. |
| Multiple conditions | Require altitude, vertical speed, acceleration, or command context as appropriate. |

### 13.1 Launch Detection

Launch can be detected from acceleration or vertical motion:

```text
launch_by_accel =
  a_norm >= boost_accel_threshold
  and h >= boost_min_alt

launch_by_motion =
  h >= boost_min_alt
  and v >= launch_min_vz
```

The candidate must remain true for the confirmation dwell:

```text
FLIGHT_PHASE_LAUNCH_CONFIRM_MS = 60
```

This guards against pad handling, vibration, or one bad IMU sample.

### 13.2 Burnout and Coast

After launch, boost must last at least:

```text
FLIGHT_PHASE_MIN_BOOST_DWELL_MS = 250
```

Burnout/coast requires lower acceleration norm, enough altitude, and positive upward velocity. The detector does not immediately declare coast from one reduced-acceleration sample. It requires a sustained candidate:

```text
FLIGHT_PHASE_BURNOUT_CONFIRM_MS = 120
```

The theory is debounce for physical state estimation:

```text
phase = latched interpretation of measurements, not raw measurement thresholding
```

### 13.3 Descent

Descent is based on sustained non-positive vertical speed after coast dwell:

```text
v <= FLIGHT_PHASE_DESCENT_VZ_MPS
```

with:

```text
FLIGHT_PHASE_DESCENT_CONFIRM_MS = 300
```

This prevents a short velocity estimate dip near apogee from instantly locking the system into descent.

## 14. Coast-Phase Flight Dynamics

The airbrake policy uses an upward-coast model. In the model:

```text
v > 0
```

and acceleration is:

```text
dv/dt = -g - k*v^2
```

where:

```text
k = rho * CDA / (2*m)
```

For airbrake command `u`:

```text
CDA(u) = CDA_body + u*CDA_brake
k(u) = rho * (CDA_body + u*CDA_brake) / (2*m)
```

The command `u` is normalized:

```text
u = 0 means no additional brake deployment intent
u = 1 means maximum permitted deployment intent
```

### 14.1 Why the Model is Coast-Only

The model omits thrust:

```text
dv/dt = -g - drag
```

During powered boost, the actual dynamics include thrust:

```text
dv/dt = thrust/m - g - drag
```

Therefore the policy model is not appropriate during boost. This is why phase gating matters. The policy is permitted only when the vehicle is in `COAST` or `BRAKE` and still moving upward above the speed threshold.

### 14.2 Ballistic Limit

If drag is negligible:

```text
k -> 0
```

the apogee prediction becomes:

```text
h_ap = h + v^2/(2*g)
```

This is the familiar energy result:

```text
kinetic energy per unit mass = altitude gain against gravity
0.5*v^2 = g*delta_h
```

### 14.3 Quadratic-Drag Apogee Formula

For:

```text
dv/dt = -g - k*v^2
```

use:

```text
dv/dt = (dv/dh)*(dh/dt) = v*(dv/dh)
```

Then:

```text
v*(dv/dh) = -g - k*v^2
```

Let:

```text
w = v^2
dw/dh = 2*v*(dv/dh)
```

So:

```text
0.5*dw/dh = -g - k*w
dw/dh = -2*g - 2*k*w
```

Solving this first-order equation from current `v` to apogee where `v = 0` gives:

```text
delta_h = ln(1 + k*v^2/g) / (2*k)
```

Therefore:

```text
h_ap(u) = h + ln(1 + k(u)*v^2/g) / (2*k(u))
```

This is the formula implemented by the policy.

## 15. Airbrake Command Theory

The policy answers this question:

```text
What normalized airbrake command u makes predicted apogee approach the target?
```

The model has a useful monotonic property:

```text
larger u -> larger CDA -> larger k -> lower predicted apogee
```

Because of that monotonic relationship, the solver can use bisection.

### 15.1 No-Command Region

First, the policy predicts apogee with no deployment:

```text
h_ap(0)
```

If:

```text
h_ap(0) <= target + deadband
```

then the policy returns zero command.

The deadband reduces command chatter around the target caused by estimator noise or small model changes.

### 15.2 Saturation Region

The policy predicts apogee at maximum permitted deployment:

```text
h_ap(u_max)
```

If:

```text
h_ap(u_max) > target
```

then even full deployment is predicted to overshoot. The best available command under the model is:

```text
u = u_max
```

This is saturation. It does not mean the vehicle will meet target. It means the available modeled drag authority is insufficient.

### 15.3 Bisection Region

If:

```text
h_ap(0) > target
h_ap(u_max) <= target
```

then a solution exists inside `[0, u_max]`.

Bisection repeatedly halves the interval:

```text
lo = 0
hi = u_max

for fixed number of steps:
    mid = 0.5*(lo + hi)
    if h_ap(mid) > target:
        lo = mid
    else:
        hi = mid
```

The code uses a fixed iteration count:

```text
POLICY_BISECTION_STEPS = 18
```

The theoretical tradeoff is favorable for embedded control:

| Bisection property | Why it matters |
| --- | --- |
| Deterministic cost | Same loop count every valid policy solve. |
| No derivative needed | Avoids sensitivity to analytical derivative errors. |
| Robust to simple monotonic nonlinear models | Good match for the implemented apogee function. |
| Requires monotonicity | If future aerodynamics break monotonicity, solver assumptions must be revisited. |

## 16. Command Shaping Theory

After the desired command is solved, the policy applies slew limiting:

```text
delta_u_allowed = POLICY_SLEW_PER_SEC * dt
```

The output cannot change more than that amount from the previous command memory.

The theoretical reasons are:

| Reason | Explanation |
| --- | --- |
| Actuator realism | Physical mechanisms do not move instantaneously. |
| Reduced mechanical stress | Avoids abrupt demand steps. |
| Noise filtering | Prevents estimator jitter from becoming rapid command motion. |
| Timing awareness | Command-rate limit scales with measured elapsed time. |

If timing is invalid or too large, the implementation collapses `dt` to zero or freezes memory in the relevant path. This prevents one delayed cycle from allowing an oversized command jump.

## 17. Runtime Authority and Safety Theory

The control law computes intent. It does not directly own hardware authority.

The non-idle command path requires:

```text
AIRBRAKE_POLICY_ENABLED at compile time
policy_runtime_enabled == true
arm_state == ARMED
software_arm_token == true
phase == COAST or phase == BRAKE
est.valid == true
finite h and v
estimator age <= POLICY_MAX_EST_AGE_MS
h >= POLICY_MIN_ALT_M
v >= POLICY_MIN_VZ_MPS
positive solved command after slew limiting
```

Then the final actuator application still requires:

```text
ACTUATION_ENABLED at compile time
cfg.valid == true
est.valid == true
estimator age <= EST_MAX_AGE_MS
```

The theory is separation of concerns:

| Layer | Responsibility |
| --- | --- |
| Policy | Computes what would be useful. |
| Runtime gates | Decide whether the policy is allowed to request non-idle intent. |
| Safety | Decides whether any non-idle intent may reach hardware now. |
| Actuator | Converts approved normalized command into servo pulse units. |

This layered design is important for review. A policy bug should not automatically imply a servo motion if safety and validity gates reject the state.

## 18. Arming Theory

The operator command path distinguishes arming from policy enable:

```text
ARM ARMED
POLICY 1
```

The `ARM ARMED` command is accepted only in `IDLE`. Any non-armed state clears policy runtime enable and forces the actuator idle through the command path.

The theoretical idea is authority staging:

| Gate | Meaning |
| --- | --- |
| Compile-time policy enable | The firmware image contains policy code. |
| Runtime arming | Operator explicitly authorizes the system before flight phase progression. |
| Runtime policy enable | Operator explicitly allows policy computation to produce non-idle intent. |
| Safety gate | Latest state remains usable at the moment of actuation. |

This is stronger than a single boolean because it makes accidental actuation require multiple independent permissions to be true.

## 19. Actuator Mapping Theory

The policy command is unitless:

```text
command01 in [0, 1]
```

The servo backend needs pulse-equivalent microseconds:

```text
us = servo_us_min + command01*(servo_us_max - servo_us_min)
```

With defaults:

```text
servo_us_min = 1000
servo_us_max = 2000
servo_us_idle = 1000
```

The code writes pulse widths directly through:

```text
writeMicroseconds(us)
```

The theoretical contract is:

| Control concept | Physical backend |
| --- | --- |
| `0.0` command | Minimum configured pulse. |
| `1.0` command | Maximum configured pulse. |
| idle | Configured idle pulse, clamped into safe span. |

Remaining validation gap:

```text
The repository still needs target-board pulse-width evidence from Teensy 4.1 output and the actual servo/mechanism.
```

Without that evidence, the code-level mapping is clear, but the physical mechanism travel and timing are not fully proven.

## 20. Warning Mask Theory

The warning mask compresses multiple health facts into one integer.

Current warning categories include:

| Bit group | Meaning |
| --- | --- |
| Sensor hardware health | Whether enabled sensor backends initialized. |
| Snapshot validity | Whether the latest baro, IMU, auxiliary, vertical acceleration, attitude, and estimator streams are usable. |
| Configuration validity | Whether runtime configuration is valid. |
| SD fault | Whether logging is unavailable or failed. |

The theory is diagnostic compression:

```text
warning mask = compact machine-readable health summary
```

Because Serial and SD use the same `telemetry_warn_mask(...)` function, both live and persistent evidence share the same health semantics.

## 21. Telemetry and Logging as Measurement Instruments

Telemetry and SD logs are not decorative. They are part of the evidence model.

A good control log must preserve:

| Evidence field | Why it matters |
| --- | --- |
| Raw sensor values | Lets reviewers inspect measurements. |
| Validity flags | Prevents treating invalid payload as truth. |
| Update flags | Shows whether a value was freshly published in that pass. |
| Sequence counters | Helps detect repeated or missing publications. |
| Timestamps | Enables freshness and timing analysis. |
| Estimator state | Shows what the controller believed. |
| Phase diagnostics | Explains state-machine transitions. |
| Policy predictions | Explains why the command was chosen. |
| Arming and policy gates | Shows whether command authority existed. |
| Actuator pulse | Shows what was requested of hardware. |
| Warning mask | Gives compact health state per row. |

The theoretical principle is decision reconstructability:

```text
A reviewer should be able to reconstruct why the firmware did or did not command deployment from the log row sequence.
```

If a future change adds a new control gate, that gate should usually appear in telemetry and SD logs.

## 22. Data Requirements for Aerodynamic Identification

The policy constants:

```text
POLICY_VEHICLE_MASS_KG
POLICY_RHO_KGPM3
POLICY_CDA_BODY_M2
POLICY_CDA_BRAKE_M2
```

define the coast-drag model. The current aerodynamic constants are placeholders. Replacing them requires data that constrains the model.

### 22.1 Body Drag Identification

To estimate body drag, useful data should include:

| Required evidence | Why |
| --- | --- |
| Coast interval after burnout | The model applies after thrust. |
| Altitude over time | Needed to observe coast trajectory and apogee. |
| Vertical speed or enough altitude samples to estimate it | Needed to fit dynamic trajectory. |
| Vehicle mass | Drag coefficient is coupled to mass through `k = rho*CDA/(2m)`. |
| Air density assumption or measurement | Drag coefficient is coupled to density. |
| Known no-brake or fully retracted condition | Body drag must be separated from brake drag. |
| Observed apogee | Needed to compare predicted and actual coast outcome. |

### 22.2 Airbrake Drag Identification

To estimate airbrake drag authority, useful data should include:

| Required evidence | Why |
| --- | --- |
| Time history of commanded deployment | Identifies when brake drag should affect trajectory. |
| Actual mechanism position if available | Servo command may not equal actual deployed geometry. |
| Coast-through-apogee data | Shows the resulting trajectory response. |
| Same estimator/log schema as policy | Keeps replay and fitting aligned with firmware semantics. |
| Multiple command levels | Helps separate linear command model from noise. |
| Comparable mass and vehicle configuration | Drag parameters change with vehicle setup. |

The existing previous-year data audit reports that the committed logs do not provide enough current-schema deployment and coast-through-apogee evidence to update the policy constants.

## 23. Replay Validation Theory

Replay validation answers:

```text
Given recorded inputs or recorded state estimates, what would the policy have predicted and commanded?
```

It is not the same as flight validation.

| Validation type | What it can show | What it cannot show by itself |
| --- | --- | --- |
| Host policy test | Formula and gate behavior match expectations. | Hardware timing and sensor behavior. |
| Replay validation | Policy behavior on recorded trajectories. | Whether future flights will match the model. |
| Coefficient fitting | Model constants explain selected data better. | That the model generalizes outside the dataset. |
| Board bench test | Commands, logs, and actuator output work on hardware. | Flight aerodynamic correctness. |
| Hardware-in-the-loop | Firmware handles repeatable injected scenarios. | Full physical flight environment unless the plant model is accurate. |
| Flight test | Real integrated behavior. | Complete coverage of all edge cases. |

The theoretical validation progression should be:

```text
unit/reference tests
-> replay validation
-> board-level bench validation
-> actuator pulse and mechanism validation
-> hardware-in-the-loop
-> carefully instrumented flight test
-> post-flight model residual analysis
```

## 24. Full Simulation and HIL Theory

A full simulation environment would need more than the current coast formula.

A useful simulation stack should model:

| Model component | Needed for |
| --- | --- |
| 1D or 6D vehicle dynamics | Predicting trajectory under thrust, drag, gravity, and attitude. |
| Motor thrust curve | Boost dynamics and burnout timing. |
| Atmospheric density variation | More realistic drag and pressure-altitude behavior. |
| Sensor noise and bias | Estimator robustness evaluation. |
| Barometer lag or pressure port effects | Altitude measurement realism. |
| IMU saturation and vibration | Phase and attitude robustness. |
| Servo dynamics | Delay, rate limit, travel limits, and nonlinearity. |
| Airbrake geometry | Mapping from servo output to drag area. |
| Scheduler and latency effects | Timing realism. |
| Fault injection | Sensor dropout, stale data, SD failures, command parser edge cases. |

Hardware-in-the-loop adds the real board:

```text
host plant model -> injected sensor interface or firmware shim -> Teensy firmware -> actuator/log outputs -> host verification
```

The challenge is interface realism. If the board still reads real I2C sensors, HIL needs either sensor emulation, firmware abstraction, or replay-capable input shims.

## 25. Common Misconceptions

| Misconception | Correct interpretation |
| --- | --- |
| `valid` means the data is fresh forever. | Validity and freshness are separate; old valid data can become unsafe. |
| `updated` is a consume latch. | It is an external observability flag for fresh publication in the latest pass. |
| Phase `COAST` proves the rocket is physically in perfect coast. | It is a conservative classification from noisy estimator and IMU data. |
| A positive policy command means hardware must move. | Safety and actuator gates still decide final output. |
| `command01 = 1` means the target will be met. | It means maximum modeled deployment is requested; authority may still be insufficient. |
| The barometer directly measures altitude. | It measures pressure; altitude is inferred from an atmospheric model and references. |
| The IMU directly measures vertical acceleration. | It measures body-frame specific force; attitude and gravity compensation are required. |
| The placeholder `CDA` values are results. | They are model inputs awaiting vehicle-specific identification. |
| A passing host test proves flight readiness. | Host tests prove selected software behavior, not integrated flight performance. |

## 26. Code-to-Theory Map

Use this table when studying source files.

| Theory topic | Primary implementation file |
| --- | --- |
| Snapshot and state semantics | `include/data_types.h` |
| Physical constants and tuning | `utils/config.h` |
| Sensor validity and unit conversion | `src/sensors.cpp` |
| Quaternion update and vertical projection | `src/attitude.cpp` |
| Estimator sequencing | `src/estimation.cpp` |
| Kalman predict and update equations | `src/kalman_alt2.cpp` |
| Dwell-latched phase classification | `src/flight_phase.cpp` |
| Coast drag and apogee prediction | `src/airbrake_policy.cpp` |
| Runtime arming and parser robustness | `utils/commands.cpp` |
| Final actuation safety predicate | `src/safety.cpp` |
| Servo pulse-width mapping | `src/actuator.cpp` |
| Live observability and warning mask | `utils/telemetry.cpp` |
| Persistent evidence logging | `utils/sd_logger.cpp` |
| Host regression evidence | `tests/host/run_host_tests.py` |
| Previous-year data limitation | `validation/results/previous_year_flight_data_audit.json` |

## 27. Mechanism-Level Review Checklist

When reviewing any future change, ask:

| Review question | Why it matters |
| --- | --- |
| Does the change preserve one writer per owned state field? | Avoids hidden multiple-owner bugs. |
| Does every new payload include validity and timestamp semantics? | Preserves evidence quality. |
| Does the estimator reject non-finite values and invalid timing? | Prevents NaN propagation and state jumps. |
| Does the phase machine avoid single-sample transitions? | Prevents chatter and false phase changes. |
| Does the policy remain bounded-time? | Preserves flight-loop determinism. |
| Does a new control gate appear in telemetry and SD logs? | Preserves decision reconstructability. |
| Does the actuator still fail idle on invalid state? | Preserves safe default behavior. |
| Does any coefficient change include data provenance? | Prevents unsupported tuning claims. |
| Does validation distinguish software behavior from flight performance? | Prevents overclaiming. |

## 28. Worked Thought Experiments

### 28.1 Stale Estimator

Scenario:

```text
state.est.valid == true
state.est.t_ms is older than the freshness threshold
policy command from previous cycle was positive
```

Expected mechanism:

```text
policy rejects stale estimate
policy resets command memory
safety rejects stale estimate
actuator is forced idle by top-level decision path
telemetry shows stale age and policy invalid
```

Lesson:

```text
validity alone is not enough for actuation.
```

### 28.2 High Altitude, Low Upward Speed

Scenario:

```text
h > POLICY_MIN_ALT_M
v < POLICY_MIN_VZ_MPS
phase == COAST
```

Expected mechanism:

```text
policy remains invalid and command remains zero
```

Reason:

```text
The model is a useful upward-coast law only while the vehicle is still climbing with enough speed.
```

### 28.3 Full Deployment Still Overshoots

Scenario:

```text
h_ap(u_max) > target
```

Expected mechanism:

```text
solver returns u_max
```

Interpretation:

```text
The model predicts insufficient drag authority. This is not a success condition; it is a saturation condition.
```

### 28.4 Invalid Attitude

Scenario:

```text
IMU acceleration is finite
attitude.valid == false
```

Expected mechanism:

```text
vertical acceleration projection returns invalid
Kalman prediction cannot use that acceleration path
estimator remains invalid or only updates from valid barometer seeding/correction as allowed
policy cannot act without valid fresh estimator state
```

Lesson:

```text
The control law depends on a chain, not isolated sensor values.
```

## 29. Study Exercises

### Exercise 1: Explain the Estimator in One Page

Include:

1. State vector.
2. Input vector.
3. Measurement model.
4. Prediction equations.
5. Update equations.
6. Meaning of `P00`.
7. Why barometer and IMU are complementary.

### Exercise 2: Derive the Apogee Formula

Start from:

```text
dv/dt = -g - k*v^2
```

Use:

```text
dv/dt = v*dv/dh
```

Show why:

```text
h_ap = h + ln(1 + k*v^2/g)/(2*k)
```

Then show the ballistic limit:

```text
h_ap = h + v^2/(2*g)
```

### Exercise 3: List Every Non-Idle Actuation Gate

Your answer should include:

1. Compile-time policy enable.
2. Runtime policy enable.
3. Arming state.
4. Software arm token.
5. Permitted phase.
6. Estimator validity.
7. Estimator freshness.
8. Altitude gate.
9. Vertical-speed gate.
10. Positive command after solve and slew limiting.
11. Compile-time actuation enable.
12. Runtime safety predicate.

### Exercise 4: Design a Coefficient Identification Log

Specify the minimum columns needed to identify body and brake drag:

1. Time.
2. Altitude.
3. Vertical speed.
4. Acceleration if available.
5. Phase.
6. Policy command.
7. Actuator pulse.
8. Actual brake position if available.
9. Mass and configuration metadata.
10. Ambient pressure or density assumption.
11. Observed apogee.
12. Warning mask and validity flags.

### Exercise 5: Review a Hypothetical Policy Change

If someone changes `POLICY_CDA_BRAKE_M2`, require:

1. Data source.
2. Fit method.
3. Fit residuals.
4. Replay results.
5. Before/after command behavior.
6. Explanation of vehicle configuration.
7. Host tests updated or rerun.
8. Explicit limitation statement.

## 30. Oral Defense Questions

Use these to prepare for a technical review:

| Question | Strong answer should mention |
| --- | --- |
| Why is the policy gated to coast? | The model omits thrust and assumes upward coast dynamics. |
| What does `CDA` mean? | Effective drag area, drag coefficient times reference area. |
| Why is bisection acceptable? | Predicted apogee is monotonic with command under the implemented model and runtime cost is fixed. |
| What does covariance do in the policy? | Altitude uncertainty lowers the effective target by a bounded margin. |
| Why is `updated` not a consume flag? | It reports fresh publication for observability; consumers use validity and age for trust. |
| What proves the constants are not identified? | The committed data audit reports no sufficient body or brake identification data. |
| What would make the system more flight-defensible? | Target-board pulse validation, current-schema flight logs, replay validation, coefficient fitting, HIL/FIL, and independent review. |

## 31. Recommended Next Development Steps

The best next engineering steps for the theory stack are:

1. Collect current-schema SD logs that include phase, policy command, actuator pulse, estimator state, covariance, warning mask, and observed coast-through-apogee behavior.
2. Add a documented coefficient-identification report that fits body and brake drag separately and records residuals.
3. Add replay validation that compares predicted apogee against observed apogee on held-out flights.
4. Build a firmware-in-the-loop shim for the estimator, phase detector, command parser, and policy using deterministic recorded inputs.
5. Validate Teensy 4.1 servo pulse width with an oscilloscope or logic analyzer and commit the result as a test artifact.
6. Extend simulation from a coast-only analytical model toward a repeatable plant model with sensor noise, actuator dynamics, and fault injection.

## 32. Final Mechanism Summary

Caelum Sufflamen is best understood as a layered evidence and control pipeline:

```text
measurements become snapshots
snapshots become estimates
estimates become phase context
phase context authorizes model use
the model predicts apogee
the solver computes deployment intent
safety decides whether intent may reach hardware
logs preserve the complete decision trail
```

The theoretical design is coherent: it separates measurement validity, estimator state, phase interpretation, model-based command intent, safety authority, and physical actuation. The main unresolved theoretical and empirical gap is not the existence of the mechanism. It is proving that the aerodynamic model parameters and actuator mapping match the actual vehicle closely enough for flight claims.

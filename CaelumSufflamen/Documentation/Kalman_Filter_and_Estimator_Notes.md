# Kalman Filter and Estimator Notes From the Ground Up

These notes explain the logic, derivation, and operation of the Kalman filter used by the Caelum Sufflamen estimator. They start from first principles and then map the mathematics directly to the repository implementation in `src/estimation.cpp`, `src/kalman_alt2.cpp`, `src/attitude.cpp`, `include/data_types.h`, and `utils/config.h`.

Source boundary: the repository is the source of truth for implemented behavior. The attached textbook, Alex Becker's `Kalman_Filter_from_the_Ground_Up_ebook_v3_1.pdf`, is used only to enrich the educational path, mathematical derivations, and study framing. Any statement about what the firmware actually does is grounded in `src/estimation.cpp`, `src/kalman_alt2.cpp`, `src/attitude.cpp`, `include/data_types.h`, and `utils/config.h`.

Textbook use policy: the textbook provides a useful progression from hidden state and uncertainty, to scalar filtering, to matrix Kalman filtering, to practical topics such as multirate updates, missing measurements, outliers, initialization, and simulation. These notes paraphrase those ideas and connect them to this repository. They do not treat the textbook examples as evidence that Caelum Sufflamen is validated for flight, and they do not replace the firmware's exact equations, constants, validity gates, or publication semantics.

## 0. Textbook-Informed Study Map

The most useful way to study this estimator is to separate three layers:

| Layer | Question | Textbook concept | Repository anchor |
| --- | --- | --- | --- |
| Statistical layer | How should uncertain information be represented? | Hidden state, random variables, variance, covariance, Gaussian belief. | `EstimatorSample` stores `h_m`, `v_mps`, `P00`, `P01`, `P10`, `P11`. |
| Dynamical layer | How does the physical state evolve between measurements? | State extrapolation, control input, process noise. | `kf_alt2_predict(...)` applies constant-acceleration kinematics using measured IMU `dt`. |
| Measurement layer | How should new observations modify belief? | Innovation, innovation covariance, Kalman gain, covariance update. | `kf_alt2_update(...)` corrects altitude and velocity from barometric relative altitude. |
| Implementation layer | What prevents invalid math from becoming flight state? | Initialization, missing data, outlier treatment, multirate filtering. | `estimation_update(...)` gates `dt`, finite values, seeding, publication, validity, and freshness. |

The textbook's rocket-altitude example is conceptually close to this firmware because both estimate altitude and vertical velocity from noisy altitude observations and a vertical-motion model. The repository differs in important ways:

| Topic | Textbook-style teaching model | Caelum implementation |
| --- | --- | --- |
| Acceleration | Often modeled as known input, assumed acceleration, or process noise depending on example. | Uses IMU-derived world-vertical acceleration as a measured input to prediction. |
| Measurement | Usually a clean scalar altitude observation in examples. | Uses barometric altitude converted into a relative frame by `estimation_relative_altitude(...)`. |
| Timing | Examples often use fixed time steps. | Uses measured IMU timestamps and rejects unreasonable `dt`. |
| Covariance update | Derivations often introduce the compact update first. | Uses Joseph form plus explicit symmetry restoration. |
| Validation | Examples can compare to known truth. | Repository requires bench, replay, and flight-log evidence before strong performance claims. |

## 1. What Problem Is the Estimator Solving?

The firmware needs a trustworthy estimate of vertical vehicle state:

```text
h = altitude above the selected reference frame [m]
v = vertical speed [m/s]
```

Neither sensor stream alone is enough:

| Sensor or derived signal | Strength | Weakness |
| --- | --- | --- |
| Barometer pressure-derived altitude | Gives an absolute altitude-like measurement. | Noisy, delayed, sensitive to pressure disturbances and reference pressure. |
| IMU acceleration | Captures fast dynamics. | Must be rotated into world vertical; integration drifts over time. |
| Gyroscope | Tracks rotation for attitude. | Integrated orientation drifts without correction. |
| Attitude quaternion | Lets body acceleration be projected onto world vertical. | Depends on valid IMU timing and sign conventions. |

The estimator combines these signals so that:

```text
IMU acceleration predicts short-term motion.
Barometer altitude corrects long-term drift.
Covariance describes how uncertain the estimate is.
```

The core result is published in `EstimatorSample`:

```cpp
float h_m;
float v_mps;
float a_mps2;
float P00;
float P01;
float P10;
float P11;
```

where `P` is the covariance matrix for altitude and vertical speed.

## 2. The Ground-Level Idea: Estimation as a Belief

A Kalman filter does not merely store "the answer." It stores a belief:

```text
estimate = best current guess
uncertainty = how much that guess may be wrong
```

For a scalar variable, this belief can be written as:

```text
x_hat = estimated value
P     = variance of estimation error
```

If `P` is large, the estimate is uncertain. If `P` is small, the estimate is confident.

The filter repeatedly performs two operations:

```text
predict  -> move the belief forward using a motion model
update   -> correct the belief using a measurement
```

The entire Kalman filter is a disciplined way to answer:

```text
How much should I trust my model prediction, and how much should I trust the new measurement?
```

### 2.1 Hidden State, Measurement, and Error

The textbook begins with the idea that many engineering variables are hidden: they exist physically, but they are not measured perfectly or directly. In this repository:

```text
hidden state:      altitude h and vertical speed v
direct measurement: barometric altitude z
derived input:     world-vertical acceleration a_vertical
```

The real state is not known exactly. If the estimate is `x_hat`, define the estimation error:

```text
e = x - x_hat
```

For a scalar variable, the variance is:

```text
P = E[(x - x_hat)^2] = E[e^2]
```

where `E[...]` means expected value. A variance has squared units:

```text
altitude variance P00:       m^2
velocity variance P11:       (m/s)^2
altitude-speed covariance:   m^2/s
```

This unit check is useful. It prevents treating `P00` as "meters" when it is actually squared meters. If a one-sigma altitude uncertainty is needed, the correct conversion is:

```text
sigma_h = sqrt(P00)
```

The repository uses exactly that interpretation in the policy uncertainty margin path: covariance is stored as variance, then converted to a distance-like uncertainty by a square root before being used as a target margin.

### 2.2 Accuracy, Precision, Bias, and Why Filtering Is Not Calibration

The textbook distinguishes measurement spread from measurement correctness. For Caelum:

| Concept | Meaning in this estimator | Example failure |
| --- | --- | --- |
| Precision | Repeated measurements are tightly clustered. | Barometer noise is low while pressure reference is wrong. |
| Accuracy | Measurements are close to the desired physical truth. | Barometer altitude is correct relative to the selected frame. |
| Bias | Persistent offset in measurement or input. | Accelerometer bias produces integrated velocity drift. |
| Variance | Random spread around a mean. | `kR` models altitude measurement spread, not a fixed offset. |

A Kalman filter can reduce random noise and blend information, but it does not automatically remove unmodeled bias. If the IMU vertical acceleration has a persistent bias, prediction will drift. If the barometric reference frame is wrong, the filter can become internally consistent but physically offset. This is why the repository documentation repeatedly treats sensor mounting, pressure baseline, and coefficient identification as validation tasks rather than solved facts.

### 2.3 Recursive Estimation Before Kalman Filtering

A helpful pre-Kalman stepping stone is the recursive mean. Given measurements `z_1 ... z_n`, the ordinary average is:

```text
x_hat_n = (z_1 + z_2 + ... + z_n) / n
```

The same average can be written recursively:

```text
x_hat_n = x_hat_{n-1} + (1/n) * (z_n - x_hat_{n-1})
```

This has the same structure as a Kalman update:

```text
new estimate = old estimate + gain * residual
```

The difference is that the recursive average uses a predetermined gain `1/n`, while the Kalman filter computes the gain from uncertainty:

```text
K = prediction uncertainty / total innovation uncertainty
```

This matters for firmware. Caelum cannot assume every sample is equally informative. Barometer samples, IMU predictions, timing gaps, and covariance growth all affect trust. The gain must be state-dependent rather than only sample-count-dependent.

## 3. A Scalar Fusion Example

Assume there is one unknown altitude `h`. Before a new measurement arrives, the filter believes:

```text
h_pred = predicted altitude
P_pred = predicted altitude variance
```

A barometer measurement arrives:

```text
z = measured altitude
R = measurement variance
```

The corrected estimate should be a weighted blend:

```text
h_new = h_pred + K * (z - h_pred)
```

The term:

```text
y = z - h_pred
```

is called the innovation or residual. It is the measurement-minus-prediction disagreement.

The gain:

```text
K = P_pred / (P_pred + R)
```

decides how much of the innovation to apply.

Interpretation:

| Case | Result |
| --- | --- |
| `P_pred` is large and `R` is small. | Prediction is uncertain, measurement is trusted, `K` approaches 1. |
| `P_pred` is small and `R` is large. | Prediction is trusted, measurement is noisy, `K` approaches 0. |
| Both are comparable. | The filter blends them. |

This scalar rule is the intuition behind the full matrix Kalman filter.

## 4. Deriving the Scalar Gain

Let the corrected estimate be:

```text
h_new = h_pred + K*(z - h_pred)
```

Rewrite it:

```text
h_new = (1 - K)*h_pred + K*z
```

Assume the prediction error and measurement error are independent:

```text
error_pred variance = P_pred
measurement noise variance = R
```

The corrected error variance is:

```text
P_new = (1 - K)^2 * P_pred + K^2 * R
```

To find the best `K`, minimize `P_new` with respect to `K`:

```text
dP_new/dK = -2*(1 - K)*P_pred + 2*K*R
```

Set derivative to zero:

```text
-2*P_pred + 2*K*P_pred + 2*K*R = 0
K*(P_pred + R) = P_pred
```

Therefore:

```text
K = P_pred / (P_pred + R)
```

This is the Kalman gain in scalar form.

### 4.1 The Same Result as Inverse-Variance Weighting

The scalar Kalman update can also be understood as the product of two independent Gaussian beliefs:

```text
prior belief:       h ~ N(h_pred, P_pred)
measurement belief: h ~ N(z,      R)
```

The posterior mean is the inverse-variance weighted average:

```text
h_new =
  (h_pred / P_pred + z / R)
  -------------------------
  (1 / P_pred + 1 / R)
```

Multiplying numerator and denominator by `P_pred*R` gives:

```text
h_new = (R*h_pred + P_pred*z) / (P_pred + R)
```

Rewrite it around the prediction:

```text
h_new = h_pred + [P_pred / (P_pred + R)] * (z - h_pred)
```

So:

```text
K = P_pred / (P_pred + R)
```

The posterior variance is:

```text
P_new = (P_pred * R) / (P_pred + R)
```

or equivalently:

```text
1/P_new = 1/P_pred + 1/R
```

Educational interpretation:

| Mathematical fact | Estimator interpretation |
| --- | --- |
| Smaller variance gives larger inverse-variance weight. | More certain information is trusted more. |
| Posterior variance is smaller than either independent input variance. | Combining independent information reduces uncertainty. |
| If `R` is large, `K` is small. | A noisy barometer should barely move the prediction. |
| If `P_pred` is large, `K` is large. | An uncertain prediction should be corrected strongly. |

Repository boundary: Caelum does not explicitly multiply Gaussian probability density functions in code. The code implements the resulting scalar equations directly in `kf_alt2_update(...)`.

### 4.2 Innovation as a Statistical Test Quantity

The residual:

```text
y = z - h_pred
```

is not just an error signal. It is a random variable. If the model and measurement noise are calibrated, its variance should be:

```text
S = P_pred + R
```

The normalized innovation is:

```text
nu = y / sqrt(S)
```

For a well-tuned scalar Gaussian filter, `nu` should usually remain within a few standard deviations. This gives a rigorous future validation diagnostic:

```text
large |nu| repeatedly -> model, sensor variance, bias, timing, or frame error may be wrong
```

The current firmware computes `y` and `S` but does not publish normalized innovation. A replay or host-side validation harness can compute it from logged predicted state, barometer measurement, and covariance if those fields are logged at the right stage.

## 5. From Scalar to Vector State

The firmware does not estimate only altitude. It estimates:

```text
x = [h, v]^T
```

where:

```text
h = altitude [m]
v = vertical speed [m/s]
```

The covariance must now describe uncertainty in both states:

```text
P = [ P00  P01
      P10  P11 ]
```

Meaning:

| Term | Meaning |
| --- | --- |
| `P00` | Variance of altitude error. |
| `P11` | Variance of vertical-speed error. |
| `P01`, `P10` | Covariance between altitude and vertical-speed errors. |

Covariance matters because a barometer measures altitude directly but can still correct vertical speed indirectly. If altitude and speed errors are correlated, an altitude residual contains information about speed.

## 6. General Linear Kalman Filter Equations

The standard linear model is:

```text
x_k = F*x_{k-1} + B*u_k + w_k
z_k = H*x_k + r_k
```

where:

| Symbol | Meaning |
| --- | --- |
| `x` | State vector. |
| `F` | State transition matrix. |
| `B` | Input matrix. |
| `u` | Known input. |
| `w` | Process noise with covariance `Q`. |
| `z` | Measurement vector. |
| `H` | Measurement matrix. |
| `r` | Measurement noise with covariance `R`. |

Prediction:

```text
x_pred = F*x + B*u
P_pred = F*P*F^T + Q
```

Update:

```text
y = z - H*x_pred
S = H*P_pred*H^T + R
K = P_pred*H^T*S^-1
x_new = x_pred + K*y
P_new = (I - K*H)*P_pred
```

Numerically safer covariance update:

```text
P_new = (I - K*H)*P_pred*(I - K*H)^T + K*R*K^T
```

The repository uses this safer Joseph-form update.

### 6.1 Dimension Check for the Caelum Filter

The textbook emphasizes dimensions because many Kalman-filter mistakes are matrix-shape mistakes. For this firmware:

```text
state dimension n = 2
measurement dimension m = 1
control/input dimension l = 1
```

Therefore:

| Symbol | Caelum size | Caelum meaning |
| --- | --- | --- |
| `x` | `2x1` | `[h, v]^T` |
| `F` | `2x2` | Constant-velocity transition over measured `dt`. |
| `B` | `2x1` | Constant-acceleration input effect. |
| `u` | `1x1` | World-vertical acceleration. |
| `P` | `2x2` | Error covariance for `[h, v]`. |
| `Q` | `2x2` | Prediction uncertainty added by acceleration uncertainty. |
| `z` | `1x1` | Relative barometric altitude. |
| `H` | `1x2` | `[1, 0]`, altitude-only observation. |
| `R` | `1x1` | Barometric altitude measurement variance. |
| `S` | `1x1` | Innovation variance. |
| `K` | `2x1` | Altitude and velocity correction gains. |

Check the gain equation:

```text
K = P_pred * H^T * S^-1
```

Dimensions:

```text
(2x2) * (2x1) * (1x1) = (2x1)
```

That matches the firmware's two scalar gain terms:

```text
K = [K0
     K1]
```

where `K0` corrects altitude and `K1` corrects vertical speed.

### 6.2 Covariance as Coupled Error Geometry

For the two-state estimator:

```text
P = [ var(h error)       cov(h error, v error)
      cov(v error, h error)  var(v error)     ]
```

The diagonal terms describe spread in each state. The off-diagonal terms describe whether errors tend to move together:

| Covariance sign | Interpretation |
| --- | --- |
| `P01 > 0` | If altitude is overestimated, velocity also tends to be overestimated. |
| `P01 < 0` | If altitude is overestimated, velocity tends to be underestimated. |
| `P01 = 0` | Altitude and velocity errors are locally uncorrelated. |

The barometer observes only altitude, but the velocity update is:

```text
v_new = v_pred + K1*y
K1 = P10 / S
```

So velocity can be corrected by altitude only when covariance has coupled the two errors. This is why the prediction step matters even before a measurement arrives: `F*P*F^T` creates physically meaningful altitude-speed covariance.

### 6.3 Prediction and Correction as Belief Transport

A compact educational summary is:

```text
Prediction transports belief through dynamics.
Correction intersects that transported belief with measurement information.
```

In equations:

```text
mean transport:       x_pred = F*x + B*u
uncertainty transport: P_pred = F*P*F^T + Q
measurement mismatch: y = z - H*x_pred
trust computation:     S = H*P_pred*H^T + R
belief correction:     x_new = x_pred + K*y
```

In Caelum terms:

```text
IMU acceleration moves the state forward.
Barometric altitude pulls the state back toward measured altitude.
Covariance determines how much pulling occurs.
```

## 7. The Caelum State Model

The implemented state is:

```text
x = [h, v]^T
```

The input is measured world-vertical acceleration:

```text
u = a_vertical
```

Assuming acceleration is approximately constant over a small time interval `dt`:

```text
h_next = h + v*dt + 0.5*a*dt^2
v_next = v + a*dt
```

Matrix form:

```text
x_next =
  [1  dt] [h] + [0.5*dt^2] a
  [0   1] [v]   [dt       ]
```

Therefore:

```text
F = [1  dt
     0   1]

B = [0.5*dt^2
     dt       ]
```

This is implemented in `kf_alt2_predict(...)`.

## 8. The Caelum Measurement Model

The barometer provides a relative altitude measurement:

```text
z = h + measurement_noise
```

So:

```text
H = [1  0]
```

The measurement sees altitude directly and vertical speed indirectly through covariance.

In the firmware:

```cpp
const float y = z_meas_m - kf.h_m;
const float S = kf.P00 + kR;
const float K0 = kf.P00 * invS;
const float K1 = kf.P10 * invS;
```

This is exactly the scalar measurement update for a two-state vector.

## 9. Prediction Step in This Firmware

The prediction function is:

```cpp
void kf_alt2_predict(KfAlt2State &kf, float a_vertical_mps2, float dt_s)
```

It rejects invalid inputs:

```text
filter must be seeded
acceleration must be finite
dt must be finite and positive
```

Then it computes:

```text
dt2 = dt^2
dt3 = dt^3
dt4 = dt^4
```

State prediction:

```text
h = h + v*dt + 0.5*a*dt^2
v = v + a*dt
```

Covariance prediction:

```text
P00_new = P00 + dt*(P10 + P01) + dt^2*P11 + Q00
P01_new = P01 + dt*P11 + Q01
P11_new = P11 + Q11
P10_new = P01_new
```

The firmware explicitly writes `P10 = P01` to preserve covariance symmetry.

## 10. Deriving the Covariance Prediction

Use:

```text
P_pred = F*P*F^T + Q
```

with:

```text
F = [1  dt
     0   1]

P = [P00 P01
     P10 P11]
```

First compute:

```text
F*P =
[1 dt] [P00 P01] = [P00 + dt*P10, P01 + dt*P11]
[0  1] [P10 P11]   [P10,           P11          ]
```

Then multiply by `F^T`:

```text
F^T = [1 0
       dt 1]
```

Result:

```text
P00_pred = P00 + dt*P10 + dt*P01 + dt^2*P11
P01_pred = P01 + dt*P11
P10_pred = P10 + dt*P11
P11_pred = P11
```

If `P` is symmetric, `P01 == P10`, so the off-diagonal terms should remain equal. The firmware enforces that explicitly after adding process noise.

## 11. Process Noise `Q`

The filter model assumes the acceleration input is not perfect. That uncertainty is represented by process noise.

The firmware constants are:

```text
kSigmaA2 = acceleration process-noise intensity
kR       = barometric altitude measurement variance
```

The implemented process-noise terms are:

```text
Q00 = kSigmaA2 * dt^4 / 4
Q01 = kSigmaA2 * dt^3 / 2
Q11 = kSigmaA2 * dt^2
```

This corresponds to applying acceleration uncertainty through:

```text
B = [0.5*dt^2
     dt       ]
```

so:

```text
Q = sigma_a^2 * B*B^T
```

which gives:

```text
Q = sigma_a^2 *
    [dt^4/4  dt^3/2
     dt^3/2  dt^2  ]
```

Study note: some continuous white-acceleration models use a different discretization, such as terms proportional to `dt^3/3`, `dt^2/2`, and `dt`. The repository implementation should be understood as the specific process-noise model actually coded here: acceleration uncertainty over the measured interval enters through the same kinematic input matrix as the measured acceleration.

### 11.1 Two Common Ways to Think About Acceleration Uncertainty

The textbook separates process noise from measurement noise and discusses that process-noise modeling is a design choice. For this repository, two interpretations are useful:

| Interpretation | Mathematical form | Meaning |
| --- | --- | --- |
| Random acceleration impulse over the interval | `Q = sigma_a^2 * B*B^T` | The acceleration input for this sample is uncertain by an amount whose variance is `sigma_a^2`. |
| Continuous white acceleration over time | Terms often scale as `dt^3`, `dt^2`, and `dt` for a position-velocity model. | Unmodeled acceleration is treated as a continuous-time random process integrated through the dynamics. |

Caelum implements the first form:

```text
B = [0.5*dt^2
     dt       ]

Q = kSigmaA2 * B*B^T
```

This is not a generic statement that all altitude Kalman filters must use this `Q`. It is a repository-specific contract. If future replay validation shows residual inconsistency, the process-noise model is one legitimate tuning or modeling target.

### 11.2 Unit Check for `Q`

Because `kSigmaA2` represents acceleration variance-like uncertainty:

```text
kSigmaA2 units: (m/s^2)^2 = m^2/s^4
```

Then:

```text
Q00 = kSigmaA2 * dt^4 / 4
units = (m^2/s^4) * s^4 = m^2
```

which matches altitude variance.

```text
Q01 = kSigmaA2 * dt^3 / 2
units = (m^2/s^4) * s^3 = m^2/s
```

which matches altitude-speed covariance.

```text
Q11 = kSigmaA2 * dt^2
units = (m^2/s^4) * s^2 = m^2/s^2
```

which matches vertical-speed variance.

This unit consistency is an important sanity check on the implementation.

### 11.3 How `Q` Affects Later Barometer Corrections

Process noise does not directly move the state mean. It expands covariance:

```text
larger Q -> larger P_pred -> larger gain on later measurements
```

That means `kSigmaA2` is not just a "noise number." It controls how quickly the filter admits that the IMU-driven prediction may have become wrong. If acceleration uncertainty is underestimated, the filter can become overconfident and resist barometer corrections. If it is overestimated, the filter can become too measurement-following and inject barometer noise into velocity through `K1`.

## 12. Measurement Update in This Firmware

The update function is:

```cpp
void kf_alt2_update(KfAlt2State &kf, float z_meas_m)
```

It rejects:

```text
unseeded filter
non-finite measurement
singular or invalid innovation variance
```

The innovation is:

```text
y = z_meas - h
```

The innovation variance is:

```text
S = P00 + R
```

where:

```text
R = kR
```

The gain is:

```text
K0 = P00 / S
K1 = P10 / S
```

Then:

```text
h = h + K0*y
v = v + K1*y
```

This is the key reason the barometer can correct vertical speed: `K1` is nonzero when altitude and velocity errors are correlated.

## 13. Why the Joseph Covariance Update Matters

The simplified covariance update is:

```text
P = (I - K*H)*P
```

The repository uses:

```text
P = (I - K*H)*P*(I - K*H)^T + K*R*K^T
```

This is called the Joseph form. It is more arithmetic, but it is safer under finite precision.

Why it matters on a microcontroller:

| Risk | Joseph-form benefit |
| --- | --- |
| Floating-point roundoff. | Better preserves positive-semidefinite covariance. |
| Repeated updates. | Reduces numerical damage accumulation. |
| Slight asymmetry in `P`. | Easier to symmetrize after update. |

The code explicitly symmetrizes:

```text
sym01 = 0.5*(nP01 + nP10)
P01 = sym01
P10 = sym01
```

This keeps the covariance matrix physically interpretable.

## 14. Seeding: Why the Filter Cannot Start From Nothing

The firmware has a `seeded` flag.

Before seeding:

```text
altitude reference is not established
vertical speed is not meaningful
policy should not trust estimator state
```

Seeding happens from the first trusted relative altitude measurement:

```text
h = h0
v = 0
P = identity
seeded = true
```

The velocity starts at zero not because the vehicle is guaranteed stationary in all cases, but because the first altitude measurement alone does not determine velocity. If seeding occurs on the pad before launch, zero velocity is physically reasonable. If seeding occurs late, the assumption is weaker and should be treated cautiously.

## 15. Relative Altitude Reference

The estimator does not blindly use absolute pressure altitude. It first computes relative altitude.

If a baseline pressure exists:

```text
base_alt = pressure_to_altitude_m(baro_baseline_hpa, sea_level_hpa)
z = current_baro_alt - base_alt
```

Otherwise:

```text
first valid baro altitude becomes the live zero reference
z = current_baro_alt - live_ref_alt
```

This matters because the policy target is interpreted in the same altitude frame as the estimator.

## 16. How Body-Frame IMU Data Becomes Vertical Acceleration

The Kalman filter requires vertical acceleration in the estimator's world frame:

```text
a_vertical
```

The IMU provides acceleration in the sensor body frame:

```text
ax, ay, az
```

The attitude module estimates a quaternion:

```text
q = [q0, q1, q2, q3]
```

The firmware computes the world vertical component:

```text
a_world_z =
  2*(q1*q3 - q0*q2)*ax
+ 2*(q0*q1 + q2*q3)*ay
+ (q0^2 - q1^2 - q2^2 + q3^2)*az
```

Then, under the repository's sign convention:

```text
a_vertical = a_world_z + g
```

This is one of the most important estimator contracts. If the IMU mounting or sign convention changes, this projection must be revalidated.

## 17. Attitude Estimation at a High Level

The attitude module uses a Madgwick-style IMU update:

```text
gyro integration - beta * accelerometer gravity correction
```

Conceptually:

| Input | Role |
| --- | --- |
| Gyroscope | Integrates angular motion. |
| Accelerometer direction | Corrects roll/pitch drift by referencing gravity direction. |
| `MADGWICK_BETA` | Sets correction strength. |

The code normalizes:

1. The accelerometer vector before using it as a direction.
2. The gradient correction.
3. The quaternion after integration.

Quaternion normalization is mandatory because a non-unit quaternion is not a pure rotation operator.

## 18. End-to-End Estimator Operation in `estimation_update(...)`

The estimator service follows this sequence:

1. Clear per-pass `updated` flags for attitude, vertical acceleration, estimator, and legacy flight state.
2. If a new IMU sample exists, compute measured `dt` from the last IMU timestamp.
3. Use the first IMU sample only to initialize the timing origin.
4. Reject `dt` outside:

```text
EST_MIN_IMU_DT_S = 0.0005
EST_MAX_IMU_DT_S = 0.1000
```

5. Update attitude using gyroscope and accelerometer.
6. Project the same IMU acceleration into world vertical acceleration.
7. If the Kalman filter is not seeded, try to seed it from relative barometric altitude.
8. If seeded and vertical acceleration is valid, run prediction.
9. If a new barometer sample exists, compute relative altitude.
10. If the filter is unseeded, seed from that altitude; otherwise correct with `kf_alt2_update(...)`.
11. Publish the estimator only if prediction or correction actually changed the private filter.

This sequence is important:

```text
IMU path predicts.
Barometer path corrects.
Publication happens only after meaningful estimator change.
```

## 19. Validity, Freshness, and Publication Semantics

The estimator publishes:

```text
valid
updated
seeded
t_ms
t_us
seq
payload
```

Meaning:

| Field | Meaning |
| --- | --- |
| `valid` | The estimate is semantically usable. |
| `updated` | The estimator published fresh output during the current service pass. |
| `seeded` | The filter has a trusted altitude reference. |
| `t_ms`, `t_us` | Publication timestamps. |
| `seq` | Publication counter. |

The policy and safety logic must not rely on an old estimate merely because it was once valid. That is why freshness checks compare the current time against `state.est.t_ms`.

### 19.1 Multirate Filtering in This Firmware

The textbook treats multirate filtering as a practical implementation issue: different sensors do not necessarily arrive at the same cadence. Caelum has exactly that structure:

```text
IMU path:        can trigger prediction when `state.imu.updated` is true
barometer path:  can trigger correction when `state.baro.updated` is true
scheduler path:  calls `estimation_update(...)` as a service routine
```

The estimator does not require every pass to contain both an IMU sample and a barometer sample:

| Available data in a service pass | Firmware behavior |
| --- | --- |
| Fresh valid IMU, no fresh barometer | Predict only, if seeded and `dt` is valid. |
| Fresh valid barometer, no usable IMU prediction | Seed or correct altitude. |
| Both paths usable | Predict and correct in the same pass. |
| Neither path usable | Publish no fresh estimator update. |

This is a practical Kalman-filter strength: prediction and correction are separable. The filter can propagate state when only dynamics information is available and correct state when a measurement appears.

Repository boundary: this is not a fully asynchronous event-driven filter. It is a deterministic service-pass implementation that consumes `updated` flags already written into `SystemState`.

### 19.2 Missing Measurements

A textbook treatment of missing measurements typically says not to invent a fake measurement. The repository follows that principle:

```text
invalid barometer -> no altitude update
invalid IMU or invalid dt -> no prediction
unseeded state -> no meaningful published estimate
```

In code terms:

```text
kf_alt2_predict(...) returns without change on invalid acceleration or dt
kf_alt2_update(...) returns without change on invalid altitude
estimation_update(...) publishes only after predictor or corrector changed state
```

This is safer than forcing stale values through the filter. A stale measurement would look mathematically valid and could incorrectly reduce covariance.

### 19.3 Outliers and Innovation Gating

The textbook discusses outliers as measurements inconsistent with the expected pattern. In Kalman-filter language, the natural outlier statistic is the normalized innovation:

```text
nu = y / sqrt(S)
```

where:

```text
y = z - H*x_pred
S = H*P_pred*H^T + R
```

Current firmware behavior:

| Outlier-related mechanism | Present now? | Notes |
| --- | --- | --- |
| Finite-value rejection | Yes | Prevents NaN or infinity contamination. |
| `dt` range rejection | Yes | Prevents extreme prediction jumps. |
| Barometer innovation magnitude gate | No | `kf_alt2_update(...)` does not reject large finite residuals. |
| Normalized innovation logging | No | Can be computed in replay if pre-update state and measurement are logged. |
| Adaptive `R` for degraded measurement conditions | No | `kR` is compile-time constant. |

This matters for future flight review. A large finite barometer pressure disturbance can pass the current finite checks and produce a strong correction if covariance says to trust it. A future validation harness should log or reconstruct `y`, `S`, and `nu`, then decide whether innovation gating is needed.

### 19.4 Initialization as an Engineering Contract

The textbook treats Kalman initialization as selection of:

```text
initial state x_0
initial covariance P_0
```

The repository implements:

```text
h_0 = first trusted relative altitude
v_0 = 0
P_0 = [1 0
       0 1]
```

This is a deliberate but limited prior:

| Prior choice | Why it is reasonable | When it becomes weak |
| --- | --- | --- |
| `h_0` from barometer | Establishes the altitude reference frame. | If pressure baseline or first live altitude is wrong. |
| `v_0 = 0` | Appropriate if seeded while stationary before flight. | Weak if seeded after launch or during motion. |
| `P_0 = I` | Simple conservative finite uncertainty. | May not match actual altitude/velocity uncertainty. |

For research-grade validation, initialization should be checked explicitly in logs. The first estimator samples should show when seeding occurred, which altitude reference was used, and whether the vehicle was actually stationary enough for `v_0 = 0` to be defensible.

## 20. What the Filter Assumes

The altitude filter assumes:

| Assumption | Consequence |
| --- | --- |
| Vertical motion is represented well enough by `[h, v]`. | Lateral motion and full 6-DOF dynamics are outside this filter. |
| Vertical acceleration is known with bounded uncertainty. | Attitude/sign errors directly affect prediction. |
| Barometric altitude is a noisy measurement of altitude. | Pressure disturbances appear as measurement noise or bias. |
| Noise tuning constants are reasonable. | Bad `Q` or `R` tuning can overtrust model or measurement. |
| Timing is valid. | Corrupt `dt` can cause state and covariance jumps, so the code rejects extreme intervals. |

The filter is not magic. It is only as defensible as its model, measurements, timing, and tuning.

## 21. What `Q` and `R` Do Practically

`Q` controls how much uncertainty grows during prediction.

If `Q` is too small:

```text
filter overtrusts IMU/model
barometer corrections become weak
drift or acceleration errors persist too long
```

If `Q` is too large:

```text
filter distrusts prediction
barometer corrections dominate
velocity can become noisy
```

`R` controls how much the filter trusts barometric altitude.

If `R` is too small:

```text
filter overtrusts barometer
pressure noise can jerk altitude and velocity
```

If `R` is too large:

```text
filter underuses barometer
integrated acceleration drift persists
```

In this repository:

```text
kR = kSigmaH2 = 5.71e-03
kSigmaA2 = 2.73e-03
```

These values should be validated against bench and flight data before strong performance claims.

## 22. Why Vertical Speed Can Be Estimated Without a Direct Speed Sensor

The barometer measures altitude only. The IMU provides acceleration. The filter estimates velocity because:

1. Prediction integrates acceleration into velocity.
2. Prediction integrates velocity into altitude.
3. The covariance matrix learns that altitude and velocity errors are coupled.
4. A barometer altitude residual therefore corrects both altitude and speed through `K0` and `K1`.

This is the key estimator insight:

```text
A measurement of one state can correct another state if the model covariance couples them.
```

## 23. Common Failure Modes

| Failure | Effect | Mitigation in current code |
| --- | --- | --- |
| Non-finite sensor value | NaN contamination. | Reject finite checks before update/predict. |
| Bad IMU `dt` | State jump or unstable integration. | `EST_MIN_IMU_DT_S` and `EST_MAX_IMU_DT_S`. |
| Missing barometer baseline | Ambiguous altitude frame. | First valid live altitude fallback. |
| Bad IMU sign convention | Wrong vertical acceleration. | Code comments document branch-specific sign convention; must be physically validated. |
| Non-unit quaternion | Rotated vector distortion. | Quaternion renormalization. |
| Overconfident covariance | Bad control trust. | Tune `Q`, `R`, compare residuals. |
| Stale estimator publication | Policy acts on old state. | Policy and safety freshness checks. |

## 24. Mapping Symbols to Code

| Theory symbol | Firmware field or constant |
| --- | --- |
| `h` | `KfAlt2State::h_m`, `EstimatorSample::h_m` |
| `v` | `KfAlt2State::v_mps`, `EstimatorSample::v_mps` |
| `a` | `state.auxvz.a_vertical`, `state.est.a_mps2` |
| `dt` | measured IMU timestamp difference in `estimation_update(...)` |
| `F` | implicit in `kf_alt2_predict(...)` covariance equations |
| `B` | implicit in state prediction terms `0.5*dt^2` and `dt` |
| `Q` | `kSigmaA2 * [[dt^4/4, dt^3/2], [dt^3/2, dt^2]]` |
| `z` | `z_meas` from `estimation_relative_altitude(...)` |
| `H` | `[1, 0]` |
| `R` | `kR` |
| `P` | `P00`, `P01`, `P10`, `P11` |
| `K` | `K0`, `K1` in `kf_alt2_update(...)` |
| innovation `y` | `z_meas_m - kf.h_m` |
| innovation variance `S` | `kf.P00 + kR` |

## 25. Worked Numerical Micro-Example

Suppose:

```text
h = 100 m
v = 40 m/s
a = -9.8 m/s^2
dt = 0.02 s
```

Prediction:

```text
h_next = 100 + 40*0.02 + 0.5*(-9.8)*(0.02)^2
       = 100 + 0.8 - 0.00196
       = 100.79804 m

v_next = 40 + (-9.8)*0.02
       = 39.804 m/s
```

Now suppose the barometer relative altitude says:

```text
z = 100.6 m
```

Innovation:

```text
y = 100.6 - 100.79804
  = -0.19804 m
```

If the Kalman gain terms are:

```text
K0 = 0.5
K1 = 0.1
```

then:

```text
h_corrected = 100.79804 + 0.5*(-0.19804)
            = 100.69902 m

v_corrected = 39.804 + 0.1*(-0.19804)
            = 39.784196 m/s
```

The altitude measurement corrected both altitude and velocity.

## 26. How to Read an Estimator Log

When reviewing telemetry or SD logs, do not start with the numerical payload. Start with metadata:

1. Check `est_valid`.
2. Check `est_updated`.
3. Check estimator age if available.
4. Check `est_seq` increments.
5. Check `P00` is finite and plausible.
6. Check phase and policy only after estimator validity is established.
7. Compare `bmp_alt`, `est_h`, and `a_vertical` around events.
8. Inspect warning mask for sensor or estimator validity faults.

Then interpret:

| Pattern | Possible meaning |
| --- | --- |
| `est_h` follows `bmp_alt` too tightly. | `R` may be too small or `Q` too large. |
| `est_h` drifts away from barometer. | `R` may be too large, barometer invalid, or acceleration bias exists. |
| `est_v` is noisy at rest. | Barometer noise may be leaking into velocity. |
| `P00` grows without correction. | Prediction is running without measurement updates. |
| `P00` collapses unrealistically. | Measurement noise may be under-modeled. |

## 27. What To Verify Next

To make the estimator more defensible, collect and analyze evidence for:

1. Barometer baseline stability on the pad.
2. Stationary IMU acceleration and gyro bias.
3. Quaternion sign and mounting convention.
4. Vertical acceleration projection under known orientations.
5. Estimator response to controlled vertical motion if possible.
6. Coast-phase flight logs with observed apogee.
7. Residuals:

```text
barometer residual = z - h_pred
```

8. Covariance calibration:

```text
Does actual error statistically match predicted uncertainty?
```

## 28. Study Derivations and Exercises

These exercises are designed to make the estimator mathematically transparent while staying tied to the repository.

### 28.1 Derive the Prediction Mean

Start from constant acceleration over one measured interval:

```text
dv/dt = a
dh/dt = v
```

Integrate velocity:

```text
v(t + dt) = v(t) + a*dt
```

Integrate altitude:

```text
h(t + dt) = h(t) + integral_0^dt [v(t) + a*tau] d_tau
          = h(t) + v(t)*dt + 0.5*a*dt^2
```

Then confirm the firmware lines in `kf_alt2_predict(...)` implement exactly this:

```text
h <- h + v*dt + 0.5*a*dt^2
v <- v + a*dt
```

### 28.2 Derive `F P F^T` by Hand

Use:

```text
F = [1 dt
     0  1]

P = [P00 P01
     P10 P11]
```

Compute:

```text
F*P*F^T =
[P00 + dt*(P10 + P01) + dt^2*P11,  P01 + dt*P11
 P10 + dt*P11,                         P11        ]
```

If `P01 = P10`, then the off-diagonal entries are equal. The firmware stores only one computed off-diagonal value after prediction:

```text
P01_new = P01 + dt*P11 + Q01
P10_new = P01_new
```

Study question: why is explicit symmetrization safer than assuming repeated floating-point operations will preserve exact equality forever?

### 28.3 Derive the Two-Element Kalman Gain

With:

```text
H = [1 0]
P = [P00 P01
     P10 P11]
```

Compute:

```text
H*P*H^T = P00
S = P00 + R
P*H^T = [P00
         P10]
```

Therefore:

```text
K = [P00/S
     P10/S]
```

This maps directly to:

```text
K0 = kf.P00 * invS
K1 = kf.P10 * invS
```

Study question: under what covariance condition would a barometer residual correct altitude but not velocity?

### 28.4 Derive the Uncertainty Margin Used by Policy

The estimator stores altitude variance:

```text
P00 = sigma_h^2
```

A one-sigma altitude uncertainty is:

```text
sigma_h = sqrt(P00)
```

If the policy subtracts `N` standard deviations from the target:

```text
uncertainty_margin = N * sqrt(P00)
target_effective = target_nominal - uncertainty_margin
```

Repository boundary: the exact policy clamp and constants are defined in `utils/config.h` and policy code. The mathematical point is that variance must be square-rooted before being used as a meter-valued altitude margin.

### 28.5 Build a Replay Residual Table

For each replayed barometer correction, record:

```text
t
z
h_pred
v_pred
P00_pred
P10_pred
R
y = z - h_pred
S = P00_pred + R
nu = y / sqrt(S)
h_post
v_post
P00_post
```

Then analyze:

| Diagnostic | Expected if model is plausible |
| --- | --- |
| Residual mean | Near zero over comparable flight segments. |
| Residual spread | Comparable to `sqrt(S)` after tuning. |
| Large repeated `|nu|` | Rare, explainable, or gated. |
| `P00` over time | Grows during prediction-only intervals, shrinks after corrections. |
| `P01` over time | Shows coupling that allows altitude to correct velocity. |

This table would turn the current estimator notes into a measurable validation plan.

## 29. Textbook Concepts Used in These Notes

The attached textbook was used for pedagogical organization around the following concepts:

| Concept | How it appears in this note | Repository source of implementation truth |
| --- | --- | --- |
| Hidden state | Altitude and vertical speed are estimated rather than directly known. | `EstimatorSample`, `KfAlt2State`. |
| Scalar Kalman intuition | Gain as uncertainty-weighted residual correction. | `kf_alt2_update(...)`. |
| Matrix KF equations | `F`, `B`, `H`, `P`, `Q`, `R`, `S`, `K`. | Explicit scalar matrix expansion in `kalman_alt2.cpp`. |
| Process noise | Acceleration uncertainty expands covariance. | `kSigmaA2` and `Q00/Q01/Q11`. |
| Multirate filtering | Prediction and correction can occur on different data arrivals. | `state.imu.updated`, `state.baro.updated`. |
| Missing measurements | Do not invent data; skip invalid predict/update paths. | finite checks, seeding checks, and publication gating. |
| Outlier reasoning | Innovation and normalized innovation are validation tools. | `y` and `S` are computed; normalized innovation is future work. |
| Initialization | Initial state and covariance define the prior. | `kf_alt2_seed(...)`, `kf_alt2_reset(...)`. |
| Development process | Simulation and replay should evaluate residuals and covariance consistency. | Host tests and future replay validation. |

## 30. Key Takeaways

The Kalman filter in this repository is a compact two-state estimator:

```text
state:       altitude and vertical speed
prediction: IMU-derived vertical acceleration
correction: barometric relative altitude
uncertainty: 2x2 covariance matrix
```

The estimator works because it preserves a disciplined chain:

```text
sensor validity
-> attitude validity
-> vertical acceleration validity
-> Kalman seed/predict/update
-> estimator publication
-> phase, policy, safety, telemetry, and SD logging
```

Its main engineering strengths are explicit validity, measured `dt`, bounded scalar math, Joseph-form covariance update, and clean publication semantics.

Its main remaining risks are physical validation risks: sensor mounting, sign convention, barometer reference behavior, noise tuning, and flight-data covariance calibration.

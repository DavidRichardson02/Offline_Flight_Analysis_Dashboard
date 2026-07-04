## Expected Behavior After Flight-Phase and Apogee-Policy Integration

After integrating the flight-phase detector with the apogee-prediction airbrake policy, the system should follow a conservative safety progression:

```text
observe sensor state
→ confirm arm/policy-enable state
→ classify flight phase
→ predict apogee
→ command airbrakes only inside the permitted phase window
```

The airbrake policy should only be capable of producing a valid nonzero deployment command during upward coast or active braking logic. It should remain inactive at rest, during boost, and during descent.

The runtime control path now also requires:

```text
arm_state              = ARMED
software_arm_token     = 1
policy_runtime_enabled = 1
```

Without those gates, the policy must remain invalid even if the estimator and phase logic would otherwise permit braking.

### At Rest

When the vehicle is on the pad, stationary, or otherwise not in a valid flight condition:

```text
phase        = IDLE
policy_valid = 0
policy_cmd   = 0
```

Expected interpretation:

* The estimator either has not entered a valid flight state or the vehicle does not satisfy altitude/velocity gates.
* The operator may also have left the system disarmed or policy-disabled.
* The airbrake policy must not authorize deployment.
* The actuator should remain idle.

### During Boost

During powered ascent, the flight-phase detector may classify the state as `BOOST` based on high acceleration and early altitude rise:

```text
phase        = BOOST
policy_valid = 0
policy_cmd   = 0
```

Expected interpretation:

* The vehicle is under motor thrust.
* Airbrake deployment is not permitted during boost.
* Even if predicted apogee appears high, the policy should remain invalid because braking during boost is outside the permitted phase window.

### During Coast Below Target

During upward coast, if the predicted apogee is at or below the effective target plus deadband:

```text
phase        = COAST
apogee_error <= deadband
policy_valid = 0
policy_cmd   = 0
```

Expected interpretation:

* The vehicle is in the correct phase for possible airbrake use.
* The system must also be explicitly armed and policy-enabled.
* However, the apogee predictor does not indicate a meaningful overshoot.
* The correct action is to keep the airbrakes retracted.

### During Coast Above Target

During upward coast, if the predicted closed-brake apogee exceeds the effective target by more than the deadband:

```text
phase        = COAST
apogee_error > deadband
policy_valid = 1
policy_cmd   > 0
```

Expected interpretation:

* The vehicle is in the permitted coast phase.
* The system is explicitly armed and policy-enabled.
* The apogee predictor indicates that the vehicle is likely to overshoot the target.
* The policy may publish a valid normalized deployment command.
* The command should still pass through safety and actuator gates before reaching hardware.

### During Descent

After apogee, when vertical velocity is non-positive and the vehicle is descending:

```text
phase        = DESCENT
policy_valid = 0
policy_cmd   = 0
```

Expected interpretation:

* The useful airbrake-control window has closed.
* Deployment intent should be cleared.
* The actuator should be forced idle unless another explicitly designed descent-mode behavior is added later.

## Summary

The intended safety progression is:

```text
IDLE    → observe only, no deployment
BOOST   → powered ascent, no deployment
COAST   → predict apogee and command only if overshoot is predicted
BRAKE   → reserved for active braking state-machine behavior
DESCENT → post-apogee, no deployment
```

This structure ensures that the airbrake system does not command deployment simply because the predicted apogee is high. Deployment intent is only valid when the vehicle is explicitly armed, the policy runtime gate is enabled, the vehicle is in the correct flight phase, the estimator is valid and fresh, and the apogee-prediction law indicates an overshoot beyond the configured deadband.

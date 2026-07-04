#include "telemetry.h"

#include "config.h"
#include "math_utils.h"
#include "actuator.h"
#include "safety.h"
#include "sensors.h"

/*
telemetry.cpp
===============================================================================
PURPOSE
  Emit fixed-schema telemetry and diagnostics.

CSV CONTRACT
  Header and row field order must remain synchronized. Invalid values are not
  reinterpreted; they are emitted directly so downstream analysis can detect NAN
  or invalid flags.

WARNING MASK CONTRACT
  Warning bits compactly summarize hardware health, snapshot validity, config
  validity, and SD health.
===============================================================================
*/

static void print_hex_u8(uint8_t value) {
  Serial.print(F("0x"));

  if (value < 0x10U) {
    Serial.print('0');
  }

  Serial.print(value, HEX);
}

static const __FlashStringHelper *i2c_bus_name(uint8_t bus_id) {
  switch (bus_id) {
    case 0U:
      return F("Wire");

    case 1U:
      return F("Wire1");

    case 2U:
      return F("Wire2");

    default:
      return F("none");
  }
}

static const __FlashStringHelper *cmps2_init_status_name(uint8_t status) {
  switch (status) {
    case 0U:
      return F("disabled");

    case 1U:
      return F("not_started");

    case 2U:
      return F("no_ack");

    case 3U:
      return F("product_read_fail");

    case 4U:
      return F("product_mismatch");

    case 5U:
      return F("measure_start_fail");

    case 6U:
      return F("ok");

    case 7U:
      return F("ok_product_unread");

    case 8U:
      return F("set_sensor_fail");

    default:
      return F("unknown");
  }
}

static const __FlashStringHelper *cmps2_runtime_status_name(uint8_t status) {
  switch (status) {
    case 0U:
      return F("disabled");

    case 1U:
      return F("not_started");

    case 2U:
      return F("start_fail");

    case 3U:
      return F("pending");

    case 4U:
      return F("status_read_fail");

    case 5U:
      return F("timeout");

    case 6U:
      return F("data_read_fail");

    case 7U:
      return F("invalid_numeric");

    case 8U:
      return F("valid");

    default:
      return F("unknown");
  }
}

static const __FlashStringHelper *sd_fault_reason_name(SdFaultReason reason) {
  switch (reason) {
    case SdFaultReason::NONE:
      return F("none");

    case SdFaultReason::NO_BUILTIN_SDCARD:
      return F("no_builtin_sdcard");

    case SdFaultReason::SD_BEGIN_FAILED:
      return F("sd_begin_failed");

    case SdFaultReason::FILENAME_EXHAUSTED:
      return F("filename_exhausted");

    case SdFaultReason::FILE_OPEN_FAILED:
      return F("file_open_failed");

    case SdFaultReason::RUNTIME_FILE_FAULT:
      return F("runtime_file_fault");

    default:
      return F("unknown");
  }
}

/*
telemetry_warn_mask(...)
------------------------------------------------------------------------------
ROLE
  Build compact health and validity bitmask.

INPUT CONTRACT
  state must refer to the shared SystemState object.

OUTPUT CONTRACT
  Returns a uint32_t warning mask.

MECHANISM
  1. Start from zero.
  2. Set hardware-health bits.
  3. Set snapshot-validity bits.
  4. Set configuration and SD-fault bits.
  5. Return the accumulated mask.

FAILURE BEHAVIOR
  No failure path exists.

DETERMINISM
  Constant-time. No loops. No hardware I/O. No dynamic allocation.
*/
uint32_t telemetry_warn_mask(const SystemState &state) {
  uint32_t w = 0U;

  // Low-order bits are hardware-availability faults. These indicate missing or
  // failed sensor backends even before looking at per-cycle validity flags.
#if BMP5XX_ENABLED
  if (!state.health.bmp_ok) w |= (1UL << 0);
#endif

#if BMI088_ENABLED
  if (!state.health.bmi_accel_ok) w |= (1UL << 1);
  if (!state.health.bmi_gyro_ok) w |= (1UL << 2);
#endif

#if LIS2DU12_ENABLED || LIS3DH_ENABLED
  if (!state.health.lis_ok) w |= (1UL << 3);
#endif

#if PMOD_ACL2_ENABLED || PMOD_ACL_ENABLED
  if (!state.health.pmod_accel_ok || !state.pmod_accel.valid) {
    w |= (1UL << WARN_PMOD_ACCEL_FAULT_BIT);
  }
#endif

  // Mid-range bits track semantic validity of the latest published snapshots.
#if BMP5XX_ENABLED
  if (!state.baro.valid) w |= (1UL << 4);
#endif

#if BMI088_ENABLED
  if (!state.imu.valid) w |= (1UL << 5);
#endif

#if LIS2DU12_ENABLED || LIS3DH_ENABLED
  if (!state.aux.valid) w |= (1UL << 6);
#endif

#if BMI088_ENABLED
  if (!state.auxvz.valid) w |= (1UL << 7);
  if (!state.attitude.valid) w |= (1UL << 8);
#endif

#if BMP5XX_ENABLED && BMI088_ENABLED
  if (!state.est.valid) w |= (1UL << 9);
#endif

  if (!state.cfg.valid) w |= (1UL << 10);

#if PMOD_CMPS2_ENABLED
  if (!state.health.mag_ok || !state.mag.valid || state.mag.interference) {
    w |= (1UL << WARN_MAG_FAULT_BIT);
  }
#endif

  if (
    (!state.sdlog.enabled) ||
    (!state.sdlog.card_ok) ||
    (!state.sdlog.file_open) ||
    state.sdlog.runtime_failed ||
    state.sdlog.fault_reason != SdFaultReason::NONE
  ) {
    w |= (1UL << WARN_SD_FAULT_BIT);
  }

  return w;
}

static uint32_t telemetry_plot_valid_mask(const SystemState &s) {
  uint32_t mask = 0U;

  if (s.baro.valid) mask |= (1UL << 0);
  if (s.imu.valid) mask |= (1UL << 1);
  if (s.aux.valid) mask |= (1UL << 2);
  if (s.pmod_accel.valid) mask |= (1UL << 3);
  if (s.mag.valid) mask |= (1UL << 4);
  if (s.attitude.valid) mask |= (1UL << 5);
  if (s.auxvz.valid) mask |= (1UL << 6);
  if (s.est.valid) mask |= (1UL << 7);
  if (s.policy.valid) mask |= (1UL << 8);

  return mask;
}

static const char *telemetry_plot_mode_token(PlotMode mode) {
  switch (mode) {
    case PLOT_MODE_OFF:
      return "OFF";

    case PLOT_MODE_OVERVIEW:
      return "OVERVIEW";

    case PLOT_MODE_IMU:
      return "IMU";

    case PLOT_MODE_APOGEE:
      return "APOGEE";

    case PLOT_MODE_ESTIMATOR:
      return "ESTIMATOR";

    case PLOT_MODE_PHASE:
      return "PHASE";

    case PLOT_MODE_HEALTH:
      return "HEALTH";

    case PLOT_MODE_ACTUATOR:
      return "ACTUATOR";

    case PLOT_MODE_ORIENT:
      return "ORIENT";

    case PLOT_MODE_SAFETY:
      return "SAFETY";

    case PLOT_MODE_PROVENANCE:
      return "PROVENANCE";

    case PLOT_MODE_ENERGY:
      return "ENERGY";

    case PLOT_MODE_HUD:
      return "HUD";

    default:
      return "UNKNOWN";
  }
}

static float telemetry_norm3(float x, float y, float z) {
  if (!is_finite_f(x) || !is_finite_f(y) || !is_finite_f(z)) {
    return NAN;
  }

  return sqrtf(x * x + y * y + z * z);
}

static float telemetry_vertical_qbar_proxy_pa(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.v_mps)) {
    return NAN;
  }

  return 0.5f * POLICY_RHO_KGPM3 * s.est.v_mps * s.est.v_mps;
}

static float telemetry_difference(float a, float b) {
  if (!is_finite_f(a) || !is_finite_f(b)) {
    return NAN;
  }

  return a - b;
}

static float telemetry_kinetic_height_m(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.v_mps)) {
    return NAN;
  }

  return (s.est.v_mps * s.est.v_mps) / (2.0f * kG);
}

static float telemetry_specific_energy_m(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.h_m) || !is_finite_f(s.est.v_mps)) {
    return NAN;
  }

  return s.est.h_m + (s.est.v_mps * s.est.v_mps) / (2.0f * kG);
}

static float telemetry_vertical_mach_proxy(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.v_mps)) {
    return NAN;
  }

  float temp_k = 288.15f;
  if (s.baro.valid && is_finite_f(s.baro.temp_c) &&
      s.baro.temp_c > -80.0f && s.baro.temp_c < 80.0f) {
    temp_k = s.baro.temp_c + 273.15f;
  }

  const float sound_speed_mps = sqrtf(1.4f * 287.05f * temp_k);
  if (!is_finite_f(sound_speed_mps) || sound_speed_mps <= 0.0f) {
    return NAN;
  }

  return fabsf(s.est.v_mps) / sound_speed_mps;
}

static float telemetry_brake_authority_m(const SystemState &s) {
  if (!is_finite_f(s.policy.predicted_apogee_no_brake_m) ||
      !is_finite_f(s.policy.predicted_apogee_full_brake_m)) {
    return NAN;
  }

  return s.policy.predicted_apogee_no_brake_m -
         s.policy.predicted_apogee_full_brake_m;
}

static float telemetry_baro_velocity_proxy_mps(const SystemState &s) {
  static bool have_previous_baro = false;
  static uint32_t previous_baro_t_ms = 0;
  static uint32_t previous_baro_seq = 0;
  static float previous_baro_alt_m = NAN;

  if (!s.baro.valid || !is_finite_f(s.baro.alt_m)) {
    have_previous_baro = false;
    return NAN;
  }

  float v_mps = NAN;
  if (have_previous_baro && s.baro.seq != previous_baro_seq &&
      s.baro.t_ms != previous_baro_t_ms &&
      is_finite_f(previous_baro_alt_m)) {
    const float dt_s = ((float)(s.baro.t_ms - previous_baro_t_ms)) * 0.001f;
    if (dt_s > 0.0f) {
      v_mps = (s.baro.alt_m - previous_baro_alt_m) / dt_s;
    }
  }

  previous_baro_t_ms = s.baro.t_ms;
  previous_baro_seq = s.baro.seq;
  previous_baro_alt_m = s.baro.alt_m;
  have_previous_baro = true;
  return v_mps;
}

static float telemetry_target_margin_m(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.h_m) ||
      !is_finite_f(s.policy.target_effective_m)) {
    return NAN;
  }

  return s.policy.target_effective_m - s.est.h_m;
}

static float telemetry_sigma_h_m(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.P00) || s.est.P00 < 0.0f) {
    return NAN;
  }

  return sqrtf(s.est.P00);
}

static float telemetry_sigma_v_mps(const SystemState &s) {
  if (!s.est.valid || !is_finite_f(s.est.P11) || s.est.P11 < 0.0f) {
    return NAN;
  }

  return sqrtf(s.est.P11);
}

static float telemetry_accel_roll_deg(const SystemState &s) {
  if (!s.aux.valid || !is_finite_f(s.aux.ay) || !is_finite_f(s.aux.az)) {
    return NAN;
  }

  return atan2f(s.aux.ay, s.aux.az) * (180.0f / 3.14159265358979323846f);
}

static float telemetry_accel_pitch_deg(const SystemState &s) {
  if (!s.aux.valid || !is_finite_f(s.aux.ax) ||
      !is_finite_f(s.aux.ay) || !is_finite_f(s.aux.az)) {
    return NAN;
  }

  const float yz_norm = sqrtf(s.aux.ay * s.aux.ay + s.aux.az * s.aux.az);
  return atan2f(-s.aux.ax, yz_norm) * (180.0f / 3.14159265358979323846f);
}

static bool telemetry_phase_allows_policy(const SystemState &s) {
  return (s.phase == FlightPhase::COAST) || (s.phase == FlightPhase::BRAKE);
}

static float telemetry_gravity_residual_mps2(const SystemState &s) {
  if (!s.aux.valid || !is_finite_f(s.aux.a_norm)) {
    return NAN;
  }

  return s.aux.a_norm - kG;
}

static uint16_t telemetry_hud_readiness_flags(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t warn_mask
) {
  uint16_t flags = 0U;

  const uint32_t est_age_ms = age_ms(now_ms, s.est.t_ms, s.est.valid);
  const bool est_fresh = s.est.valid && est_age_ms <= EST_MAX_AGE_MS;
  const bool sd_ready =
    s.sdlog.enabled &&
    s.sdlog.card_ok &&
    s.sdlog.file_open &&
    !s.sdlog.runtime_failed &&
    s.sdlog.fault_reason == SdFaultReason::NONE;

  // Bit assignments are intentionally compact and stable for tiny onboard
  // displays: cfg, est, est_fresh, phase, policy, safety runtime, safety
  // actuation, SD, warning-free, aux gravity, magnetic quality, barometer, IMU.
  if (s.cfg.valid) flags |= (1U << 0);
  if (s.est.valid) flags |= (1U << 1);
  if (est_fresh) flags |= (1U << 2);
  if (telemetry_phase_allows_policy(s)) flags |= (1U << 3);
  if (s.policy.valid) flags |= (1U << 4);
  if (safety_runtime_ok(s)) flags |= (1U << 5);
  if (safety_allows_actuation(s)) flags |= (1U << 6);
  if (sd_ready) flags |= (1U << 7);
  if (warn_mask == 0U) flags |= (1U << 8);
  if (s.aux.valid) flags |= (1U << 9);
  if (s.mag.valid && !s.mag.interference) flags |= (1U << 10);
  if (s.baro.valid) flags |= (1U << 11);
  if (s.imu.valid) flags |= (1U << 12);

  return flags;
}

static void telemetry_emit_plot_hud(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  static uint8_t hud_page = 0U;

  const uint8_t page = hud_page;
  hud_page = (uint8_t)((hud_page + 1U) & 0x03U);

  Serial.print(F("PLOT,HUD,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print(page);
  Serial.print(',');
  Serial.print(4U);
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.phase));
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(s.est.a_mps2);
  Serial.print(',');
  Serial.print(telemetry_sigma_h_m(s));
  Serial.print(',');
  Serial.print(telemetry_specific_energy_m(s));
  Serial.print(',');
  Serial.print(s.policy.target_effective_m);
  Serial.print(',');
  Serial.print(telemetry_target_margin_m(s));
  Serial.print(',');
  Serial.print(s.policy.apogee_error_m);
  Serial.print(',');
  Serial.print(telemetry_brake_authority_m(s));
  Serial.print(',');
  Serial.print(s.policy.command01);
  Serial.print(',');
  Serial.print(actuator_last_us());
  Serial.print(',');
  Serial.print(telemetry_accel_roll_deg(s));
  Serial.print(',');
  Serial.print(telemetry_accel_pitch_deg(s));
  Serial.print(',');
  Serial.print(s.mag.heading_deg);
  Serial.print(',');
  Serial.print(telemetry_gravity_residual_mps2(s));
  Serial.print(',');
  Serial.print(s.mag.norm_uT);
  Serial.print(',');
  Serial.print(s.mag.interference ? 1 : 0);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.aux.t_ms, s.aux.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.mag.t_ms, s.mag.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
  Serial.print(',');
  Serial.print(safety_runtime_ok(s) ? 1 : 0);
  Serial.print(',');
  Serial.print(safety_allows_actuation(s) ? 1 : 0);
  Serial.print(',');
  Serial.print(s.sdlog.card_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.sdlog.file_open ? 1 : 0);
  Serial.print(',');
  Serial.print(s.sdlog.runtime_failed ? 1 : 0);
  Serial.print(',');
  Serial.println(telemetry_hud_readiness_flags(s, now_ms, warn_mask));
}

static void telemetry_emit_plot_orient(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  Serial.print(F("PLOT,ORIENT,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(s.aux.ax);
  Serial.print(',');
  Serial.print(s.aux.ay);
  Serial.print(',');
  Serial.print(s.aux.az);
  Serial.print(',');
  Serial.print(s.aux.a_norm);
  Serial.print(',');
  Serial.print(telemetry_accel_roll_deg(s));
  Serial.print(',');
  Serial.print(telemetry_accel_pitch_deg(s));
  Serial.print(',');
  Serial.print(s.mag.cal_x);
  Serial.print(',');
  Serial.print(s.mag.cal_y);
  Serial.print(',');
  Serial.print(s.mag.cal_z);
  Serial.print(',');
  Serial.print(s.mag.norm_uT);
  Serial.print(',');
  Serial.print(s.mag.heading_deg);
  Serial.print(',');
  Serial.print(s.mag.interference ? 1 : 0);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.aux.t_ms, s.aux.valid));
  Serial.print(',');
  Serial.println(age_ms(now_ms, s.mag.t_ms, s.mag.valid));
}

static void telemetry_emit_plot_estimator(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  Serial.print(F("PLOT,ESTIMATOR,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.attitude.t_ms, s.attitude.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.auxvz.t_ms, s.auxvz.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
  Serial.print(',');
  Serial.print(s.baro.alt_m);
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(s.est.a_mps2);
  Serial.print(',');
  Serial.print(s.est.P00);
  Serial.print(',');
  Serial.print(s.est.P01);
  Serial.print(',');
  Serial.print(s.est.P10);
  Serial.print(',');
  Serial.print(s.est.P11);
  Serial.print(',');
  Serial.print(telemetry_sigma_h_m(s));
  Serial.print(',');
  Serial.print(telemetry_sigma_v_mps(s));
  Serial.print(',');
  Serial.println(s.est.seeded ? 1 : 0);
}

static void telemetry_emit_plot_phase(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  Serial.print(F("PLOT,PHASE,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.phase));
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(s.imu.a_norm);
  Serial.print(',');
  Serial.print(s.policy.command01);
  Serial.print(',');
  Serial.print(actuator_last_us());
  Serial.print(',');
  Serial.print(s.phase_diag.launch_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.launch_candidate ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_candidate ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_candidate ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.boost_dwell_met ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.coast_dwell_met ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.brake_active ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.launch_confirm_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_confirm_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_confirm_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.since_launch_ms);
  Serial.print(',');
  Serial.println(s.phase_diag.since_burnout_ms);
}

static void telemetry_emit_plot_health(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  Serial.print(F("PLOT,HEALTH,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(s.health.bmp_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.health.bmi_accel_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.health.bmi_gyro_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.health.lis_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.health.pmod_accel_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.health.mag_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.baro.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.imu.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.aux.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.pmod_accel.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.mag.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.attitude.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.auxvz.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.est.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.cfg.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.aux.t_ms, s.aux.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.pmod_accel.t_ms, s.pmod_accel.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.mag.t_ms, s.mag.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.attitude.t_ms, s.attitude.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.auxvz.t_ms, s.auxvz.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.phase_diag.t_ms, s.phase_diag.valid));
  Serial.print(',');
  Serial.print(s.sdlog.card_ok ? 1 : 0);
  Serial.print(',');
  Serial.print(s.sdlog.runtime_failed ? 1 : 0);
  Serial.print(',');
  Serial.println(s.sdlog.fail_count);
}

static void telemetry_emit_plot_actuator(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  Serial.print(F("PLOT,ACTUATOR,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.phase));
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.arm_state));
  Serial.print(',');
  Serial.print(s.policy_runtime_enabled ? 1 : 0);
  Serial.print(',');
  Serial.print(s.software_arm_token ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy.command01);
  Serial.print(',');
  Serial.print(actuator_last_us());
  Serial.print(',');
  Serial.print(s.actuator_cfg.servo_us_min);
  Serial.print(',');
  Serial.print(s.actuator_cfg.servo_us_idle);
  Serial.print(',');
  Serial.print(s.actuator_cfg.servo_us_max);
  Serial.print(',');
  Serial.print(s.est.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(s.policy.target_effective_m);
  Serial.print(',');
  Serial.print(s.policy.predicted_apogee_no_brake_m);
  Serial.print(',');
  Serial.print(s.policy.predicted_apogee_full_brake_m);
  Serial.print(',');
  Serial.print(s.policy.apogee_error_m);
  Serial.print(',');
  Serial.print(s.policy.uncertainty_margin_m);
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.println(warn_mask);
}

static void telemetry_emit_plot_safety(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  const uint32_t est_age_ms = age_ms(now_ms, s.est.t_ms, s.est.valid);
  const bool est_fresh = s.est.valid && est_age_ms <= EST_MAX_AGE_MS;

  Serial.print(F("PLOT,SAFETY,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(s.cfg.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.est.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.est.seeded ? 1 : 0);
  Serial.print(',');
  Serial.print(est_age_ms);
  Serial.print(',');
  Serial.print(est_fresh ? 1 : 0);
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.arm_state));
  Serial.print(',');
  Serial.print(s.software_arm_token ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy_runtime_enabled ? 1 : 0);
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.phase));
  Serial.print(',');
  Serial.print(telemetry_phase_allows_policy(s) ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy.command01);
  Serial.print(',');
  Serial.print(safety_runtime_ok(s) ? 1 : 0);
  Serial.print(',');
  Serial.print(safety_allows_actuation(s) ? 1 : 0);
  Serial.print(',');
  Serial.print(actuator_last_us());
  Serial.print(',');
  Serial.print(s.phase_diag.launch_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.boost_dwell_met ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.coast_dwell_met ? 1 : 0);
  Serial.print(',');
  Serial.println(s.phase_diag.brake_active ? 1 : 0);
}

static void telemetry_emit_plot_provenance(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  const float baro_v_proxy_mps = telemetry_baro_velocity_proxy_mps(s);

  Serial.print(F("PLOT,PROVENANCE,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.attitude.t_ms, s.attitude.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.auxvz.t_ms, s.auxvz.valid));
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
  Serial.print(',');
  Serial.print(s.baro.alt_m);
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(telemetry_difference(s.est.h_m, s.baro.alt_m));
  Serial.print(',');
  Serial.print(baro_v_proxy_mps);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(telemetry_difference(s.est.v_mps, baro_v_proxy_mps));
  Serial.print(',');
  Serial.print(s.auxvz.a_vertical);
  Serial.print(',');
  Serial.print(s.est.a_mps2);
  Serial.print(',');
  Serial.print(telemetry_difference(s.est.a_mps2, s.auxvz.a_vertical));
  Serial.print(',');
  Serial.print(s.est.P00);
  Serial.print(',');
  Serial.print(s.est.P11);
  Serial.print(',');
  Serial.print(telemetry_sigma_h_m(s));
  Serial.print(',');
  Serial.print(telemetry_sigma_v_mps(s));
  Serial.print(',');
  Serial.print(s.est.seeded ? 1 : 0);
  Serial.print(',');
  Serial.print(s.baro.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.auxvz.valid ? 1 : 0);
  Serial.print(',');
  Serial.println(s.est.valid ? 1 : 0);
}

static void telemetry_emit_plot_energy(
  const SystemState &s,
  uint32_t now_ms,
  uint32_t valid_mask,
  uint32_t warn_mask
) {
  Serial.print(F("PLOT,ENERGY,"));
  Serial.print(now_ms);
  Serial.print(',');
  Serial.print((unsigned int)((uint8_t)s.phase));
  Serial.print(',');
  Serial.print(valid_mask);
  Serial.print(',');
  Serial.print(warn_mask);
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(telemetry_specific_energy_m(s));
  Serial.print(',');
  Serial.print(telemetry_kinetic_height_m(s));
  Serial.print(',');
  Serial.print(telemetry_vertical_qbar_proxy_pa(s));
  Serial.print(',');
  Serial.print(telemetry_vertical_mach_proxy(s));
  Serial.print(',');
  Serial.print(s.policy.predicted_apogee_no_brake_m);
  Serial.print(',');
  Serial.print(s.policy.predicted_apogee_full_brake_m);
  Serial.print(',');
  Serial.print(s.policy.target_effective_m);
  Serial.print(',');
  Serial.print(telemetry_target_margin_m(s));
  Serial.print(',');
  Serial.print(telemetry_brake_authority_m(s));
  Serial.print(',');
  Serial.print(s.policy.command01);
  Serial.print(',');
  Serial.print(s.policy.valid ? 1 : 0);
  Serial.print(',');
  Serial.println(age_ms(now_ms, s.est.t_ms, s.est.valid));
}

/*
telemetry_print_header(...)
------------------------------------------------------------------------------
ROLE
  Emit the compact CSV schema.

INPUT CONTRACT
  Serial should already be initialized.

OUTPUT CONTRACT
  A single header line is emitted.

MECHANISM
  1. Print one fixed header string.
  2. Maintain exact field order correspondence with telemetry_emit_tlm(...).

FAILURE BEHAVIOR
  Serial output is best-effort.

DETERMINISM
  Bounded Serial output. No loops. No hardware I/O. No dynamic allocation.
*/
void telemetry_print_header(void) {
  Serial.println(
    F("HDR,t_ms,"
      "baro_valid,baro_upd,baro_seq,bmp_T,bmp_P,bmp_alt,"
      "imu_valid,imu_upd,imu_seq,ax,ay,az,gx,gy,gz,"
      "aux_valid,aux_upd,aux_seq,lis_ax,lis_ay,lis_az,"
      "pmod_accel_valid,pmod_accel_upd,pmod_accel_seq,pmod_accel_kind,"
      "pmod_raw_x,pmod_raw_y,pmod_raw_z,pmod_ax,pmod_ay,pmod_az,pmod_a_norm,"
      "mag_valid,mag_upd,mag_seq,mag_raw_x,mag_raw_y,mag_raw_z,"
      "mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,"
      "att_valid,att_upd,att_seq,q0,q1,q2,q3,"
      "auxvz_valid,auxvz_upd,auxvz_seq,a_vertical,"
      "est_valid,est_upd,est_seeded,est_seq,est_h,est_v,est_a,"
      "arm_state,policy_runtime_enabled,software_arm_token,phase,actuator_us,"
      "phase_diag_valid,phase_diag_updated,phase_diag_seq,"
      "phase_diag_t_ms,phase_diag_age_ms,"
      "phase_launch_latched,phase_burnout_latched,phase_descent_latched,"
      "phase_launch_candidate,phase_burnout_candidate,phase_descent_candidate,"
      "phase_boost_dwell_met,phase_coast_dwell_met,phase_brake_active,"
      "phase_launch_confirm_ms,phase_burnout_confirm_ms,phase_descent_confirm_ms,"
      "phase_since_launch_ms,phase_since_burnout_ms,"
      "policy_valid,policy_cmd,"
      "apogee_no_brake,apogee_full_brake,target_apogee,apogee_error,"
      "target_nominal,target_effective,uncertainty_margin,"
      "sea_level_hpa,baro_baseline_hpa,"
      "warn_mask"));
}

/*
telemetry_print_plot_header(...)
------------------------------------------------------------------------------
ROLE
  Emit the schema for the optional low-rate visual telemetry stream.

INPUT CONTRACT
  mode selects one of the documented plot row layouts.

OUTPUT CONTRACT
  A single PLOT_HDR line is emitted. OFF emits an explicit OFF header.

MECHANISM
  Select the fixed header for the active plot mode.

FAILURE BEHAVIOR
  Unknown modes emit PLOT_HDR,UNKNOWN and do not change runtime state.

DETERMINISM
  Bounded Serial output. No loops. No hardware I/O beyond Serial.
*/
void telemetry_print_plot_header(PlotMode mode) {
  switch (mode) {
    case PLOT_MODE_OFF:
      Serial.println(F("PLOT_HDR,OFF"));
      return;

    case PLOT_MODE_OVERVIEW:
      Serial.println(
        F("PLOT_HDR,OVERVIEW,t_ms,phase,valid_mask,warn_mask,"
          "baro_age_ms,imu_age_ms,est_age_ms,"
          "est_h_m,est_v_mps,est_a_mps2,baro_alt_m,cmd01,actuator_us,"
          "P00_m2,P11_m2,sigma_h_m,sigma_v_mps,"
          "uncertainty_margin_m,target_effective_m,policy_valid,est_seeded"));
      return;

    case PLOT_MODE_IMU:
      Serial.println(
        F("PLOT_HDR,IMU,t_ms,"
          "imu_ax,imu_ay,imu_az,imu_a_norm,"
          "aux_a_norm,pmod_a_norm,gyro_norm_radps,"
          "mag_norm_uT,mag_heading_deg,mag_interference,"
          "att_roll_deg,att_pitch_deg,att_yaw_deg,"
          "auxvz_a_vertical_mps2,valid_mask,warn_mask"));
      return;

    case PLOT_MODE_APOGEE:
      Serial.println(
        F("PLOT_HDR,APOGEE,t_ms,phase,"
          "est_h_m,est_v_mps,baro_alt_m,qbar_v_proxy_pa,specific_energy_m,"
          "mach_v_proxy,pred_no_brake_m,pred_full_brake_m,"
          "target_effective_m,target_nominal_m,target_margin_m,apogee_error_m,"
          "brake_authority_m,cmd01,uncertainty_margin_m,"
          "P00_m2,P11_m2,sigma_h_m,baro_age_ms,imu_age_ms,est_age_ms,"
          "policy_valid,actuator_us,valid_mask,warn_mask"));
      return;

    case PLOT_MODE_ESTIMATOR:
      Serial.println(
        F("PLOT_HDR,ESTIMATOR,t_ms,"
          "valid_mask,warn_mask,"
          "baro_age_ms,imu_age_ms,att_age_ms,auxvz_age_ms,est_age_ms,"
          "baro_alt_m,est_h_m,est_v_mps,est_a_mps2,"
          "P00,P01,P10,P11,sigma_h_m,sigma_v_mps,"
          "est_seeded"));
      return;

    case PLOT_MODE_PHASE:
      Serial.println(
        F("PLOT_HDR,PHASE,t_ms,"
          "phase,valid_mask,warn_mask,"
          "est_h_m,est_v_mps,imu_a_norm,cmd01,actuator_us,"
          "launch_latched,burnout_latched,descent_latched,"
          "launch_candidate,burnout_candidate,descent_candidate,"
          "boost_dwell_met,coast_dwell_met,brake_active,"
          "launch_confirm_ms,burnout_confirm_ms,descent_confirm_ms,"
          "since_launch_ms,since_burnout_ms"));
      return;

    case PLOT_MODE_HEALTH:
      Serial.println(
        F("PLOT_HDR,HEALTH,t_ms,"
          "valid_mask,warn_mask,"
          "bmp_ok,bmi_accel_ok,bmi_gyro_ok,lis_ok,pmod_accel_ok,mag_ok,"
          "baro_valid,imu_valid,aux_valid,pmod_valid,mag_valid,"
          "att_valid,auxvz_valid,est_valid,policy_valid,cfg_valid,"
          "baro_age_ms,imu_age_ms,aux_age_ms,pmod_age_ms,mag_age_ms,"
          "att_age_ms,auxvz_age_ms,est_age_ms,phase_diag_age_ms,"
          "sd_card_ok,sd_runtime_failed,sd_fail_count"));
      return;

    case PLOT_MODE_ACTUATOR:
      Serial.println(
        F("PLOT_HDR,ACTUATOR,t_ms,"
          "phase,arm_state,policy_runtime_enabled,software_arm_token,"
          "policy_valid,cmd01,actuator_us,servo_min_us,servo_idle_us,servo_max_us,"
          "est_valid,est_age_ms,est_h_m,est_v_mps,"
          "target_effective_m,pred_no_brake_m,pred_full_brake_m,"
          "apogee_error_m,uncertainty_margin_m,"
          "valid_mask,warn_mask"));
      return;

    case PLOT_MODE_ORIENT:
      Serial.println(
        F("PLOT_HDR,ORIENT,t_ms,"
          "valid_mask,warn_mask,"
          "aux_ax_mps2,aux_ay_mps2,aux_az_mps2,aux_a_norm_mps2,"
          "accel_roll_deg,accel_pitch_deg,"
          "mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,"
          "aux_age_ms,mag_age_ms"));
      return;

    case PLOT_MODE_SAFETY:
      Serial.println(
        F("PLOT_HDR,SAFETY,t_ms,"
          "valid_mask,warn_mask,"
          "cfg_valid,est_valid,est_seeded,est_age_ms,est_fresh,"
          "arm_state,software_arm_token,policy_runtime_enabled,"
          "phase,phase_allows_policy,policy_valid,cmd01,"
          "safety_runtime_ok,safety_allows_actuation,actuator_us,"
          "launch_latched,burnout_latched,descent_latched,"
          "boost_dwell_met,coast_dwell_met,brake_active"));
      return;

    case PLOT_MODE_PROVENANCE:
      Serial.println(
        F("PLOT_HDR,PROVENANCE,t_ms,"
          "valid_mask,warn_mask,"
          "baro_age_ms,imu_age_ms,att_age_ms,auxvz_age_ms,est_age_ms,"
          "baro_alt_m,est_h_m,alt_residual_m,"
          "baro_v_proxy_mps,est_v_mps,velocity_residual_mps,"
          "auxvz_a_vertical_mps2,est_a_mps2,accel_residual_mps2,"
          "P00_m2,P11_m2,sigma_h_m,sigma_v_mps,"
          "est_seeded,baro_valid,auxvz_valid,est_valid"));
      return;

    case PLOT_MODE_ENERGY:
      Serial.println(
        F("PLOT_HDR,ENERGY,t_ms,phase,"
          "valid_mask,warn_mask,"
          "est_h_m,est_v_mps,specific_energy_m,kinetic_height_m,"
          "qbar_v_proxy_pa,mach_v_proxy,"
          "pred_no_brake_m,pred_full_brake_m,"
          "target_effective_m,target_margin_m,brake_authority_m,"
          "cmd01,policy_valid,est_age_ms"));
      return;

    case PLOT_MODE_HUD:
      Serial.println(
        F("PLOT_HDR,HUD,t_ms,page,page_count,phase,valid_mask,warn_mask,"
          "est_h_m,est_v_mps,est_a_mps2,sigma_h_m,specific_energy_m,"
          "target_effective_m,target_margin_m,apogee_error_m,brake_authority_m,"
          "cmd01,actuator_us,roll_deg,pitch_deg,heading_deg,"
          "gravity_residual_mps2,mag_norm_uT,mag_interference,"
          "baro_age_ms,imu_age_ms,aux_age_ms,mag_age_ms,est_age_ms,"
          "safety_runtime_ok,safety_allows_actuation,"
          "sd_card_ok,sd_file_open,sd_runtime_failed,readiness_flags"));
      return;

    default:
      Serial.println(F("PLOT_HDR,UNKNOWN"));
      return;
  }
}

/*
telemetry_emit_plot(...)
------------------------------------------------------------------------------
ROLE
  Emit one visually compact, science-oriented plot row.

INPUT CONTRACT
  now_ms must be the scheduler's current millis() value. state.plot_mode selects
  the active schema printed by telemetry_print_plot_header(...).

OUTPUT CONTRACT
  A single PLOT row is emitted for the active visual mode. OFF emits nothing.

SCIENTIFIC CONTRACT
  qbar_v_proxy_pa and mach_v_proxy are vertical-speed-derived proxies, not true
  airspeed-derived dynamic pressure or full Mach number. They are useful for live
  trend visualization and post-test sanity checks but must not be treated as
  aerodynamic truth without an airspeed estimate.

DETERMINISM
  Bounded Serial output. No loops. No hardware I/O beyond Serial.
*/
void telemetry_emit_plot(const SystemState &s, uint32_t now_ms) {
  const uint32_t valid_mask = telemetry_plot_valid_mask(s);
  const uint32_t warn_mask = telemetry_warn_mask(s);

  switch (s.plot_mode) {
    case PLOT_MODE_OVERVIEW:
      Serial.print(F("PLOT,"));
      Serial.print(telemetry_plot_mode_token(s.plot_mode));
      Serial.print(',');
      Serial.print(now_ms);
      Serial.print(',');
      Serial.print((unsigned int)((uint8_t)s.phase));
      Serial.print(',');
      Serial.print(valid_mask);
      Serial.print(',');
      Serial.print(warn_mask);
      Serial.print(',');
      Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));
      Serial.print(',');
      Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));
      Serial.print(',');
      Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
      Serial.print(',');
      Serial.print(s.est.h_m);
      Serial.print(',');
      Serial.print(s.est.v_mps);
      Serial.print(',');
      Serial.print(s.est.a_mps2);
      Serial.print(',');
      Serial.print(s.baro.alt_m);
      Serial.print(',');
      Serial.print(s.policy.command01);
      Serial.print(',');
      Serial.print(actuator_last_us());
      Serial.print(',');
      Serial.print(s.est.P00);
      Serial.print(',');
      Serial.print(s.est.P11);
      Serial.print(',');
      Serial.print(telemetry_sigma_h_m(s));
      Serial.print(',');
      Serial.print(telemetry_sigma_v_mps(s));
      Serial.print(',');
      Serial.print(s.policy.uncertainty_margin_m);
      Serial.print(',');
      Serial.print(s.policy.target_effective_m);
      Serial.print(',');
      Serial.print(s.policy.valid ? 1 : 0);
      Serial.print(',');
      Serial.println(s.est.seeded ? 1 : 0);
      return;

    case PLOT_MODE_IMU:
      Serial.print(F("PLOT,"));
      Serial.print(telemetry_plot_mode_token(s.plot_mode));
      Serial.print(',');
      Serial.print(now_ms);
      Serial.print(',');
      Serial.print(s.imu.ax);
      Serial.print(',');
      Serial.print(s.imu.ay);
      Serial.print(',');
      Serial.print(s.imu.az);
      Serial.print(',');
      Serial.print(s.imu.a_norm);
      Serial.print(',');
      Serial.print(s.aux.a_norm);
      Serial.print(',');
      Serial.print(s.pmod_accel.a_norm);
      Serial.print(',');
      Serial.print(telemetry_norm3(s.imu.gx, s.imu.gy, s.imu.gz));
      Serial.print(',');
      Serial.print(s.mag.norm_uT);
      Serial.print(',');
      Serial.print(s.mag.heading_deg);
      Serial.print(',');
      Serial.print(s.mag.interference ? 1 : 0);
      Serial.print(',');
      Serial.print(s.attitude.roll_deg);
      Serial.print(',');
      Serial.print(s.attitude.pitch_deg);
      Serial.print(',');
      Serial.print(s.attitude.yaw_deg);
      Serial.print(',');
      Serial.print(s.auxvz.a_vertical);
      Serial.print(',');
      Serial.print(valid_mask);
      Serial.print(',');
      Serial.println(warn_mask);
      return;

    case PLOT_MODE_APOGEE:
      Serial.print(F("PLOT,"));
      Serial.print(telemetry_plot_mode_token(s.plot_mode));
      Serial.print(',');
      Serial.print(now_ms);
      Serial.print(',');
      Serial.print((unsigned int)((uint8_t)s.phase));
      Serial.print(',');
      Serial.print(s.est.h_m);
      Serial.print(',');
      Serial.print(s.est.v_mps);
      Serial.print(',');
      Serial.print(s.baro.alt_m);
      Serial.print(',');
      Serial.print(telemetry_vertical_qbar_proxy_pa(s));
      Serial.print(',');
      Serial.print(telemetry_specific_energy_m(s));
      Serial.print(',');
      Serial.print(telemetry_vertical_mach_proxy(s));
      Serial.print(',');
      Serial.print(s.policy.predicted_apogee_no_brake_m);
      Serial.print(',');
      Serial.print(s.policy.predicted_apogee_full_brake_m);
      Serial.print(',');
      Serial.print(s.policy.target_effective_m);
      Serial.print(',');
      Serial.print(s.policy.target_nominal_m);
      Serial.print(',');
      Serial.print(telemetry_target_margin_m(s));
      Serial.print(',');
      Serial.print(s.policy.apogee_error_m);
      Serial.print(',');
      Serial.print(telemetry_brake_authority_m(s));
      Serial.print(',');
      Serial.print(s.policy.command01);
      Serial.print(',');
      Serial.print(s.policy.uncertainty_margin_m);
      Serial.print(',');
      Serial.print(s.est.P00);
      Serial.print(',');
      Serial.print(s.est.P11);
      Serial.print(',');
      Serial.print(telemetry_sigma_h_m(s));
      Serial.print(',');
      Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));
      Serial.print(',');
      Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));
      Serial.print(',');
      Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));
      Serial.print(',');
      Serial.print(s.policy.valid ? 1 : 0);
      Serial.print(',');
      Serial.print(actuator_last_us());
      Serial.print(',');
      Serial.print(valid_mask);
      Serial.print(',');
      Serial.println(warn_mask);
      return;

    case PLOT_MODE_ESTIMATOR:
      telemetry_emit_plot_estimator(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_PHASE:
      telemetry_emit_plot_phase(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_HEALTH:
      telemetry_emit_plot_health(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_ACTUATOR:
      telemetry_emit_plot_actuator(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_ORIENT:
      telemetry_emit_plot_orient(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_SAFETY:
      telemetry_emit_plot_safety(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_PROVENANCE:
      telemetry_emit_plot_provenance(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_ENERGY:
      telemetry_emit_plot_energy(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_HUD:
      telemetry_emit_plot_hud(s, now_ms, valid_mask, warn_mask);
      return;

    case PLOT_MODE_OFF:
    default:
      return;
  }
}

/*
telemetry_emit_tlm(...)
------------------------------------------------------------------------------
ROLE
  Emit one compact telemetry row.

INPUT CONTRACT
  Snapshot valid flags are emitted next to payload values so the log consumer can
  decide which numerical fields are meaningful.

OUTPUT CONTRACT
  A single TLM CSV row is emitted.

MECHANISM
  1. Print current timestamp.
  2. Print snapshot flags and payloads.
  3. Print attitude and estimator outputs.
  4. Print configuration references.
  5. Print warning mask.

FAILURE BEHAVIOR
  Invalid snapshots still occupy their CSV fields. Valid flags define payload
  usability.

DETERMINISM
  Bounded Serial output. No loops. No hardware I/O. No dynamic allocation.
*/
void telemetry_emit_tlm(const SystemState &s) {
  const uint32_t now_ms = millis();

  Serial.print(F("TLM,"));
  Serial.print(now_ms);
  Serial.print(',');

  // Every payload group is preceded by validity/update metadata so downstream
  // analysis can distinguish "field is numerically NAN because source invalid"
  // from "field is numerically zero and source valid."
  Serial.print(s.baro.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.baro.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.baro.seq);
  Serial.print(',');
  Serial.print(s.baro.temp_c);
  Serial.print(',');
  Serial.print(s.baro.press_hpa);
  Serial.print(',');
  Serial.print(s.baro.alt_m);
  Serial.print(',');

  Serial.print(s.imu.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.imu.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.imu.seq);
  Serial.print(',');
  Serial.print(s.imu.ax);
  Serial.print(',');
  Serial.print(s.imu.ay);
  Serial.print(',');
  Serial.print(s.imu.az);
  Serial.print(',');
  Serial.print(s.imu.gx);
  Serial.print(',');
  Serial.print(s.imu.gy);
  Serial.print(',');
  Serial.print(s.imu.gz);
  Serial.print(',');

  Serial.print(s.aux.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.aux.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.aux.seq);
  Serial.print(',');
  Serial.print(s.aux.ax);
  Serial.print(',');
  Serial.print(s.aux.ay);
  Serial.print(',');
  Serial.print(s.aux.az);
  Serial.print(',');

  Serial.print(s.pmod_accel.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.pmod_accel.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.pmod_accel.seq);
  Serial.print(',');
  Serial.print((uint8_t)s.pmod_accel.kind);
  Serial.print(',');
  Serial.print(s.pmod_accel.raw_x);
  Serial.print(',');
  Serial.print(s.pmod_accel.raw_y);
  Serial.print(',');
  Serial.print(s.pmod_accel.raw_z);
  Serial.print(',');
  Serial.print(s.pmod_accel.ax);
  Serial.print(',');
  Serial.print(s.pmod_accel.ay);
  Serial.print(',');
  Serial.print(s.pmod_accel.az);
  Serial.print(',');
  Serial.print(s.pmod_accel.a_norm);
  Serial.print(',');

  Serial.print(s.mag.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.mag.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.mag.seq);
  Serial.print(',');
  Serial.print(s.mag.raw_x);
  Serial.print(',');
  Serial.print(s.mag.raw_y);
  Serial.print(',');
  Serial.print(s.mag.raw_z);
  Serial.print(',');
  Serial.print(s.mag.cal_x);
  Serial.print(',');
  Serial.print(s.mag.cal_y);
  Serial.print(',');
  Serial.print(s.mag.cal_z);
  Serial.print(',');
  Serial.print(s.mag.norm_uT);
  Serial.print(',');
  Serial.print(s.mag.heading_deg);
  Serial.print(',');
  Serial.print(s.mag.interference ? 1 : 0);
  Serial.print(',');

  Serial.print(s.attitude.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.attitude.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.attitude.seq);
  Serial.print(',');
  Serial.print(s.attitude.q0);
  Serial.print(',');
  Serial.print(s.attitude.q1);
  Serial.print(',');
  Serial.print(s.attitude.q2);
  Serial.print(',');
  Serial.print(s.attitude.q3);
  Serial.print(',');

  Serial.print(s.auxvz.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.auxvz.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.auxvz.seq);
  Serial.print(',');
  Serial.print(s.auxvz.a_vertical);
  Serial.print(',');

  Serial.print(s.est.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.est.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.est.seeded ? 1 : 0);
  Serial.print(',');
  Serial.print(s.est.seq);
  Serial.print(',');
  Serial.print(s.est.h_m);
  Serial.print(',');
  Serial.print(s.est.v_mps);
  Serial.print(',');
  Serial.print(s.est.a_mps2);
  Serial.print(',');

  Serial.print((uint8_t)s.arm_state);
  Serial.print(',');
  Serial.print(s.policy_runtime_enabled ? 1 : 0);
  Serial.print(',');
  Serial.print(s.software_arm_token ? 1 : 0);
  Serial.print(',');
  Serial.print((uint8_t)s.phase);
  Serial.print(',');
  Serial.print(actuator_last_us());
  Serial.print(',');

  Serial.print(s.phase_diag.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.updated ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.seq);
  Serial.print(',');
  Serial.print(s.phase_diag.t_ms);
  Serial.print(',');
  Serial.print(age_ms(now_ms, s.phase_diag.t_ms, s.phase_diag.valid));
  Serial.print(',');
  Serial.print(s.phase_diag.launch_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_latched ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.launch_candidate ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_candidate ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_candidate ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.boost_dwell_met ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.coast_dwell_met ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.brake_active ? 1 : 0);
  Serial.print(',');
  Serial.print(s.phase_diag.launch_confirm_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.burnout_confirm_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.descent_confirm_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.since_launch_ms);
  Serial.print(',');
  Serial.print(s.phase_diag.since_burnout_ms);
  Serial.print(',');

  Serial.print(s.policy.valid ? 1 : 0);
  Serial.print(',');
  Serial.print(s.policy.command01);
  Serial.print(',');
  Serial.print(s.policy.predicted_apogee_no_brake_m);
  Serial.print(',');
  Serial.print(s.policy.predicted_apogee_full_brake_m);
  Serial.print(',');
  Serial.print(s.policy.target_apogee_m);
  Serial.print(',');
  Serial.print(s.policy.apogee_error_m);
  Serial.print(',');

  Serial.print(s.policy.target_nominal_m);
  Serial.print(',');
  Serial.print(s.policy.target_effective_m);
  Serial.print(',');
  Serial.print(s.policy.uncertainty_margin_m);
  Serial.print(',');

  // The configuration references are emitted with every row because they define
  // the physical meaning of the altitude-related fields in that same row.
  Serial.print(s.cfg.sea_level_hpa);
  Serial.print(',');
  Serial.print(s.cfg.baro_baseline_hpa);
  Serial.print(',');
  Serial.println(telemetry_warn_mask(s));
}

/*
telemetry_print_status(...)
------------------------------------------------------------------------------
ROLE
  Emit human-readable system status for command-line inspection.

INPUT CONTRACT
  state must refer to the shared SystemState object.

OUTPUT CONTRACT
  A compact status line is emitted.

MECHANISM
  1. Print sensor health flags.
  2. Print major snapshot validity flags.
  3. Print active SD filename.

FAILURE BEHAVIOR
  No recovery is attempted.

DETERMINISM
  Bounded Serial output. No loops. No hardware I/O. No dynamic allocation.
*/
void telemetry_print_status(const SystemState &s) {
  Serial.print(F("STATUS,bmp_ok="));
  Serial.print(s.health.bmp_ok ? 1 : 0);

  Serial.print(F(",bmi_accel_ok="));
  Serial.print(s.health.bmi_accel_ok ? 1 : 0);

  Serial.print(F(",bmi_gyro_ok="));
  Serial.print(s.health.bmi_gyro_ok ? 1 : 0);

  Serial.print(F(",lis_ok="));
  Serial.print(s.health.lis_ok ? 1 : 0);

  Serial.print(F(",lis_i2c_addr="));
  print_hex_u8(sensors_lis3dh_i2c_address());

  Serial.print(F(",lis_i2c_bus="));
  Serial.print(i2c_bus_name(sensors_lis3dh_i2c_bus()));

  Serial.print(F(",pmod_accel_ok="));
  Serial.print(s.health.pmod_accel_ok ? 1 : 0);

  Serial.print(F(",mag_ok="));
  Serial.print(s.health.mag_ok ? 1 : 0);

  const uint8_t cmps2_status = sensors_pmod_cmps2_init_status();

  Serial.print(F(",cmps2_init="));
  Serial.print(cmps2_init_status_name(cmps2_status));

  Serial.print(F(",cmps2_runtime="));
  Serial.print(cmps2_runtime_status_name(sensors_pmod_cmps2_runtime_status()));

  Serial.print(F(",cmps2_product_id="));
  print_hex_u8(sensors_pmod_cmps2_product_id());

  Serial.print(F(",baro_valid="));
  Serial.print(s.baro.valid ? 1 : 0);

  Serial.print(F(",imu_valid="));
  Serial.print(s.imu.valid ? 1 : 0);

  Serial.print(F(",pmod_accel_valid="));
  Serial.print(s.pmod_accel.valid ? 1 : 0);

  Serial.print(F(",mag_valid="));
  Serial.print(s.mag.valid ? 1 : 0);

  Serial.print(F(",pmod_accel_age_ms="));
  Serial.print(age_ms(millis(), s.pmod_accel.t_ms, s.pmod_accel.valid));

  Serial.print(F(",mag_age_ms="));
  Serial.print(age_ms(millis(), s.mag.t_ms, s.mag.valid));

  Serial.print(F(",mag_interference="));
  Serial.print(s.mag.interference ? 1 : 0);

  Serial.print(F(",att_valid="));
  Serial.print(s.attitude.valid ? 1 : 0);

  Serial.print(F(",est_valid="));
  Serial.print(s.est.valid ? 1 : 0);

  Serial.print(F(",arm_state="));
  Serial.print(arming_state_name(s.arm_state));

  Serial.print(F(",policy_runtime_enabled="));
  Serial.print(s.policy_runtime_enabled ? 1 : 0);

  Serial.print(F(",software_arm_token="));
  Serial.print(s.software_arm_token ? 1 : 0);

  Serial.print(F(",baro_baseline_hpa="));
  Serial.print(s.cfg.baro_baseline_hpa);

  Serial.print(F(",sd_file="));
  Serial.print(s.sdlog.filename);

  Serial.print(F(",sd_enabled="));
  Serial.print(s.sdlog.enabled ? 1 : 0);

  Serial.print(F(",sd_card_ok="));
  Serial.print(s.sdlog.card_ok ? 1 : 0);

  Serial.print(F(",sd_file_open="));
  Serial.print(s.sdlog.file_open ? 1 : 0);

  Serial.print(F(",sd_runtime_failed="));
  Serial.print(s.sdlog.runtime_failed ? 1 : 0);

  Serial.print(F(",sd_fail_count="));
  Serial.print(s.sdlog.fail_count);

  Serial.print(F(",sd_fault_reason="));
  Serial.print(sd_fault_reason_name(s.sdlog.fault_reason));

  Serial.print(F(",cfg_bmp5xx_enabled="));
  Serial.print((uint8_t)BMP5XX_ENABLED);

  Serial.print(F(",cfg_bmi088_enabled="));
  Serial.print((uint8_t)BMI088_ENABLED);

  Serial.print(F(",cfg_bmi088_use_spi="));
  Serial.print((uint8_t)BMI088_USE_SPI);

  Serial.print(F(",cfg_lis3dh_enabled="));
  Serial.print((uint8_t)LIS3DH_ENABLED);

  Serial.print(F(",cfg_pmod_cmps2_enabled="));
  Serial.print((uint8_t)PMOD_CMPS2_ENABLED);

  Serial.print(F(",plot_valid_mask="));
  Serial.print(telemetry_plot_valid_mask(s));

  Serial.print(F(",policy_valid="));
  Serial.print(s.policy.valid ? 1 : 0);

  Serial.print(F(",policy_cmd="));
  Serial.print(s.policy.command01);

  Serial.print(F(",apogee_no_brake="));
  Serial.print(s.policy.predicted_apogee_no_brake_m);

  Serial.print(F(",apogee_full_brake="));
  Serial.print(s.policy.predicted_apogee_full_brake_m);

  Serial.print(F(",target_apogee="));
  Serial.print(s.policy.target_apogee_m);

  Serial.print(F(",apogee_error="));
  Serial.print(s.policy.apogee_error_m);

  Serial.print(F(",phase="));
  Serial.print((uint8_t)s.phase);

  Serial.print(F(",phase_launch_latched="));
  Serial.print(s.phase_diag.launch_latched ? 1 : 0);

  Serial.print(F(",phase_burnout_latched="));
  Serial.print(s.phase_diag.burnout_latched ? 1 : 0);

  Serial.print(F(",phase_descent_latched="));
  Serial.print(s.phase_diag.descent_latched ? 1 : 0);

  Serial.print(F(",phase_launch_confirm_ms="));
  Serial.print(s.phase_diag.launch_confirm_ms);

  Serial.print(F(",phase_burnout_confirm_ms="));
  Serial.print(s.phase_diag.burnout_confirm_ms);

  Serial.print(F(",phase_descent_confirm_ms="));
  Serial.print(s.phase_diag.descent_confirm_ms);

  Serial.print(F(",target_nominal="));
  Serial.print(s.policy.target_nominal_m);

  Serial.print(F(",target_effective="));
  Serial.print(s.policy.target_effective_m);

  Serial.print(F(",uncertainty_margin="));
  Serial.print(s.policy.uncertainty_margin_m);

  Serial.print(F(",actuator_us="));
  Serial.print(actuator_last_us());

  Serial.print(F(",warn_mask="));
  Serial.println(telemetry_warn_mask(s));
}

/*
telemetry_emit_diag(...)
------------------------------------------------------------------------------
ROLE
  Emit age-oriented diagnostics.

INPUT CONTRACT
  state must refer to the shared SystemState object. now_ms must be current
  millis() time.

OUTPUT CONTRACT
  A single diagnostic line is emitted.

MECHANISM
  1. Print current timestamp.
  2. Print age of major snapshots using invalid-sentinel semantics.
  3. Print warning mask.

FAILURE BEHAVIOR
  Invalid snapshots produce the age sentinel instead of a misleading fresh age.

DETERMINISM
  Bounded Serial output. No loops. No hardware I/O. No dynamic allocation.
*/
void telemetry_emit_diag(const SystemState &s, uint32_t now_ms) {
  Serial.print(F("DIAG,RUN,t_ms="));
  Serial.print(now_ms);

  Serial.print(F(",baro_age_ms="));
  Serial.print(age_ms(now_ms, s.baro.t_ms, s.baro.valid));

  Serial.print(F(",imu_age_ms="));
  Serial.print(age_ms(now_ms, s.imu.t_ms, s.imu.valid));

  Serial.print(F(",pmod_accel_age_ms="));
  Serial.print(age_ms(now_ms, s.pmod_accel.t_ms, s.pmod_accel.valid));

  Serial.print(F(",mag_age_ms="));
  Serial.print(age_ms(now_ms, s.mag.t_ms, s.mag.valid));

  Serial.print(F(",att_age_ms="));
  Serial.print(age_ms(now_ms, s.attitude.t_ms, s.attitude.valid));

  Serial.print(F(",auxvz_age_ms="));
  Serial.print(age_ms(now_ms, s.auxvz.t_ms, s.auxvz.valid));

  Serial.print(F(",est_age_ms="));
  Serial.print(age_ms(now_ms, s.est.t_ms, s.est.valid));

  Serial.print(F(",phase_diag_age_ms="));
  Serial.print(age_ms(now_ms, s.phase_diag.t_ms, s.phase_diag.valid));

  Serial.print(F(",phase_latches="));
  Serial.print(s.phase_diag.launch_latched ? 1 : 0);
  Serial.print('/');
  Serial.print(s.phase_diag.burnout_latched ? 1 : 0);
  Serial.print('/');
  Serial.print(s.phase_diag.descent_latched ? 1 : 0);

  Serial.print(F(",phase_candidates="));
  Serial.print(s.phase_diag.launch_candidate ? 1 : 0);
  Serial.print('/');
  Serial.print(s.phase_diag.burnout_candidate ? 1 : 0);
  Serial.print('/');
  Serial.print(s.phase_diag.descent_candidate ? 1 : 0);

  Serial.print(F(",sd_enabled="));
  Serial.print(s.sdlog.enabled ? 1 : 0);

  Serial.print(F(",sd_card_ok="));
  Serial.print(s.sdlog.card_ok ? 1 : 0);

  Serial.print(F(",sd_file_open="));
  Serial.print(s.sdlog.file_open ? 1 : 0);

  Serial.print(F(",sd_runtime_failed="));
  Serial.print(s.sdlog.runtime_failed ? 1 : 0);

  Serial.print(F(",sd_fail_count="));
  Serial.print(s.sdlog.fail_count);

  Serial.print(F(",sd_fault_reason="));
  Serial.print(sd_fault_reason_name(s.sdlog.fault_reason));

  Serial.print(F(",plot_valid_mask="));
  Serial.print(telemetry_plot_valid_mask(s));

  Serial.print(F(",warn_mask="));
  Serial.println(telemetry_warn_mask(s));
}

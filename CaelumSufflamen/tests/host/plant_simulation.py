from __future__ import annotations

import argparse
import csv
import json
import math
import random
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
ROOT = THIS_DIR.parents[1]
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from policy_coast_sim import (  # noqa: E402
    K_G,
    POLICY_APOGEE_DEADBAND_M,
    POLICY_BISECTION_STEPS,
    POLICY_CDA_BRAKE_M2,
    POLICY_CDA_BODY_M2,
    POLICY_MAX_COMMAND01,
    POLICY_MIN_ALT_M,
    POLICY_MIN_VZ_MPS,
    POLICY_RHO_KGPM3,
    POLICY_SLEW_PER_SEC,
    POLICY_TARGET_APOGEE_M,
    POLICY_VEHICLE_MASS_KG,
    clamp01,
    policy_drag_k,
    predict_apogee_m,
    solve_policy_command01,
)


def first_existing_path(*relative_paths: str) -> Path:
    for relative_path in relative_paths:
        candidate = ROOT / relative_path
        if candidate.exists():
            return candidate
    joined = ", ".join(relative_paths)
    raise FileNotFoundError(f"Could not locate any expected source file: {joined}")


CONFIG_H = first_existing_path("utils/config.h", "config.h")
SD_LOGGER_CPP = first_existing_path("utils/sd_logger.cpp", "sd_logger.cpp")

PHASE_IDLE = 0
PHASE_BOOST = 1
PHASE_COAST = 2
PHASE_BRAKE = 3
PHASE_DESCENT = 4

WARN_BARO_INVALID = 1 << 4
WARN_IMU_INVALID = 1 << 5
WARN_AUX_INVALID = 1 << 6
WARN_AUXVZ_INVALID = 1 << 7
WARN_ATT_INVALID = 1 << 8
WARN_EST_INVALID = 1 << 9

SUPPORTED_FAULTS = {
    "baro_dropout",
    "baro_bias",
    "imu_dropout",
    "imu_bias",
    "est_dropout",
    "est_freeze",
    "actuator_stuck",
    "actuator_bias",
    "noise_burst",
}


def extract_constant(text: str, name: str) -> str:
    static_pattern = rf"static const [A-Za-z0-9_:\*]+ {name}\s*=\s*([^;\r\n]+)"
    match = re.search(static_pattern, text)
    if match:
        return match.group(1).strip()

    define_pattern = rf"#define {name}\s+([^\r\n]+)"
    match = re.search(define_pattern, text)
    if match:
        return match.group(1).strip()

    raise ValueError(f"Could not find constant {name}")


def parse_numeric_literal(expr: str) -> float:
    cleaned = expr.replace("UL", "").replace("U", "").replace("f", "").replace("F", "")
    return float(cleaned)


CONFIG_TEXT = CONFIG_H.read_text(encoding="utf-8")
SERVO_US_MIN_DEFAULT = int(round(parse_numeric_literal(extract_constant(CONFIG_TEXT, "SERVO_US_MIN_DEFAULT"))))
SERVO_US_MAX_DEFAULT = int(round(parse_numeric_literal(extract_constant(CONFIG_TEXT, "SERVO_US_MAX_DEFAULT"))))
SERVO_US_IDLE_DEFAULT = int(round(parse_numeric_literal(extract_constant(CONFIG_TEXT, "SERVO_US_IDLE_DEFAULT"))))


@dataclass(frozen=True)
class FaultSpec:
    kind: str
    start_s: float
    end_s: float
    value: float = 0.0

    def active_at(self, t_s: float) -> bool:
        return self.start_s <= t_s < self.end_s


@dataclass(frozen=True)
class PlantConfig:
    seed: int = 1
    mode: str = "policy"
    h0_m: float = 0.0
    v0_mps: float = 0.0
    burn_time_s: float = 2.0
    boost_accel_mps2: float = 170.0
    target_apogee_m: float = POLICY_TARGET_APOGEE_M
    manual_command01: float = 0.0
    dt_s: float = 0.02
    max_time_s: float = 30.0
    post_apogee_s: float = 0.50
    baro_noise_m: float = 0.8
    imu_noise_mps2: float = 0.35
    gyro_noise_radps: float = 0.01
    mag_noise_ut: float = 0.4
    estimator_baro_gain: float = 0.12
    estimator_velocity_gain: float = 0.02
    actuator_tau_s: float = 0.20
    actuator_rate_per_s: float = 3.0


@dataclass
class EstimatorSurrogate:
    seeded: bool = False
    h_m: float = 0.0
    v_mps: float = 0.0
    p00: float = 4.0
    p01: float = 0.0
    p10: float = 0.0
    p11: float = 25.0


def extract_sd_header_fields() -> list[str]:
    text = SD_LOGGER_CPP.read_text(encoding="utf-8")
    match = re.search(
        r"static void sd_write_header\(File &f\).*?f\.println\((.*?)\);",
        text,
        re.DOTALL,
    )
    if match is None:
        raise RuntimeError("Could not extract SD logger header from utils/sd_logger.cpp")

    header = "".join(re.findall(r'"([^"]*)"', match.group(1)))
    fields = [field for field in header.split(",") if field]
    if not fields:
        raise RuntimeError("Extracted SD logger header was empty")
    return fields


def parse_fault_spec(text: str) -> FaultSpec:
    parts = text.split(":")
    if len(parts) not in (3, 4):
        raise ValueError(
            "Faults use kind:start_s:end_s[:value], for example baro_dropout:3.0:3.4"
        )

    kind = parts[0].strip().lower()
    if kind not in SUPPORTED_FAULTS:
        supported = ", ".join(sorted(SUPPORTED_FAULTS))
        raise ValueError(f"Unsupported fault kind '{kind}'. Supported: {supported}")

    start_s = float(parts[1])
    end_s = float(parts[2])
    if not math.isfinite(start_s) or not math.isfinite(end_s) or end_s <= start_s:
        raise ValueError(f"Invalid fault interval: {text}")

    if len(parts) == 4:
        value = float(parts[3])
    else:
        value = {
            "baro_bias": 10.0,
            "imu_bias": 3.0,
            "actuator_bias": 0.25,
            "noise_burst": 5.0,
        }.get(kind, 0.0)

    if not math.isfinite(value):
        raise ValueError(f"Invalid fault value: {text}")

    return FaultSpec(kind=kind, start_s=start_s, end_s=end_s, value=value)


def active_faults(faults: list[FaultSpec], t_s: float, kind: str | None = None) -> list[FaultSpec]:
    return [fault for fault in faults if fault.active_at(t_s) and (kind is None or fault.kind == kind)]


def fault_value(faults: list[FaultSpec], t_s: float, kind: str) -> float:
    return sum(fault.value for fault in active_faults(faults, t_s, kind))


def any_fault(faults: list[FaultSpec], t_s: float, kind: str) -> bool:
    return bool(active_faults(faults, t_s, kind))


def pressure_from_altitude_m(alt_m: float, sea_level_hpa: float = 1013.25) -> float:
    if not math.isfinite(alt_m):
        return math.nan
    base = max(0.05, 1.0 - alt_m / 44330.0)
    return sea_level_hpa * (base ** 5.255)


def finite_or_nan(value: float) -> float | str:
    return value if math.isfinite(value) else "nan"


def bounded_slew(current: float, target: float, max_rate_per_s: float, dt_s: float) -> float:
    max_delta = max(0.0, max_rate_per_s) * max(0.0, dt_s)
    delta = target - current
    if delta > max_delta:
        delta = max_delta
    elif delta < -max_delta:
        delta = -max_delta
    return clamp01(current + delta)


def first_order_actuator_step(current: float, target: float, config: PlantConfig) -> float:
    if config.actuator_tau_s <= 0.0:
        lagged = target
    else:
        alpha = 1.0 - math.exp(-config.dt_s / config.actuator_tau_s)
        lagged = current + alpha * (target - current)
    return bounded_slew(current, lagged, config.actuator_rate_per_s, config.dt_s)


def resolve_desired_policy_command(
    *,
    mode: str,
    phase: int,
    est_valid: bool,
    est_h_m: float,
    est_v_mps: float,
    target_apogee_m: float,
    manual_command01: float,
) -> tuple[bool, float]:
    eligible = phase in (PHASE_COAST, PHASE_BRAKE) and est_valid
    if not eligible:
        return False, 0.0

    if mode == "closed":
        desired = 0.0
    elif mode == "open":
        desired = clamp01(POLICY_MAX_COMMAND01)
    elif mode == "manual":
        desired = clamp01(manual_command01)
    elif mode == "policy":
        if est_h_m < POLICY_MIN_ALT_M or est_v_mps < POLICY_MIN_VZ_MPS:
            return True, 0.0
        desired = solve_policy_command01(est_h_m, est_v_mps, target_apogee_m)
    else:
        raise ValueError(f"Unsupported simulation mode: {mode}")

    return True, clamp01(desired)


def update_estimator(
    estimator: EstimatorSurrogate,
    *,
    config: PlantConfig,
    baro_valid: bool,
    baro_alt_m: float,
    imu_valid: bool,
    measured_a_vertical_mps2: float,
    freeze: bool,
) -> tuple[bool, bool]:
    if freeze:
        return estimator.seeded, False

    if not estimator.seeded:
        estimator.seeded = True
        estimator.h_m = baro_alt_m if baro_valid and math.isfinite(baro_alt_m) else config.h0_m
        estimator.v_mps = config.v0_mps
        return True, True

    a_mps2 = measured_a_vertical_mps2 if imu_valid and math.isfinite(measured_a_vertical_mps2) else 0.0
    pred_h_m = estimator.h_m + estimator.v_mps * config.dt_s + 0.5 * a_mps2 * config.dt_s * config.dt_s
    pred_v_mps = estimator.v_mps + a_mps2 * config.dt_s

    if baro_valid and math.isfinite(baro_alt_m):
        residual_m = baro_alt_m - pred_h_m
        estimator.h_m = pred_h_m + config.estimator_baro_gain * residual_m
        estimator.v_mps = pred_v_mps + (config.estimator_velocity_gain / config.dt_s) * residual_m
        estimator.p00 = max(0.25, 0.96 * estimator.p00 + config.baro_noise_m * config.baro_noise_m * 0.04)
        estimator.p11 = max(1.0, 0.98 * estimator.p11 + 0.05)
    else:
        estimator.h_m = pred_h_m
        estimator.v_mps = pred_v_mps
        estimator.p00 = min(2500.0, estimator.p00 + 0.5 + abs(estimator.v_mps) * 0.002)
        estimator.p11 = min(2500.0, estimator.p11 + 0.25)

    return True, True


def base_row(fields: list[str], row_seq: int, t_us: int) -> dict[str, object]:
    row: dict[str, object] = {field: "nan" for field in fields}
    row.update(
        {
            "row_seq": row_seq,
            "t_us": t_us,
            "pmod_accel_valid": 0,
            "pmod_accel_updated": 0,
            "pmod_accel_seq": 0,
            "pmod_accel_kind": 0,
            "pmod_raw_x": 0,
            "pmod_raw_y": 0,
            "pmod_raw_z": 0,
            "pmod_ax": "nan",
            "pmod_ay": "nan",
            "pmod_az": "nan",
            "pmod_a_norm": "nan",
            "att_valid": 1,
            "att_updated": 1,
            "att_seq": row_seq + 1,
            "q0": 1.0,
            "q1": 0.0,
            "q2": 0.0,
            "q3": 0.0,
            "arm_state": 2,
            "policy_runtime_enabled": 1,
            "software_arm_token": 1,
            "phase_diag_valid": 1,
            "phase_diag_updated": 1,
            "phase_diag_seq": row_seq + 1,
            "phase_diag_t_ms": t_us // 1000,
            "phase_diag_age_ms": 0,
            "phase_launch_confirm_ms": 60,
            "phase_burnout_confirm_ms": 120,
            "phase_descent_confirm_ms": 0,
            "phase_since_launch_ms": t_us // 1000,
            "phase_since_burnout_ms": 0xFFFFFFFF,
            "target_nominal": POLICY_TARGET_APOGEE_M,
        }
    )
    return row


def simulate_plant(config: PlantConfig, faults: list[FaultSpec] | None = None) -> dict:
    if faults is None:
        faults = []
    if config.dt_s <= 0.0:
        raise ValueError("dt_s must be positive")
    if config.max_time_s <= 0.0:
        raise ValueError("max_time_s must be positive")
    if config.post_apogee_s < 0.0:
        raise ValueError("post_apogee_s must be non-negative")

    fields = extract_sd_header_fields()
    rng = random.Random(config.seed)
    estimator = EstimatorSurrogate(h_m=config.h0_m, v_mps=config.v0_mps)

    h_m = config.h0_m
    v_mps = config.v0_mps
    t_s = 0.0
    row_seq = 0
    policy_cmd = 0.0
    actuator_pos01 = 0.0
    true_apogee_m = h_m
    descent_start_s: float | None = None
    burnout_s: float | None = None
    fault_counts = {kind: 0 for kind in sorted(SUPPORTED_FAULTS)}
    csv_rows: list[dict[str, object]] = []
    samples: list[dict[str, object]] = []
    shim_rows: list[dict[str, str]] = []

    while t_s <= config.max_time_s + 1.0e-9:
        active_kinds = sorted({fault.kind for fault in active_faults(faults, t_s)})
        for kind in active_kinds:
            fault_counts[kind] += 1

        noise_scale = max([1.0] + [fault.value for fault in active_faults(faults, t_s, "noise_burst")])
        baro_valid = not any_fault(faults, t_s, "baro_dropout")
        imu_valid = not any_fault(faults, t_s, "imu_dropout")
        est_valid = not any_fault(faults, t_s, "est_dropout")
        est_freeze = any_fault(faults, t_s, "est_freeze")

        motor_accel_mps2 = config.boost_accel_mps2 if t_s < config.burn_time_s else 0.0
        if t_s >= config.burn_time_s and burnout_s is None:
            burnout_s = t_s

        actuator_bias = fault_value(faults, t_s, "actuator_bias")
        actual_brake01 = clamp01(actuator_pos01 + actuator_bias)
        drag_k_inv_m = policy_drag_k(actual_brake01)
        true_a_mps2 = motor_accel_mps2 - K_G - drag_k_inv_m * v_mps * abs(v_mps)
        specific_force_mps2 = true_a_mps2 + K_G

        baro_alt_m = h_m + fault_value(faults, t_s, "baro_bias")
        baro_alt_m += rng.gauss(0.0, config.baro_noise_m * noise_scale)
        if not baro_valid:
            baro_alt_m = math.nan

        measured_a_vertical_mps2 = true_a_mps2 + fault_value(faults, t_s, "imu_bias")
        measured_a_vertical_mps2 += rng.gauss(0.0, config.imu_noise_mps2 * noise_scale)
        measured_specific_force_mps2 = specific_force_mps2 + fault_value(faults, t_s, "imu_bias")
        measured_specific_force_mps2 += rng.gauss(0.0, config.imu_noise_mps2 * noise_scale)
        if not imu_valid:
            measured_a_vertical_mps2 = math.nan
            measured_specific_force_mps2 = math.nan

        est_seeded, est_updated = update_estimator(
            estimator,
            config=config,
            baro_valid=baro_valid,
            baro_alt_m=baro_alt_m,
            imu_valid=imu_valid,
            measured_a_vertical_mps2=measured_a_vertical_mps2,
            freeze=est_freeze,
        )

        if not est_valid:
            est_updated = False

        if v_mps <= 0.0 and t_s >= config.burn_time_s:
            if descent_start_s is None:
                descent_start_s = t_s
            phase = PHASE_DESCENT
        elif t_s < config.burn_time_s:
            phase = PHASE_BOOST
        elif policy_cmd >= 0.01:
            phase = PHASE_BRAKE
        else:
            phase = PHASE_COAST

        policy_valid, desired_cmd = resolve_desired_policy_command(
            mode=config.mode,
            phase=phase,
            est_valid=est_valid and est_seeded,
            est_h_m=estimator.h_m,
            est_v_mps=estimator.v_mps,
            target_apogee_m=config.target_apogee_m,
            manual_command01=config.manual_command01,
        )
        max_policy_delta = POLICY_SLEW_PER_SEC * config.dt_s
        policy_cmd = clamp01(policy_cmd + max(-max_policy_delta, min(max_policy_delta, desired_cmd - policy_cmd)))

        if not any_fault(faults, t_s, "actuator_stuck"):
            actuator_pos01 = first_order_actuator_step(actuator_pos01, policy_cmd, config)
        actual_brake01 = clamp01(actuator_pos01 + actuator_bias)

        apogee_no_brake_m = predict_apogee_m(estimator.h_m, estimator.v_mps, 0.0)
        apogee_full_brake_m = predict_apogee_m(estimator.h_m, estimator.v_mps, POLICY_MAX_COMMAND01)
        apogee_error_m = apogee_no_brake_m - config.target_apogee_m

        warn_mask = 0
        if not baro_valid:
            warn_mask |= WARN_BARO_INVALID
        if not imu_valid:
            warn_mask |= WARN_IMU_INVALID | WARN_AUX_INVALID | WARN_AUXVZ_INVALID
        if not est_valid:
            warn_mask |= WARN_EST_INVALID

        t_us = int(round(t_s * 1_000_000.0))
        row = base_row(fields, row_seq, t_us)
        bmp_temp_c = 20.0 - 0.0065 * h_m + rng.gauss(0.0, 0.05 * noise_scale)
        bmp_press_hpa = pressure_from_altitude_m(baro_alt_m)
        gyro_x = rng.gauss(0.0, config.gyro_noise_radps * noise_scale)
        gyro_y = rng.gauss(0.0, config.gyro_noise_radps * noise_scale)
        gyro_z = rng.gauss(0.0, config.gyro_noise_radps * noise_scale)
        mag_x = 20.0 + rng.gauss(0.0, config.mag_noise_ut * noise_scale)
        mag_y = 5.0 + rng.gauss(0.0, config.mag_noise_ut * noise_scale)
        mag_z = 43.0 + rng.gauss(0.0, config.mag_noise_ut * noise_scale)
        mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)
        mag_heading = math.degrees(math.atan2(mag_y, mag_x))
        actuator_us = int(round(SERVO_US_IDLE_DEFAULT + actual_brake01 * (SERVO_US_MAX_DEFAULT - SERVO_US_MIN_DEFAULT)))
        phase_descent_latched = descent_start_s is not None and (t_s - descent_start_s) >= 0.300
        target_effective_m = config.target_apogee_m

        row.update(
            {
                "baro_valid": 1 if baro_valid else 0,
                "baro_updated": 1 if baro_valid else 0,
                "baro_seq": row_seq + 1,
                "bmp_T": finite_or_nan(bmp_temp_c if baro_valid else math.nan),
                "bmp_P": finite_or_nan(bmp_press_hpa if baro_valid else math.nan),
                "bmp_alt": finite_or_nan(baro_alt_m),
                "imu_valid": 1 if imu_valid else 0,
                "imu_updated": 1 if imu_valid else 0,
                "imu_seq": row_seq + 1,
                "ax": 0.0 if imu_valid else "nan",
                "ay": 0.0 if imu_valid else "nan",
                "az": finite_or_nan(measured_specific_force_mps2),
                "gx": finite_or_nan(gyro_x if imu_valid else math.nan),
                "gy": finite_or_nan(gyro_y if imu_valid else math.nan),
                "gz": finite_or_nan(gyro_z if imu_valid else math.nan),
                "aux_valid": 1 if imu_valid else 0,
                "aux_updated": 1 if imu_valid else 0,
                "aux_seq": row_seq + 1,
                "lis_ax": 0.0 if imu_valid else "nan",
                "lis_ay": 0.0 if imu_valid else "nan",
                "lis_az": finite_or_nan(measured_specific_force_mps2),
                "mag_valid": 1,
                "mag_updated": 1,
                "mag_seq": row_seq + 1,
                "mag_raw_x": mag_x,
                "mag_raw_y": mag_y,
                "mag_raw_z": mag_z,
                "mag_x_uT": mag_x,
                "mag_y_uT": mag_y,
                "mag_z_uT": mag_z,
                "mag_norm_uT": mag_norm,
                "mag_heading_deg": mag_heading,
                "mag_interference": 0,
                "auxvz_valid": 1 if imu_valid else 0,
                "auxvz_updated": 1 if imu_valid else 0,
                "auxvz_seq": row_seq + 1,
                "a_vertical": finite_or_nan(measured_a_vertical_mps2),
                "est_valid": 1 if est_valid else 0,
                "est_updated": 1 if est_updated else 0,
                "est_seeded": 1 if est_seeded else 0,
                "est_seq": row_seq + 1,
                "est_h": finite_or_nan(estimator.h_m if est_valid else math.nan),
                "est_v": finite_or_nan(estimator.v_mps if est_valid else math.nan),
                "est_a": finite_or_nan(measured_a_vertical_mps2),
                "P00": estimator.p00,
                "P01": estimator.p01,
                "P10": estimator.p10,
                "P11": estimator.p11,
                "phase": phase,
                "actuator_us": actuator_us,
                "phase_launch_latched": 1 if t_s >= 0.060 else 0,
                "phase_burnout_latched": 1 if burnout_s is not None and t_s >= burnout_s + 0.120 else 0,
                "phase_descent_latched": 1 if phase_descent_latched else 0,
                "phase_launch_candidate": 1 if t_s < 0.060 else 0,
                "phase_burnout_candidate": 1 if burnout_s is not None and t_s < burnout_s + 0.120 else 0,
                "phase_descent_candidate": 1 if descent_start_s is not None and not phase_descent_latched else 0,
                "phase_boost_dwell_met": 1 if t_s >= 0.250 else 0,
                "phase_coast_dwell_met": 1 if burnout_s is not None and t_s >= burnout_s + 0.250 else 0,
                "phase_brake_active": 1 if phase == PHASE_BRAKE else 0,
                "phase_descent_confirm_ms": int(round(max(0.0, t_s - descent_start_s) * 1000.0)) if descent_start_s is not None else 0,
                "phase_since_burnout_ms": int(round(max(0.0, t_s - burnout_s) * 1000.0)) if burnout_s is not None else 0xFFFFFFFF,
                "policy_valid": 1 if policy_valid else 0,
                "policy_cmd": policy_cmd,
                "apogee_no_brake": finite_or_nan(apogee_no_brake_m),
                "apogee_full_brake": finite_or_nan(apogee_full_brake_m),
                "target_apogee": target_effective_m,
                "apogee_error": finite_or_nan(apogee_error_m),
                "target_nominal": config.target_apogee_m,
                "target_effective": target_effective_m,
                "uncertainty_margin": 0.0,
                "warn_mask": warn_mask,
            }
        )
        csv_rows.append(row)

        imu_a_norm = abs(measured_specific_force_mps2) if math.isfinite(measured_specific_force_mps2) else math.nan
        serial = "ARM ARMED\nPOLICY 1\n" if row_seq == 0 else ""
        shim_rows.append(
            {
                "t_ms": str(t_us // 1000),
                "serial": serial,
                "est_h": str(row["est_h"]),
                "est_v": str(row["est_v"]),
                "imu_a_norm": str(finite_or_nan(imu_a_norm)),
            }
        )

        sample = {
            "t_s": t_s,
            "phase": phase,
            "true_h_m": h_m,
            "true_v_mps": v_mps,
            "true_a_mps2": true_a_mps2,
            "motor_accel_mps2": motor_accel_mps2,
            "baro_alt_m": finite_or_nan(baro_alt_m),
            "est_h_m": finite_or_nan(estimator.h_m if est_valid else math.nan),
            "est_v_mps": finite_or_nan(estimator.v_mps if est_valid else math.nan),
            "policy_cmd": policy_cmd,
            "actuator_pos01": actuator_pos01,
            "actual_brake01": actual_brake01,
            "actuator_us": actuator_us,
            "warn_mask": warn_mask,
            "active_faults": active_kinds,
        }
        samples.append(sample)

        true_apogee_m = max(true_apogee_m, h_m)
        if descent_start_s is not None and (t_s - descent_start_s) >= config.post_apogee_s:
            break

        next_h_m = h_m + v_mps * config.dt_s + 0.5 * true_a_mps2 * config.dt_s * config.dt_s
        next_v_mps = v_mps + true_a_mps2 * config.dt_s
        h_m = max(0.0, next_h_m)
        v_mps = next_v_mps
        t_s += config.dt_s
        row_seq += 1

    max_est_h_m = max(
        (float(row["est_h"]) for row in csv_rows if row["est_h"] != "nan"),
        default=math.nan,
    )
    summary = {
        "seed": config.seed,
        "mode": config.mode,
        "row_count": len(csv_rows),
        "true_apogee_m": true_apogee_m,
        "max_est_h_m": max_est_h_m,
        "apogee_estimation_error_m": max_est_h_m - true_apogee_m if math.isfinite(max_est_h_m) else math.nan,
        "max_policy_cmd": max(float(row["policy_cmd"]) for row in csv_rows),
        "max_actuator_pos01": max(float(sample["actuator_pos01"]) for sample in samples),
        "max_actual_brake01": max(float(sample["actual_brake01"]) for sample in samples),
        "fault_counts": {kind: count for kind, count in fault_counts.items() if count > 0},
        "faulted_row_count": sum(1 for sample in samples if sample["active_faults"]),
        "controller_model": {
            "body_cda_m2": POLICY_CDA_BODY_M2,
            "brake_cda_m2": POLICY_CDA_BRAKE_M2,
            "mass_kg": POLICY_VEHICLE_MASS_KG,
            "rho_kgpm3": POLICY_RHO_KGPM3,
            "target_apogee_m": config.target_apogee_m,
            "apogee_deadband_m": POLICY_APOGEE_DEADBAND_M,
            "bisection_steps": POLICY_BISECTION_STEPS,
        },
    }

    return {
        "configuration": asdict(config),
        "faults": [asdict(fault) for fault in faults],
        "summary": summary,
        "fields": fields,
        "csv_rows": csv_rows,
        "shim_rows": shim_rows,
        "samples": samples,
    }


def write_current_schema_csv(path: Path, result: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=result["fields"], extrasaction="ignore")
        writer.writeheader()
        writer.writerows(result["csv_rows"])


def write_shim_csv(path: Path, result: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["t_ms", "serial", "est_h", "est_v", "imu_a_norm"])
        writer.writeheader()
        writer.writerows(result["shim_rows"])


def write_json(path: Path, result: dict, *, include_samples: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = dict(result)
    if not include_samples:
        payload.pop("samples", None)
        payload.pop("csv_rows", None)
        payload.pop("shim_rows", None)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run a deterministic 1D plant simulation with sensor noise, actuator dynamics, and fault injection."
    )
    parser.add_argument("--mode", choices=("closed", "open", "manual", "policy"), default="policy")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--h0-m", type=float, default=0.0)
    parser.add_argument("--v0-mps", type=float, default=0.0)
    parser.add_argument("--burn-time-s", type=float, default=2.0)
    parser.add_argument("--boost-accel-mps2", type=float, default=170.0)
    parser.add_argument("--target-apogee-m", type=float, default=POLICY_TARGET_APOGEE_M)
    parser.add_argument("--manual-command01", type=float, default=0.0)
    parser.add_argument("--dt-s", type=float, default=0.02)
    parser.add_argument("--max-time-s", type=float, default=30.0)
    parser.add_argument("--post-apogee-s", type=float, default=0.50)
    parser.add_argument("--baro-noise-m", type=float, default=0.8)
    parser.add_argument("--imu-noise-mps2", type=float, default=0.35)
    parser.add_argument("--gyro-noise-radps", type=float, default=0.01)
    parser.add_argument("--mag-noise-ut", type=float, default=0.4)
    parser.add_argument("--estimator-baro-gain", type=float, default=0.12)
    parser.add_argument("--estimator-velocity-gain", type=float, default=0.02)
    parser.add_argument("--actuator-tau-s", type=float, default=0.20)
    parser.add_argument("--actuator-rate-per-s", type=float, default=3.0)
    parser.add_argument(
        "--fault",
        action="append",
        default=[],
        help="Fault spec kind:start_s:end_s[:value]. Supported kinds include baro_dropout, imu_dropout, est_freeze, actuator_stuck.",
    )
    parser.add_argument("--csv-out", type=Path)
    parser.add_argument("--shim-csv-out", type=Path)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--json-samples", action="store_true", help="Include per-row samples and CSV rows in JSON output.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    faults = [parse_fault_spec(item) for item in args.fault]
    config = PlantConfig(
        seed=args.seed,
        mode=args.mode,
        h0_m=args.h0_m,
        v0_mps=args.v0_mps,
        burn_time_s=args.burn_time_s,
        boost_accel_mps2=args.boost_accel_mps2,
        target_apogee_m=args.target_apogee_m,
        manual_command01=args.manual_command01,
        dt_s=args.dt_s,
        max_time_s=args.max_time_s,
        post_apogee_s=args.post_apogee_s,
        baro_noise_m=args.baro_noise_m,
        imu_noise_mps2=args.imu_noise_mps2,
        gyro_noise_radps=args.gyro_noise_radps,
        mag_noise_ut=args.mag_noise_ut,
        estimator_baro_gain=args.estimator_baro_gain,
        estimator_velocity_gain=args.estimator_velocity_gain,
        actuator_tau_s=args.actuator_tau_s,
        actuator_rate_per_s=args.actuator_rate_per_s,
    )
    result = simulate_plant(config, faults)

    if args.csv_out is not None:
        write_current_schema_csv(args.csv_out, result)
    if args.shim_csv_out is not None:
        write_shim_csv(args.shim_csv_out, result)
    if args.json_out is not None:
        write_json(args.json_out, result, include_samples=args.json_samples)

    summary = result["summary"]
    print(f"mode={summary['mode']}")
    print(f"seed={summary['seed']}")
    print(f"rows={summary['row_count']}")
    print(f"true_apogee_m={summary['true_apogee_m']:.3f}")
    print(f"max_est_h_m={summary['max_est_h_m']:.3f}")
    print(f"max_policy_cmd={summary['max_policy_cmd']:.3f}")
    print(f"max_actual_brake01={summary['max_actual_brake01']:.3f}")
    if summary["fault_counts"]:
        print(f"fault_counts={summary['fault_counts']}")
    else:
        print("fault_counts={}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

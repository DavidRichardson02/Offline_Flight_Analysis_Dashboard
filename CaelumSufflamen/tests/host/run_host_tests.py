from __future__ import annotations

import csv
import io
import importlib.util
import math
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def read_first_existing(*relative_paths: str) -> str:
    for relative_path in relative_paths:
        candidate = ROOT / relative_path
        if candidate.exists():
            return candidate.read_text(encoding="utf-8")
    joined = ", ".join(relative_paths)
    raise AssertionError(f"Could not locate any expected source file: {joined}")


def extract_constant(text: str, name: str) -> str:
    static_pattern = rf"static const [A-Za-z0-9_:\*]+ {name}\s*=\s*([^;\r\n]+)"
    match = re.search(static_pattern, text)
    if match:
        return match.group(1).strip()

    define_pattern = rf"#define {name}\s+([^\r\n]+)"
    match = re.search(define_pattern, text)
    if match:
        return match.group(1).strip()

    raise AssertionError(f"Could not find constant {name}")


def parse_numeric_literal(expr: str) -> float:
    cleaned = expr.replace("UL", "").replace("U", "").replace("f", "").replace("F", "")
    return float(cleaned)


def parse_int_constant(text: str, name: str) -> int:
    return int(round(parse_numeric_literal(extract_constant(text, name))))


def parse_float_constant(text: str, name: str) -> float:
    return parse_numeric_literal(extract_constant(text, name))


CONFIG_H = read_first_existing("config.h", "utils/config.h")
FLIGHT_PHASE_CPP = read_first_existing("flight_phase.cpp", "src/flight_phase.cpp")
COMMANDS_CPP = read_first_existing("commands.cpp", "utils/commands.cpp")
TELEMETRY_CPP = read_first_existing("telemetry.cpp", "utils/telemetry.cpp")
ACTUATOR_CPP = read_first_existing("actuator.cpp", "src/actuator.cpp")
SD_LOGGER_CPP = read_first_existing("sd_logger.cpp", "utils/sd_logger.cpp")
DATA_TYPES_H = read_first_existing("data_types.h", "include/data_types.h")
SKETCH_INO = read_text("CaelumSufflamen.ino")
README_MD = read_first_existing("README.md", "tests/README.md")
BUILDING_MD = read_first_existing("BUILDING.md", "Documentation/BUILDING.md")
BUILD_WRAPPER_PS1 = read_text("tools/teensy41_arduino_cli.ps1")
AERO_LOG_SCHEMA_CSV = read_text("validation/current_flight_log_schema.csv")
AERO_FIT_SCRIPT = ROOT / "tests" / "host" / "policy_aero_empirical_fit.py"
AERO_REPORT_SCRIPT = ROOT / "tests" / "host" / "policy_aero_identification_report.py"
AERO_OBSERVABILITY_SCRIPT = ROOT / "tests" / "host" / "aero_observability_map.py"
LANDING_FOOTPRINT_SCRIPT = ROOT / "tests" / "host" / "wind_relative_landing_footprint.py"
HUD_PAGES_SCRIPT = ROOT / "tests" / "host" / "onboard_science_hud_pages.py"
COAST_SIM_SCRIPT = ROOT / "tests" / "host" / "policy_coast_sim.py"
PLANT_SIM_SCRIPT = ROOT / "tests" / "host" / "plant_simulation.py"
APOGEE_EVIDENCE_SCRIPT = ROOT / "tests" / "host" / "apogee_evidence_view.py"
APOGEE_RESIDUAL_SCRIPT = ROOT / "tests" / "host" / "apogee_prediction_residual_timeline.py"
PROVENANCE_EVIDENCE_SCRIPT = ROOT / "tests" / "host" / "provenance_evidence_view.py"
EKF_DASHBOARD_SCRIPT = ROOT / "tests" / "host" / "ekf_innovation_covariance_dashboard.py"
TEMPORAL_OSCILLOSCOPE_SCRIPT = ROOT / "tests" / "host" / "temporal_freshness_latency_oscilloscope.py"
ENERGY_PHASE_SCRIPT = ROOT / "tests" / "host" / "energy_phase_view.py"
ESTIMATOR_POLICY_PHASE_SPACE_SCRIPT = ROOT / "tests" / "host" / "estimator_policy_phase_space_view.py"
PHASE_TIMELINE_SCRIPT = ROOT / "tests" / "host" / "phase_timeline_view.py"
HEALTH_DASHBOARD_SCRIPT = ROOT / "tests" / "host" / "health_dashboard_view.py"
ORIENTATION_VECTOR_SCRIPT = ROOT / "tests" / "host" / "orientation_vector_view.py"
MAGNETIC_FIELD_SCRIPT = ROOT / "tests" / "host" / "magnetic_field_quality_view.py"
GRAVITY_STABILITY_SCRIPT = ROOT / "tests" / "host" / "gravity_norm_stability_view.py"
SENSOR_FRAME_SCRIPT = ROOT / "tests" / "host" / "sensor_frame_alignment_verifier.py"
READINESS_GATE_SCRIPT = ROOT / "tests" / "host" / "readiness_gate_view.py"
HEADING_DEMO_SCRIPT = ROOT / "tests" / "host" / "tilt_compensated_heading_view.py"
HEADING_VALIDATOR_SCRIPT = ROOT / "tests" / "host" / "heading_sign_calibration_validator.py"
REPLAY_VALIDATOR_SCRIPT = ROOT / "tests" / "host" / "replay_policy_validation.py"
HELDOUT_REPLAY_SCRIPT = ROOT / "tests" / "host" / "heldout_replay_validation.py"
FIRMWARE_LOOP_SHIM_SCRIPT = ROOT / "tests" / "host" / "firmware_in_loop_shim.py"
FLIGHT_DATA_AUDIT_SCRIPT = ROOT / "tests" / "host" / "audit_previous_year_flight_data.py"


def previous_year_data_dir() -> Path:
    for relative_path in ("validation/flight data", "flight data"):
        candidate = ROOT / relative_path
        if candidate.exists():
            return candidate
    return ROOT / "validation" / "flight data"


PREVIOUS_YEAR_DATA_DIR = previous_year_data_dir()


K_G = parse_float_constant(CONFIG_H, "kG")
POLICY_TARGET_APOGEE_M = parse_float_constant(CONFIG_H, "POLICY_TARGET_APOGEE_M")
POLICY_MIN_ALT_M = parse_float_constant(CONFIG_H, "POLICY_MIN_ALT_M")
POLICY_MIN_VZ_MPS = parse_float_constant(CONFIG_H, "POLICY_MIN_VZ_MPS")
POLICY_APOGEE_DEADBAND_M = parse_float_constant(CONFIG_H, "POLICY_APOGEE_DEADBAND_M")
POLICY_VEHICLE_MASS_KG = parse_float_constant(CONFIG_H, "POLICY_VEHICLE_MASS_KG")
POLICY_RHO_KGPM3 = parse_float_constant(CONFIG_H, "POLICY_RHO_KGPM3")
POLICY_CDA_BODY_M2 = parse_float_constant(CONFIG_H, "POLICY_CDA_BODY_M2")
POLICY_CDA_BRAKE_M2 = parse_float_constant(CONFIG_H, "POLICY_CDA_BRAKE_M2")
POLICY_MAX_COMMAND01 = parse_float_constant(CONFIG_H, "POLICY_MAX_COMMAND01")
POLICY_SLEW_PER_SEC = parse_float_constant(CONFIG_H, "POLICY_SLEW_PER_SEC")
POLICY_MAX_EST_AGE_MS = parse_int_constant(CONFIG_H, "POLICY_MAX_EST_AGE_MS")
POLICY_BISECTION_STEPS = parse_int_constant(CONFIG_H, "POLICY_BISECTION_STEPS")
POLICY_SIGMA_MARGIN_N = parse_float_constant(CONFIG_H, "POLICY_SIGMA_MARGIN_N")
POLICY_MAX_UNCERTAINTY_MARGIN_M = parse_float_constant(CONFIG_H, "POLICY_MAX_UNCERTAINTY_MARGIN_M")
CMD_BUF_N = parse_int_constant(CONFIG_H, "CMD_BUF_N")

FLIGHT_PHASE_BOOST_ACCEL_NORM_MPS2 = parse_float_constant(CONFIG_H, "FLIGHT_PHASE_BOOST_ACCEL_NORM_MPS2")
FLIGHT_PHASE_BOOST_MIN_ALT_M = parse_float_constant(CONFIG_H, "FLIGHT_PHASE_BOOST_MIN_ALT_M")
FLIGHT_PHASE_DESCENT_VZ_MPS = parse_float_constant(CONFIG_H, "FLIGHT_PHASE_DESCENT_VZ_MPS")

FLIGHT_PHASE_LAUNCH_MIN_VZ_MPS = parse_float_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_LAUNCH_MIN_VZ_MPS")
FLIGHT_PHASE_BURNOUT_ACCEL_NORM_MPS2 = parse_float_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_BURNOUT_ACCEL_NORM_MPS2")
FLIGHT_PHASE_COAST_MIN_ALT_M = parse_float_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_COAST_MIN_ALT_M")
FLIGHT_PHASE_COAST_MIN_VZ_MPS = parse_float_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_COAST_MIN_VZ_MPS")
FLIGHT_PHASE_BRAKE_MIN_COMMAND01 = parse_float_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_BRAKE_MIN_COMMAND01")
FLIGHT_PHASE_LAUNCH_CONFIRM_MS = parse_int_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_LAUNCH_CONFIRM_MS")
FLIGHT_PHASE_BURNOUT_CONFIRM_MS = parse_int_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_BURNOUT_CONFIRM_MS")
FLIGHT_PHASE_DESCENT_CONFIRM_MS = parse_int_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_DESCENT_CONFIRM_MS")
FLIGHT_PHASE_MIN_BOOST_DWELL_MS = parse_int_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_MIN_BOOST_DWELL_MS")
FLIGHT_PHASE_MIN_COAST_DWELL_MS = parse_int_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_MIN_COAST_DWELL_MS")


DISARMED = 0
SAFE = 1
ARMED = 2

IDLE = 0
BOOST = 1
COAST = 2
BRAKE = 3
DESCENT = 4


def clamp01(x: float) -> float:
    if not math.isfinite(x):
        return 0.0
    return min(1.0, max(0.0, x))


def policy_drag_k(command01: float) -> float:
    u = clamp01(command01)
    cda = POLICY_CDA_BODY_M2 + u * POLICY_CDA_BRAKE_M2
    if POLICY_RHO_KGPM3 <= 0.0 or POLICY_VEHICLE_MASS_KG <= 0.0 or cda < 0.0:
        return 0.0
    return (POLICY_RHO_KGPM3 * cda) / (2.0 * POLICY_VEHICLE_MASS_KG)


def policy_predict_apogee_m(h_m: float, v_mps: float, command01: float) -> float:
    if not math.isfinite(h_m) or not math.isfinite(v_mps):
        return math.nan
    if v_mps <= 0.0:
        return h_m
    k = policy_drag_k(command01)
    v2 = v_mps * v_mps
    if not math.isfinite(k) or k < 1.0e-7:
        return h_m + v2 / (2.0 * K_G)
    argument = 1.0 + (k * v2) / K_G
    if not math.isfinite(argument) or argument <= 0.0:
        return math.nan
    return h_m + math.log(argument) / (2.0 * k)


def policy_solve_command01(h_m: float, v_mps: float, target_apogee_m: float) -> float:
    if not math.isfinite(h_m) or not math.isfinite(v_mps) or not math.isfinite(target_apogee_m):
        return 0.0
    if v_mps <= 0.0:
        return 0.0

    u_max = clamp01(POLICY_MAX_COMMAND01)
    apogee_u0 = policy_predict_apogee_m(h_m, v_mps, 0.0)
    if not math.isfinite(apogee_u0):
        return 0.0
    if apogee_u0 <= target_apogee_m + POLICY_APOGEE_DEADBAND_M:
        return 0.0

    apogee_umax = policy_predict_apogee_m(h_m, v_mps, u_max)
    if not math.isfinite(apogee_umax):
        return 0.0
    if apogee_umax > target_apogee_m:
        return u_max

    lo = 0.0
    hi = u_max
    for _ in range(POLICY_BISECTION_STEPS):
        mid = 0.5 * (lo + hi)
        apogee_mid = policy_predict_apogee_m(h_m, v_mps, mid)
        if not math.isfinite(apogee_mid):
            return 0.0
        if apogee_mid > target_apogee_m:
            lo = mid
        else:
            hi = mid
    return clamp01(0.5 * (lo + hi))


def policy_uncertainty_margin_m(p00: float) -> float:
    if not math.isfinite(p00) or p00 < 0.0:
        return 0.0
    margin = POLICY_SIGMA_MARGIN_N * math.sqrt(p00)
    if not math.isfinite(margin) or margin < 0.0:
        return 0.0
    return min(margin, POLICY_MAX_UNCERTAINTY_MARGIN_M)


def load_module(module_name: str, path: Path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise AssertionError(f"Could not import module from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def required_velocity_for_apogee_delta(delta_h_m: float, command01: float) -> float:
    cda_m2 = POLICY_CDA_BODY_M2 + command01 * POLICY_CDA_BRAKE_M2
    k_inv_m = (POLICY_RHO_KGPM3 * cda_m2) / (2.0 * POLICY_VEHICLE_MASS_KG)
    if k_inv_m < 1.0e-9:
        return math.sqrt(2.0 * K_G * delta_h_m)
    return math.sqrt((K_G / k_inv_m) * (math.exp(2.0 * k_inv_m * delta_h_m) - 1.0))


def write_analytic_aero_fixture(
    log_path: Path,
    *,
    actual_apogee_m: float,
    phase_rows: list[tuple[float, float, int]] | None = None,
) -> None:
    rows = phase_rows or [
        (50.0, 0.00, COAST),
        (90.0, 0.00, COAST),
        (130.0, 0.25, BRAKE),
        (170.0, 0.50, BRAKE),
        (210.0, 0.75, BRAKE),
        (250.0, 1.00, BRAKE),
    ]

    with log_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["t_us", "phase", "est_h", "est_v", "policy_cmd", "policy_valid"],
        )
        writer.writeheader()

        t_us = 0
        for h_m, command01, phase in rows:
            delta_h_m = actual_apogee_m - h_m
            writer.writerow(
                {
                    "t_us": t_us,
                    "phase": phase,
                    "est_h": h_m,
                    "est_v": required_velocity_for_apogee_delta(delta_h_m, command01),
                    "policy_cmd": command01,
                    "policy_valid": 1 if command01 > 0.0 else 0,
                }
            )
            t_us += 20000

        writer.writerow(
            {
                "t_us": t_us,
                "phase": DESCENT,
                "est_h": actual_apogee_m,
                "est_v": -5.0,
                "policy_cmd": 0.0,
                "policy_valid": 0,
            }
        )


class PolicyRuntime:
    def __init__(self) -> None:
        self.prev_command01 = 0.0
        self.prev_ms = 0

    def reset(self, now_ms: int) -> None:
        self.prev_command01 = 0.0
        self.prev_ms = now_ms

    def apply_slew_limit(self, desired_command01: float, dt_s: float) -> float:
        desired = clamp01(desired_command01)
        if not math.isfinite(dt_s) or dt_s < 0.0:
            return self.prev_command01
        max_step = POLICY_SLEW_PER_SEC * dt_s
        limited = min(desired, self.prev_command01 + max_step)
        limited = max(limited, self.prev_command01 - max_step)
        limited = clamp01(limited)
        self.prev_command01 = limited
        return limited

    def compute(
        self,
        *,
        policy_runtime_enabled: bool,
        arm_state: int,
        software_arm_token: bool,
        phase: int,
        est_valid: bool,
        est_h_m: float,
        est_v_mps: float,
        est_p00: float,
        est_t_ms: int,
        now_ms: int,
    ) -> tuple[bool, float]:
        if not policy_runtime_enabled:
            self.reset(now_ms)
            return False, 0.0
        if arm_state != ARMED or not software_arm_token:
            self.reset(now_ms)
            return False, 0.0
        if phase not in (COAST, BRAKE):
            self.reset(now_ms)
            return False, 0.0
        if not est_valid or not math.isfinite(est_h_m) or not math.isfinite(est_v_mps):
            self.reset(now_ms)
            return False, 0.0
        if (now_ms - est_t_ms) > POLICY_MAX_EST_AGE_MS:
            self.reset(now_ms)
            return False, 0.0
        if est_h_m < POLICY_MIN_ALT_M or est_v_mps < POLICY_MIN_VZ_MPS:
            self.reset(now_ms)
            return False, 0.0

        uncertainty_margin = policy_uncertainty_margin_m(est_p00)
        target_eff_m = max(0.0, POLICY_TARGET_APOGEE_M - uncertainty_margin)

        dt_s = (now_ms - self.prev_ms) * 0.001
        self.prev_ms = now_ms
        if not math.isfinite(dt_s) or dt_s < 0.0 or dt_s > 1.0:
            dt_s = 0.0

        desired = policy_solve_command01(est_h_m, est_v_mps, target_eff_m)
        command01 = self.apply_slew_limit(desired, dt_s)
        return command01 > 0.0, command01


@dataclass
class PhaseInput:
    now_ms: int
    h_m: float
    v_mps: float
    a_norm: float
    policy_valid: bool = False
    policy_command01: float = 0.0
    est_valid: bool = True
    imu_valid: bool = True


class FlightPhaseDetector:
    def __init__(self) -> None:
        self.phase = IDLE
        self.launch_latched = False
        self.burnout_latched = False
        self.descent_latched = False
        self.launch_latch_ms = 0
        self.burnout_latch_ms = 0
        self.launch_candidate_ms = 0
        self.burnout_candidate_ms = 0
        self.descent_candidate_ms = 0

    @staticmethod
    def elapsed(now_ms: int, then_ms: int) -> int:
        return now_ms - then_ms

    def condition_confirmed(self, condition: bool, now_ms: int, dwell_ms: int, candidate_ms_name: str) -> bool:
        candidate_ms = getattr(self, candidate_ms_name)
        if not condition:
            setattr(self, candidate_ms_name, 0)
            return False
        if candidate_ms == 0:
            candidate_ms = now_ms
            setattr(self, candidate_ms_name, candidate_ms)
        return self.elapsed(now_ms, candidate_ms) >= dwell_ms

    def update(self, sample: PhaseInput) -> int:
        if not sample.est_valid or not sample.imu_valid:
            if not self.launch_latched:
                self.launch_candidate_ms = 0
                self.phase = IDLE
            elif not self.burnout_latched:
                self.burnout_candidate_ms = 0
                self.descent_candidate_ms = 0
            elif not self.descent_latched:
                self.descent_candidate_ms = 0
            return self.phase

        h_m = sample.h_m
        v_mps = sample.v_mps
        a_norm = sample.a_norm
        if not all(math.isfinite(x) for x in (h_m, v_mps, a_norm)):
            if not self.launch_latched:
                self.launch_candidate_ms = 0
                self.phase = IDLE
            elif not self.burnout_latched:
                self.burnout_candidate_ms = 0
                self.descent_candidate_ms = 0
            elif not self.descent_latched:
                self.descent_candidate_ms = 0
            return self.phase

        launch_by_accel = (
            a_norm >= FLIGHT_PHASE_BOOST_ACCEL_NORM_MPS2 and
            h_m >= FLIGHT_PHASE_BOOST_MIN_ALT_M
        )
        launch_by_motion = (
            h_m >= FLIGHT_PHASE_BOOST_MIN_ALT_M and
            v_mps >= FLIGHT_PHASE_LAUNCH_MIN_VZ_MPS
        )

        if not self.launch_latched:
            if self.condition_confirmed(
                launch_by_accel or launch_by_motion,
                sample.now_ms,
                FLIGHT_PHASE_LAUNCH_CONFIRM_MS,
                "launch_candidate_ms",
            ):
                self.launch_latched = True
                self.launch_latch_ms = sample.now_ms
                self.phase = BOOST
            else:
                self.phase = IDLE
            return self.phase

        if not self.burnout_latched:
            boost_dwell_met = self.elapsed(sample.now_ms, self.launch_latch_ms) >= FLIGHT_PHASE_MIN_BOOST_DWELL_MS
            pre_burnout_descent_candidate = (
                boost_dwell_met and
                h_m >= FLIGHT_PHASE_COAST_MIN_ALT_M and
                v_mps <= FLIGHT_PHASE_DESCENT_VZ_MPS
            )
            if self.condition_confirmed(
                pre_burnout_descent_candidate,
                sample.now_ms,
                FLIGHT_PHASE_DESCENT_CONFIRM_MS,
                "descent_candidate_ms",
            ):
                self.burnout_latched = True
                self.descent_latched = True
                self.burnout_latch_ms = sample.now_ms
                self.phase = DESCENT
                return self.phase

            burnout_candidate = (
                boost_dwell_met and
                a_norm <= FLIGHT_PHASE_BURNOUT_ACCEL_NORM_MPS2 and
                h_m >= FLIGHT_PHASE_COAST_MIN_ALT_M and
                v_mps >= FLIGHT_PHASE_COAST_MIN_VZ_MPS
            )
            if self.condition_confirmed(
                burnout_candidate,
                sample.now_ms,
                FLIGHT_PHASE_BURNOUT_CONFIRM_MS,
                "burnout_candidate_ms",
            ):
                self.burnout_latched = True
                self.burnout_latch_ms = sample.now_ms
                self.phase = COAST
            else:
                self.phase = BOOST
            return self.phase

        if not self.descent_latched:
            coast_dwell_met = self.elapsed(sample.now_ms, self.burnout_latch_ms) >= FLIGHT_PHASE_MIN_COAST_DWELL_MS
            descent_candidate = (
                coast_dwell_met and
                h_m >= FLIGHT_PHASE_COAST_MIN_ALT_M and
                v_mps <= FLIGHT_PHASE_DESCENT_VZ_MPS
            )
            if self.condition_confirmed(
                descent_candidate,
                sample.now_ms,
                FLIGHT_PHASE_DESCENT_CONFIRM_MS,
                "descent_candidate_ms",
            ):
                self.descent_latched = True
                self.phase = DESCENT
                return self.phase

        if self.descent_latched:
            self.phase = DESCENT
            return self.phase

        brake_active = sample.policy_valid and sample.policy_command01 >= FLIGHT_PHASE_BRAKE_MIN_COMMAND01
        self.phase = BRAKE if brake_active else COAST
        return self.phase


class CommandParserModel:
    def __init__(self, max_len: int) -> None:
        self.max_len = max_len
        self.buf = []
        self.discarding = False
        self.executed = []
        self.errors = []

    def feed(self, text: str) -> None:
        for ch in text:
            if ch in "\r\n":
                if self.discarding:
                    self.discarding = False
                    self.buf.clear()
                    continue
                if self.buf:
                    self.executed.append("".join(self.buf))
                    self.buf.clear()
                continue

            if self.discarding:
                continue

            if len(self.buf) + 1 < self.max_len:
                self.buf.append(ch)
            else:
                self.buf.clear()
                self.discarding = True
                self.errors.append("ERR,CMD_TOO_LONG")


def test_policy_valid_command_in_coast() -> None:
    runtime = PolicyRuntime()
    runtime.reset(0)
    valid, command01 = runtime.compute(
        policy_runtime_enabled=True,
        arm_state=ARMED,
        software_arm_token=True,
        phase=COAST,
        est_valid=True,
        est_h_m=2400.0,
        est_v_mps=250.0,
        est_p00=1.0,
        est_t_ms=100,
        now_ms=200,
    )
    assert valid, "Expected a valid policy command in COAST when armed and enabled"
    assert command01 > 0.0, "Expected a non-zero command in overshoot conditions"


def test_policy_stays_invalid_when_disarmed() -> None:
    runtime = PolicyRuntime()
    runtime.reset(0)
    valid, command01 = runtime.compute(
        policy_runtime_enabled=True,
        arm_state=SAFE,
        software_arm_token=False,
        phase=COAST,
        est_valid=True,
        est_h_m=120.0,
        est_v_mps=80.0,
        est_p00=1.0,
        est_t_ms=100,
        now_ms=200,
    )
    assert not valid, "Disarmed or un-tokened state must not produce a valid policy command"
    assert command01 == 0.0


def test_phase_detector_reaches_coast_and_descent() -> None:
    detector = FlightPhaseDetector()
    assert detector.update(PhaseInput(0, 0.0, 0.0, 9.8)) == IDLE
    assert detector.update(PhaseInput(70, 3.0, 8.0, 30.0)) == IDLE
    assert detector.update(PhaseInput(140, 6.0, 20.0, 30.0)) == BOOST
    assert detector.update(PhaseInput(390, 40.0, 35.0, 12.0)) == BOOST
    assert detector.update(PhaseInput(520, 80.0, 30.0, 12.0)) == COAST
    assert detector.update(PhaseInput(770, 120.0, 0.0, 9.8)) == COAST
    assert detector.update(PhaseInput(1085, 118.0, -5.0, 9.8)) == DESCENT


def test_command_overflow_discard_until_newline() -> None:
    parser = CommandParserModel(CMD_BUF_N)
    parser.feed(("X" * CMD_BUF_N) + "STATUS\n")
    assert parser.errors == ["ERR,CMD_TOO_LONG"], "Expected one overflow error"
    assert parser.executed == [], "Overflow line suffix must not execute as a command"
    parser.feed("STATUS\n")
    assert parser.executed == ["STATUS"], "Parser must recover cleanly after newline"


def test_source_integrations_present() -> None:
    assert "writeMicroseconds" in ACTUATOR_CPP, "Actuator should write microseconds directly"
    assert "telemetry_warn_mask(state)" in SD_LOGGER_CPP, "SD logger should share the telemetry warning mask helper"
    assert "ARM <DISARMED|SAFE|ARMED>|POLICY 0|1" in COMMANDS_CPP, "Command help text should expose the new control path"
    assert "PLOT <OFF|OVERVIEW|IMU|APOGEE|ESTIMATOR|PHASE|HEALTH|ACTUATOR|ORIENT|SAFETY|PROVENANCE|ENERGY|HUD>" in COMMANDS_CPP, "Command help should expose visual telemetry modes"
    assert "telemetry_emit_plot" in TELEMETRY_CPP, "Telemetry should implement the low-rate plot stream"
    assert "P00_m2,P11_m2,sigma_h_m" in TELEMETRY_CPP, "Apogee plot stream should include estimator uncertainty evidence"
    assert "P00_m2,P11_m2,sigma_h_m,sigma_v_mps" in TELEMETRY_CPP, "Overview plot stream should include covariance evidence"
    assert "safety_runtime_ok,safety_allows_actuation" in TELEMETRY_CPP, "Safety plot stream should expose final actuation gates"
    assert "baro_v_proxy_mps,est_v_mps,velocity_residual_mps" in TELEMETRY_CPP, "Provenance plot stream should expose raw-vs-filtered velocity evidence"
    assert "specific_energy_m,kinetic_height_m" in TELEMETRY_CPP, "Energy plot stream should expose height-equivalent energy state"
    assert "readiness_flags" in TELEMETRY_CPP, "HUD plot stream should expose compact page-readiness evidence"
    assert "PLOT,HUD" in TELEMETRY_CPP, "HUD plot stream should emit fixed-schema HUD rows"
    assert "SdFaultReason" in DATA_TYPES_H, "SD logger state should preserve explicit fault reasons"
    assert "BOOT,SD_REASON" in SD_LOGGER_CPP, "SD boot diagnostics should expose the init-failure reason"
    assert "sd_fault_reason=" in TELEMETRY_CPP, "STATUS/DIAG should expose the latched SD fault reason"
    assert "cfg_bmp5xx_enabled=" in TELEMETRY_CPP, "STATUS should expose whether barometer support is compiled"
    assert "cfg_bmi088_enabled=" in TELEMETRY_CPP, "STATUS should expose whether BMI088 support is compiled"
    assert "plot_valid_mask=" in TELEMETRY_CPP, "STATUS/DIAG should expose plot validity bits for recapture readiness"
    for mode in ("PLOT_MODE_ESTIMATOR", "PLOT_MODE_PHASE", "PLOT_MODE_HEALTH", "PLOT_MODE_ACTUATOR", "PLOT_MODE_ORIENT", "PLOT_MODE_SAFETY", "PLOT_MODE_PROVENANCE", "PLOT_MODE_ENERGY", "PLOT_MODE_HUD"):
        assert mode in DATA_TYPES_H, f"PlotMode enum should include {mode}"
        assert mode in COMMANDS_CPP, f"Command parser should accept {mode}"
        assert mode in TELEMETRY_CPP, f"Telemetry should emit {mode}"
    for header in ("PLOT_HDR,ESTIMATOR", "PLOT_HDR,PHASE", "PLOT_HDR,HEALTH", "PLOT_HDR,ACTUATOR", "PLOT_HDR,ORIENT", "PLOT_HDR,SAFETY", "PLOT_HDR,PROVENANCE", "PLOT_HDR,ENERGY", "PLOT_HDR,HUD"):
        assert header in TELEMETRY_CPP, f"Missing visual telemetry header {header}"
    assert "PLOT_PERIOD_MS" in CONFIG_H, "Visual telemetry cadence should be a named config constant"
    assert "LIS3DH_ENABLED" in CONFIG_H, "Config should expose the LIS3DH auxiliary accelerometer backend"
    assert "#define PMOD_CMPS2_ENABLED 1" in CONFIG_H, "Bench profile should enable Pmod CMPS2 by default"
    sensors_cpp = read_text("sensors.cpp")
    assert "Adafruit_LIS3DH" in sensors_cpp, "Sensors backend should include LIS3DH acquisition support"
    assert "lis3dh_wire1" in sensors_cpp, "LIS3DH backend should support the shared Wire1 bench bus"
    assert "lis_i2c_bus" in TELEMETRY_CPP, "STATUS should report which I2C bus produced LIS3DH telemetry"
    assert "state.plot_mode != PLOT_MODE_OFF" in SKETCH_INO, "Runtime loop should schedule plot rows only when enabled"
    assert "Runtime Control Path" in README_MD, "README should document the runtime arming/policy flow"
    assert "Visual Telemetry Stream" in README_MD, "README should document plot telemetry semantics"
    assert "teensy:avr:teensy41" in BUILDING_MD, "BUILDING.md should pin the intended Teensy FQBN"
    assert "staged_sketch" in BUILD_WRAPPER_PS1, "Build wrapper should stage a normalized Arduino sketch"
    assert "StageOnly" in BUILD_WRAPPER_PS1, "Build wrapper should support deterministic staging without compile"
    assert "FlightStateProfile" in BUILD_WRAPPER_PS1, "Build wrapper should expose a barometer+BMI088 flight-state profile"
    assert "build.flags.defs" in BUILD_WRAPPER_PS1, "Build wrapper should pass validated Teensy preprocessor defines to Arduino CLI"
    assert "Define NAME=VALUE" in BUILDING_MD, "BUILDING.md should document reviewed compile-time overrides"
    assert "flat sketch root" in BUILD_WRAPPER_PS1, "Build wrapper should support the current flat source layout"
    assert "staged_sketch.ino" in BUILDING_MD, "BUILDING.md should document the staged Arduino sketch filename"
    assert "previous_year_flight_data_audit.json" in CONFIG_H, "Config should reference the real-data audit result"


def test_hud_plot_schema_and_golden_row_contract() -> None:
    expected_fields = [
        "t_ms",
        "page",
        "page_count",
        "phase",
        "valid_mask",
        "warn_mask",
        "est_h_m",
        "est_v_mps",
        "est_a_mps2",
        "sigma_h_m",
        "specific_energy_m",
        "target_effective_m",
        "target_margin_m",
        "apogee_error_m",
        "brake_authority_m",
        "cmd01",
        "actuator_us",
        "roll_deg",
        "pitch_deg",
        "heading_deg",
        "gravity_residual_mps2",
        "mag_norm_uT",
        "mag_interference",
        "baro_age_ms",
        "imu_age_ms",
        "aux_age_ms",
        "mag_age_ms",
        "est_age_ms",
        "safety_runtime_ok",
        "safety_allows_actuation",
        "sd_card_ok",
        "sd_file_open",
        "sd_runtime_failed",
        "readiness_flags",
    ]

    marker = 'F("PLOT_HDR,HUD,'
    start = TELEMETRY_CPP.index(marker)
    end = TELEMETRY_CPP.index("));", start)
    header_block = TELEMETRY_CPP[start:end]
    header_text = "".join(re.findall(r'"([^"]*)"', header_block))
    assert header_text == "PLOT_HDR,HUD," + ",".join(expected_fields)

    golden_row = (
        "PLOT,HUD,1234,2,4,3,511,0,"
        "120.5,31.25,9.81,1.5,171.0,"
        "900.0,779.5,42.0,180.0,0.35,1350,"
        "1.25,-2.5,270.0,0.02,48.0,0,"
        "10,11,12,13,14,1,1,1,1,0,8191"
    )
    fieldnames = ["record", "mode"] + expected_fields
    assert len(golden_row.split(",")) == len(fieldnames)

    reader = csv.DictReader(
        io.StringIO(",".join(fieldnames) + "\n" + golden_row)
    )
    row = next(reader)

    assert row["record"] == "PLOT"
    assert row["mode"] == "HUD"
    assert int(row["page_count"]) == 4
    assert int(row["phase"]) == BRAKE
    assert int(row["valid_mask"]) == 511
    assert int(row["warn_mask"]) == 0
    assert abs(float(row["est_h_m"]) - 120.5) < 1.0e-9
    assert abs(float(row["est_v_mps"]) - 31.25) < 1.0e-9
    assert abs(float(row["target_margin_m"]) - 779.5) < 1.0e-9
    assert abs(float(row["brake_authority_m"]) - 180.0) < 1.0e-9
    assert int(row["actuator_us"]) == 1350
    assert int(row["safety_runtime_ok"]) == 1
    assert int(row["safety_allows_actuation"]) == 1
    assert int(row["sd_card_ok"]) == 1
    assert int(row["sd_file_open"]) == 1
    assert int(row["sd_runtime_failed"]) == 0

    readiness_flags = int(row["readiness_flags"])
    for bit in range(13):
        assert readiness_flags & (1 << bit), f"HUD readiness flag bit {bit} should be set in the nominal golden row"


def test_sd_logger_p0_identification_schema_present() -> None:
    required_sd_fields = {
        "row_seq",
        "baro_valid",
        "baro_updated",
        "baro_seq",
        "imu_valid",
        "imu_updated",
        "imu_seq",
        "aux_valid",
        "aux_updated",
        "aux_seq",
        "att_valid",
        "att_updated",
        "att_seq",
        "auxvz_valid",
        "auxvz_updated",
        "auxvz_seq",
        "est_valid",
        "est_updated",
        "est_seeded",
        "est_seq",
        "target_nominal",
        "target_effective",
        "uncertainty_margin",
    }

    for field in required_sd_fields:
        assert field in SD_LOGGER_CPP, f"SD logger header should include {field}"

    header_match = re.search(
        r"static void sd_write_header\(File &f\).*?f\.println\((.*?)\);",
        SD_LOGGER_CPP,
        re.DOTALL,
    )
    assert header_match is not None, "Could not extract SD header string"
    header_fields = [
        field
        for field in "".join(re.findall(r'"([^"]*)"', header_match.group(1))).split(",")
        if field
    ]
    for field in required_sd_fields:
        assert field in header_fields, f"SD CSV header should include {field}"

    service_body = SD_LOGGER_CPP.split("void sd_logger_service", 1)[1].split("/*\nsd_logger_ok", 1)[0]
    row_value_count = 0
    for match in re.finditer(r"state\.sdlog\.file\.(?:print|println)\((.*?)\);", service_body):
        arg = match.group(1).strip()
        if arg == "','":
            continue
        row_value_count += 1
    assert row_value_count == len(header_fields), (
        f"SD CSV header/row mismatch: header={len(header_fields)} row={row_value_count}"
    )

    source_contracts = [
        "uint32_t row_seq",
        "state.sdlog.row_seq = 0",
        "state.sdlog.file.print(state.sdlog.row_seq)",
        "++state.sdlog.row_seq",
        "state.baro.valid ? 1 : 0",
        "state.imu.valid ? 1 : 0",
        "state.attitude.valid ? 1 : 0",
        "state.auxvz.valid ? 1 : 0",
        "state.est.valid ? 1 : 0",
        "state.est.updated ? 1 : 0",
        "state.est.seeded ? 1 : 0",
        "state.est.seq",
        "state.policy.target_nominal_m",
        "state.policy.target_effective_m",
        "state.policy.uncertainty_margin_m",
    ]

    combined_source = DATA_TYPES_H + "\n" + SD_LOGGER_CPP
    for contract in source_contracts:
        assert contract in combined_source, f"Missing SD P0 source contract: {contract}"

    manifest_reader = csv.DictReader(io.StringIO(AERO_LOG_SCHEMA_CSV))
    manifest_fields = {row["column"] for row in manifest_reader}
    for field in required_sd_fields:
        assert field in manifest_fields, f"Schema manifest should include {field}"


def test_policy_coast_sim_reduces_apogee_with_more_brake() -> None:
    module = load_module("policy_coast_sim", COAST_SIM_SCRIPT)

    closed = module.simulate_coast(
        h0_m=2400.0,
        v0_mps=250.0,
        mode="closed",
        target_apogee_m=POLICY_TARGET_APOGEE_M,
        dt_s=0.02,
        max_time_s=30.0,
    )
    open_loop = module.simulate_coast(
        h0_m=2400.0,
        v0_mps=250.0,
        mode="open",
        target_apogee_m=POLICY_TARGET_APOGEE_M,
        dt_s=0.02,
        max_time_s=30.0,
    )
    policy = module.simulate_coast(
        h0_m=2400.0,
        v0_mps=250.0,
        mode="policy",
        target_apogee_m=POLICY_TARGET_APOGEE_M,
        dt_s=0.02,
        max_time_s=30.0,
    )

    assert open_loop["apogee_m"] < closed["apogee_m"], "Full brake should reduce apogee versus closed brake"
    assert policy["apogee_m"] <= closed["apogee_m"], "Policy simulation should not exceed the closed-brake apogee"
    assert 0.0 <= policy["max_command01"] <= 1.0, "Policy command should remain normalized"
    assert policy["max_command01"] > 0.0, "Overshoot scenario should deploy some brake in policy mode"


def test_plant_simulation_is_repeatable_and_faulted() -> None:
    module = load_module("plant_simulation", PLANT_SIM_SCRIPT)
    config = module.PlantConfig(seed=42, target_apogee_m=900.0, max_time_s=12.0)
    faults = [
        module.FaultSpec(kind="baro_dropout", start_s=3.0, end_s=3.4),
        module.FaultSpec(kind="actuator_stuck", start_s=4.0, end_s=5.0),
        module.FaultSpec(kind="noise_burst", start_s=6.0, end_s=6.5, value=8.0),
    ]

    first = module.simulate_plant(config, faults)
    second = module.simulate_plant(config, faults)

    assert first["summary"] == second["summary"], "Plant simulation must be repeatable for the same seed"
    assert first["csv_rows"] == second["csv_rows"], "Current-schema rows must be deterministic"
    assert first["shim_rows"] == second["shim_rows"], "Firmware-shim rows must be deterministic"

    summary = first["summary"]
    assert summary["max_policy_cmd"] > 0.0, "Lower target should exercise the policy command path"
    assert summary["max_actual_brake01"] > 0.0, "Actuator model should move under policy command"
    assert summary["max_actual_brake01"] < summary["max_policy_cmd"], "Lagged actuator should trail peak policy command"
    assert summary["fault_counts"]["baro_dropout"] > 0
    assert summary["fault_counts"]["actuator_stuck"] > 0
    assert summary["fault_counts"]["noise_burst"] > 0

    fields = set(first["fields"])
    for required in ("t_us", "baro_valid", "est_h", "est_v", "phase", "actuator_us", "policy_cmd", "warn_mask"):
        assert required in fields, f"Plant current-schema output missing {required}"

    dropout_rows = [row for row in first["csv_rows"] if row["baro_valid"] == 0]
    assert dropout_rows, "Barometer dropout fault should invalidate barometer rows"
    assert all(int(row["warn_mask"]) & (1 << 4) for row in dropout_rows), "Dropout rows should set baro warning bit"
    assert "ARM ARMED" in first["shim_rows"][0]["serial"]
    assert "POLICY 1" in first["shim_rows"][0]["serial"]

    with tempfile.TemporaryDirectory() as temp_dir:
        current_schema_log = Path(temp_dir) / "LOG_PLANT.CSV"
        shim_csv = Path(temp_dir) / "plant_shim.csv"
        module.write_current_schema_csv(current_schema_log, first)
        module.write_shim_csv(shim_csv, first)

        with current_schema_log.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            assert reader.fieldnames == first["fields"]
            rows = list(reader)
        assert len(rows) == summary["row_count"]

        with shim_csv.open("r", encoding="utf-8", newline="") as handle:
            shim_reader = csv.DictReader(handle)
            shim_rows = list(shim_reader)
        assert len(shim_rows) == summary["row_count"]


def test_apogee_evidence_view_renders_plant_log() -> None:
    plant_module = load_module("plant_simulation", PLANT_SIM_SCRIPT)
    view_module = load_module("apogee_evidence_view", APOGEE_EVIDENCE_SCRIPT)
    config = plant_module.PlantConfig(seed=9, target_apogee_m=900.0, max_time_s=12.0)
    result = plant_module.simulate_plant(config, [])

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_PLANT.CSV"
        svg_path = Path(temp_dir) / "apogee_evidence.svg"
        json_path = Path(temp_dir) / "apogee_evidence.json"
        layout_path = Path(temp_dir) / "apogee_layout.json"
        plant_module.write_current_schema_csv(log_path, result)

        samples = view_module.read_samples([log_path], "auto")
        summary = view_module.summarize_samples(samples)
        layout = view_module.normalize_apogee_envelope(samples)
        svg = view_module.render_svg(samples, title="test evidence")
        view_module.write_json(json_path, samples, summary)
        view_module.write_layout_json(layout_path, samples)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == result["summary"]["row_count"]
        assert summary["max_brake_authority_m"] >= 0.0
        assert layout["schema"] == "apogee-envelope-layout-v1"
        assert len(layout["series"]) == summary["sample_count"]
        assert layout["series"][0]["x_px"] >= layout["panels"]["apogee"]["x0_px"]
        assert layout["series"][-1]["x_px"] <= layout["panels"]["apogee"]["x1_px"]
        assert "<svg" in svg
        assert "test evidence" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000
        assert layout_path.exists() and layout_path.stat().st_size > 1000

        plot_samples = view_module.parse_plot_lines(
            [
                (
                    "PLOT_HDR,APOGEE,t_ms,phase,est_h_m,est_v_mps,baro_alt_m,"
                    "qbar_v_proxy_pa,specific_energy_m,mach_v_proxy,pred_no_brake_m,"
                    "pred_full_brake_m,target_effective_m,target_nominal_m,target_margin_m,"
                    "apogee_error_m,brake_authority_m,cmd01,uncertainty_margin_m,"
                    "P00_m2,P11_m2,sigma_h_m,baro_age_ms,imu_age_ms,est_age_ms,"
                    "policy_valid,actuator_us,valid_mask,warn_mask"
                ),
                "PLOT,APOGEE,1000,2,100,45,98,1200,203,0.13,980,820,900,920,800,80,160,0.25,20,4,9,2,10,11,12,1,1250,511,0",
                "PLOT,APOGEE,1200,3,120,40,118,1000,202,0.12,940,800,900,920,780,40,140,0.50,20,4,9,2,10,11,260,1,1500,511,512",
            ]
        )
        plot_layout = view_module.normalize_apogee_envelope(plot_samples)
        assert len(plot_samples) == 2
        assert plot_layout["series"][1]["est_stale"]
        assert plot_layout["series"][1]["warn_active"]
        assert plot_layout["series"][0]["authority_top_y_px"] <= plot_layout["series"][0]["authority_bottom_y_px"]

        headerless_plot_samples = view_module.parse_plot_lines(
            [
                "PLOT,APOGEE,1468572,0,0.00,0.00,nan,nan,nan,nan,nan,nan,nan,3048.00,nan,nan,nan,0.00,nan,1.00,1.00,nan,4294967295,4294967295,4294967295,0,1000,20,8192",
                "PLOT,APOGEE,147",
            ]
        )
        assert len(headerless_plot_samples) == 1
        assert headerless_plot_samples[0].warn_mask == 8192
        assert headerless_plot_samples[0].est_age_ms == 4294967295


def test_apogee_prediction_residual_timeline_labels_model_error() -> None:
    module = load_module("apogee_prediction_residual_timeline", APOGEE_RESIDUAL_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_APOGEE_RESIDUAL.CSV"
        svg_path = Path(temp_dir) / "apogee_prediction_residual.svg"
        json_path = Path(temp_dir) / "apogee_prediction_residual.json"
        write_analytic_aero_fixture(log_path, actual_apogee_m=300.0)

        source_samples = module.read_samples([log_path], "auto")
        residuals, summary = module.build_residual_samples(
            source_samples,
            observed_apogee_m=300.0,
            body_cda_m2=POLICY_CDA_BODY_M2,
            brake_cda_m2=POLICY_CDA_BRAKE_M2,
            mass_kg=POLICY_VEHICLE_MASS_KG,
            rho_kgpm3=POLICY_RHO_KGPM3,
            stale_age_ms=200.0,
        )
        svg = module.render_svg(residuals, summary, title="apogee residual test")
        module.write_json(json_path, residuals, summary)
        svg_path.write_text(svg, encoding="utf-8")

        selected_residuals = [
            sample.residual_selected_m
            for sample in residuals
            if sample.phase in (COAST, BRAKE) and math.isfinite(sample.residual_selected_m)
        ]
        no_brake_residuals = [
            sample.residual_no_brake_m
            for sample in residuals
            if sample.phase in (COAST, BRAKE) and math.isfinite(sample.residual_no_brake_m)
        ]

        assert summary["passed_basic_input_check"]
        assert summary["observed_apogee_source"] == "provided"
        assert summary["finite_selected_residual_rows"] == 7
        assert summary["model_assisted_rows"] == 7
        assert summary["final_label"] == "residual_timeline_model_assisted"
        assert max(abs(value) for value in selected_residuals) < 1.0e-6
        assert max(abs(value) for value in no_brake_residuals) > 1.0
        assert "<svg" in svg
        assert "apogee residual test" in svg
        assert "prediction residuals" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_estimator_policy_phase_space_view_renders_causal_plot_rows() -> None:
    view_module = load_module("estimator_policy_phase_space_view", ESTIMATOR_POLICY_PHASE_SPACE_SCRIPT)
    plot_lines = [
        (
            "PLOT_HDR,APOGEE,t_ms,phase,est_h_m,est_v_mps,baro_alt_m,"
            "qbar_v_proxy_pa,specific_energy_m,mach_v_proxy,pred_no_brake_m,"
            "pred_full_brake_m,target_effective_m,target_nominal_m,target_margin_m,"
            "apogee_error_m,brake_authority_m,cmd01,uncertainty_margin_m,"
            "P00_m2,P11_m2,sigma_h_m,baro_age_ms,imu_age_ms,est_age_ms,"
            "policy_valid,actuator_us,valid_mask,warn_mask"
        ),
        "PLOT,APOGEE,1000,2,45,34,44,708,104,0.10,980,810,900,920,855,80,170,0.10,20,4,9,2,10,11,15,1,1100,511,0",
        "PLOT,APOGEE,1200,2,62,32,61,627,114,0.09,960,815,900,920,838,60,145,0.25,20,4,9,2,10,11,15,1,1250,511,0",
        "PLOT,APOGEE,1400,3,76,29,75,515,119,0.09,940,820,900,920,824,40,120,0.35,20,4,9,2,10,11,15,1,1350,511,0",
        "PLOT,APOGEE,1600,3,88,25,87,383,120,0.07,925,825,900,920,812,25,100,0.45,20,4,9,2,10,11,15,1,1450,511,0",
        "PLOT,APOGEE,1800,3,98,20,97,245,118,0.06,912,830,900,920,802,12,82,0.30,20,4,9,2,10,11,15,1,1300,511,0",
    ]

    with tempfile.TemporaryDirectory() as temp_dir:
        plot_path = Path(temp_dir) / "causal_apogee_capture.txt"
        svg_path = Path(temp_dir) / "estimator_policy_phase_space.svg"
        json_path = Path(temp_dir) / "estimator_policy_phase_space.json"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.read_samples([plot_path], "auto")
        summary = view_module.summarize_samples(
            samples,
            min_alt_m=30.0,
            min_vz_mps=15.0,
            stale_age_ms=200.0,
            apogee_deadband_m=5.0,
            actuator_tolerance01=0.15,
            command_threshold01=0.01,
        )
        svg = view_module.render_svg(samples, summary, title="causal policy test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 5
        assert summary["finite_prediction_rows"] == 5
        assert summary["prerequisite_pass_rows"] == 5
        assert summary["policy_valid_rows"] == 5
        assert summary["command_row_count"] == 5
        assert summary["command_without_prereq_rows"] == 0
        assert summary["actuator_mismatch_rows"] == 0
        assert summary["final_label"] == "causal_chain_supported"
        assert summary["gate_counts"]["phase"]["pass"] == 5
        assert summary["gate_counts"]["demand"]["pass"] == 5
        assert "<svg" in svg
        assert "causal policy test" in svg
        assert "causal gate raster" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000

        headerless_plot_samples = view_module.parse_plot_lines(
            [
                "PLOT,APOGEE,1468572,0,0.00,0.00,nan,nan,nan,nan,nan,nan,nan,3048.00,nan,nan,nan,0.00,nan,1.00,1.00,nan,4294967295,4294967295,4294967295,0,1000,20,8192",
                "PLOT,APOGEE,147",
            ]
        )
        assert len(headerless_plot_samples) == 1
        assert headerless_plot_samples[0].warn_mask == 8192
        assert headerless_plot_samples[0].est_age_ms == 4294967295


def test_provenance_evidence_view_renders_plant_log() -> None:
    plant_module = load_module("plant_simulation", PLANT_SIM_SCRIPT)
    view_module = load_module("provenance_evidence_view", PROVENANCE_EVIDENCE_SCRIPT)
    config = plant_module.PlantConfig(seed=25, target_apogee_m=900.0, max_time_s=10.0)
    result = plant_module.simulate_plant(config, [])

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_PLANT.CSV"
        svg_path = Path(temp_dir) / "provenance.svg"
        json_path = Path(temp_dir) / "provenance.json"
        layout_path = Path(temp_dir) / "provenance_layout.json"
        plant_module.write_current_schema_csv(log_path, result)

        samples = view_module.read_samples([log_path], "auto")
        summary = view_module.summarize_samples(samples)
        layout = view_module.normalize_provenance(samples)
        svg = view_module.render_svg(samples, title="provenance test")
        view_module.write_json(json_path, samples, summary)
        view_module.write_layout_json(layout_path, samples)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == result["summary"]["row_count"]
        assert summary["baro_velocity_proxy_count"] > 0
        assert layout["schema"] == "provenance-layout-v1"
        assert len(layout["series"]) == summary["sample_count"]
        assert layout["series"][0]["x_px"] >= layout["panels"]["altitude"]["x0_px"]
        assert layout["series"][-1]["x_px"] <= layout["panels"]["altitude"]["x1_px"]
        assert "<svg" in svg
        assert "provenance test" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000
        assert layout_path.exists() and layout_path.stat().st_size > 1000

        plot_samples = view_module.parse_plot_lines(
            [
                (
                    "PLOT_HDR,PROVENANCE,t_ms,valid_mask,warn_mask,"
                    "baro_age_ms,imu_age_ms,att_age_ms,auxvz_age_ms,est_age_ms,"
                    "baro_alt_m,est_h_m,alt_residual_m,"
                    "baro_v_proxy_mps,est_v_mps,velocity_residual_mps,"
                    "auxvz_a_vertical_mps2,est_a_mps2,accel_residual_mps2,"
                    "P00_m2,P11_m2,sigma_h_m,sigma_v_mps,"
                    "est_seeded,baro_valid,auxvz_valid,est_valid"
                ),
                "PLOT,PROVENANCE,1000,511,0,10,11,12,13,14,99,100,1,42,45,3,9,10,1,4,9,2,3,1,1,1,1",
                "PLOT,PROVENANCE,1200,511,512,10,11,12,13,260,101,103,2,41,45,4,8,10,2,4,9,2,3,1,1,1,1",
            ]
        )
        plot_layout = view_module.normalize_provenance(plot_samples)
        assert len(plot_samples) == 2
        assert plot_layout["series"][1]["est_stale"]
        assert plot_layout["series"][1]["warn_active"]
        assert plot_layout["series"][0]["velocity_residual_mps"] == 3.0


def test_ekf_innovation_covariance_dashboard_renders_estimator_plot_rows() -> None:
    view_module = load_module("ekf_innovation_covariance_dashboard", EKF_DASHBOARD_SCRIPT)
    plot_lines = [
        (
            "PLOT_HDR,ESTIMATOR,t_ms,valid_mask,warn_mask,"
            "baro_age_ms,imu_age_ms,att_age_ms,auxvz_age_ms,est_age_ms,"
            "baro_alt_m,est_h_m,est_v_mps,est_a_mps2,"
            "P00,P01,P10,P11,sigma_h_m,sigma_v_mps,est_seeded"
        )
    ]
    valid_mask = (1 << 0) | (1 << 1) | (1 << 5) | (1 << 6) | (1 << 7)
    for index in range(5):
        baro_alt = 10.0 * index
        est_h = baro_alt + 0.10
        est_v = 10.0
        plot_lines.append(
            "PLOT,ESTIMATOR,"
            f"{1000 + index * 1000},{valid_mask},0,"
            "10,11,12,13,14,"
            f"{baro_alt:.3f},{est_h:.3f},{est_v:.3f},0.0,"
            "1.0,0.1,0.1,4.0,1.0,2.0,1"
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        plot_path = Path(temp_dir) / "estimator_capture.txt"
        svg_path = Path(temp_dir) / "ekf_dashboard.svg"
        json_path = Path(temp_dir) / "ekf_dashboard.json"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.read_samples([plot_path], "auto", 5.71e-03)
        summary = view_module.summarize_samples(
            samples,
            stale_age_ms=200.0,
            measurement_variance_m2=5.71e-03,
            symmetry_tolerance=1.0e-5,
            sigma_tolerance=1.0e-4,
            max_norm_residual=4.0,
        )
        svg = view_module.render_svg(samples, summary, title="ekf dashboard test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 5
        assert summary["seeded_rows"] == 5
        assert summary["finite_alt_residual_rows"] == 5
        assert summary["finite_velocity_residual_rows"] == 4
        assert summary["covariance_invalid_rows"] == 0
        assert summary["residual_outlier_rows"] == 0
        assert summary["gate_counts"]["covariance_psd"]["pass"] == 5
        assert summary["gate_counts"]["covariance_symmetric"]["pass"] == 5
        assert summary["gate_counts"]["sigma_h_matches"]["pass"] == 5
        assert summary["final_label"] == "innovation_covariance_consistent"
        assert abs(summary["max_abs_norm_alt_residual"] - (0.10 / math.sqrt(1.0 + 5.71e-03))) < 1.0e-9
        assert "<svg" in svg
        assert "ekf dashboard test" in svg
        assert "normalized residual proxy timeline" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_temporal_freshness_latency_oscilloscope_renders_health_plot_rows() -> None:
    view_module = load_module("temporal_freshness_latency_oscilloscope", TEMPORAL_OSCILLOSCOPE_SCRIPT)
    plot_lines = [
        (
            "PLOT_HDR,HEALTH,t_ms,"
            "valid_mask,warn_mask,"
            "bmp_ok,bmi_accel_ok,bmi_gyro_ok,lis_ok,pmod_accel_ok,mag_ok,"
            "baro_valid,imu_valid,aux_valid,pmod_valid,mag_valid,"
            "att_valid,auxvz_valid,est_valid,policy_valid,cfg_valid,"
            "baro_age_ms,imu_age_ms,aux_age_ms,pmod_age_ms,mag_age_ms,"
            "att_age_ms,auxvz_age_ms,est_age_ms,phase_diag_age_ms,"
            "sd_card_ok,sd_runtime_failed,sd_fail_count"
        )
    ]
    for index in range(5):
        t_ms = 1000 + index * 200
        plot_lines.append(
            "PLOT,HEALTH,"
            f"{t_ms},511,0,"
            "1,1,1,1,1,1,"
            "1,1,1,1,1,1,1,1,1,1,"
            f"{10 + index},{8 + index},{6 + index},{4 + index},{3 + index},"
            f"{7 + index},{9 + index},{5 + index},{2 + index},"
            "1,0,0"
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        plot_path = Path(temp_dir) / "health_capture.txt"
        svg_path = Path(temp_dir) / "temporal_oscilloscope.svg"
        json_path = Path(temp_dir) / "temporal_oscilloscope.json"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.read_samples([plot_path], "auto")
        summary = view_module.summarize_samples(
            samples,
            stale_age_ms=200.0,
            expected_period_ms=200.0,
            gap_factor=1.5,
            jitter_fraction=0.35,
            required_channels=set(),
        )
        svg = view_module.render_svg(samples, summary, title="temporal scope test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 5
        assert summary["source_kinds"] == ["plot"]
        assert summary["observed_channels"] == ["baro", "imu", "aux", "pmod", "mag", "att", "auxvz", "est", "phase"]
        assert abs(summary["mean_dt_ms"] - 200.0) < 1.0e-9
        assert summary["timebase_gap_rows"] == 0
        assert summary["channel_sequence_gap_rows"] == 0
        assert summary["warn_row_count"] == 0
        assert summary["channel_stats"]["baro"]["max_age_ms"] == 14.0
        assert summary["final_label"] == "temporal_contract_nominal"
        assert "<svg" in svg
        assert "temporal scope test" in svg
        assert "sample period / timebase jitter" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_energy_phase_view_renders_plant_log() -> None:
    plant_module = load_module("plant_simulation", PLANT_SIM_SCRIPT)
    view_module = load_module("energy_phase_view", ENERGY_PHASE_SCRIPT)
    config = plant_module.PlantConfig(seed=26, target_apogee_m=900.0, max_time_s=10.0)
    result = plant_module.simulate_plant(config, [])

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_PLANT.CSV"
        svg_path = Path(temp_dir) / "energy_phase.svg"
        json_path = Path(temp_dir) / "energy_phase.json"
        layout_path = Path(temp_dir) / "energy_phase_layout.json"
        plant_module.write_current_schema_csv(log_path, result)

        samples = view_module.read_samples([log_path], "auto")
        summary = view_module.summarize_samples(samples)
        layout = view_module.normalize_energy_phase(samples)
        svg = view_module.render_svg(samples, title="energy test")
        view_module.write_json(json_path, samples, summary)
        view_module.write_layout_json(layout_path, samples)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == result["summary"]["row_count"]
        assert summary["max_specific_energy_m"] >= summary["max_est_h_m"]
        assert layout["schema"] == "energy-phase-layout-v1"
        assert len(layout["series"]) == summary["sample_count"]
        assert "<svg" in svg
        assert "energy test" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000
        assert layout_path.exists() and layout_path.stat().st_size > 1000

        plot_samples = view_module.parse_plot_lines(
            [
                "PLOT,ENERGY,1000,2,511,0,100,45,203.24,103.24,1200,0.13,980,820,900,800,160,0.25,1,10",
                "PLOT,ENERGY,1200,3,511,512,120,40,201.55,81.55,1000,0.12,940,800,900,780,140,0.50,1,260",
                "PLOT,ENERGY,147",
            ]
        )
        plot_layout = view_module.normalize_energy_phase(plot_samples)
        assert len(plot_samples) == 2
        assert plot_layout["series"][1]["est_stale"]
        assert plot_layout["series"][1]["warn_active"]
        assert plot_layout["series"][0]["phase_name"] == "COAST"


def test_phase_timeline_view_renders_plant_log() -> None:
    plant_module = load_module("plant_simulation", PLANT_SIM_SCRIPT)
    view_module = load_module("phase_timeline_view", PHASE_TIMELINE_SCRIPT)
    config = plant_module.PlantConfig(seed=10, target_apogee_m=900.0, max_time_s=12.0)
    result = plant_module.simulate_plant(config, [])

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_PLANT.CSV"
        svg_path = Path(temp_dir) / "phase_timeline.svg"
        json_path = Path(temp_dir) / "phase_timeline.json"
        plant_module.write_current_schema_csv(log_path, result)

        samples = view_module.read_samples([log_path], "auto")
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="phase test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == result["summary"]["row_count"]
        assert summary["transition_count"] >= 2
        assert summary["phase_counts"].get("BOOST", 0) > 0
        assert summary["phase_counts"].get("DESCENT", 0) > 0
        assert "<svg" in svg
        assert "phase test" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_health_dashboard_view_renders_faulted_plant_log() -> None:
    plant_module = load_module("plant_simulation", PLANT_SIM_SCRIPT)
    view_module = load_module("health_dashboard_view", HEALTH_DASHBOARD_SCRIPT)
    config = plant_module.PlantConfig(seed=12, target_apogee_m=900.0, max_time_s=12.0)
    faults = [
        plant_module.FaultSpec(kind="baro_dropout", start_s=3.0, end_s=3.4),
        plant_module.FaultSpec(kind="imu_dropout", start_s=5.0, end_s=5.3),
        plant_module.FaultSpec(kind="est_dropout", start_s=6.0, end_s=6.2),
    ]
    result = plant_module.simulate_plant(config, faults)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_PLANT_FAULTED.CSV"
        svg_path = Path(temp_dir) / "health_dashboard.svg"
        json_path = Path(temp_dir) / "health_dashboard.json"
        plant_module.write_current_schema_csv(log_path, result)

        samples = view_module.read_samples([log_path], "auto")
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="health test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == result["summary"]["row_count"]
        assert summary["warn_row_count"] > 0
        assert summary["invalid_counts"]["barometer"] > 0
        assert summary["invalid_counts"]["IMU"] > 0
        assert summary["invalid_counts"]["estimator"] > 0
        assert summary["warn_bit_counts"]["baro_invalid"] > 0
        assert summary["warn_bit_counts"]["imu_invalid"] > 0
        assert summary["warn_bit_counts"]["est_invalid"] > 0
        assert "<svg" in svg
        assert "health test" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_orientation_vector_view_renders_plot_rows() -> None:
    view_module = load_module("orientation_vector_view", ORIENTATION_VECTOR_SCRIPT)
    plot_lines = [
        "ACK,PLOT,ORIENT",
        (
            "PLOT_HDR,ORIENT,t_ms,valid_mask,warn_mask,"
            "aux_ax_mps2,aux_ay_mps2,aux_az_mps2,aux_a_norm_mps2,"
            "accel_roll_deg,accel_pitch_deg,"
            "mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,"
            "aux_age_ms,mag_age_ms"
        ),
        "PLOT,ORIENT,1000,20,8192,0.10,0.20,9.70,9.703,1.181,-0.591,25.0,5.0,38.0,45.716,78.0,0,8,7",
        "PLOT,ORIENT,1200,20,8192,0.20,0.10,9.75,9.753,0.588,-1.175,26.0,6.0,37.0,45.596,81.0,0,9,6",
        "PLOT,ORIENT,1400,20,8192,0.25,-0.05,9.80,9.803,-0.292,-1.461,26.5,6.4,37.2,46.087,83.0,0,9,7",
    ]

    with tempfile.TemporaryDirectory() as temp_dir:
        svg_path = Path(temp_dir) / "orientation_vector.svg"
        json_path = Path(temp_dir) / "orientation_vector.json"
        plot_path = Path(temp_dir) / "orientation_capture.txt"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.parse_plot_lines(plot_lines)
        auto_samples = view_module.read_samples([plot_path], "auto")
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="orientation test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 3
        assert len(auto_samples) == 3
        assert summary["aux_valid_rows"] == 3
        assert summary["mag_valid_rows"] == 3
        assert summary["warn_bit_counts"]["sd_fault"] == 3
        assert abs(summary["mag_norm_mean_uT"] - 45.79966666666667) < 1.0e-6
        assert "<svg" in svg
        assert "orientation test" in svg
        assert "gravity horizon" in svg
        assert "magnetic compass" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_magnetic_field_quality_view_renders_plot_rows() -> None:
    view_module = load_module("magnetic_field_quality_view", MAGNETIC_FIELD_SCRIPT)
    plot_lines = [
        "ACK,PLOT,ORIENT",
        (
            "PLOT_HDR,ORIENT,t_ms,valid_mask,warn_mask,"
            "aux_ax_mps2,aux_ay_mps2,aux_az_mps2,aux_a_norm_mps2,"
            "accel_roll_deg,accel_pitch_deg,"
            "mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,"
            "aux_age_ms,mag_age_ms"
        ),
    ]
    center_x = 8.0
    center_y = -5.0
    center_z = 36.0
    for idx in range(36):
        heading = idx * 10.0
        rad = math.radians(heading)
        mag_x = center_x + 30.0 * math.cos(rad)
        mag_y = center_y + 20.0 * math.sin(rad)
        mag_z = center_z + 2.0 * math.sin(2.0 * rad)
        mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)
        interference = 1 if idx in (7, 25) else 0
        warn_mask = 1 << 12 if interference else 0
        plot_lines.append(
            "PLOT,ORIENT,"
            f"{1000 + idx * 100},16,{warn_mask},"
            "0.0,0.0,9.80,9.80,0.0,0.0,"
            f"{mag_x:.6f},{mag_y:.6f},{mag_z:.6f},{mag_norm:.6f},{heading:.3f},{interference},"
            "5,6"
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        svg_path = Path(temp_dir) / "bench_magnetic_field_quality.svg"
        json_path = Path(temp_dir) / "bench_magnetic_field_quality.json"
        plot_path = Path(temp_dir) / "magnetic_capture.txt"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.parse_plot_lines(plot_lines)
        auto_samples = view_module.read_samples([plot_path], "auto")
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="magnetic quality test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 36
        assert len(auto_samples) == 36
        assert summary["mag_valid_rows"] == 36
        assert summary["mag_interference_rows"] == 2
        assert summary["warn_bit_counts"]["mag_fault"] == 2
        assert summary["heading_coverage_bins"] == 24
        assert abs(summary["hard_iron_offset_x_uT"] - center_x) < 1.0e-6
        assert abs(summary["hard_iron_offset_y_uT"] - center_y) < 1.0e-6
        assert summary["centered_xy_radius_std_uT"] > 0.0
        assert "<svg" in svg
        assert "magnetic quality test" in svg
        assert "XY magnetic scatter" in svg
        assert "heading-binned |B| heat/ring map" in svg
        assert "bench hard-iron centroid" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_gravity_norm_stability_view_renders_plot_rows() -> None:
    view_module = load_module("gravity_norm_stability_view", GRAVITY_STABILITY_SCRIPT)
    plot_lines = [
        "ACK,PLOT,ORIENT",
        (
            "PLOT_HDR,ORIENT,t_ms,valid_mask,warn_mask,"
            "aux_ax_mps2,aux_ay_mps2,aux_az_mps2,aux_a_norm_mps2,"
            "accel_roll_deg,accel_pitch_deg,"
            "mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,"
            "aux_age_ms,mag_age_ms"
        ),
    ]
    for idx in range(60):
        t_ms = 1000 + idx * 100
        ax = 0.05 * math.sin(idx * 0.2)
        ay = 0.08 * math.cos(idx * 0.17)
        az = 9.80665 + 0.06 * math.sin(idx * 0.37)
        a_norm = math.sqrt(ax * ax + ay * ay + az * az)
        roll = math.degrees(math.atan2(ay, az))
        pitch = math.degrees(math.atan2(-ax, math.hypot(ay, az)))
        warn_mask = 1 << 13
        plot_lines.append(
            "PLOT,ORIENT,"
            f"{t_ms},20,{warn_mask},"
            f"{ax:.6f},{ay:.6f},{az:.6f},{a_norm:.6f},{roll:.6f},{pitch:.6f},"
            "25.0,5.0,38.0,45.7,78.0,0,8,7"
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        svg_path = Path(temp_dir) / "bench_gravity_norm_stability.svg"
        json_path = Path(temp_dir) / "bench_gravity_norm_stability.json"
        plot_path = Path(temp_dir) / "gravity_capture.txt"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.parse_plot_lines(plot_lines)
        auto_samples = view_module.read_samples([plot_path], "auto")
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="gravity stability test")
        view_module.write_json(json_path, samples, summary)
        json_samples = view_module.read_samples([json_path], "json")
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 60
        assert len(auto_samples) == 60
        assert len(json_samples) == 60
        assert summary["aux_valid_rows"] == 60
        assert summary["warn_bit_counts"]["sd_fault"] == 60
        assert summary["warn_bit_counts"]["lis_hw"] == 0
        assert summary["warn_bit_counts"]["aux_invalid"] == 0
        assert summary["aux_norm_std_mps2"] > 0.0
        assert summary["vibration_delta_rms_mps2_per_sample"] > 0.0
        assert summary["stability_class"] in ("stable_static", "usable_bench_motion")
        assert "<svg" in svg
        assert "gravity stability test" in svg
        assert "gravity residual timeline" in svg
        assert "tilt stability" in svg
        assert "absolute acceleration norm" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_sensor_frame_alignment_verifier_accepts_six_face_plot_rows() -> None:
    view_module = load_module("sensor_frame_alignment_verifier", SENSOR_FRAME_SCRIPT)
    face_vectors = [
        ("+X", (K_G, 0.0, 0.0)),
        ("-X", (-K_G, 0.0, 0.0)),
        ("+Y", (0.0, K_G, 0.0)),
        ("-Y", (0.0, -K_G, 0.0)),
        ("+Z", (0.0, 0.0, K_G)),
        ("-Z", (0.0, 0.0, -K_G)),
    ]
    plot_lines: list[str] = ["ACK,PLOT,ORIENT"]
    sample_index = 0
    for face_index, (_, axes) in enumerate(face_vectors):
        ax, ay, az = axes
        accel_norm = math.sqrt(ax * ax + ay * ay + az * az)
        roll_deg = math.degrees(math.atan2(ay, az))
        pitch_deg = math.degrees(math.atan2(-ax, math.hypot(ay, az)))
        for _ in range(10):
            heading_deg = (face_index * 31.0 + sample_index) % 360.0
            mag_x = 30.0 + 0.05 * sample_index
            mag_y = 6.0 + 0.02 * sample_index
            mag_z = 37.0
            mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)
            plot_lines.append(
                "PLOT,ORIENT,"
                f"{1000 + sample_index * 100},20,8192,"
                f"{ax:.6f},{ay:.6f},{az:.6f},{accel_norm:.6f},{roll_deg:.6f},{pitch_deg:.6f},"
                f"{mag_x:.6f},{mag_y:.6f},{mag_z:.6f},{mag_norm:.6f},{heading_deg:.3f},0,8,7"
            )
            sample_index += 1

    with tempfile.TemporaryDirectory() as temp_dir:
        plot_path = Path(temp_dir) / "six_face_orient_capture.txt"
        svg_path = Path(temp_dir) / "sensor_frame_alignment.svg"
        json_path = Path(temp_dir) / "sensor_frame_alignment.json"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.read_samples([plot_path], "auto")
        summary, faces, runs = view_module.summarize_alignment(
            samples,
            min_face_samples=8,
            min_dominance_ratio=0.82,
            max_gravity_rms_mps2=1.0,
            max_angle_formula_rmse_deg=2.0,
            expected_sequence=["+X", "-X", "+Y", "-Y", "+Z", "-Z"],
        )
        svg = view_module.render_svg(samples, summary, faces, runs, title="sensor frame test")
        view_module.write_json(json_path, [plot_path], summary, faces, runs)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["sample_count"] == 60
        assert summary["aux_valid_rows"] == 60
        assert summary["mag_valid_rows"] == 60
        assert summary["accepted_face_count"] == 6
        assert summary["accepted_faces"] == ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]
        assert summary["expected_sequence_matches"] is True
        assert summary["final_label"] == "frame_alignment_supported"
        assert summary["gravity_residual_rms_mps2"] < 0.001
        assert summary["roll_formula_rmse_deg"] < 0.001
        assert summary["pitch_formula_rmse_deg"] < 0.001
        assert "sensor frame test" in svg
        assert "six-face gravity coverage" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_readiness_gate_view_marks_uninstalled_sensors_truthfully() -> None:
    view_module = load_module("readiness_gate_view", READINESS_GATE_SCRIPT)
    plot_lines = [
        "ACK,PLOT,HEALTH",
        (
            "PLOT_HDR,HEALTH,t_ms,"
            "valid_mask,warn_mask,"
            "bmp_ok,bmi_accel_ok,bmi_gyro_ok,lis_ok,pmod_accel_ok,mag_ok,"
            "baro_valid,imu_valid,aux_valid,pmod_valid,mag_valid,"
            "att_valid,auxvz_valid,est_valid,policy_valid,cfg_valid,"
            "baro_age_ms,imu_age_ms,aux_age_ms,pmod_age_ms,mag_age_ms,"
            "att_age_ms,auxvz_age_ms,est_age_ms,phase_diag_age_ms,"
            "sd_card_ok,sd_runtime_failed,sd_fail_count"
        ),
    ]
    for idx in range(5):
        plot_lines.append(
            "PLOT,HEALTH,"
            f"{1000 + idx * 200},20,8192,"
            "0,0,0,1,0,1,"
            "0,0,1,0,1,"
            "0,0,0,0,1,"
            "4294967295,4294967295,8,4294967295,7,"
            "4294967295,4294967295,4294967295,0,"
            "0,0,0"
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        svg_path = Path(temp_dir) / "bench_readiness_gate.svg"
        json_path = Path(temp_dir) / "bench_readiness_gate.json"
        plot_path = Path(temp_dir) / "readiness_capture.txt"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = view_module.parse_plot_lines(plot_lines)
        auto_samples = view_module.read_samples([plot_path], "auto")
        summary = view_module.summarize_samples(samples, installed={"lis3dh", "cmps2"}, max_age_ms=1000.0)
        svg = view_module.render_svg(samples, installed={"lis3dh", "cmps2"}, max_age_ms=1000.0, title="readiness test")
        view_module.write_json(json_path, samples, summary)
        json_samples = view_module.read_samples([json_path], "json")
        svg_path.write_text(svg, encoding="utf-8")

        component_status = {item["key"]: item["status"] for item in summary["components"]}
        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 5
        assert len(auto_samples) == 5
        assert len(json_samples) == 5
        assert summary["readiness_state"] == "bench_ready"
        assert component_status["lis3dh"] == "passed"
        assert component_status["cmps2"] == "passed"
        assert component_status["bmp5xx"] == "not_installed_configured"
        assert component_status["bmi088_accel"] == "not_installed_configured"
        assert component_status["sd"] == "not_installed_configured"
        assert summary["warn_bit_counts"]["sd_fault"] == 5
        assert "<svg" in svg
        assert "readiness test" in svg
        assert "not_installed_configured" in svg
        assert "readiness gate matrix" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000

        full_summary = view_module.summarize_samples(samples, installed={"lis3dh", "cmps2", "bmp5xx"}, max_age_ms=1000.0)
        full_status = {item["key"]: item["status"] for item in full_summary["components"]}
        assert full_summary["readiness_state"] == "not_ready"
        assert full_status["bmp5xx"] == "failed"


def quaternion_from_euler_zyx(roll_deg: float, pitch_deg: float, yaw_deg: float) -> tuple[float, float, float, float]:
    roll = math.radians(roll_deg)
    pitch = math.radians(pitch_deg)
    yaw = math.radians(yaw_deg)
    cr = math.cos(0.5 * roll)
    sr = math.sin(0.5 * roll)
    cp = math.cos(0.5 * pitch)
    sp = math.sin(0.5 * pitch)
    cy = math.cos(0.5 * yaw)
    sy = math.sin(0.5 * yaw)
    return (
        cr * cp * cy + sr * sp * sy,
        sr * cp * cy - cr * sp * sy,
        cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy,
    )


def body_mag_from_horizontal_vector(
    horizontal_x_uT: float,
    horizontal_y_uT: float,
    vertical_z_uT: float,
    roll_deg: float,
    pitch_deg: float,
) -> tuple[float, float, float]:
    roll = math.radians(roll_deg)
    pitch = math.radians(pitch_deg)
    sr = math.sin(roll)
    cr = math.cos(roll)
    sp = math.sin(pitch)
    cp = math.cos(pitch)
    mag_x = cp * horizontal_x_uT + sr * sp * horizontal_y_uT - cr * sp * vertical_z_uT
    mag_y = cr * horizontal_y_uT + sr * vertical_z_uT
    mag_z = sp * horizontal_x_uT - sr * cp * horizontal_y_uT + cr * cp * vertical_z_uT
    return mag_x, mag_y, mag_z


def test_tilt_compensated_heading_view_renders_current_schema_log() -> None:
    view_module = load_module("tilt_compensated_heading_view", HEADING_DEMO_SCRIPT)
    fields = [
        "t_us",
        "aux_valid",
        "lis_ax",
        "lis_ay",
        "lis_az",
        "mag_valid",
        "mag_x_uT",
        "mag_y_uT",
        "mag_z_uT",
        "mag_norm_uT",
        "mag_heading_deg",
        "mag_interference",
        "att_valid",
        "q0",
        "q1",
        "q2",
        "q3",
        "warn_mask",
    ]

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_HEADING.CSV"
        svg_path = Path(temp_dir) / "tilt_heading.svg"
        json_path = Path(temp_dir) / "tilt_heading.json"

        with log_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            for idx in range(24):
                roll_deg = 18.0 + 0.4 * idx
                pitch_deg = -9.0 + 0.1 * idx
                q0, q1, q2, q3 = quaternion_from_euler_zyx(roll_deg, pitch_deg, 0.0)
                mag_x = 34.0
                mag_y = 6.0 + 0.05 * idx
                mag_z = 29.0
                mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)
                writer.writerow(
                    {
                        "t_us": idx * 100000,
                        "aux_valid": 1,
                        "lis_ax": 0.03 * math.sin(idx),
                        "lis_ay": 0.02 * math.cos(idx),
                        "lis_az": K_G + 0.04 * math.sin(0.5 * idx),
                        "mag_valid": 1,
                        "mag_x_uT": mag_x,
                        "mag_y_uT": mag_y,
                        "mag_z_uT": mag_z,
                        "mag_norm_uT": mag_norm,
                        "mag_heading_deg": math.degrees(math.atan2(mag_y, mag_x)),
                        "mag_interference": 0,
                        "att_valid": 1,
                        "q0": q0,
                        "q1": q1,
                        "q2": q2,
                        "q3": q3,
                        "warn_mask": 0,
                    }
                )

        samples = view_module.read_samples(
            [log_path],
            "auto",
            gravity_tolerance_mps2=0.75,
            mag_norm_min_uT=20.0,
            mag_norm_max_uT=80.0,
            max_q_norm_error=0.05,
        )
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="heading test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 24
        assert summary["ready_count"] == 24
        assert summary["max_abs_heading_compensation_deg"] > 1.0
        assert summary["quality_label_counts"]["heading_ready"] == 24
        assert "<svg" in svg
        assert "heading test" in svg
        assert "prerequisite readiness lanes" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_tilt_compensated_heading_view_renders_plot_orient_rows() -> None:
    view_module = load_module("tilt_compensated_heading_view", HEADING_DEMO_SCRIPT)
    plot_lines = [
        "ACK,PLOT,ORIENT",
        (
            "PLOT_HDR,ORIENT,t_ms,valid_mask,warn_mask,"
            "aux_ax_mps2,aux_ay_mps2,aux_az_mps2,aux_a_norm_mps2,"
            "accel_roll_deg,accel_pitch_deg,"
            "mag_x_uT,mag_y_uT,mag_z_uT,mag_norm_uT,mag_heading_deg,mag_interference,"
            "aux_age_ms,mag_age_ms"
        ),
    ]
    for idx, roll_deg in enumerate((-24.0, -16.0, -8.0, 0.0, 8.0, 16.0, 24.0, 32.0)):
        pitch_deg = -10.0 + idx * 2.0
        mag_x = 34.0
        mag_y = 6.0 + 0.2 * idx
        mag_z = 29.0
        mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)
        planar = math.degrees(math.atan2(mag_y, mag_x))
        plot_lines.append(
            ",".join(
                str(value)
                for value in (
                    "PLOT",
                    "ORIENT",
                    1000 + idx * 100,
                    20,
                    0,
                    0.02,
                    0.01,
                    K_G,
                    K_G,
                    roll_deg,
                    pitch_deg,
                    mag_x,
                    mag_y,
                    mag_z,
                    mag_norm,
                    planar,
                    0,
                    8,
                    7,
                )
            )
        )

    with tempfile.TemporaryDirectory() as temp_dir:
        plot_path = Path(temp_dir) / "heading_orient_capture.txt"
        svg_path = Path(temp_dir) / "tilt_heading_plot.svg"
        json_path = Path(temp_dir) / "tilt_heading_plot.json"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        rows = view_module.read_rows_from_plot_lines(plot_lines)
        samples = view_module.rows_to_samples(
            rows,
            gravity_tolerance_mps2=0.75,
            mag_norm_min_uT=20.0,
            mag_norm_max_uT=80.0,
            max_q_norm_error=0.05,
        )
        auto_samples = view_module.read_samples(
            [plot_path],
            "auto",
            gravity_tolerance_mps2=0.75,
            mag_norm_min_uT=20.0,
            mag_norm_max_uT=80.0,
            max_q_norm_error=0.05,
        )
        summary = view_module.summarize_samples(samples)
        svg = view_module.render_svg(samples, title="plot heading test")
        view_module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 8
        assert len(auto_samples) == 8
        assert summary["ready_count"] == 8
        assert summary["quality_label_counts"]["heading_ready"] == 8
        assert summary["max_abs_heading_compensation_deg"] > 5.0
        assert samples[0].roll_deg == -24.0
        assert samples[-1].pitch_deg == 4.0
        assert "<svg" in svg
        assert "plot heading test" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_heading_sign_calibration_validator_segments_controlled_pose_capture() -> None:
    heading_module = load_module("tilt_compensated_heading_view", HEADING_DEMO_SCRIPT)
    validator_module = load_module("heading_sign_calibration_validator", HEADING_VALIDATOR_SCRIPT)
    pose_sequence = [
        ("level", 0.0, 0.0),
        ("roll_pos", 25.0, 0.0),
        ("roll_neg", -25.0, 0.0),
        ("pitch_pos", 0.0, 18.0),
        ("pitch_neg", 0.0, -18.0),
    ]
    plot_lines: list[str] = []
    row_index = 0
    for _, roll_deg, pitch_deg in pose_sequence:
        for sample_index in range(12):
            mag_x, mag_y, mag_z = body_mag_from_horizontal_vector(34.0, 8.0, 40.0, roll_deg, pitch_deg)
            mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)
            planar_heading = math.degrees(math.atan2(mag_y, mag_x)) % 360.0
            plot_lines.append(
                ",".join(
                    str(value)
                    for value in (
                        "PLOT",
                        "ORIENT",
                        1000 + row_index * 200,
                        20,
                        8192,
                        0.0,
                        0.0,
                        K_G + 0.02 * math.sin(sample_index),
                        K_G + 0.02 * math.sin(sample_index),
                        roll_deg,
                        pitch_deg,
                        mag_x,
                        mag_y,
                        mag_z,
                        mag_norm,
                        planar_heading,
                        0,
                        8,
                        7,
                    )
                )
            )
            row_index += 1

    with tempfile.TemporaryDirectory() as temp_dir:
        plot_path = Path(temp_dir) / "pose_orient_capture.txt"
        heading_json_path = Path(temp_dir) / "pose_heading.json"
        validator_json_path = Path(temp_dir) / "pose_validator.json"
        validator_svg_path = Path(temp_dir) / "pose_validator.svg"
        plot_path.write_text("\n".join(plot_lines), encoding="utf-8")

        samples = heading_module.read_samples(
            [plot_path],
            "auto",
            gravity_tolerance_mps2=0.75,
            mag_norm_min_uT=20.0,
            mag_norm_max_uT=80.0,
            max_q_norm_error=0.05,
        )
        heading_summary = heading_module.summarize_samples(samples)
        heading_module.write_json(heading_json_path, samples, heading_summary)

        validator_samples, source_summary = validator_module.read_heading_json(heading_json_path)
        summary, segments, bins = validator_module.summarize_validation(
            validator_samples,
            source_summary,
            pose_change_deg=8.0,
            min_pose_samples=8,
            min_ready_fraction=0.80,
            max_tilt_heading_span_deg=15.0,
            heading_bin_count=24,
            min_calibration_bins=18,
            min_partial_calibration_bins=8,
            max_static_mag_norm_std_uT=2.0,
        )
        svg = validator_module.render_svg(validator_samples, segments, bins, summary, "pose validator test")
        validator_module.write_json(validator_json_path, heading_json_path, summary, segments, bins)
        validator_svg_path.write_text(svg, encoding="utf-8")

        assert heading_summary["sample_count"] == 60
        assert heading_summary["ready_count"] == 60
        assert summary["accepted_pose_count"] == 5
        assert summary["sign_state"] == "sign_convention_supported"
        assert summary["calibration_state"] == "insufficient_heading_coverage"
        assert summary["accepted_tilt_heading_span_deg"] < 1.0
        assert summary["accepted_planar_heading_span_deg"] > 20.0
        assert summary["roll_pair"]["opposes_reference"]
        assert summary["pitch_pair"]["opposes_reference"]
        assert "pose validator test" in svg
        assert "magnetic heading-bin coverage" in svg
        assert validator_svg_path.exists() and validator_svg_path.stat().st_size > 1000
        assert validator_json_path.exists() and validator_json_path.stat().st_size > 1000


def test_previous_year_flight_data_audit_blocks_aero_fit() -> None:
    module = load_module("audit_previous_year_flight_data", FLIGHT_DATA_AUDIT_SCRIPT)
    result = module.audit_directory(PREVIOUS_YEAR_DATA_DIR)

    assert result["file_count"] >= 1
    assert not result["can_update_policy_cda_body_m2"]
    assert not result["can_update_policy_cda_brake_m2"]


def test_empirical_aero_fit_on_analytic_fixture() -> None:
    module = load_module("policy_aero_empirical_fit", AERO_FIT_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_FIXTURE.CSV"
        write_analytic_aero_fixture(log_path, actual_apogee_m=300.0)

        result = module.analyze_logs(
            [log_path],
            mass_kg=POLICY_VEHICLE_MASS_KG,
            rho_kgpm3=POLICY_RHO_KGPM3,
            current_body_cda_m2=POLICY_CDA_BODY_M2,
            current_brake_cda_m2=POLICY_CDA_BRAKE_M2,
            closed_cmd_threshold=0.05,
            open_cmd_threshold=0.20,
            min_alt_m=POLICY_MIN_ALT_M,
            min_vz_mps=POLICY_MIN_VZ_MPS,
        )

        aggregate = result["aggregate"]
        body_cda_m2 = aggregate["recommended_body_cda_m2"]
        brake_cda_m2 = aggregate["recommended_brake_cda_m2"]

        assert body_cda_m2 is not None, "Analytic fixture should recover body CDA"
        assert brake_cda_m2 is not None, "Analytic fixture should recover brake CDA"
        assert abs(body_cda_m2 - POLICY_CDA_BODY_M2) < 1.0e-4
        assert abs(brake_cda_m2 - POLICY_CDA_BRAKE_M2) < 1.0e-4


def test_coefficient_report_records_body_and_brake_residuals() -> None:
    module = load_module("policy_aero_identification_report", AERO_REPORT_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_REPORT_FIXTURE.CSV"
        write_analytic_aero_fixture(log_path, actual_apogee_m=300.0)

        result = module.build_report(
            [log_path],
            mass_kg=POLICY_VEHICLE_MASS_KG,
            rho_kgpm3=POLICY_RHO_KGPM3,
            current_body_cda_m2=POLICY_CDA_BODY_M2,
            current_brake_cda_m2=POLICY_CDA_BRAKE_M2,
            closed_cmd_threshold=0.05,
            open_cmd_threshold=0.20,
            min_alt_m=POLICY_MIN_ALT_M,
            min_vz_mps=POLICY_MIN_VZ_MPS,
            max_residual_rows=20,
        )

        markdown = result["markdown"]
        residuals = result["residuals"]
        subsets = {record["subset"] for record in residuals}
        models = {record["model"] for record in residuals}

        assert "Coefficient Identification Report" in markdown
        assert "Residual Summary" in markdown
        assert "body" in subsets
        assert "brake" in subsets
        assert "current" in models
        assert "fitted" in models
        assert result["fit"]["aggregate"]["recommended_body_cda_m2"] is not None
        assert result["fit"]["aggregate"]["recommended_brake_cda_m2"] is not None


def test_aero_observability_map_classifies_analytic_fixture() -> None:
    module = load_module("aero_observability_map", AERO_OBSERVABILITY_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_AERO_OBSERVABLE.CSV"
        svg_path = Path(temp_dir) / "aero_observability.svg"
        json_path = Path(temp_dir) / "aero_observability.json"
        write_analytic_aero_fixture(log_path, actual_apogee_m=300.0)

        samples = module.read_samples(
            [log_path],
            mass_kg=POLICY_VEHICLE_MASS_KG,
            rho_kgpm3=POLICY_RHO_KGPM3,
            current_body_cda_m2=POLICY_CDA_BODY_M2,
            current_brake_cda_m2=POLICY_CDA_BRAKE_M2,
            closed_cmd_threshold=0.05,
            open_cmd_threshold=0.20,
            min_alt_m=POLICY_MIN_ALT_M,
            min_vz_mps=POLICY_MIN_VZ_MPS,
            min_delta_h_m=5.0,
            reject_warned_rows=True,
        )
        summary = module.summarize_samples(
            samples,
            min_body_samples=2,
            min_brake_samples=3,
            min_total_samples=6,
            min_command_span=0.20,
            max_condition_number=25.0,
        )
        svg = module.render_svg(samples, summary, title="aero observability test")
        module.write_json(json_path, samples, summary)
        svg_path.write_text(svg, encoding="utf-8")

        assert summary["passed_basic_input_check"]
        assert summary["sample_count"] == 7
        assert summary["eligible_sample_count"] == 6
        assert summary["body_sample_count"] == 2
        assert summary["brake_sample_count"] == 4
        assert summary["command_span"] == 1.0
        assert summary["condition_number"] < 10.0
        assert summary["measured_brake_rows"] == 0
        assert summary["command_proxy_rows"] == 6
        assert summary["final_label"] == "command_proxy_observable"
        assert abs(summary["body_equiv_cda_m2_median"] - POLICY_CDA_BODY_M2) < 1.0e-4
        assert abs(summary["brake_increment_cda_m2_median"] - POLICY_CDA_BRAKE_M2) < 1.0e-4
        assert "<svg" in svg
        assert "aero observability test" in svg
        assert "observability gate raster" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000


def test_wind_relative_landing_footprint_requires_horizontal_and_wind_evidence() -> None:
    module = load_module("wind_relative_landing_footprint", LANDING_FOOTPRINT_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        horizontal_log = Path(temp_dir) / "LOG_LANDING_GPS.CSV"
        vertical_only_log = Path(temp_dir) / "LOG_VERTICAL_ONLY.CSV"
        svg_path = Path(temp_dir) / "landing_footprint.svg"
        json_path = Path(temp_dir) / "landing_footprint.json"

        with horizontal_log.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=[
                    "t_us",
                    "phase",
                    "est_h",
                    "est_v",
                    "P00",
                    "gps_x",
                    "gps_y",
                    "gps_z",
                    "gps_vx",
                    "gps_vy",
                    "gps_vz",
                    "warn_mask",
                ],
            )
            writer.writeheader()
            writer.writerow(
                {
                    "t_us": "0",
                    "phase": "3",
                    "est_h": "100",
                    "est_v": "-8",
                    "P00": "4",
                    "gps_x": "0",
                    "gps_y": "0",
                    "gps_z": "100",
                    "gps_vx": "2",
                    "gps_vy": "1",
                    "gps_vz": "-8",
                    "warn_mask": "0",
                }
            )
            writer.writerow(
                {
                    "t_us": "1000000",
                    "phase": "3",
                    "est_h": "80",
                    "est_v": "-8",
                    "P00": "4",
                    "gps_x": "10",
                    "gps_y": "5",
                    "gps_z": "80",
                    "gps_vx": "2",
                    "gps_vy": "1",
                    "gps_vz": "-8",
                    "warn_mask": "0",
                }
            )
            writer.writerow(
                {
                    "t_us": "4000000",
                    "phase": "3",
                    "est_h": "50",
                    "est_v": "-8",
                    "P00": "4",
                    "gps_x": "",
                    "gps_y": "",
                    "gps_z": "50",
                    "gps_vx": "",
                    "gps_vy": "",
                    "gps_vz": "-8",
                    "warn_mask": "0",
                }
            )

        with vertical_only_log.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=["t_us", "phase", "est_h", "est_v", "P00", "warn_mask"])
            writer.writeheader()
            writer.writerow({"t_us": "0", "phase": "3", "est_h": "90", "est_v": "-9", "P00": "9", "warn_mask": "0"})
            writer.writerow({"t_us": "1000000", "phase": "3", "est_h": "72", "est_v": "-9", "P00": "9", "warn_mask": "0"})

        wind = module.wind_from_components(
            speed_mps=1.0,
            direction_deg=0.0,
            direction_convention="toward",
            sigma_mps=0.2,
            source="test",
        )
        samples = module.read_samples([horizontal_log])
        summary = module.build_summary(
            samples,
            wind=wind,
            configured_descent_rate_mps=8.0,
            min_descent_rate_mps=1.0,
            max_descent_time_s=600.0,
            descent_time_sigma_frac=0.10,
            assumed_horizontal_position_sigma_m=3.0,
            horizontal_velocity_sigma_mps=0.5,
            max_state_age_s=5.0,
        )
        svg = module.render_svg(samples, summary, title="landing footprint test")
        svg_path.write_text(svg, encoding="utf-8")
        module.write_json(json_path, samples, summary, wind)

        assert summary["final_label"] == "wind_relative_footprint_supported"
        assert abs(summary["selected_state_age_s"] - 3.0) < 1.0e-9
        assert abs(summary["descent_time_s"] - 10.0) < 1.0e-9
        assert abs(summary["predicted_landing_x_m"] - 30.0) < 1.0e-9
        assert abs(summary["predicted_landing_y_m"] - 15.0) < 1.0e-9
        assert abs(summary["no_wind_landing_x_m"] - 20.0) < 1.0e-9
        assert abs(summary["wind_drift_x_m"] - 10.0) < 1.0e-9
        assert abs(summary["air_relative_vx_mps"] - 1.0) < 1.0e-9
        assert summary["sigma_landing_x_m"] > 0.0
        assert "<svg" in svg
        assert "landing footprint test" in svg
        assert "observability gate" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000

        stale_summary = module.build_summary(
            samples,
            wind=wind,
            configured_descent_rate_mps=8.0,
            min_descent_rate_mps=1.0,
            max_descent_time_s=600.0,
            descent_time_sigma_frac=0.10,
            assumed_horizontal_position_sigma_m=3.0,
            horizontal_velocity_sigma_mps=0.5,
            max_state_age_s=2.0,
        )
        assert stale_summary["final_label"] == "horizontal_state_stale"

        vertical_samples = module.read_samples([vertical_only_log])
        vertical_summary = module.build_summary(
            vertical_samples,
            wind=wind,
            configured_descent_rate_mps=8.0,
            min_descent_rate_mps=1.0,
            max_descent_time_s=600.0,
            descent_time_sigma_frac=0.10,
            assumed_horizontal_position_sigma_m=3.0,
            horizontal_velocity_sigma_mps=0.5,
            max_state_age_s=2.0,
        )
        assert vertical_summary["final_label"] == "horizontal_state_unavailable"


def test_onboard_science_hud_pages_render_minimal_ready_pages() -> None:
    module = load_module("onboard_science_hud_pages", HUD_PAGES_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        log_path = Path(temp_dir) / "LOG_HUD_READY.CSV"
        plot_path = Path(temp_dir) / "PLOT_HUD_CAPTURE.txt"
        svg_path = Path(temp_dir) / "hud_pages.svg"
        json_path = Path(temp_dir) / "hud_pages.json"

        fields = [
            "t_us",
            "baro_valid",
            "imu_valid",
            "aux_valid",
            "mag_valid",
            "mag_interference",
            "est_valid",
            "policy_valid",
            "est_age_ms",
            "phase",
            "est_h",
            "est_v",
            "est_a",
            "P00",
            "target_effective",
            "apogee_no_brake",
            "apogee_full_brake",
            "apogee_error",
            "policy_cmd",
            "actuator_us",
            "lis_ax",
            "lis_ay",
            "lis_az",
            "mag_heading_deg",
            "mag_norm_uT",
            "safety_runtime_ok",
            "safety_allows_actuation",
            "sd_runtime_failed",
            "warn_mask",
        ]
        with log_path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerow(
                {
                    "t_us": "1000000",
                    "baro_valid": "1",
                    "imu_valid": "1",
                    "aux_valid": "1",
                    "mag_valid": "1",
                    "mag_interference": "0",
                    "est_valid": "1",
                    "policy_valid": "1",
                    "est_age_ms": "20",
                    "phase": str(COAST),
                    "est_h": "120",
                    "est_v": "35",
                    "est_a": "0.5",
                    "P00": "4",
                    "target_effective": "300",
                    "apogee_no_brake": "360",
                    "apogee_full_brake": "260",
                    "apogee_error": "60",
                    "policy_cmd": "0.42",
                    "actuator_us": "1420",
                    "lis_ax": "0",
                    "lis_ay": "0",
                    "lis_az": "9.80665",
                    "mag_heading_deg": "12",
                    "mag_norm_uT": "51",
                    "safety_runtime_ok": "1",
                    "safety_allows_actuation": "1",
                    "sd_runtime_failed": "0",
                    "warn_mask": "0",
                }
            )

        plot_path.write_text(
            "\n".join(
                [
                    "PLOT_HDR,HUD,t_ms,page,page_count,phase,valid_mask,warn_mask,est_h_m,est_v_mps,est_a_mps2,sigma_h_m,specific_energy_m,target_effective_m,target_margin_m,apogee_error_m,brake_authority_m,cmd01,actuator_us,roll_deg,pitch_deg,heading_deg,gravity_residual_mps2,mag_norm_uT,mag_interference,baro_age_ms,imu_age_ms,aux_age_ms,mag_age_ms,est_age_ms,safety_runtime_ok,safety_allows_actuation,sd_card_ok,sd_file_open,sd_runtime_failed,readiness_flags",
                    "PLOT,HUD,1000,0,4,2,511,0,120,35,0.5,2,182.46,300,180,60,100,0.42,1420,0,0,12,0,51,0,20,20,20,20,20,1,1,1,1,0,8191",
                ]
            ),
            encoding="utf-8",
        )

        samples = module.read_samples([log_path])
        summary = module.summarize_samples(samples)
        svg = module.render_svg(samples, summary, "hud page test")
        svg_path.write_text(svg, encoding="utf-8")
        module.write_json(json_path, samples, summary)

        assert summary["final_label"] == "hud_pages_ready"
        assert summary["page_readiness"]["flight"]
        assert summary["page_readiness"]["control"]
        assert summary["page_readiness"]["attitude"]
        assert abs(summary["latest"]["target_margin_m"] - 180.0) < 1.0e-9
        assert "<svg" in svg
        assert "PAGE 1 - FLIGHT" in svg
        assert "PAGE 4 - READINESS" in svg
        assert svg_path.exists() and svg_path.stat().st_size > 1000
        assert json_path.exists() and json_path.stat().st_size > 1000

        plot_samples = module.read_samples([plot_path])
        plot_summary = module.summarize_samples(plot_samples)
        assert len(plot_samples) == 1
        assert plot_summary["final_label"] == "hud_pages_ready"


def test_heldout_replay_validation_on_analytic_fixtures() -> None:
    module = load_module("heldout_replay_validation", HELDOUT_REPLAY_SCRIPT)

    with tempfile.TemporaryDirectory() as temp_dir:
        train_log = Path(temp_dir) / "LOG_TRAIN.CSV"
        heldout_log = Path(temp_dir) / "LOG_HELDOUT.CSV"
        write_analytic_aero_fixture(train_log, actual_apogee_m=300.0)
        write_analytic_aero_fixture(
            heldout_log,
            actual_apogee_m=340.0,
            phase_rows=[
                (70.0, 0.00, COAST),
                (115.0, 0.00, COAST),
                (160.0, 0.30, BRAKE),
                (205.0, 0.55, BRAKE),
                (250.0, 0.80, BRAKE),
                (295.0, 1.00, BRAKE),
            ],
        )

        result = module.validate_heldout(
            fit_logs=[train_log],
            heldout_logs=[heldout_log],
            mass_kg=POLICY_VEHICLE_MASS_KG,
            rho_kgpm3=POLICY_RHO_KGPM3,
            current_body_cda_m2=POLICY_CDA_BODY_M2,
            current_brake_cda_m2=POLICY_CDA_BRAKE_M2,
            closed_cmd_threshold=0.05,
            open_cmd_threshold=0.20,
            min_alt_m=POLICY_MIN_ALT_M,
            min_vz_mps=POLICY_MIN_VZ_MPS,
            max_rmse_m=0.001,
            max_abs_error_m=0.001,
            require_improvement=True,
        )

        assert result["comparison"]["passed"]
        assert abs(result["comparison"]["fitted_body_cda_m2"] - POLICY_CDA_BODY_M2) < 1.0e-4
        assert abs(result["comparison"]["fitted_brake_cda_m2"] - POLICY_CDA_BRAKE_M2) < 1.0e-4
        assert result["fitted_replay"]["aggregate"]["median_prediction_rmse_m"] < 1.0e-3


def test_firmware_loop_shim_replays_commands_phase_and_policy() -> None:
    module = load_module("firmware_in_loop_shim", FIRMWARE_LOOP_SHIM_SCRIPT)

    rows = [
        {"t_ms": "0", "serial": "ARM ARMED\nPOLICY 1\n", "est_h": "0", "est_v": "0", "imu_a_norm": "9.8"},
        {"t_ms": "100", "serial": "", "est_h": "3", "est_v": "8", "imu_a_norm": "30"},
        {"t_ms": "180", "serial": "", "est_h": "6", "est_v": "20", "imu_a_norm": "30"},
        {"t_ms": "500", "serial": "", "est_h": "100", "est_v": "100", "imu_a_norm": "12"},
        {"t_ms": "650", "serial": "", "est_h": "2400", "est_v": "250", "imu_a_norm": "12"},
        {"t_ms": "800", "serial": "", "est_h": "2430", "est_v": "230", "imu_a_norm": "12"},
    ]

    result = module.replay_rows(rows)
    responses = [item["response"] for item in result["command_responses"]]

    assert "ACK,ARM,ARMED" in responses
    assert "ACK,POLICY,1" in responses
    assert result["summary"]["parser_error_count"] == 0
    assert result["summary"]["policy_valid_count"] >= 1
    assert result["summary"]["max_policy_cmd"] > 0.0
    assert result["outputs"][-1]["phase"] in (COAST, BRAKE)


def run_test(name: str, fn) -> bool:
    try:
        fn()
    except Exception as exc:  # noqa: BLE001
        print(f"[FAIL] {name}: {exc}")
        return False
    print(f"[PASS] {name}")
    return True


def main() -> int:
    tests = [
        ("policy_valid_command_in_coast", test_policy_valid_command_in_coast),
        ("policy_invalid_when_disarmed", test_policy_stays_invalid_when_disarmed),
        ("phase_detector_reaches_coast_and_descent", test_phase_detector_reaches_coast_and_descent),
        ("command_overflow_discard_until_newline", test_command_overflow_discard_until_newline),
        ("source_integrations_present", test_source_integrations_present),
        ("hud_plot_schema_and_golden_row_contract", test_hud_plot_schema_and_golden_row_contract),
        ("sd_logger_p0_identification_schema_present", test_sd_logger_p0_identification_schema_present),
        ("policy_coast_sim_reduces_apogee_with_more_brake", test_policy_coast_sim_reduces_apogee_with_more_brake),
        ("plant_simulation_is_repeatable_and_faulted", test_plant_simulation_is_repeatable_and_faulted),
        ("apogee_evidence_view_renders_plant_log", test_apogee_evidence_view_renders_plant_log),
        ("apogee_prediction_residual_timeline_labels_model_error", test_apogee_prediction_residual_timeline_labels_model_error),
        ("estimator_policy_phase_space_view_renders_causal_plot_rows", test_estimator_policy_phase_space_view_renders_causal_plot_rows),
        ("provenance_evidence_view_renders_plant_log", test_provenance_evidence_view_renders_plant_log),
        ("ekf_innovation_covariance_dashboard_renders_estimator_plot_rows", test_ekf_innovation_covariance_dashboard_renders_estimator_plot_rows),
        ("temporal_freshness_latency_oscilloscope_renders_health_plot_rows", test_temporal_freshness_latency_oscilloscope_renders_health_plot_rows),
        ("energy_phase_view_renders_plant_log", test_energy_phase_view_renders_plant_log),
        ("phase_timeline_view_renders_plant_log", test_phase_timeline_view_renders_plant_log),
        ("health_dashboard_view_renders_faulted_plant_log", test_health_dashboard_view_renders_faulted_plant_log),
        ("orientation_vector_view_renders_plot_rows", test_orientation_vector_view_renders_plot_rows),
        ("magnetic_field_quality_view_renders_plot_rows", test_magnetic_field_quality_view_renders_plot_rows),
        ("gravity_norm_stability_view_renders_plot_rows", test_gravity_norm_stability_view_renders_plot_rows),
        ("sensor_frame_alignment_verifier_accepts_six_face_plot_rows", test_sensor_frame_alignment_verifier_accepts_six_face_plot_rows),
        ("readiness_gate_view_marks_uninstalled_sensors_truthfully", test_readiness_gate_view_marks_uninstalled_sensors_truthfully),
        ("tilt_compensated_heading_view_renders_current_schema_log", test_tilt_compensated_heading_view_renders_current_schema_log),
        ("tilt_compensated_heading_view_renders_plot_orient_rows", test_tilt_compensated_heading_view_renders_plot_orient_rows),
        ("heading_sign_calibration_validator_segments_controlled_pose_capture", test_heading_sign_calibration_validator_segments_controlled_pose_capture),
        ("previous_year_flight_data_audit_blocks_aero_fit", test_previous_year_flight_data_audit_blocks_aero_fit),
        ("empirical_aero_fit_on_analytic_fixture", test_empirical_aero_fit_on_analytic_fixture),
        ("coefficient_report_records_body_and_brake_residuals", test_coefficient_report_records_body_and_brake_residuals),
        ("aero_observability_map_classifies_analytic_fixture", test_aero_observability_map_classifies_analytic_fixture),
        ("wind_relative_landing_footprint_requires_horizontal_and_wind_evidence", test_wind_relative_landing_footprint_requires_horizontal_and_wind_evidence),
        ("onboard_science_hud_pages_render_minimal_ready_pages", test_onboard_science_hud_pages_render_minimal_ready_pages),
        ("heldout_replay_validation_on_analytic_fixtures", test_heldout_replay_validation_on_analytic_fixtures),
        ("firmware_loop_shim_replays_commands_phase_and_policy", test_firmware_loop_shim_replays_commands_phase_and_policy),
    ]

    failures = 0
    for name, fn in tests:
        if not run_test(name, fn):
            failures += 1

    if failures:
        print(f"{failures} host-side test(s) failed.")
        return 1

    print("All host-side tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

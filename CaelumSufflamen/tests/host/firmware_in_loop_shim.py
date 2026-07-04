from __future__ import annotations

import argparse
import csv
import json
import math
import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read_first_existing(*relative_paths: str) -> str:
    for relative_path in relative_paths:
        candidate = ROOT / relative_path
        if candidate.exists():
            return candidate.read_text(encoding="utf-8")
    joined = ", ".join(relative_paths)
    raise FileNotFoundError(f"Could not locate any expected source file: {joined}")


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


def parse_float_constant(text: str, name: str) -> float:
    return parse_numeric_literal(extract_constant(text, name))


def parse_int_constant(text: str, name: str) -> int:
    return int(round(parse_numeric_literal(extract_constant(text, name))))


CONFIG_H = read_first_existing("config.h", "utils/config.h")
FLIGHT_PHASE_CPP = read_first_existing("flight_phase.cpp", "src/flight_phase.cpp")

K_G = parse_float_constant(CONFIG_H, "kG")
CMD_BUF_N = parse_int_constant(CONFIG_H, "CMD_BUF_N")
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

FLIGHT_PHASE_BOOST_ACCEL_NORM_MPS2 = parse_float_constant(CONFIG_H, "FLIGHT_PHASE_BOOST_ACCEL_NORM_MPS2")
FLIGHT_PHASE_BOOST_MIN_ALT_M = parse_float_constant(CONFIG_H, "FLIGHT_PHASE_BOOST_MIN_ALT_M")
FLIGHT_PHASE_DESCENT_VZ_MPS = parse_float_constant(CONFIG_H, "FLIGHT_PHASE_DESCENT_VZ_MPS")
FLIGHT_PHASE_LAUNCH_MIN_VZ_MPS = parse_float_constant(FLIGHT_PHASE_CPP, "FLIGHT_PHASE_LAUNCH_MIN_VZ_MPS")
FLIGHT_PHASE_BURNOUT_ACCEL_NORM_MPS2 = parse_float_constant(
    FLIGHT_PHASE_CPP,
    "FLIGHT_PHASE_BURNOUT_ACCEL_NORM_MPS2",
)
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

PHASE_NAMES = {
    IDLE: "IDLE",
    BOOST: "BOOST",
    COAST: "COAST",
    BRAKE: "BRAKE",
    DESCENT: "DESCENT",
}


def clamp01(value: float) -> float:
    if not math.isfinite(value):
        return 0.0
    return min(1.0, max(0.0, value))


def parse_float_cell(row: dict[str, str], *names: str) -> float:
    for name in names:
        if name in row and row[name] not in ("", None):
            try:
                return float(row[name])
            except ValueError:
                return math.nan
    return math.nan


def parse_int_cell(row: dict[str, str], *names: str) -> int | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            try:
                return int(float(row[name]))
            except ValueError:
                return None
    return None


def policy_drag_k(command01: float) -> float:
    cda_m2 = POLICY_CDA_BODY_M2 + clamp01(command01) * POLICY_CDA_BRAKE_M2
    if POLICY_RHO_KGPM3 <= 0.0 or POLICY_VEHICLE_MASS_KG <= 0.0 or cda_m2 < 0.0:
        return 0.0
    return (POLICY_RHO_KGPM3 * cda_m2) / (2.0 * POLICY_VEHICLE_MASS_KG)


def predict_apogee_m(h_m: float, v_mps: float, command01: float) -> float:
    if not math.isfinite(h_m) or not math.isfinite(v_mps):
        return math.nan
    if v_mps <= 0.0:
        return h_m

    k_inv_m = policy_drag_k(command01)
    v2 = v_mps * v_mps
    if not math.isfinite(k_inv_m) or k_inv_m < 1.0e-7:
        return h_m + v2 / (2.0 * K_G)

    argument = 1.0 + (k_inv_m * v2) / K_G
    if not math.isfinite(argument) or argument <= 0.0:
        return math.nan
    return h_m + math.log(argument) / (2.0 * k_inv_m)


def solve_command01(h_m: float, v_mps: float, target_apogee_m: float) -> float:
    if not math.isfinite(h_m) or not math.isfinite(v_mps) or not math.isfinite(target_apogee_m):
        return 0.0
    if v_mps <= 0.0:
        return 0.0

    u_max = clamp01(POLICY_MAX_COMMAND01)
    apogee_u0 = predict_apogee_m(h_m, v_mps, 0.0)
    if not math.isfinite(apogee_u0):
        return 0.0
    if apogee_u0 <= target_apogee_m + POLICY_APOGEE_DEADBAND_M:
        return 0.0

    apogee_umax = predict_apogee_m(h_m, v_mps, u_max)
    if not math.isfinite(apogee_umax):
        return 0.0
    if apogee_umax > target_apogee_m:
        return u_max

    lo = 0.0
    hi = u_max
    for _ in range(POLICY_BISECTION_STEPS):
        mid = 0.5 * (lo + hi)
        apogee_mid = predict_apogee_m(h_m, v_mps, mid)
        if not math.isfinite(apogee_mid):
            return 0.0
        if apogee_mid > target_apogee_m:
            lo = mid
        else:
            hi = mid
    return clamp01(0.5 * (lo + hi))


class CommandParserShim:
    def __init__(self, max_len: int = CMD_BUF_N) -> None:
        self.max_len = max_len
        self.buffer: list[str] = []
        self.discarding = False
        self.errors: list[str] = []

    def feed(self, text: str) -> list[str]:
        commands: list[str] = []
        for ch in text:
            if ch in "\r\n":
                if self.discarding:
                    self.discarding = False
                    self.buffer.clear()
                    continue
                if self.buffer:
                    commands.append("".join(self.buffer))
                    self.buffer.clear()
                continue

            if self.discarding:
                continue

            if len(self.buffer) + 1 < self.max_len:
                self.buffer.append(ch)
            else:
                self.buffer.clear()
                self.discarding = True
                self.errors.append("ERR,CMD_TOO_LONG")

        return commands


class EstimatorShim:
    def __init__(self) -> None:
        self.valid = False
        self.seeded = False
        self.h_m = 0.0
        self.v_mps = 0.0
        self.a_mps2 = math.nan
        self.p00 = 1.0
        self.seq = 0
        self.previous_t_ms: int | None = None
        self.previous_h_m: float | None = None
        self.baro_reference_m: float | None = None

    def update(self, row: dict[str, str], now_ms: int) -> dict:
        recorded_h_m = parse_float_cell(row, "est_h", "est_h_m")
        recorded_v_mps = parse_float_cell(row, "est_v", "est_v_mps")
        a_mps2 = parse_float_cell(row, "est_a", "a_vertical", "a_vertical_mps2")

        if math.isfinite(recorded_h_m) and math.isfinite(recorded_v_mps):
            self.h_m = recorded_h_m
            self.v_mps = recorded_v_mps
            self.a_mps2 = a_mps2
            self.valid = True
            self.seeded = True
        else:
            baro_alt_m = parse_float_cell(row, "baro_alt_m", "bmp_alt")
            if not math.isfinite(baro_alt_m):
                self.valid = False
                return self.snapshot(now_ms, updated=False)

            if self.baro_reference_m is None:
                self.baro_reference_m = baro_alt_m

            h_m = baro_alt_m - self.baro_reference_m
            if self.previous_t_ms is not None and self.previous_h_m is not None and now_ms > self.previous_t_ms:
                dt_s = (now_ms - self.previous_t_ms) * 0.001
                self.v_mps = (h_m - self.previous_h_m) / dt_s
            else:
                self.v_mps = 0.0

            self.h_m = h_m
            self.a_mps2 = a_mps2
            self.valid = True
            self.seeded = True
            self.previous_t_ms = now_ms
            self.previous_h_m = h_m

        self.seq += 1
        return self.snapshot(now_ms, updated=True)

    def snapshot(self, now_ms: int, *, updated: bool) -> dict:
        return {
            "valid": self.valid,
            "updated": updated,
            "seeded": self.seeded,
            "seq": self.seq,
            "t_ms": now_ms,
            "h_m": self.h_m,
            "v_mps": self.v_mps,
            "a_mps2": self.a_mps2,
            "P00": self.p00,
        }


class FlightPhaseShim:
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
    def confirmed(condition: bool, now_ms: int, dwell_ms: int, candidate_ms: int) -> tuple[bool, int]:
        if not condition:
            return False, 0
        if candidate_ms == 0:
            candidate_ms = now_ms
        return (now_ms - candidate_ms) >= dwell_ms, candidate_ms

    def update(
        self,
        *,
        now_ms: int,
        est: dict,
        imu_valid: bool,
        imu_a_norm: float,
        previous_policy_valid: bool,
        previous_policy_cmd: float,
    ) -> int:
        if not est["valid"] or not imu_valid:
            if not self.launch_latched:
                self.launch_candidate_ms = 0
                self.phase = IDLE
            return self.phase

        h_m = float(est["h_m"])
        v_mps = float(est["v_mps"])
        if not all(math.isfinite(value) for value in (h_m, v_mps, imu_a_norm)):
            if not self.launch_latched:
                self.launch_candidate_ms = 0
                self.phase = IDLE
            return self.phase

        launch_condition = (
            (imu_a_norm >= FLIGHT_PHASE_BOOST_ACCEL_NORM_MPS2 and h_m >= FLIGHT_PHASE_BOOST_MIN_ALT_M)
            or (h_m >= FLIGHT_PHASE_BOOST_MIN_ALT_M and v_mps >= FLIGHT_PHASE_LAUNCH_MIN_VZ_MPS)
        )

        if not self.launch_latched:
            ok, self.launch_candidate_ms = self.confirmed(
                launch_condition,
                now_ms,
                FLIGHT_PHASE_LAUNCH_CONFIRM_MS,
                self.launch_candidate_ms,
            )
            if ok:
                self.launch_latched = True
                self.launch_latch_ms = now_ms
                self.phase = BOOST
            else:
                self.phase = IDLE
            return self.phase

        if not self.burnout_latched:
            boost_dwell_met = (now_ms - self.launch_latch_ms) >= FLIGHT_PHASE_MIN_BOOST_DWELL_MS
            burnout_condition = (
                boost_dwell_met
                and imu_a_norm <= FLIGHT_PHASE_BURNOUT_ACCEL_NORM_MPS2
                and h_m >= FLIGHT_PHASE_COAST_MIN_ALT_M
                and v_mps >= FLIGHT_PHASE_COAST_MIN_VZ_MPS
            )
            ok, self.burnout_candidate_ms = self.confirmed(
                burnout_condition,
                now_ms,
                FLIGHT_PHASE_BURNOUT_CONFIRM_MS,
                self.burnout_candidate_ms,
            )
            if ok:
                self.burnout_latched = True
                self.burnout_latch_ms = now_ms
                self.phase = COAST
            else:
                self.phase = BOOST
            return self.phase

        if not self.descent_latched:
            coast_dwell_met = (now_ms - self.burnout_latch_ms) >= FLIGHT_PHASE_MIN_COAST_DWELL_MS
            descent_condition = (
                coast_dwell_met
                and h_m >= FLIGHT_PHASE_COAST_MIN_ALT_M
                and v_mps <= FLIGHT_PHASE_DESCENT_VZ_MPS
            )
            ok, self.descent_candidate_ms = self.confirmed(
                descent_condition,
                now_ms,
                FLIGHT_PHASE_DESCENT_CONFIRM_MS,
                self.descent_candidate_ms,
            )
            if ok:
                self.descent_latched = True
                self.phase = DESCENT
                return self.phase

        if self.descent_latched:
            self.phase = DESCENT
            return self.phase

        brake_active = previous_policy_valid and previous_policy_cmd >= FLIGHT_PHASE_BRAKE_MIN_COMMAND01
        self.phase = BRAKE if brake_active else COAST
        return self.phase


class PolicyShim:
    def __init__(self) -> None:
        self.previous_command01 = 0.0
        self.previous_ms = 0

    def reset(self, now_ms: int) -> None:
        self.previous_command01 = 0.0
        self.previous_ms = now_ms

    def compute(
        self,
        *,
        now_ms: int,
        arm_state: int,
        policy_runtime_enabled: bool,
        software_arm_token: bool,
        phase: int,
        est: dict,
    ) -> dict:
        out = {
            "valid": False,
            "command01": 0.0,
            "predicted_apogee_no_brake_m": math.nan,
            "predicted_apogee_full_brake_m": math.nan,
            "target_apogee_m": math.nan,
        }

        if not policy_runtime_enabled or arm_state != ARMED or not software_arm_token:
            self.reset(now_ms)
            return out
        if phase not in (COAST, BRAKE):
            self.reset(now_ms)
            return out
        if not est["valid"] or not math.isfinite(est["h_m"]) or not math.isfinite(est["v_mps"]):
            self.reset(now_ms)
            return out
        if (now_ms - int(est["t_ms"])) > POLICY_MAX_EST_AGE_MS:
            self.reset(now_ms)
            return out
        if est["h_m"] < POLICY_MIN_ALT_M or est["v_mps"] < POLICY_MIN_VZ_MPS:
            self.reset(now_ms)
            return out

        uncertainty_margin_m = min(
            POLICY_MAX_UNCERTAINTY_MARGIN_M,
            max(0.0, POLICY_SIGMA_MARGIN_N * math.sqrt(max(0.0, float(est["P00"])))),
        )
        target_eff_m = max(0.0, POLICY_TARGET_APOGEE_M - uncertainty_margin_m)
        out["target_apogee_m"] = target_eff_m
        out["predicted_apogee_no_brake_m"] = predict_apogee_m(est["h_m"], est["v_mps"], 0.0)
        out["predicted_apogee_full_brake_m"] = predict_apogee_m(
            est["h_m"],
            est["v_mps"],
            clamp01(POLICY_MAX_COMMAND01),
        )

        desired = solve_command01(est["h_m"], est["v_mps"], target_eff_m)
        dt_s = (now_ms - self.previous_ms) * 0.001
        self.previous_ms = now_ms
        if not math.isfinite(dt_s) or dt_s < 0.0 or dt_s > 1.0:
            dt_s = 0.0

        max_step = POLICY_SLEW_PER_SEC * dt_s
        command01 = min(desired, self.previous_command01 + max_step)
        command01 = max(command01, self.previous_command01 - max_step)
        command01 = clamp01(command01)
        self.previous_command01 = command01

        if command01 > 0.0:
            out["valid"] = True
            out["command01"] = command01
        return out


@dataclass
class RuntimeState:
    arm_state: int = DISARMED
    software_arm_token: bool = False
    policy_runtime_enabled: bool = False
    previous_policy_valid: bool = False
    previous_policy_cmd: float = 0.0


def apply_command(line: str, state: RuntimeState, phase: int, policy: PolicyShim, now_ms: int) -> str:
    token, _, arg = line.strip().partition(" ")
    token = token.upper()
    arg = arg.strip()

    if token == "ARM":
        arm_arg = arg.upper()
        if arm_arg in ("DISARMED", "0"):
            state.arm_state = DISARMED
            state.software_arm_token = False
            state.policy_runtime_enabled = False
            policy.reset(now_ms)
            return "ACK,ARM,DISARMED"
        if arm_arg in ("SAFE", "1"):
            state.arm_state = SAFE
            state.software_arm_token = False
            state.policy_runtime_enabled = False
            policy.reset(now_ms)
            return "ACK,ARM,SAFE"
        if arm_arg in ("ARMED", "2"):
            if phase != IDLE:
                return "ERR,ARM,PHASE_NOT_IDLE"
            state.arm_state = ARMED
            state.software_arm_token = True
            policy.reset(now_ms)
            return "ACK,ARM,ARMED"
        return "ERR,ARM"

    if token == "POLICY":
        arg_upper = arg.upper()
        if arg_upper in ("1", "ON", "ENABLE"):
            state.policy_runtime_enabled = True
            return "ACK,POLICY,1"
        if arg_upper in ("0", "OFF", "DISABLE"):
            state.policy_runtime_enabled = False
            policy.reset(now_ms)
            return "ACK,POLICY,0"
        return "ERR,POLICY"

    if token == "HELP":
        return "ACK,HELP"
    if token == "STATUS":
        return "ACK,STATUS"
    return "ERR,UNKNOWN_CMD"


def replay_rows(rows: list[dict[str, str]]) -> dict:
    parser = CommandParserShim()
    estimator = EstimatorShim()
    phase_machine = FlightPhaseShim()
    policy = PolicyShim()
    runtime = RuntimeState()

    outputs: list[dict] = []
    command_responses: list[dict] = []

    for index, row in enumerate(rows):
        now_ms = parse_int_cell(row, "t_ms", "ms")
        if now_ms is None:
            t_us = parse_int_cell(row, "t_us")
            if t_us is None:
                raise ValueError(f"Row {index} is missing t_ms or t_us")
            now_ms = t_us // 1000

        for line in parser.feed(row.get("serial", "")):
            response = apply_command(line, runtime, phase_machine.phase, policy, now_ms)
            command_responses.append({"t_ms": now_ms, "command": line, "response": response})

        est = estimator.update(row, now_ms)
        imu_a_norm = parse_float_cell(row, "imu_a_norm", "a_norm")
        imu_valid = math.isfinite(imu_a_norm)

        phase = phase_machine.update(
            now_ms=now_ms,
            est=est,
            imu_valid=imu_valid,
            imu_a_norm=imu_a_norm,
            previous_policy_valid=runtime.previous_policy_valid,
            previous_policy_cmd=runtime.previous_policy_cmd,
        )

        policy_out = policy.compute(
            now_ms=now_ms,
            arm_state=runtime.arm_state,
            policy_runtime_enabled=runtime.policy_runtime_enabled,
            software_arm_token=runtime.software_arm_token,
            phase=phase,
            est=est,
        )
        runtime.previous_policy_valid = bool(policy_out["valid"])
        runtime.previous_policy_cmd = float(policy_out["command01"])

        outputs.append(
            {
                "row": index,
                "t_ms": now_ms,
                "arm_state": runtime.arm_state,
                "software_arm_token": int(runtime.software_arm_token),
                "policy_runtime_enabled": int(runtime.policy_runtime_enabled),
                "est_valid": int(est["valid"]),
                "est_h_m": est["h_m"],
                "est_v_mps": est["v_mps"],
                "imu_a_norm": imu_a_norm,
                "phase": phase,
                "phase_name": PHASE_NAMES.get(phase, "UNKNOWN"),
                "policy_valid": int(policy_out["valid"]),
                "policy_cmd": policy_out["command01"],
                "apogee_no_brake_m": policy_out["predicted_apogee_no_brake_m"],
                "apogee_full_brake_m": policy_out["predicted_apogee_full_brake_m"],
                "target_apogee_m": policy_out["target_apogee_m"],
            }
        )

    return {
        "row_count": len(rows),
        "parser_errors": parser.errors,
        "command_responses": command_responses,
        "outputs": outputs,
        "summary": {
            "final_phase": outputs[-1]["phase"] if outputs else IDLE,
            "final_phase_name": outputs[-1]["phase_name"] if outputs else "IDLE",
            "max_policy_cmd": max((row["policy_cmd"] for row in outputs), default=0.0),
            "policy_valid_count": sum(row["policy_valid"] for row in outputs),
            "executed_command_count": len(command_responses),
            "parser_error_count": len(parser.errors),
        },
    }


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, outputs: list[dict]) -> None:
    if not outputs:
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(outputs[0].keys()))
        writer.writeheader()
        writer.writerows(outputs)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay deterministic rows through a host firmware-loop shim."
    )
    parser.add_argument("input_csv", type=Path)
    parser.add_argument("--csv-out", type=Path)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    result = replay_rows(read_csv_rows(args.input_csv))

    if args.csv_out is not None:
        write_csv(args.csv_out, result["outputs"])

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")

    summary = result["summary"]
    print(f"rows={result['row_count']}")
    print(f"executed_commands={summary['executed_command_count']}")
    print(f"parser_errors={summary['parser_error_count']}")
    print(f"final_phase={summary['final_phase_name']}")
    print(f"policy_valid_count={summary['policy_valid_count']}")
    print(f"max_policy_cmd={summary['max_policy_cmd']:.6f}")
    return 0 if summary["parser_error_count"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

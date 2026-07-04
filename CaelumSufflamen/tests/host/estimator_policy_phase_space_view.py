from __future__ import annotations

import argparse
import csv
import html
import json
import math
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


PHASE_NAMES = {
    0: "IDLE",
    1: "BOOST",
    2: "COAST",
    3: "BRAKE",
    4: "DESCENT",
}

PHASE_COLORS = {
    0: "#94a3b8",
    1: "#dc2626",
    2: "#ea580c",
    3: "#7c3aed",
    4: "#2563eb",
}

UINT32_MAX = 4294967295.0
DEFAULT_STALE_AGE_MS = 200.0
DEFAULT_POLICY_MIN_ALT_M = 30.0
DEFAULT_POLICY_MIN_VZ_MPS = 15.0
DEFAULT_APOGEE_DEADBAND_M = 5.0

PLOT_APOGEE_HEADER = [
    "t_ms",
    "phase",
    "est_h_m",
    "est_v_mps",
    "baro_alt_m",
    "qbar_v_proxy_pa",
    "specific_energy_m",
    "mach_v_proxy",
    "pred_no_brake_m",
    "pred_full_brake_m",
    "target_effective_m",
    "target_nominal_m",
    "target_margin_m",
    "apogee_error_m",
    "brake_authority_m",
    "cmd01",
    "uncertainty_margin_m",
    "P00_m2",
    "P11_m2",
    "sigma_h_m",
    "baro_age_ms",
    "imu_age_ms",
    "est_age_ms",
    "policy_valid",
    "actuator_us",
    "valid_mask",
    "warn_mask",
]

GATE_ORDER = [
    "phase",
    "runtime",
    "armed",
    "estimator",
    "fresh",
    "altitude",
    "climb",
    "demand",
    "authority",
    "policy_valid",
    "command",
    "actuator",
]

GATE_LABELS = {
    "phase": "phase",
    "runtime": "runtime",
    "armed": "armed",
    "estimator": "est",
    "fresh": "fresh",
    "altitude": "alt",
    "climb": "vz",
    "demand": "demand",
    "authority": "authority",
    "policy_valid": "policy valid",
    "command": "cmd",
    "actuator": "actuator",
}


@dataclass
class CausalSample:
    t_s: float
    phase: int | None = None
    est_h_m: float = math.nan
    est_v_mps: float = math.nan
    baro_alt_m: float = math.nan
    pred_no_brake_m: float = math.nan
    pred_full_brake_m: float = math.nan
    target_effective_m: float = math.nan
    target_nominal_m: float = math.nan
    target_margin_m: float = math.nan
    apogee_error_m: float = math.nan
    brake_authority_m: float = math.nan
    cmd01: float = math.nan
    actuator_us: float = math.nan
    actuator01: float = math.nan
    uncertainty_margin_m: float = math.nan
    p00_m2: float = math.nan
    p11_m2: float = math.nan
    sigma_h_m: float = math.nan
    est_age_ms: float = math.nan
    policy_valid: bool | None = None
    policy_runtime_enabled: bool | None = None
    software_arm_token: bool | None = None
    arm_state: int | None = None
    est_valid: bool | None = None
    valid_mask: int | None = None
    warn_mask: int | None = None


def parse_float(value: object) -> float:
    if value is None:
        return math.nan
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if not text:
        return math.nan
    try:
        return float(text)
    except ValueError:
        return math.nan


def parse_int(value: object) -> int | None:
    value_f = parse_float(value)
    if not math.isfinite(value_f):
        return None
    return int(round(value_f))


def first_present(row: dict[str, str], *names: str) -> str | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    return None


def bool_cell(row: dict[str, str], *names: str) -> bool | None:
    value = parse_int(first_present(row, *names))
    if value is None:
        return None
    return value != 0


def finite_or_none(value: float) -> float | None:
    return float(value) if math.isfinite(value) else None


def json_safe(value: object) -> object:
    if isinstance(value, float):
        return finite_or_none(value)
    if isinstance(value, dict):
        return {str(key): json_safe(child) for key, child in value.items()}
    if isinstance(value, list):
        return [json_safe(child) for child in value]
    return value


def estimate_actuator01(actuator_us: float) -> float:
    if not math.isfinite(actuator_us):
        return math.nan
    return max(0.0, min(1.0, (actuator_us - 1000.0) / 1000.0))


def age_is_fresh(age_ms: float, stale_age_ms: float) -> bool | None:
    if not math.isfinite(age_ms):
        return None
    if age_ms >= UINT32_MAX:
        return False
    return age_ms <= stale_age_ms


def finite_values(samples: list[CausalSample], attr: str) -> list[float]:
    values: list[float] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            values.append(float(value))
    return values


def sample_from_row(row: dict[str, str]) -> CausalSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    pred_no_brake = parse_float(first_present(row, "apogee_no_brake", "pred_no_brake_m"))
    pred_full_brake = parse_float(first_present(row, "apogee_full_brake", "pred_full_brake_m"))
    brake_authority = parse_float(first_present(row, "brake_authority_m"))
    if not math.isfinite(brake_authority) and math.isfinite(pred_no_brake) and math.isfinite(pred_full_brake):
        brake_authority = pred_no_brake - pred_full_brake

    est_h = parse_float(first_present(row, "est_h", "est_h_m", "kf_h"))
    target_effective = parse_float(first_present(row, "target_effective", "target_apogee", "target_effective_m"))
    target_margin = parse_float(first_present(row, "target_margin_m"))
    if not math.isfinite(target_margin) and math.isfinite(target_effective) and math.isfinite(est_h):
        target_margin = target_effective - est_h

    apogee_error = parse_float(first_present(row, "apogee_error", "apogee_error_m"))
    if not math.isfinite(apogee_error) and math.isfinite(pred_no_brake) and math.isfinite(target_effective):
        apogee_error = pred_no_brake - target_effective

    p00 = parse_float(first_present(row, "P00", "P00_m2", "p00_m2"))
    p11 = parse_float(first_present(row, "P11", "P11_m2", "p11_m2"))
    sigma_h = parse_float(first_present(row, "sigma_h_m"))
    if not math.isfinite(sigma_h) and math.isfinite(p00) and p00 >= 0.0:
        sigma_h = math.sqrt(p00)

    actuator_us = parse_float(first_present(row, "actuator_us"))
    actuator01 = parse_float(first_present(row, "actuator01", "policy_cmd_applied"))
    if not math.isfinite(actuator01):
        actuator01 = estimate_actuator01(actuator_us)

    return CausalSample(
        t_s=t_s,
        phase=parse_int(first_present(row, "phase")),
        est_h_m=est_h,
        est_v_mps=parse_float(first_present(row, "est_v", "est_v_mps", "kf_v")),
        baro_alt_m=parse_float(first_present(row, "bmp_alt", "baro_alt_m", "bmp_alt_rel")),
        pred_no_brake_m=pred_no_brake,
        pred_full_brake_m=pred_full_brake,
        target_effective_m=target_effective,
        target_nominal_m=parse_float(first_present(row, "target_nominal", "target_nominal_m")),
        target_margin_m=target_margin,
        apogee_error_m=apogee_error,
        brake_authority_m=brake_authority,
        cmd01=parse_float(first_present(row, "policy_cmd", "cmd01")),
        actuator_us=actuator_us,
        actuator01=actuator01,
        uncertainty_margin_m=parse_float(first_present(row, "uncertainty_margin", "uncertainty_margin_m")),
        p00_m2=p00,
        p11_m2=p11,
        sigma_h_m=sigma_h,
        est_age_ms=parse_float(first_present(row, "est_age_ms")),
        policy_valid=bool_cell(row, "policy_valid"),
        policy_runtime_enabled=bool_cell(row, "policy_runtime_enabled"),
        software_arm_token=bool_cell(row, "software_arm_token"),
        arm_state=parse_int(first_present(row, "arm_state")),
        est_valid=bool_cell(row, "est_valid"),
        valid_mask=parse_int(first_present(row, "valid_mask")),
        warn_mask=parse_int(first_present(row, "warn_mask")),
    )


def read_sd_csv(path: Path) -> list[CausalSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    return [sample for row in reader if (sample := sample_from_row(row)) is not None]


def parse_plot_lines(lines: Iterable[str]) -> list[CausalSample]:
    header: list[str] | None = None
    samples: list[CausalSample] = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "APOGEE":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "APOGEE":
            continue
        active_header = header or PLOT_APOGEE_HEADER
        if len(parts) - 2 < len(active_header):
            continue
        sample = sample_from_row(dict(zip(active_header, parts[2:])))
        if sample is not None:
            samples.append(sample)
    return samples


def read_serial_lines(
    port: str,
    baud: int,
    duration_s: float | None,
    max_rows: int | None,
    serial_commands: list[str] | None = None,
    settle_s: float = 0.25,
) -> list[str]:
    try:
        import serial  # type: ignore
    except ImportError as exc:
        raise RuntimeError("Serial input requires pyserial. Install pyserial or capture PLOT lines to a text file.") from exc

    deadline = None if duration_s is None else time.monotonic() + duration_s
    lines: list[str] = []
    with serial.Serial(port, baudrate=baud, timeout=0.2) as handle:
        if settle_s > 0.0:
            time.sleep(settle_s)
        for command in serial_commands or []:
            text = command.strip()
            if text:
                handle.write((text + "\n").encode("ascii"))
                handle.flush()
                if settle_s > 0.0:
                    time.sleep(settle_s)
        while True:
            if deadline is not None and time.monotonic() >= deadline:
                break
            if max_rows is not None and len(lines) >= max_rows:
                break
            raw = handle.readline()
            if raw:
                lines.append(raw.decode("utf-8", errors="replace"))
    return lines


def read_samples(paths: list[Path], input_format: str) -> list[CausalSample]:
    all_samples: list[CausalSample] = []
    for path in paths:
        if input_format == "sd":
            all_samples.extend(read_sd_csv(path))
            continue
        if input_format == "plot":
            all_samples.extend(parse_plot_lines(path.read_text(encoding="utf-8", errors="replace").splitlines()))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        first_line = next((line for line in text.splitlines() if line.strip()), "")
        if first_line.startswith("PLOT_HDR") or first_line.startswith("PLOT,"):
            all_samples.extend(parse_plot_lines(text.splitlines()))
        else:
            all_samples.extend(read_sd_csv(path))
    return sorted(all_samples, key=lambda sample: sample.t_s)


def gate_states(
    sample: CausalSample,
    *,
    min_alt_m: float,
    min_vz_mps: float,
    stale_age_ms: float,
    apogee_deadband_m: float,
    actuator_tolerance01: float,
    command_threshold01: float,
) -> dict[str, bool | None]:
    phase_ok = sample.phase in (2, 3) if sample.phase is not None else None
    runtime_ok = sample.policy_runtime_enabled if sample.policy_runtime_enabled is not None else None
    armed_ok = None
    if sample.arm_state is not None:
        armed_ok = sample.arm_state == 2
    if sample.software_arm_token is not None:
        armed_ok = sample.software_arm_token if armed_ok is None else (armed_ok and sample.software_arm_token)
    estimator_ok = sample.est_valid if sample.est_valid is not None else (
        math.isfinite(sample.est_h_m) and math.isfinite(sample.est_v_mps)
    )
    fresh_ok = age_is_fresh(sample.est_age_ms, stale_age_ms)
    altitude_ok = sample.est_h_m >= min_alt_m if math.isfinite(sample.est_h_m) else None
    climb_ok = sample.est_v_mps >= min_vz_mps if math.isfinite(sample.est_v_mps) else None
    demand_ok = sample.apogee_error_m > apogee_deadband_m if math.isfinite(sample.apogee_error_m) else None
    authority_ok = sample.brake_authority_m > 0.0 if math.isfinite(sample.brake_authority_m) else None
    command_ok = sample.cmd01 > command_threshold01 if math.isfinite(sample.cmd01) else None
    actuator_ok = None
    if math.isfinite(sample.cmd01) and math.isfinite(sample.actuator01):
        actuator_ok = abs(sample.actuator01 - sample.cmd01) <= actuator_tolerance01
    elif math.isfinite(sample.cmd01) and sample.cmd01 <= command_threshold01 and not math.isfinite(sample.actuator01):
        actuator_ok = None

    return {
        "phase": phase_ok,
        "runtime": runtime_ok,
        "armed": armed_ok,
        "estimator": estimator_ok,
        "fresh": fresh_ok,
        "altitude": altitude_ok,
        "climb": climb_ok,
        "demand": demand_ok,
        "authority": authority_ok,
        "policy_valid": sample.policy_valid,
        "command": command_ok,
        "actuator": actuator_ok,
    }


def prerequisite_gates(states: dict[str, bool | None]) -> list[str]:
    return ["phase", "estimator", "altitude", "climb", "demand", "authority"]


def prerequisites_pass(states: dict[str, bool | None]) -> bool:
    required = prerequisite_gates(states)
    if states.get("runtime") is not None:
        required.append("runtime")
    if states.get("armed") is not None:
        required.append("armed")
    if states.get("fresh") is not None:
        required.append("fresh")
    return all(states.get(name) is True for name in required)


def summarize_samples(
    samples: list[CausalSample],
    *,
    min_alt_m: float,
    min_vz_mps: float,
    stale_age_ms: float,
    apogee_deadband_m: float,
    actuator_tolerance01: float,
    command_threshold01: float,
) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "final_label": "no_samples",
            "final_rationale": "No estimator-policy samples were available.",
        }

    gate_counts = {name: {"pass": 0, "fail": 0, "unknown": 0} for name in GATE_ORDER}
    prereq_pass_rows = 0
    command_rows = 0
    command_without_prereq_rows = 0
    actuator_mismatch_rows = 0
    policy_valid_rows = 0
    finite_prediction_rows = 0
    warn_rows = 0
    stale_rows = 0
    phase_counts: dict[str, int] = {}

    for sample in samples:
        phase_key = PHASE_NAMES.get(sample.phase, str(sample.phase))
        phase_counts[phase_key] = phase_counts.get(phase_key, 0) + 1
        if sample.warn_mask not in (None, 0):
            warn_rows += 1
        if age_is_fresh(sample.est_age_ms, stale_age_ms) is False:
            stale_rows += 1
        if math.isfinite(sample.pred_no_brake_m) and math.isfinite(sample.pred_full_brake_m):
            finite_prediction_rows += 1

        states = gate_states(
            sample,
            min_alt_m=min_alt_m,
            min_vz_mps=min_vz_mps,
            stale_age_ms=stale_age_ms,
            apogee_deadband_m=apogee_deadband_m,
            actuator_tolerance01=actuator_tolerance01,
            command_threshold01=command_threshold01,
        )
        prereq_ok = prerequisites_pass(states)
        if prereq_ok:
            prereq_pass_rows += 1
        if sample.policy_valid is True:
            policy_valid_rows += 1
        if math.isfinite(sample.cmd01) and sample.cmd01 > command_threshold01:
            command_rows += 1
            hard_violation_gates = ["phase", "runtime", "armed", "estimator", "fresh", "altitude", "climb", "authority"]
            hard_violation = any(states.get(name) is False for name in hard_violation_gates)
            if sample.policy_valid is not True and hard_violation:
                command_without_prereq_rows += 1
        if states.get("actuator") is False and math.isfinite(sample.cmd01) and sample.cmd01 > command_threshold01:
            actuator_mismatch_rows += 1

        for name in GATE_ORDER:
            state = states[name]
            if state is True:
                gate_counts[name]["pass"] += 1
            elif state is False:
                gate_counts[name]["fail"] += 1
            else:
                gate_counts[name]["unknown"] += 1

    blocker_candidates = ["phase", "runtime", "armed", "estimator", "fresh", "altitude", "climb", "demand", "authority"]
    primary_blocker = max(blocker_candidates, key=lambda name: gate_counts[name]["fail"])
    if gate_counts[primary_blocker]["fail"] == 0:
        primary_blocker = ""

    if finite_prediction_rows == 0:
        final_label = "prediction_fields_unavailable"
        rationale = "No finite no-brake/full-brake apogee prediction rows were available."
    elif command_without_prereq_rows > 0:
        final_label = "command_without_prerequisites"
        rationale = "One or more nonzero commands occurred when causal prerequisite gates did not all pass."
    elif actuator_mismatch_rows > 0:
        final_label = "actuator_mismatch"
        rationale = "Commanded deployment and actuator-normalized deployment differ beyond tolerance."
    elif prereq_pass_rows > 0 and command_rows > 0 and policy_valid_rows > 0:
        final_label = "causal_chain_supported"
        rationale = "Estimator state, policy prediction corridor, gating, command, and actuator evidence are causally aligned."
    elif prereq_pass_rows > 0 and command_rows == 0:
        final_label = "prerequisites_without_command"
        rationale = "Policy prerequisite gates pass at least once, but no nonzero command is visible."
    elif primary_blocker:
        final_label = f"blocked_by_{primary_blocker}"
        rationale = f"The dominant causal blocker is {GATE_LABELS.get(primary_blocker, primary_blocker)}."
    else:
        final_label = "policy_inactive_or_inconclusive"
        rationale = "The display could not identify a complete nonzero policy-command chain."

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "phase_counts": phase_counts,
        "max_est_h_m": max(finite_values(samples, "est_h_m"), default=math.nan),
        "max_est_v_mps": max(finite_values(samples, "est_v_mps"), default=math.nan),
        "max_pred_no_brake_m": max(finite_values(samples, "pred_no_brake_m"), default=math.nan),
        "min_pred_full_brake_m": min(finite_values(samples, "pred_full_brake_m"), default=math.nan),
        "max_brake_authority_m": max(finite_values(samples, "brake_authority_m"), default=math.nan),
        "max_apogee_error_m": max(finite_values(samples, "apogee_error_m"), default=math.nan),
        "max_cmd01": max(finite_values(samples, "cmd01"), default=math.nan),
        "max_actuator01": max(finite_values(samples, "actuator01"), default=math.nan),
        "finite_prediction_rows": finite_prediction_rows,
        "prerequisite_pass_rows": prereq_pass_rows,
        "policy_valid_rows": policy_valid_rows,
        "command_row_count": command_rows,
        "command_without_prereq_rows": command_without_prereq_rows,
        "actuator_mismatch_rows": actuator_mismatch_rows,
        "warn_row_count": warn_rows,
        "stale_est_row_count": stale_rows,
        "gate_counts": gate_counts,
        "primary_blocker": primary_blocker,
        "parameters": {
            "min_alt_m": min_alt_m,
            "min_vz_mps": min_vz_mps,
            "stale_age_ms": stale_age_ms,
            "apogee_deadband_m": apogee_deadband_m,
            "actuator_tolerance01": actuator_tolerance01,
            "command_threshold01": command_threshold01,
        },
        "final_label": final_label,
        "final_rationale": rationale,
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def bounds(values: list[float], minimum_span: float, include_zero: bool = False) -> tuple[float, float]:
    if include_zero:
        values = values + [0.0]
    if not values:
        return -minimum_span / 2.0, minimum_span / 2.0
    lo = min(values)
    hi = max(values)
    span = max(minimum_span, hi - lo)
    pad = 0.08 * span
    center = 0.5 * (lo + hi)
    return min(lo - pad, center - span / 2.0), max(hi + pad, center + span / 2.0)


def phase_space_bounds(samples: list[CausalSample]) -> tuple[float, float, float, float]:
    h_min, h_max = bounds(finite_values(samples, "est_h_m") + finite_values(samples, "target_effective_m"), 1.0, include_zero=True)
    v_min, v_max = bounds(finite_values(samples, "est_v_mps"), 1.0, include_zero=True)
    return h_min, h_max, v_min, v_max


def apogee_bounds(samples: list[CausalSample]) -> tuple[float, float]:
    values = (
        finite_values(samples, "pred_no_brake_m")
        + finite_values(samples, "pred_full_brake_m")
        + finite_values(samples, "target_effective_m")
        + finite_values(samples, "target_nominal_m")
    )
    return bounds(values, 1.0, include_zero=True)


def panel(x: float, y: float, w: float, h: float, title: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="#cbd5e1"/>'
        f'<text x="{x + 12}" y="{y + 24}" class="panel-title">{html.escape(title)}</text>'
    )


def polyline_time(samples: list[CausalSample], attr: str, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            points.append(f"{sx(sample.t_s):.2f},{sy(float(value)):.2f}")
    return " ".join(points)


def phase_space_segments(samples: list[CausalSample], sx, sy) -> str:
    segments: list[str] = []
    for left, right in zip(samples, samples[1:]):
        if not (
            math.isfinite(left.est_h_m)
            and math.isfinite(left.est_v_mps)
            and math.isfinite(right.est_h_m)
            and math.isfinite(right.est_v_mps)
        ):
            continue
        color = PHASE_COLORS.get(left.phase, "#64748b")
        segments.append(
            f'<line x1="{sx(left.est_h_m):.2f}" y1="{sy(left.est_v_mps):.2f}" '
            f'x2="{sx(right.est_h_m):.2f}" y2="{sy(right.est_v_mps):.2f}" stroke="{color}" stroke-width="2.2" opacity="0.85"/>'
        )
    return "\n".join(segments)


def command_points(samples: list[CausalSample], sx, sy, threshold: float) -> str:
    circles: list[str] = []
    for sample in samples:
        if not (math.isfinite(sample.est_h_m) and math.isfinite(sample.est_v_mps) and math.isfinite(sample.cmd01)):
            continue
        if sample.cmd01 <= threshold:
            continue
        radius = 3.0 + 5.0 * max(0.0, min(1.0, sample.cmd01))
        circles.append(
            f'<circle cx="{sx(sample.est_h_m):.2f}" cy="{sy(sample.est_v_mps):.2f}" r="{radius:.2f}" '
            'fill="#7c3aed" stroke="#ffffff" stroke-width="1" opacity="0.86"/>'
        )
    return "\n".join(circles)


def corridor_polygon(samples: list[CausalSample], sx, sy) -> str:
    upper: list[str] = []
    lower: list[str] = []
    for sample in samples:
        if math.isfinite(sample.pred_no_brake_m) and math.isfinite(sample.pred_full_brake_m):
            top = max(sample.pred_no_brake_m, sample.pred_full_brake_m)
            bottom = min(sample.pred_no_brake_m, sample.pred_full_brake_m)
            upper.append(f"{sx(sample.t_s):.2f},{sy(top):.2f}")
            lower.append(f"{sx(sample.t_s):.2f},{sy(bottom):.2f}")
    if len(upper) < 2:
        return ""
    return " ".join(upper + list(reversed(lower)))


def gate_raster(
    samples: list[CausalSample],
    sx,
    x: float,
    y: float,
    w: float,
    row_h: float,
    *,
    min_alt_m: float,
    min_vz_mps: float,
    stale_age_ms: float,
    apogee_deadband_m: float,
    actuator_tolerance01: float,
    command_threshold01: float,
) -> str:
    pieces: list[str] = []
    for row_index, gate in enumerate(GATE_ORDER):
        y0 = y + row_index * row_h
        pieces.append(f'<text x="{x}" y="{y0 + row_h - 4:.2f}" class="tiny">{html.escape(GATE_LABELS[gate])}</text>')
        pieces.append(f'<line x1="{x + 92}" y1="{y0 + row_h - 2:.2f}" x2="{x + w}" y2="{y0 + row_h - 2:.2f}" stroke="#e2e8f0"/>')
    for left, right in zip(samples, samples[1:]):
        states = gate_states(
            left,
            min_alt_m=min_alt_m,
            min_vz_mps=min_vz_mps,
            stale_age_ms=stale_age_ms,
            apogee_deadband_m=apogee_deadband_m,
            actuator_tolerance01=actuator_tolerance01,
            command_threshold01=command_threshold01,
        )
        x0 = sx(left.t_s)
        width = max(1.0, sx(right.t_s) - x0)
        for row_index, gate in enumerate(GATE_ORDER):
            state = states[gate]
            color = "#22c55e" if state is True else "#ef4444" if state is False else "#cbd5e1"
            opacity = "0.72" if state is not None else "0.50"
            pieces.append(
                f'<rect x="{x0:.2f}" y="{y + row_index * row_h:.2f}" width="{width:.2f}" height="{row_h - 2:.2f}" '
                f'fill="{color}" opacity="{opacity}"/>'
            )
    return "\n".join(pieces)


def warning_ticks(samples: list[CausalSample], sx, y0: float, y1: float) -> str:
    ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            ticks.append(f'<line x1="{x:.2f}" y1="{y0:.2f}" x2="{x:.2f}" y2="{y1:.2f}" stroke="#dc2626" stroke-width="1" opacity="0.22"/>')
    return "\n".join(ticks)


def legend_item(x: int, y: int, color: str, label: str, dashed: bool = False) -> str:
    dash = ' stroke-dasharray="6 5"' if dashed else ""
    return (
        f'<line x1="{x}" y1="{y}" x2="{x + 28}" y2="{y}" stroke="{color}" stroke-width="3"{dash}/>'
        f'<text x="{x + 36}" y="{y + 4}" class="legend">{html.escape(label)}</text>'
    )


def status_color(label: str) -> str:
    if label == "causal_chain_supported":
        return "#16a34a"
    if label in {"prerequisites_without_command", "policy_inactive_or_inconclusive"} or label.startswith("blocked_by_"):
        return "#f59e0b"
    return "#dc2626"


def render_svg(
    samples: list[CausalSample],
    summary: dict,
    title: str = "Estimator-Policy Causal Phase-Space Display",
) -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1220
    height = 860
    phase_panel = (84.0, 84.0, 500.0, 300.0)
    apogee_panel = (620.0, 84.0, 520.0, 300.0)
    gate_panel = (84.0, 430.0, 1056.0, 230.0)
    command_panel = (84.0, 695.0, 1056.0, 92.0)

    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    h_min, h_max, v_min, v_max = phase_space_bounds(samples)
    apogee_min, apogee_max = apogee_bounds(samples)
    sx_phase = scale_fn(h_min, h_max, phase_panel[0] + 44.0, phase_panel[0] + phase_panel[2] - 24.0)
    sy_phase = scale_fn(v_min, v_max, phase_panel[1] + phase_panel[3] - 36.0, phase_panel[1] + 42.0)
    sx_time = scale_fn(t_min, t_max, apogee_panel[0] + 34.0, apogee_panel[0] + apogee_panel[2] - 22.0)
    sy_apogee = scale_fn(apogee_min, apogee_max, apogee_panel[1] + apogee_panel[3] - 36.0, apogee_panel[1] + 42.0)
    sx_gate = scale_fn(t_min, t_max, gate_panel[0] + 98.0, gate_panel[0] + gate_panel[2] - 18.0)
    sx_command = scale_fn(t_min, t_max, command_panel[0] + 34.0, command_panel[0] + command_panel[2] - 20.0)
    sy_command = scale_fn(0.0, 1.05, command_panel[1] + command_panel[3] - 28.0, command_panel[1] + 28.0)

    corridor = corridor_polygon(samples, sx_time, sy_apogee)
    corridor_svg = f'<polygon points="{corridor}" fill="#bfdbfe" opacity="0.35"/>' if corridor else ""
    target_values = finite_values(samples, "target_effective_m")
    target_phase_line = ""
    if target_values:
        target_x = sx_phase(target_values[-1])
        target_phase_line = (
            f'<line x1="{target_x:.2f}" y1="{phase_panel[1] + 34:.2f}" '
            f'x2="{target_x:.2f}" y2="{phase_panel[1] + phase_panel[3] - 30:.2f}" '
            'stroke="#15803d" stroke-width="2" stroke-dasharray="7 5"/>'
        )

    verdict = summary["final_label"]
    verdict_color = status_color(verdict)
    parameters = summary["parameters"]
    gate_summary = " ".join(
        f"{GATE_LABELS[name]}={summary['gate_counts'][name]['pass']}/{summary['gate_counts'][name]['fail']}/{summary['gate_counts'][name]['unknown']}"
        for name in ("phase", "fresh", "altitude", "climb", "demand", "policy_valid", "command", "actuator")
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .panel-title {{ font: 700 14px Arial, sans-serif; fill: #0f172a; }}
  .axis-label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .legend {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
  .tiny {{ font: 11px Arial, sans-serif; fill: #334155; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="84" y="35" class="title">{html.escape(title)}</text>
<text x="84" y="56" class="subtitle">Estimator h/v state, policy prediction corridor, gate sequence, command, actuator, freshness, and warnings on one causal display.</text>
<rect x="84" y="806" width="1056" height="36" fill="#ffffff" stroke="{verdict_color}" stroke-width="3"/>
<text x="104" y="830" class="metric">final={html.escape(verdict)} | {html.escape(summary['final_rationale'])}</text>
{panel(*phase_panel, "estimator phase-space path")}
{panel(*apogee_panel, "apogee prediction corridor")}
{panel(*gate_panel, "causal gate raster: pass / fail / unknown")}
{panel(*command_panel, "command and actuator response")}
{target_phase_line}
{phase_space_segments(samples, sx_phase, sy_phase)}
{command_points(samples, sx_phase, sy_phase, parameters['command_threshold01'])}
{corridor_svg}
{warning_ticks(samples, sx_time, apogee_panel[1] + 36.0, apogee_panel[1] + apogee_panel[3] - 28.0)}
<polyline points="{polyline_time(samples, "pred_no_brake_m", sx_time, sy_apogee)}" fill="none" stroke="#dc2626" stroke-width="2"/>
<polyline points="{polyline_time(samples, "pred_full_brake_m", sx_time, sy_apogee)}" fill="none" stroke="#ea580c" stroke-width="2"/>
<polyline points="{polyline_time(samples, "target_effective_m", sx_time, sy_apogee)}" fill="none" stroke="#15803d" stroke-width="2" stroke-dasharray="7 5"/>
{gate_raster(samples, sx_gate, gate_panel[0] + 12.0, gate_panel[1] + 42.0, gate_panel[2] - 30.0, 14.0, min_alt_m=parameters['min_alt_m'], min_vz_mps=parameters['min_vz_mps'], stale_age_ms=parameters['stale_age_ms'], apogee_deadband_m=parameters['apogee_deadband_m'], actuator_tolerance01=parameters['actuator_tolerance01'], command_threshold01=parameters['command_threshold01'])}
{warning_ticks(samples, sx_command, command_panel[1] + 26.0, command_panel[1] + command_panel[3] - 24.0)}
<polyline points="{polyline_time(samples, "cmd01", sx_command, sy_command)}" fill="none" stroke="#7c3aed" stroke-width="2.5"/>
<polyline points="{polyline_time(samples, "actuator01", sx_command, sy_command)}" fill="none" stroke="#0f766e" stroke-width="2" stroke-dasharray="6 4"/>
<text x="260" y="400" class="axis-label">estimated altitude [m]</text>
<text x="30" y="258" class="axis-label" transform="rotate(-90 30 258)">estimated vertical velocity [m/s]</text>
<text x="850" y="400" class="axis-label">time [s]</text>
<text x="32" y="752" class="axis-label" transform="rotate(-90 32 752)">normalized command</text>
<text x="96" y="684" class="metric">samples={summary['sample_count']} prereq_pass={summary['prerequisite_pass_rows']} policy_valid={summary['policy_valid_rows']} command_rows={summary['command_row_count']} max_cmd={summary['max_cmd01']:.3f} max_authority={summary['max_brake_authority_m']:.2f}m warn_rows={summary['warn_row_count']} stale_est={summary['stale_est_row_count']}</text>
<text x="96" y="848" class="metric">{html.escape(gate_summary)}</text>
{legend_item(330, 32, "#7c3aed", "command samples")}
{legend_item(504, 32, "#dc2626", "no-brake apogee")}
{legend_item(690, 32, "#ea580c", "full-brake apogee")}
{legend_item(884, 32, "#15803d", "effective target", True)}
{legend_item(1030, 32, "#0f766e", "actuator", True)}
</svg>
"""


def write_json(path: Path, samples: list[CausalSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "estimator-policy-causal-phase-space-v1",
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(json_safe(payload), indent=2, sort_keys=True, allow_nan=False), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render an estimator-policy causal phase-space SVG/JSON view from current-schema SD CSV or captured PLOT APOGEE rows."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV or captured PLOT APOGEE text file.")
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
    parser.add_argument("--serial-port", help="Optional live serial port. Requires pyserial.")
    parser.add_argument("--serial-command", action="append", default=[], help="Command to send after opening serial. Repeatable.")
    parser.add_argument("--serial-settle-ms", type=int, default=250)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration-s", type=float, default=10.0)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--min-alt-m", type=float, default=DEFAULT_POLICY_MIN_ALT_M)
    parser.add_argument("--min-vz-mps", type=float, default=DEFAULT_POLICY_MIN_VZ_MPS)
    parser.add_argument("--stale-age-ms", type=float, default=DEFAULT_STALE_AGE_MS)
    parser.add_argument("--apogee-deadband-m", type=float, default=DEFAULT_APOGEE_DEADBAND_M)
    parser.add_argument("--actuator-tolerance01", type=float, default=0.15)
    parser.add_argument("--command-threshold01", type=float, default=0.01)
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Estimator-Policy Causal Phase-Space Display")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.serial_port:
        lines = read_serial_lines(
            args.serial_port,
            args.baud,
            args.duration_s,
            args.max_rows,
            args.serial_command,
            max(0.0, args.serial_settle_ms / 1000.0),
        )
        samples = parse_plot_lines(lines)
    else:
        if not args.input:
            raise SystemExit("Provide at least one input file or --serial-port.")
        samples = read_samples(args.input, args.input_format)

    if args.max_rows is not None:
        samples = samples[: args.max_rows]
    if not samples:
        raise SystemExit("No usable estimator-policy samples found.")

    summary = summarize_samples(
        samples,
        min_alt_m=args.min_alt_m,
        min_vz_mps=args.min_vz_mps,
        stale_age_ms=args.stale_age_ms,
        apogee_deadband_m=args.apogee_deadband_m,
        actuator_tolerance01=args.actuator_tolerance01,
        command_threshold01=args.command_threshold01,
    )
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, summary, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"prerequisite_pass_rows={summary['prerequisite_pass_rows']}")
    print(f"policy_valid_rows={summary['policy_valid_rows']}")
    print(f"command_row_count={summary['command_row_count']}")
    print(f"max_cmd01={summary['max_cmd01']:.3f}")
    print(f"primary_blocker={summary['primary_blocker']}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

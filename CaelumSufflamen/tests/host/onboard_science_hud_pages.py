from __future__ import annotations

import argparse
import csv
import html
import json
import math
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


K_G = 9.80665
SCHEMA_NAME = "onboard-minimal-science-hud-pages-v1"

PLOT_HUD_HEADER = [
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

PHASE_NAMES = {
    0: "IDLE",
    1: "BOOST",
    2: "COAST",
    3: "BRAKE",
    4: "DESCENT",
}

READINESS_BITS = [
    (0, "cfg"),
    (1, "est"),
    (2, "fresh"),
    (3, "phase"),
    (4, "policy"),
    (5, "safe_rt"),
    (6, "safe_act"),
    (7, "sd"),
    (8, "warn0"),
    (9, "aux"),
    (10, "mag"),
    (11, "baro"),
    (12, "imu"),
]


@dataclass
class HudSample:
    source: str
    index: int
    t_s: float
    page: int
    page_count: int
    phase: int | None
    valid_mask: int | None
    warn_mask: int | None
    est_h_m: float
    est_v_mps: float
    est_a_mps2: float
    sigma_h_m: float
    specific_energy_m: float
    target_effective_m: float
    target_margin_m: float
    apogee_error_m: float
    brake_authority_m: float
    cmd01: float
    actuator_us: float
    roll_deg: float
    pitch_deg: float
    heading_deg: float
    gravity_residual_mps2: float
    mag_norm_uT: float
    mag_interference: bool | None
    baro_age_ms: float
    imu_age_ms: float
    aux_age_ms: float
    mag_age_ms: float
    est_age_ms: float
    safety_runtime_ok: bool | None
    safety_allows_actuation: bool | None
    sd_card_ok: bool | None
    sd_file_open: bool | None
    sd_runtime_failed: bool | None
    readiness_flags: int | None


def parse_float(value: object) -> float:
    if value is None:
        return math.nan
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


def parse_bool(value: object) -> bool | None:
    value_i = parse_int(value)
    if value_i is None:
        return None
    return value_i != 0


def finite(value: float) -> bool:
    return math.isfinite(value)


def first_present(row: dict[str, str], *names: str) -> object | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    return None


def float_cell(row: dict[str, str], *names: str) -> float:
    return parse_float(first_present(row, *names))


def int_cell(row: dict[str, str], *names: str) -> int | None:
    return parse_int(first_present(row, *names))


def bool_cell(row: dict[str, str], *names: str) -> bool | None:
    return parse_bool(first_present(row, *names))


def row_time_s(row: dict[str, str], fallback_index: int) -> float:
    t_us = float_cell(row, "t_us")
    if finite(t_us):
        return t_us / 1_000_000.0
    t_ms = float_cell(row, "t_ms")
    if finite(t_ms):
        return t_ms / 1000.0
    return float(fallback_index)


def sigma_from_p00(row: dict[str, str]) -> float:
    p00 = float_cell(row, "P00", "p00")
    if finite(p00) and p00 >= 0.0:
        return math.sqrt(p00)
    return math.nan


def specific_energy(h_m: float, v_mps: float) -> float:
    if not finite(h_m) or not finite(v_mps):
        return math.nan
    return h_m + v_mps * v_mps / (2.0 * K_G)


def target_margin(target_effective_m: float, est_h_m: float) -> float:
    if not finite(target_effective_m) or not finite(est_h_m):
        return math.nan
    return target_effective_m - est_h_m


def derived_no_brake_apogee_m(sample: HudSample) -> float:
    if not finite(sample.target_effective_m) or not finite(sample.apogee_error_m):
        return math.nan
    return sample.target_effective_m + sample.apogee_error_m


def derived_full_brake_apogee_m(sample: HudSample) -> float:
    no_brake_m = derived_no_brake_apogee_m(sample)
    if not finite(no_brake_m) or not finite(sample.brake_authority_m):
        return math.nan
    return no_brake_m - sample.brake_authority_m


def brake_authority(no_brake_m: float, full_brake_m: float) -> float:
    if not finite(no_brake_m) or not finite(full_brake_m):
        return math.nan
    return no_brake_m - full_brake_m


def accel_roll_deg(row: dict[str, str]) -> float:
    ay = float_cell(row, "lis_ay", "aux_ay_mps2")
    az = float_cell(row, "lis_az", "aux_az_mps2")
    if not finite(ay) or not finite(az):
        return math.nan
    return math.degrees(math.atan2(ay, az))


def accel_pitch_deg(row: dict[str, str]) -> float:
    ax = float_cell(row, "lis_ax", "aux_ax_mps2")
    ay = float_cell(row, "lis_ay", "aux_ay_mps2")
    az = float_cell(row, "lis_az", "aux_az_mps2")
    if not finite(ax) or not finite(ay) or not finite(az):
        return math.nan
    yz_norm = math.hypot(ay, az)
    return math.degrees(math.atan2(-ax, yz_norm))


def aux_norm(row: dict[str, str]) -> float:
    value = float_cell(row, "aux_a_norm_mps2")
    if finite(value):
        return value
    ax = float_cell(row, "lis_ax")
    ay = float_cell(row, "lis_ay")
    az = float_cell(row, "lis_az")
    if finite(ax) and finite(ay) and finite(az):
        return math.sqrt(ax * ax + ay * ay + az * az)
    return math.nan


def plot_valid_mask(row: dict[str, str]) -> int:
    bit_fields = [
        "baro_valid",
        "imu_valid",
        "aux_valid",
        "pmod_accel_valid",
        "mag_valid",
        "att_valid",
        "auxvz_valid",
        "est_valid",
        "policy_valid",
    ]
    mask = 0
    for bit, name in enumerate(bit_fields):
        if bool_cell(row, name):
            mask |= 1 << bit
    return mask


def readiness_flags_from_row(row: dict[str, str], valid_mask: int, warn_mask: int | None) -> int:
    flags = 0
    phase = int_cell(row, "phase")
    est_age = float_cell(row, "est_age_ms")
    est_fresh = bool_cell(row, "est_valid") and (not finite(est_age) or est_age <= 1000.0)
    sd_ok = not bool_cell(row, "sd_runtime_failed")
    mag_good = bool_cell(row, "mag_valid") and not bool_cell(row, "mag_interference")

    if True:
        flags |= 1 << 0
    if bool_cell(row, "est_valid"):
        flags |= 1 << 1
    if est_fresh:
        flags |= 1 << 2
    if phase in (2, 3):
        flags |= 1 << 3
    if bool_cell(row, "policy_valid"):
        flags |= 1 << 4
    if bool_cell(row, "safety_runtime_ok"):
        flags |= 1 << 5
    if bool_cell(row, "safety_allows_actuation"):
        flags |= 1 << 6
    if sd_ok:
        flags |= 1 << 7
    if warn_mask == 0:
        flags |= 1 << 8
    if valid_mask & (1 << 2):
        flags |= 1 << 9
    if mag_good:
        flags |= 1 << 10
    if valid_mask & (1 << 0):
        flags |= 1 << 11
    if valid_mask & (1 << 1):
        flags |= 1 << 12
    return flags


def sample_from_sd_row(row: dict[str, str], source: str, index: int) -> HudSample:
    t_s = row_time_s(row, index)
    est_h = float_cell(row, "est_h", "est_h_m")
    est_v = float_cell(row, "est_v", "est_v_mps")
    target_effective = float_cell(row, "target_effective", "target_effective_m")
    no_brake = float_cell(row, "apogee_no_brake", "pred_no_brake_m")
    full_brake = float_cell(row, "apogee_full_brake", "pred_full_brake_m")
    warn_mask = int_cell(row, "warn_mask")
    valid_mask = plot_valid_mask(row)
    norm = aux_norm(row)
    flags = readiness_flags_from_row(row, valid_mask, warn_mask)

    return HudSample(
        source=source,
        index=index,
        t_s=t_s,
        page=index % 4,
        page_count=4,
        phase=int_cell(row, "phase"),
        valid_mask=valid_mask,
        warn_mask=warn_mask,
        est_h_m=est_h,
        est_v_mps=est_v,
        est_a_mps2=float_cell(row, "est_a", "est_a_mps2"),
        sigma_h_m=sigma_from_p00(row),
        specific_energy_m=specific_energy(est_h, est_v),
        target_effective_m=target_effective,
        target_margin_m=target_margin(target_effective, est_h),
        apogee_error_m=float_cell(row, "apogee_error", "apogee_error_m"),
        brake_authority_m=brake_authority(no_brake, full_brake),
        cmd01=float_cell(row, "policy_cmd_applied", "policy_cmd", "cmd01"),
        actuator_us=float_cell(row, "actuator_us"),
        roll_deg=accel_roll_deg(row),
        pitch_deg=accel_pitch_deg(row),
        heading_deg=float_cell(row, "mag_heading_deg", "heading_deg"),
        gravity_residual_mps2=norm - K_G if finite(norm) else math.nan,
        mag_norm_uT=float_cell(row, "mag_norm_uT"),
        mag_interference=bool_cell(row, "mag_interference"),
        baro_age_ms=float_cell(row, "baro_age_ms"),
        imu_age_ms=float_cell(row, "imu_age_ms"),
        aux_age_ms=float_cell(row, "aux_age_ms"),
        mag_age_ms=float_cell(row, "mag_age_ms"),
        est_age_ms=float_cell(row, "est_age_ms"),
        safety_runtime_ok=bool_cell(row, "safety_runtime_ok"),
        safety_allows_actuation=bool_cell(row, "safety_allows_actuation"),
        sd_card_ok=not bool_cell(row, "sd_runtime_failed"),
        sd_file_open=not bool_cell(row, "sd_runtime_failed"),
        sd_runtime_failed=bool_cell(row, "sd_runtime_failed"),
        readiness_flags=flags,
    )


def read_sd_csv(path: Path) -> list[HudSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    if reader.fieldnames is None:
        raise ValueError(f"{path} does not contain a readable CSV header")
    return [sample_from_sd_row(row, str(path), index) for index, row in enumerate(reader)]


def read_plot_hud_text(path: Path) -> list[HudSample]:
    header = PLOT_HUD_HEADER
    samples: list[HudSample] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = [part.strip() for part in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "HUD":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "HUD":
            continue
        row = dict(zip(header, parts[2:]))
        index = len(samples)
        samples.append(
            HudSample(
                source=str(path),
                index=index,
                t_s=float_cell(row, "t_ms") / 1000.0,
                page=int_cell(row, "page") or 0,
                page_count=int_cell(row, "page_count") or 4,
                phase=int_cell(row, "phase"),
                valid_mask=int_cell(row, "valid_mask"),
                warn_mask=int_cell(row, "warn_mask"),
                est_h_m=float_cell(row, "est_h_m"),
                est_v_mps=float_cell(row, "est_v_mps"),
                est_a_mps2=float_cell(row, "est_a_mps2"),
                sigma_h_m=float_cell(row, "sigma_h_m"),
                specific_energy_m=float_cell(row, "specific_energy_m"),
                target_effective_m=float_cell(row, "target_effective_m"),
                target_margin_m=float_cell(row, "target_margin_m"),
                apogee_error_m=float_cell(row, "apogee_error_m"),
                brake_authority_m=float_cell(row, "brake_authority_m"),
                cmd01=float_cell(row, "cmd01"),
                actuator_us=float_cell(row, "actuator_us"),
                roll_deg=float_cell(row, "roll_deg"),
                pitch_deg=float_cell(row, "pitch_deg"),
                heading_deg=float_cell(row, "heading_deg"),
                gravity_residual_mps2=float_cell(row, "gravity_residual_mps2"),
                mag_norm_uT=float_cell(row, "mag_norm_uT"),
                mag_interference=bool_cell(row, "mag_interference"),
                baro_age_ms=float_cell(row, "baro_age_ms"),
                imu_age_ms=float_cell(row, "imu_age_ms"),
                aux_age_ms=float_cell(row, "aux_age_ms"),
                mag_age_ms=float_cell(row, "mag_age_ms"),
                est_age_ms=float_cell(row, "est_age_ms"),
                safety_runtime_ok=bool_cell(row, "safety_runtime_ok"),
                safety_allows_actuation=bool_cell(row, "safety_allows_actuation"),
                sd_card_ok=bool_cell(row, "sd_card_ok"),
                sd_file_open=bool_cell(row, "sd_file_open"),
                sd_runtime_failed=bool_cell(row, "sd_runtime_failed"),
                readiness_flags=int_cell(row, "readiness_flags"),
            )
        )
    return samples


def is_plot_hud_text(path: Path) -> bool:
    try:
        for line in path.read_text(encoding="utf-8").splitlines()[:20]:
            if line.startswith("PLOT_HDR,HUD") or line.startswith("PLOT,HUD"):
                return True
    except UnicodeDecodeError:
        return False
    return False


def read_samples(paths: list[Path]) -> list[HudSample]:
    samples: list[HudSample] = []
    for path in paths:
        if is_plot_hud_text(path):
            samples.extend(read_plot_hud_text(path))
        else:
            samples.extend(read_sd_csv(path))
    for index, sample in enumerate(samples):
        sample.index = index
    return samples


def latest_sample(samples: list[HudSample]) -> HudSample | None:
    candidates = [sample for sample in samples if finite(sample.t_s)]
    if not candidates:
        return samples[-1] if samples else None
    return max(candidates, key=lambda sample: sample.t_s)


def page_ready(sample: HudSample, required_bits: list[int]) -> bool:
    if sample.readiness_flags is None:
        return False
    return all(sample.readiness_flags & (1 << bit) for bit in required_bits)


def summarize_samples(samples: list[HudSample]) -> dict[str, object]:
    sample = latest_sample(samples)
    if sample is None:
        return {
            "schema": SCHEMA_NAME,
            "sample_count": 0,
            "final_label": "telemetry_empty",
            "final_rationale": "No HUD or SD telemetry samples were available.",
        }

    flight_ready = page_ready(sample, [1, 2])
    control_ready = page_ready(sample, [3, 4, 5])
    attitude_ready = page_ready(sample, [9, 10])
    readiness_ready = sample.readiness_flags is not None
    warning_free = sample.warn_mask == 0

    if not flight_ready:
        final_label = "flight_page_not_ready"
        rationale = "Estimator state is missing or stale."
    elif not control_ready:
        final_label = "control_page_caution"
        rationale = "Policy, phase, or safety evidence is not ready for a control HUD page."
    elif not attitude_ready:
        final_label = "attitude_page_caution"
        rationale = "Auxiliary gravity or magnetic heading evidence is not ready."
    elif not warning_free:
        final_label = "warning_present"
        rationale = "HUD pages are populated, but warning mask is nonzero."
    else:
        final_label = "hud_pages_ready"
        rationale = "Flight, control, attitude, and readiness pages have the required evidence bits."

    return {
        "schema": SCHEMA_NAME,
        "sample_count": len(samples),
        "time_start_s": min((s.t_s for s in samples if finite(s.t_s)), default=None),
        "time_end_s": max((s.t_s for s in samples if finite(s.t_s)), default=None),
        "final_label": final_label,
        "final_rationale": rationale,
        "latest": asdict(sample),
        "apogee_authority_ladder": apogee_ladder_model(sample),
        "page_readiness": {
            "flight": flight_ready,
            "control": control_ready,
            "attitude": attitude_ready,
            "readiness": readiness_ready,
        },
        "readiness_bit_labels": {str(bit): label for bit, label in READINESS_BITS},
    }


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def fmt(value: object, digits: int = 1) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, float):
        if not finite(value):
            return "n/a"
        return f"{value:.{digits}f}"
    return str(value)


def phase_name(phase: int | None) -> str:
    return PHASE_NAMES.get(phase, "n/a")


def apogee_ladder_model(sample: HudSample) -> dict[str, object]:
    no_brake_m = derived_no_brake_apogee_m(sample)
    full_brake_m = derived_full_brake_apogee_m(sample)
    values = [
        sample.est_h_m,
        sample.target_effective_m,
        no_brake_m,
        full_brake_m,
    ]

    if finite(sample.est_h_m) and finite(sample.sigma_h_m):
        values.extend([sample.est_h_m - sample.sigma_h_m, sample.est_h_m + sample.sigma_h_m])

    finite_values = [value for value in values if finite(value)]
    if not finite_values:
        return {
            "ready": False,
            "rationale": "No finite altitude, target, or apogee prediction values were available.",
        }

    min_m = min(finite_values)
    max_m = max(finite_values)
    span_m = max_m - min_m
    pad_m = max(10.0, span_m * 0.12)
    min_m -= pad_m
    max_m += pad_m

    authority_bottom_m = math.nan
    authority_top_m = math.nan
    if finite(no_brake_m) and finite(full_brake_m):
        authority_bottom_m = min(no_brake_m, full_brake_m)
        authority_top_m = max(no_brake_m, full_brake_m)

    return {
        "ready": True,
        "min_m": min_m,
        "max_m": max_m,
        "now_m": sample.est_h_m,
        "target_m": sample.target_effective_m,
        "no_brake_m": no_brake_m,
        "full_brake_m": full_brake_m,
        "sigma_h_m": sample.sigma_h_m,
        "authority_bottom_m": authority_bottom_m,
        "authority_top_m": authority_top_m,
        "authority_span_m": sample.brake_authority_m,
        "command01": sample.cmd01,
        "actuator_us": sample.actuator_us,
        "target_margin_m": sample.target_margin_m,
        "apogee_error_m": sample.apogee_error_m,
    }


def apogee_ladder_svg(sample: HudSample, x: int, y: int, w: int, h: int) -> str:
    model = apogee_ladder_model(sample)
    if not model.get("ready"):
        return (
            f'<text x="{x}" y="{y + 18}" class="ladder-title">APOGEE AUTHORITY LADDER</text>'
            f'<text x="{x}" y="{y + 48}" class="ladder-label">insufficient prediction evidence</text>'
        )

    min_m = float(model["min_m"])
    max_m = float(model["max_m"])
    axis_x = x + 54
    top_y = y + 22
    bottom_y = y + h - 28

    def y_for(value: object) -> float:
        if not isinstance(value, (int, float)) or not finite(float(value)) or max_m <= min_m:
            return math.nan
        frac = (float(value) - min_m) / (max_m - min_m)
        frac = max(0.0, min(1.0, frac))
        return bottom_y - frac * (bottom_y - top_y)

    def marker(label: str, value: object, color: str, dx: int = 12) -> str:
        yy = y_for(value)
        if not finite(yy):
            return ""
        return "\n".join(
            [
                f'<line x1="{axis_x - 18}" y1="{yy:.2f}" x2="{axis_x + 18}" y2="{yy:.2f}" stroke="{color}" stroke-width="2"/>',
                f'<circle cx="{axis_x}" cy="{yy:.2f}" r="4" fill="{color}"/>',
                f'<text x="{axis_x + dx}" y="{yy - 4:.2f}" class="ladder-label">{esc(label)}</text>',
                f'<text x="{axis_x + dx}" y="{yy + 10:.2f}" class="ladder-value">{esc(fmt(value))} m</text>',
            ]
        )

    authority_bottom_y = y_for(model["authority_bottom_m"])
    authority_top_y = y_for(model["authority_top_m"])
    authority_rect = ""
    if finite(authority_bottom_y) and finite(authority_top_y):
        rect_y = min(authority_top_y, authority_bottom_y)
        rect_h = max(2.0, abs(authority_bottom_y - authority_top_y))
        authority_rect = (
            f'<rect x="{axis_x - 12}" y="{rect_y:.2f}" width="24" height="{rect_h:.2f}" '
            'fill="#f59e0b" opacity="0.30" stroke="#f59e0b" stroke-width="1"/>'
        )

    sigma_rect = ""
    if finite(sample.est_h_m) and finite(sample.sigma_h_m):
        sigma_low_y = y_for(sample.est_h_m - sample.sigma_h_m)
        sigma_high_y = y_for(sample.est_h_m + sample.sigma_h_m)
        if finite(sigma_low_y) and finite(sigma_high_y):
            rect_y = min(sigma_low_y, sigma_high_y)
            rect_h = max(2.0, abs(sigma_low_y - sigma_high_y))
            sigma_rect = (
                f'<rect x="{axis_x - 30}" y="{rect_y:.2f}" width="60" height="{rect_h:.2f}" '
                'fill="#38bdf8" opacity="0.18" stroke="#38bdf8" stroke-width="1"/>'
            )

    command_fill_w = 0.0
    if finite(sample.cmd01):
        command_fill_w = max(0.0, min(1.0, sample.cmd01)) * (w - 28)

    return "\n".join(
        [
            f'<text x="{x}" y="{y + 12}" class="ladder-title">APOGEE AUTHORITY LADDER</text>',
            f'<line x1="{axis_x}" y1="{top_y}" x2="{axis_x}" y2="{bottom_y}" stroke="#64748b" stroke-width="3"/>',
            authority_rect,
            sigma_rect,
            marker("no brake", model["no_brake_m"], "#ef4444"),
            marker("target", model["target_m"], "#22c55e"),
            marker("full brake", model["full_brake_m"], "#a855f7"),
            marker("now", model["now_m"], "#38bdf8", -70),
            f'<rect x="{x}" y="{y + h - 15}" width="{w - 28}" height="8" rx="4" fill="#1e293b" stroke="#475569"/>',
            f'<rect x="{x}" y="{y + h - 15}" width="{command_fill_w:.2f}" height="8" rx="4" fill="#f97316"/>',
            f'<text x="{x}" y="{y + h + 6}" class="ladder-label">u={esc(fmt(sample.cmd01, 2))} act={esc(fmt(sample.actuator_us, 0))}us</text>',
        ]
    )


def panel(x: int, y: int, w: int, h: int, title: str, ready: bool) -> str:
    stroke = "#16a34a" if ready else "#f59e0b"
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="#0f172a" stroke="{stroke}" stroke-width="3"/>'
        f'<text x="{x + 18}" y="{y + 34}" class="panel-title">{esc(title)}</text>'
        f'<circle cx="{x + w - 28}" cy="{y + 24}" r="8" fill="{stroke}"/>'
    )


def text_line(x: int, y: int, label: str, value: object, unit: str = "", emph: bool = False) -> str:
    cls = "metric-emph" if emph else "metric"
    suffix = f" {unit}" if unit else ""
    return (
        f'<text x="{x}" y="{y}" class="label">{esc(label)}</text>'
        f'<text x="{x + 170}" y="{y}" class="{cls}">{esc(fmt(value))}{esc(suffix)}</text>'
    )


def readiness_chips(sample: HudSample, x: int, y: int) -> str:
    parts: list[str] = []
    flags = sample.readiness_flags or 0
    for idx, (bit, label) in enumerate(READINESS_BITS):
        col = idx % 5
        row = idx // 5
        xx = x + col * 82
        yy = y + row * 31
        ok = bool(flags & (1 << bit))
        fill = "#166534" if ok else "#7f1d1d"
        parts.append(f'<rect x="{xx}" y="{yy}" width="70" height="22" rx="4" fill="{fill}" stroke="#334155"/>')
        parts.append(f'<text x="{xx + 35}" y="{yy + 15}" text-anchor="middle" class="chip">{esc(label)}</text>')
    return "\n".join(parts)


def render_svg(samples: list[HudSample], summary: dict[str, object], title: str) -> str:
    sample = latest_sample(samples)
    width, height = 980, 720
    if sample is None:
        return "\n".join(
            [
                f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
                '<rect x="0" y="0" width="980" height="720" fill="#f8fafc"/>',
                f'<text x="48" y="42" font-family="Arial" font-size="28" font-weight="700" fill="#0f172a">{esc(title)}</text>',
                '<text x="48" y="96" font-family="Arial" font-size="18" fill="#dc2626">No HUD or SD telemetry samples were available.</text>',
                "</svg>",
            ]
        )

    ready = summary.get("page_readiness", {})
    flight_ready = bool(ready.get("flight")) if isinstance(ready, dict) else False
    control_ready = bool(ready.get("control")) if isinstance(ready, dict) else False
    attitude_ready = bool(ready.get("attitude")) if isinstance(ready, dict) else False
    readiness_ready = bool(ready.get("readiness")) if isinstance(ready, dict) else False

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text { font-family: Arial, Helvetica, sans-serif; }",
        ".title { font-size: 28px; font-weight: 700; fill: #0f172a; }",
        ".subtitle { font-size: 14px; fill: #334155; }",
        ".panel-title { font-size: 19px; font-weight: 700; fill: #f8fafc; }",
        ".label { font-size: 13px; fill: #cbd5e1; }",
        ".metric { font-size: 18px; font-weight: 700; fill: #f8fafc; }",
        ".metric-emph { font-size: 30px; font-weight: 800; fill: #f8fafc; }",
        ".chip { font-size: 11px; fill: #f8fafc; }",
        ".mono { font-family: Consolas, Menlo, monospace; font-size: 12px; fill: #334155; }",
        "</style>",
        '<rect x="0" y="0" width="980" height="720" fill="#f8fafc"/>',
        f'<text x="48" y="42" class="title">{esc(title)}</text>',
        '<text x="48" y="64" class="subtitle">Four compact onboard pages derived from fixed telemetry evidence, not decorative gauges.</text>',
        panel(48, 92, 420, 240, "PAGE 1 - FLIGHT", flight_ready),
        panel(512, 92, 420, 240, "PAGE 2 - APOGEE / CONTROL", control_ready),
        panel(48, 366, 420, 240, "PAGE 3 - ATTITUDE / FIELD", attitude_ready),
        panel(512, 366, 420, 240, "PAGE 4 - READINESS", readiness_ready),
        text_line(72, 154, "phase", phase_name(sample.phase), emph=True),
        text_line(72, 203, "altitude", sample.est_h_m, "m"),
        text_line(72, 232, "vertical speed", sample.est_v_mps, "m/s"),
        text_line(72, 261, "sigma altitude", sample.sigma_h_m, "m"),
        text_line(72, 290, "specific energy", sample.specific_energy_m, "m"),
        text_line(536, 154, "target", sample.target_effective_m, "m"),
        text_line(536, 183, "target margin", sample.target_margin_m, "m"),
        text_line(536, 212, "apogee error", sample.apogee_error_m, "m"),
        text_line(536, 241, "brake authority", sample.brake_authority_m, "m"),
        text_line(536, 270, "command", sample.cmd01, "", emph=True),
        text_line(536, 310, "actuator", sample.actuator_us, "us"),
        text_line(72, 428, "roll", sample.roll_deg, "deg"),
        text_line(72, 457, "pitch", sample.pitch_deg, "deg"),
        text_line(72, 486, "heading", sample.heading_deg, "deg", emph=True),
        text_line(72, 527, "gravity residual", sample.gravity_residual_mps2, "m/s^2"),
        text_line(72, 556, "mag norm", sample.mag_norm_uT, "uT"),
        text_line(72, 585, "mag interference", sample.mag_interference),
        readiness_chips(sample, 536, 424),
        text_line(536, 552, "warn mask", sample.warn_mask),
        text_line(536, 581, "safety allows", sample.safety_allows_actuation),
        f'<text x="48" y="660" class="mono">label={esc(summary.get("final_label"))} | {esc(summary.get("final_rationale"))}</text>',
        f'<text x="48" y="682" class="mono">samples={len(samples)} latest_t={fmt(sample.t_s, 3)}s readiness_flags={fmt(sample.readiness_flags)}</text>',
        "</svg>",
    ]
    return "\n".join(parts)


def json_safe(value: object) -> object:
    if isinstance(value, float):
        return value if finite(value) else None
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    return value


def write_json(path: Path, samples: list[HudSample], summary: dict[str, object]) -> None:
    payload = {"schema": SCHEMA_NAME, "summary": summary, "samples": [asdict(sample) for sample in samples]}
    path.write_text(json.dumps(json_safe(payload), indent=2, sort_keys=True), encoding="utf-8")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render onboard minimal science HUD pages from SD CSV or captured PLOT HUD rows.")
    parser.add_argument("input", nargs="+", type=Path)
    parser.add_argument("--svg-out", type=Path, default=None)
    parser.add_argument("--json-out", type=Path, default=None)
    parser.add_argument("--title", default="Onboard Minimal Science HUD Pages")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    samples = read_samples(args.input)
    summary = summarize_samples(samples)

    if args.svg_out is not None:
        args.svg_out.parent.mkdir(parents=True, exist_ok=True)
        args.svg_out.write_text(render_svg(samples, summary, args.title), encoding="utf-8")
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        write_json(args.json_out, samples, summary)

    print(f"samples={summary.get('sample_count')}")
    print(f"final_label={summary.get('final_label')}")
    print(f"final_rationale={summary.get('final_rationale')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

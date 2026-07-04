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


K_G_MPS2 = 9.80665
WARN_MAG_FAULT_BIT = 12
DEFAULT_PLOT_ORIENT_HEADER = [
    "t_ms",
    "valid_mask",
    "warn_mask",
    "aux_ax_mps2",
    "aux_ay_mps2",
    "aux_az_mps2",
    "aux_a_norm_mps2",
    "accel_roll_deg",
    "accel_pitch_deg",
    "mag_x_uT",
    "mag_y_uT",
    "mag_z_uT",
    "mag_norm_uT",
    "mag_heading_deg",
    "mag_interference",
    "aux_age_ms",
    "mag_age_ms",
]


@dataclass
class HeadingSample:
    t_s: float
    att_valid: bool
    aux_valid: bool
    mag_valid: bool
    mag_interference: bool
    warn_mask: int | None
    roll_deg: float
    pitch_deg: float
    yaw_deg: float
    q_norm_error: float
    accel_norm_mps2: float
    gravity_residual_mps2: float
    mag_x_uT: float
    mag_y_uT: float
    mag_z_uT: float
    mag_norm_uT: float
    planar_heading_deg: float
    tilt_heading_deg: float
    heading_delta_deg: float
    attitude_ready: bool
    gravity_ready: bool
    magnetic_ready: bool
    heading_ready: bool
    quality_label: str
    rationale: str


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


def first_present(row: dict[str, str], *names: str) -> str | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    return None


def bool_cell(row: dict[str, str], *names: str) -> bool:
    value = parse_int(first_present(row, *names))
    return value is not None and value != 0


def wrap360(deg: float) -> float:
    if not math.isfinite(deg):
        return math.nan
    wrapped = deg % 360.0
    if wrapped < 0.0:
        wrapped += 360.0
    return wrapped


def signed_angle_delta_deg(a_deg: float, b_deg: float) -> float:
    if not math.isfinite(a_deg) or not math.isfinite(b_deg):
        return math.nan
    return ((a_deg - b_deg + 180.0) % 360.0) - 180.0


def quaternion_to_euler_zyx(q0: float, q1: float, q2: float, q3: float) -> tuple[float, float, float, float]:
    norm = math.sqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3)
    if not math.isfinite(norm) or norm < 1.0e-9:
        return math.nan, math.nan, math.nan, math.nan

    qw = q0 / norm
    qx = q1 / norm
    qy = q2 / norm
    qz = q3 / norm

    sinr_cosp = 2.0 * (qw * qx + qy * qz)
    cosr_cosp = 1.0 - 2.0 * (qx * qx + qy * qy)
    roll = math.atan2(sinr_cosp, cosr_cosp)

    sinp = 2.0 * (qw * qy - qz * qx)
    sinp = max(-1.0, min(1.0, sinp))
    pitch = math.asin(sinp)

    siny_cosp = 2.0 * (qw * qz + qx * qy)
    cosy_cosp = 1.0 - 2.0 * (qy * qy + qz * qz)
    yaw = math.atan2(siny_cosp, cosy_cosp)

    return math.degrees(roll), math.degrees(pitch), math.degrees(yaw), abs(norm - 1.0)


def tilt_compensated_heading_deg(
    mag_x_uT: float,
    mag_y_uT: float,
    mag_z_uT: float,
    roll_deg: float,
    pitch_deg: float,
) -> float:
    if not all(math.isfinite(v) for v in (mag_x_uT, mag_y_uT, mag_z_uT, roll_deg, pitch_deg)):
        return math.nan

    roll = math.radians(roll_deg)
    pitch = math.radians(pitch_deg)

    x_h = mag_x_uT * math.cos(pitch) + mag_z_uT * math.sin(pitch)
    y_h = (
        mag_x_uT * math.sin(roll) * math.sin(pitch)
        + mag_y_uT * math.cos(roll)
        - mag_z_uT * math.sin(roll) * math.cos(pitch)
    )

    if abs(x_h) < 1.0e-12 and abs(y_h) < 1.0e-12:
        return math.nan

    return wrap360(math.degrees(math.atan2(y_h, x_h)))


def classify_sample(
    *,
    att_valid: bool,
    aux_valid: bool,
    mag_valid: bool,
    mag_interference: bool,
    warn_mask: int | None,
    q_norm_error: float,
    gravity_residual_mps2: float,
    mag_norm_uT: float,
    tilt_heading_deg: float,
    gravity_tolerance_mps2: float,
    mag_norm_min_uT: float,
    mag_norm_max_uT: float,
    max_q_norm_error: float,
) -> tuple[bool, bool, bool, bool, str, str]:
    attitude_ready = (
        att_valid
        and math.isfinite(q_norm_error)
        and q_norm_error <= max_q_norm_error
    )
    gravity_ready = (
        aux_valid
        and math.isfinite(gravity_residual_mps2)
        and abs(gravity_residual_mps2) <= gravity_tolerance_mps2
    )
    magnetic_ready = (
        mag_valid
        and not mag_interference
        and (warn_mask is None or not bool(warn_mask & (1 << WARN_MAG_FAULT_BIT)))
        and math.isfinite(mag_norm_uT)
        and mag_norm_min_uT <= mag_norm_uT <= mag_norm_max_uT
    )

    heading_ready = (
        attitude_ready
        and gravity_ready
        and magnetic_ready
        and math.isfinite(tilt_heading_deg)
    )

    if not att_valid:
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "attitude_invalid", "Attitude snapshot is invalid."
    if not math.isfinite(q_norm_error) or q_norm_error > max_q_norm_error:
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "quaternion_norm_bad", "Attitude quaternion norm is outside tolerance."
    if not mag_valid:
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "mag_invalid", "Magnetometer snapshot is invalid."
    if mag_interference:
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "mag_interference", "Magnetometer interference flag is asserted."
    if warn_mask is not None and bool(warn_mask & (1 << WARN_MAG_FAULT_BIT)):
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "mag_warning", "Warning mask marks the magnetometer evidence as faulted."
    if not math.isfinite(mag_norm_uT) or not (mag_norm_min_uT <= mag_norm_uT <= mag_norm_max_uT):
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "mag_norm_bad", "Magnetic-field norm is outside the configured quality band."
    if not aux_valid:
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "gravity_missing", "Auxiliary accelerometer gravity evidence is invalid."
    if not math.isfinite(gravity_residual_mps2) or abs(gravity_residual_mps2) > gravity_tolerance_mps2:
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "gravity_unstable", "Acceleration norm is not close enough to gravity for tilt-compass evidence."
    if not math.isfinite(tilt_heading_deg):
        return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "heading_unavailable", "Tilt-compensated heading could not be computed."
    return attitude_ready, gravity_ready, magnetic_ready, heading_ready, "heading_ready", "Tilt-compensated heading prerequisites are all satisfied."


def sample_from_row(
    row: dict[str, str],
    *,
    gravity_tolerance_mps2: float,
    mag_norm_min_uT: float,
    mag_norm_max_uT: float,
    max_q_norm_error: float,
) -> HeadingSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    valid_mask = parse_int(first_present(row, "valid_mask"))
    att_valid_cell = first_present(row, "att_valid")
    aux_valid_cell = first_present(row, "aux_valid")
    mag_valid_cell = first_present(row, "mag_valid")
    att_valid = bool_cell(row, "att_valid")
    aux_valid = bool_cell(row, "aux_valid")
    mag_valid = bool_cell(row, "mag_valid")
    if valid_mask is not None:
        if aux_valid_cell is None:
            aux_valid = bool(valid_mask & (1 << 2))
        if mag_valid_cell is None:
            mag_valid = bool(valid_mask & (1 << 4))
    mag_interference = bool_cell(row, "mag_interference")
    warn_mask = parse_int(first_present(row, "warn_mask"))

    q0 = parse_float(first_present(row, "q0"))
    q1 = parse_float(first_present(row, "q1"))
    q2 = parse_float(first_present(row, "q2"))
    q3 = parse_float(first_present(row, "q3"))
    roll_deg, pitch_deg, yaw_deg, q_norm_error = quaternion_to_euler_zyx(q0, q1, q2, q3)
    if not math.isfinite(roll_deg) or not math.isfinite(pitch_deg):
        roll_candidate = parse_float(first_present(row, "accel_roll_deg", "roll_deg"))
        pitch_candidate = parse_float(first_present(row, "accel_pitch_deg", "pitch_deg"))
        if math.isfinite(roll_candidate) and math.isfinite(pitch_candidate):
            roll_deg = roll_candidate
            pitch_deg = pitch_candidate
            yaw_deg = math.nan
            q_norm_error = 0.0
            if att_valid_cell is None:
                att_valid = aux_valid

    ax = parse_float(first_present(row, "lis_ax", "aux_ax", "aux_ax_mps2"))
    ay = parse_float(first_present(row, "lis_ay", "aux_ay", "aux_ay_mps2"))
    az = parse_float(first_present(row, "lis_az", "aux_az", "aux_az_mps2"))
    accel_norm = parse_float(first_present(row, "aux_a_norm_mps2", "accel_norm_mps2"))
    if not math.isfinite(accel_norm) and all(math.isfinite(v) for v in (ax, ay, az)):
        accel_norm = math.sqrt(ax * ax + ay * ay + az * az)
    gravity_residual = accel_norm - K_G_MPS2 if math.isfinite(accel_norm) else math.nan

    mag_x = parse_float(first_present(row, "mag_x_uT"))
    mag_y = parse_float(first_present(row, "mag_y_uT"))
    mag_z = parse_float(first_present(row, "mag_z_uT"))
    mag_norm = parse_float(first_present(row, "mag_norm_uT"))
    if not math.isfinite(mag_norm) and all(math.isfinite(v) for v in (mag_x, mag_y, mag_z)):
        mag_norm = math.sqrt(mag_x * mag_x + mag_y * mag_y + mag_z * mag_z)

    planar_heading = parse_float(first_present(row, "mag_heading_deg"))
    if not math.isfinite(planar_heading) and math.isfinite(mag_x) and math.isfinite(mag_y):
        planar_heading = wrap360(math.degrees(math.atan2(mag_y, mag_x)))
    else:
        planar_heading = wrap360(planar_heading)

    tilt_heading = tilt_compensated_heading_deg(mag_x, mag_y, mag_z, roll_deg, pitch_deg)
    heading_delta = signed_angle_delta_deg(tilt_heading, planar_heading)

    attitude_ready, gravity_ready, magnetic_ready, heading_ready, label, rationale = classify_sample(
        att_valid=att_valid,
        aux_valid=aux_valid,
        mag_valid=mag_valid,
        mag_interference=mag_interference,
        warn_mask=warn_mask,
        q_norm_error=q_norm_error,
        gravity_residual_mps2=gravity_residual,
        mag_norm_uT=mag_norm,
        tilt_heading_deg=tilt_heading,
        gravity_tolerance_mps2=gravity_tolerance_mps2,
        mag_norm_min_uT=mag_norm_min_uT,
        mag_norm_max_uT=mag_norm_max_uT,
        max_q_norm_error=max_q_norm_error,
    )

    return HeadingSample(
        t_s=t_s,
        att_valid=att_valid,
        aux_valid=aux_valid,
        mag_valid=mag_valid,
        mag_interference=mag_interference,
        warn_mask=warn_mask,
        roll_deg=roll_deg,
        pitch_deg=pitch_deg,
        yaw_deg=yaw_deg,
        q_norm_error=q_norm_error,
        accel_norm_mps2=accel_norm,
        gravity_residual_mps2=gravity_residual,
        mag_x_uT=mag_x,
        mag_y_uT=mag_y,
        mag_z_uT=mag_z,
        mag_norm_uT=mag_norm,
        planar_heading_deg=planar_heading,
        tilt_heading_deg=tilt_heading,
        heading_delta_deg=heading_delta,
        attitude_ready=attitude_ready,
        gravity_ready=gravity_ready,
        magnetic_ready=magnetic_ready,
        heading_ready=heading_ready,
        quality_label=label,
        rationale=rationale,
    )


def read_rows_from_current_schema(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    if not lines:
        return []
    reader = csv.DictReader(lines)
    return list(reader)


def read_rows_from_tlm_lines(lines: Iterable[str]) -> list[dict[str, str]]:
    header: list[str] | None = None
    rows: list[dict[str, str]] = []
    aliases = {
        "baro_upd": "baro_updated",
        "imu_upd": "imu_updated",
        "aux_upd": "aux_updated",
        "mag_upd": "mag_updated",
        "att_upd": "att_updated",
    }

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "HDR":
            header = parts[1:]
            continue
        if parts[0] != "TLM" or header is None:
            continue
        row = dict(zip(header, parts[1:]))
        for src, dst in aliases.items():
            if src in row and dst not in row:
                row[dst] = row[src]
        rows.append(row)
    return rows


def read_rows_from_plot_lines(lines: Iterable[str]) -> list[dict[str, str]]:
    header: list[str] | None = None
    rows: list[dict[str, str]] = []

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "ORIENT":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "ORIENT" or header is None:
            if parts[0] == "PLOT" and parts[1] == "ORIENT" and header is None and len(parts[2:]) == len(DEFAULT_PLOT_ORIENT_HEADER):
                header = DEFAULT_PLOT_ORIENT_HEADER
            else:
                continue
        if parts[0] != "PLOT" or parts[1] != "ORIENT":
            continue
        rows.append(dict(zip(header, parts[2:])))
    return rows


def rows_to_samples(
    rows: Iterable[dict[str, str]],
    *,
    gravity_tolerance_mps2: float,
    mag_norm_min_uT: float,
    mag_norm_max_uT: float,
    max_q_norm_error: float,
) -> list[HeadingSample]:
    samples: list[HeadingSample] = []
    for row in rows:
        sample = sample_from_row(
            row,
            gravity_tolerance_mps2=gravity_tolerance_mps2,
            mag_norm_min_uT=mag_norm_min_uT,
            mag_norm_max_uT=mag_norm_max_uT,
            max_q_norm_error=max_q_norm_error,
        )
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
        raise RuntimeError("Serial input requires pyserial. Install pyserial or capture PLOT ORIENT lines to a text file.") from exc

    deadline = None if duration_s is None else time.monotonic() + duration_s
    lines: list[str] = []
    with serial.Serial(port, baudrate=baud, timeout=0.2) as handle:
        if settle_s > 0.0:
            time.sleep(settle_s)
        for command in serial_commands or []:
            text = command.strip()
            if not text:
                continue
            try:
                handle.write((text + "\n").encode("ascii"))
                handle.flush()
            except serial.SerialException as exc:
                raise RuntimeError(f"Serial write failed on {port}: {exc}") from exc
            if settle_s > 0.0:
                time.sleep(settle_s)
        while True:
            if deadline is not None and time.monotonic() >= deadline:
                break
            if max_rows is not None and len(lines) >= max_rows:
                break
            try:
                raw = handle.readline()
            except serial.SerialException as exc:
                if lines:
                    print(f"WARN,SERIAL_READ_INTERRUPTED,port={port},rows={len(lines)},error={exc}", file=sys.stderr)
                    break
                raise RuntimeError(
                    f"Serial read failed on {port} before any rows were captured. "
                    "Close other serial clients, unplug/replug the board if needed, wait a few seconds, and retry. "
                    f"Original error: {exc}"
                ) from exc
            if raw:
                lines.append(raw.decode("utf-8", errors="replace"))
    return lines


def read_samples(
    paths: list[Path],
    input_format: str,
    *,
    gravity_tolerance_mps2: float,
    mag_norm_min_uT: float,
    mag_norm_max_uT: float,
    max_q_norm_error: float,
) -> list[HeadingSample]:
    samples: list[HeadingSample] = []
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        first_line = next((line for line in text.splitlines() if line.strip()), "")
        if input_format == "plot" or (
            input_format == "auto"
            and any(line.strip().startswith(("PLOT_HDR,ORIENT", "PLOT,ORIENT")) for line in lines)
        ):
            rows = read_rows_from_plot_lines(lines)
        elif input_format == "tlm" or (input_format == "auto" and first_line.startswith("HDR,")):
            rows = read_rows_from_tlm_lines(text.splitlines())
        else:
            rows = read_rows_from_current_schema(path)
        samples.extend(
            rows_to_samples(
                rows,
                gravity_tolerance_mps2=gravity_tolerance_mps2,
                mag_norm_min_uT=mag_norm_min_uT,
                mag_norm_max_uT=mag_norm_max_uT,
                max_q_norm_error=max_q_norm_error,
            )
        )
    return sorted(samples, key=lambda sample: sample.t_s)


def finite_values(values: Iterable[float]) -> list[float]:
    return [float(value) for value in values if math.isfinite(float(value))]


def last_finite(values: Iterable[float]) -> float:
    result = math.nan
    for value in values:
        if math.isfinite(float(value)):
            result = float(value)
    return result


def summarize_samples(samples: list[HeadingSample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable heading samples",
        }

    ready_count = sum(1 for sample in samples if sample.heading_ready)
    labels: dict[str, int] = {}
    for sample in samples:
        labels[sample.quality_label] = labels.get(sample.quality_label, 0) + 1

    heading_delta_values = finite_values(abs(sample.heading_delta_deg) for sample in samples)
    gravity_values = finite_values(abs(sample.gravity_residual_mps2) for sample in samples)
    mag_norm_values = finite_values(sample.mag_norm_uT for sample in samples)

    latest_ready = next((sample for sample in reversed(samples) if sample.heading_ready), None)
    final_sample = samples[-1]

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "ready_count": ready_count,
        "ready_fraction": ready_count / len(samples),
        "attitude_ready_fraction": sum(1 for sample in samples if sample.attitude_ready) / len(samples),
        "gravity_ready_fraction": sum(1 for sample in samples if sample.gravity_ready) / len(samples),
        "magnetic_ready_fraction": sum(1 for sample in samples if sample.magnetic_ready) / len(samples),
        "quality_label_counts": labels,
        "mean_abs_heading_compensation_deg": sum(heading_delta_values) / len(heading_delta_values) if heading_delta_values else math.nan,
        "max_abs_heading_compensation_deg": max(heading_delta_values) if heading_delta_values else math.nan,
        "max_abs_gravity_residual_mps2": max(gravity_values) if gravity_values else math.nan,
        "mean_mag_norm_uT": sum(mag_norm_values) / len(mag_norm_values) if mag_norm_values else math.nan,
        "final_tilt_heading_deg": final_sample.tilt_heading_deg,
        "final_planar_heading_deg": final_sample.planar_heading_deg,
        "final_heading_delta_deg": final_sample.heading_delta_deg,
        "final_label": final_sample.quality_label,
        "final_rationale": final_sample.rationale,
        "latest_ready_t_s": latest_ready.t_s if latest_ready is not None else math.nan,
        "latest_ready_heading_deg": latest_ready.tilt_heading_deg if latest_ready is not None else math.nan,
        "latest_roll_deg": last_finite(sample.roll_deg for sample in samples),
        "latest_pitch_deg": last_finite(sample.pitch_deg for sample in samples),
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def polyline(samples: list[HeadingSample], sx, sy, attr: str, color: str, width: float = 2.0, dash: str = "") -> str:
    paths: list[str] = []
    current: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if math.isfinite(value):
            current.append(f"{sx(sample.t_s):.2f},{sy(value):.2f}")
        elif current:
            paths.append(" ".join(current))
            current = []
    if current:
        paths.append(" ".join(current))
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return "\n".join(
        f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{width}"{dash_attr}/>'
        for points in paths
    )


def axis_panel(x: float, y: float, w: float, h: float, title: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="#cbd5e1"/>'
        f'<text x="{x + 16}" y="{y + 28}" class="panel_title">{html.escape(title)}</text>'
    )


def ready_color(value: bool) -> str:
    return "#16a34a" if value else "#dc2626"


def readiness_lane(samples: list[HeadingSample], attr: str, sx, y: float, label: str) -> str:
    pieces = [f'<text x="84" y="{y + 13:.2f}" class="label">{html.escape(label)}</text>']
    for left, right in zip(samples, samples[1:]):
        x0 = sx(left.t_s)
        x1 = sx(right.t_s)
        pieces.append(
            f'<rect x="{x0:.2f}" y="{y:.2f}" width="{max(1.0, x1 - x0):.2f}" height="15" fill="{ready_color(bool(getattr(left, attr)))}" opacity="0.78"/>'
        )
    return "\n".join(pieces)


def heading_compass(sample: HeadingSample | None, x: float, y: float, size: float) -> str:
    cx = x + size / 2.0
    cy = y + size / 2.0
    radius = size * 0.42
    if sample is None or not math.isfinite(sample.tilt_heading_deg):
        pointer = '<text x="{:.2f}" y="{:.2f}" text-anchor="middle" class="label">no ready heading</text>'.format(cx, cy)
    else:
        angle = math.radians(sample.tilt_heading_deg - 90.0)
        x2 = cx + math.cos(angle) * radius * 0.82
        y2 = cy + math.sin(angle) * radius * 0.82
        pointer = (
            f'<line x1="{cx:.2f}" y1="{cy:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="#2563eb" stroke-width="4"/>'
            f'<circle cx="{x2:.2f}" cy="{y2:.2f}" r="6" fill="#2563eb"/>'
            f'<text x="{cx:.2f}" y="{y + size - 20:.2f}" text-anchor="middle" class="metric">'
            f'tilt heading={sample.tilt_heading_deg:.2f} deg</text>'
        )
        if math.isfinite(sample.planar_heading_deg):
            planar = math.radians(sample.planar_heading_deg - 90.0)
            px2 = cx + math.cos(planar) * radius * 0.62
            py2 = cy + math.sin(planar) * radius * 0.62
            pointer += (
                f'<line x1="{cx:.2f}" y1="{cy:.2f}" x2="{px2:.2f}" y2="{py2:.2f}" stroke="#f97316" '
                f'stroke-width="2" stroke-dasharray="5 5"/>'
            )
    return f"""
<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{radius:.2f}" fill="#f8fafc" stroke="#0f172a" stroke-width="2"/>
<line x1="{cx:.2f}" y1="{cy - radius:.2f}" x2="{cx:.2f}" y2="{cy + radius:.2f}" stroke="#cbd5e1"/>
<line x1="{cx - radius:.2f}" y1="{cy:.2f}" x2="{cx + radius:.2f}" y2="{cy:.2f}" stroke="#cbd5e1"/>
<text x="{cx:.2f}" y="{cy - radius - 8:.2f}" text-anchor="middle" class="label">N</text>
<text x="{cx + radius + 10:.2f}" y="{cy + 4:.2f}" class="label">E</text>
<text x="{cx:.2f}" y="{cy + radius + 18:.2f}" text-anchor="middle" class="label">S</text>
<text x="{cx - radius - 18:.2f}" y="{cy + 4:.2f}" class="label">W</text>
{pointer}
"""


def metric_text(summary: dict, sample: HeadingSample | None, x: float, y: float) -> str:
    latest = sample
    lines = [
        f"samples={summary['sample_count']} ready={summary['ready_count']} ({summary['ready_fraction']:.3f})",
        f"att={summary['attitude_ready_fraction']:.3f} gravity={summary['gravity_ready_fraction']:.3f} mag={summary['magnetic_ready_fraction']:.3f}",
        f"mean |delta|={summary['mean_abs_heading_compensation_deg']:.2f} deg max={summary['max_abs_heading_compensation_deg']:.2f} deg",
        f"max |g resid|={summary['max_abs_gravity_residual_mps2']:.3f} m/s2 mean |B|={summary['mean_mag_norm_uT']:.2f} uT",
    ]
    if latest is not None:
        lines.extend(
            [
                f"latest t={latest.t_s:.2f}s roll={latest.roll_deg:.2f} deg pitch={latest.pitch_deg:.2f} deg",
                f"planar={latest.planar_heading_deg:.2f} deg tilt={latest.tilt_heading_deg:.2f} deg delta={latest.heading_delta_deg:.2f} deg",
                f"label={latest.quality_label}",
            ]
        )
    else:
        lines.append("latest ready sample unavailable")

    return "\n".join(
        f'<text x="{x}" y="{y + idx * 20:.2f}" class="metric">{html.escape(line)}</text>'
        for idx, line in enumerate(lines)
    )


def render_svg(samples: list[HeadingSample], title: str = "Tilt-Compensated Heading Demonstrator") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 860
    left = 84
    right = 1128
    summary = summarize_samples(samples)
    ready_sample = next((sample for sample in reversed(samples) if sample.heading_ready), None)
    latest_sample = ready_sample if ready_sample is not None else samples[-1]

    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, left, right)

    heading_y = 330
    heading_h = 210
    sy_heading = scale_fn(0.0, 360.0, heading_y + heading_h - 32, heading_y + 42)

    delta_values = finite_values(sample.heading_delta_deg for sample in samples)
    delta_abs = max([abs(v) for v in delta_values], default=10.0)
    delta_lim = max(10.0, min(90.0, math.ceil(delta_abs / 10.0) * 10.0))
    delta_y = 575
    delta_h = 140
    sy_delta = scale_fn(-delta_lim, delta_lim, delta_y + delta_h - 28, delta_y + 38)

    ready_top = 748
    ready_rows = [
        readiness_lane(samples, "attitude_ready", sx, ready_top, "attitude"),
        readiness_lane(samples, "gravity_ready", sx, ready_top + 24, "gravity"),
        readiness_lane(samples, "magnetic_ready", sx, ready_top + 48, "magnetic"),
        readiness_lane(samples, "heading_ready", sx, ready_top + 72, "heading"),
    ]

    compass_panel = axis_panel(84, 85, 330, 210, "latest ready heading")
    metric_panel = axis_panel(454, 85, 674, 210, "readiness summary")

    heading_panel = axis_panel(left, heading_y, right - left, heading_h, "heading timeline")
    delta_panel = axis_panel(left, delta_y, right - left, delta_h, "tilt correction / attitude")
    readiness_panel = axis_panel(left, ready_top - 38, right - left, 130, "prerequisite readiness lanes")

    heading_grid = "\n".join(
        f'<line x1="{left}" y1="{sy_heading(v):.2f}" x2="{right}" y2="{sy_heading(v):.2f}" stroke="#e2e8f0"/>'
        f'<text x="{left - 40}" y="{sy_heading(v) + 4:.2f}" class="label">{int(v)}</text>'
        for v in (0.0, 90.0, 180.0, 270.0, 360.0)
    )
    delta_grid = "\n".join(
        f'<line x1="{left}" y1="{sy_delta(v):.2f}" x2="{right}" y2="{sy_delta(v):.2f}" stroke="#e2e8f0"/>'
        f'<text x="{left - 52}" y="{sy_delta(v) + 4:.2f}" class="label">{v:.0f}</text>'
        for v in (-delta_lim, 0.0, delta_lim)
    )
    ready_ticks = "\n".join(
        f'<line x1="{sx(sample.t_s):.2f}" y1="{heading_y + 38}" x2="{sx(sample.t_s):.2f}" y2="{heading_y + heading_h - 28}" stroke="#16a34a" stroke-width="1" opacity="0.20"/>'
        for sample in samples
        if sample.heading_ready
    )

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
  .panel_title {{ font: 700 13px Arial, sans-serif; fill: #0f172a; }}
  .axis {{ stroke: #334155; stroke-width: 1.2; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="{left}" y="35" class="title">{html.escape(title)}</text>
<text x="{left}" y="57" class="subtitle">Offline demonstrator: heading is computed from roll/pitch tilt compensation and magnetic-vector evidence; attitude/tilt, gravity, and magnetic gates are displayed separately.</text>
{compass_panel}
{heading_compass(ready_sample, 104, 105, 170)}
<text x="104" y="276" class="label">blue: tilt-compensated, orange dashed: planar magnetic heading</text>
{metric_panel}
{metric_text(summary, latest_sample, 474, 126)}
<text x="474" y="274" class="label">{html.escape(str(summary['final_rationale']))}</text>
{heading_panel}
{heading_grid}
{ready_ticks}
{polyline(samples, sx, sy_heading, "tilt_heading_deg", "#2563eb", 2.4)}
{polyline(samples, sx, sy_heading, "planar_heading_deg", "#f97316", 1.8, "5 5")}
<line x1="{left}" y1="{heading_y + heading_h - 26}" x2="{right}" y2="{heading_y + heading_h - 26}" class="axis"/>
<text x="{left}" y="{heading_y + heading_h - 6}" class="label">{t_min:.2f}s</text>
<text x="{right - 52}" y="{heading_y + heading_h - 6}" class="label">{t_max:.2f}s</text>
<text x="{right - 220}" y="{heading_y + 28}" class="label">blue tilt heading | orange planar heading | green ticks ready</text>
{delta_panel}
{delta_grid}
{polyline(samples, sx, sy_delta, "heading_delta_deg", "#7c3aed", 2.2)}
{polyline(samples, sx, sy_delta, "roll_deg", "#0d9488", 1.5, "4 4")}
{polyline(samples, sx, sy_delta, "pitch_deg", "#64748b", 1.5, "2 4")}
<line x1="{left}" y1="{delta_y + delta_h - 24}" x2="{right}" y2="{delta_y + delta_h - 24}" class="axis"/>
<text x="{right - 280}" y="{delta_y + 28}" class="label">purple: tilt - planar heading, green: roll, gray: pitch [deg]</text>
{readiness_panel}
{''.join(ready_rows)}
<line x1="{left}" y1="{ready_top + 95}" x2="{right}" y2="{ready_top + 95}" class="axis"/>
<text x="{left}" y="{ready_top + 114}" class="label">{t_min:.2f}s</text>
<text x="{right - 52}" y="{ready_top + 114}" class="label">{t_max:.2f}s</text>
<rect x="928" y="{ready_top - 24}" width="14" height="14" fill="#16a34a" opacity="0.78"/><text x="950" y="{ready_top - 12}" class="label">ready</text>
<rect x="1008" y="{ready_top - 24}" width="14" height="14" fill="#dc2626" opacity="0.78"/><text x="1030" y="{ready_top - 12}" class="label">blocked</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[HeadingSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a tilt-compensated heading demonstrator from current-schema SD CSV, HDR/TLM captures, or PLOT ORIENT bench captures."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV, HDR/TLM text, or captured PLOT ORIENT text file.")
    parser.add_argument("--input-format", choices=("auto", "sd", "tlm", "plot"), default="auto")
    parser.add_argument("--serial-port", help="Optional live serial port. Requires pyserial.")
    parser.add_argument(
        "--serial-command",
        action="append",
        default=[],
        help="Command to send after opening the serial port before capture. Repeatable, for example HDR 0 then PLOT ORIENT.",
    )
    parser.add_argument("--serial-settle-ms", type=int, default=250)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration-s", type=float, default=10.0)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--raw-out", type=Path, help="Optional path for saving raw live serial lines before parsing.")
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Tilt-Compensated Heading Demonstrator")
    parser.add_argument("--gravity-tolerance-mps2", type=float, default=0.75)
    parser.add_argument("--mag-norm-min-uT", type=float, default=20.0)
    parser.add_argument("--mag-norm-max-uT", type=float, default=80.0)
    parser.add_argument("--max-q-norm-error", type=float, default=0.05)
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
        if args.raw_out is not None:
            args.raw_out.parent.mkdir(parents=True, exist_ok=True)
            args.raw_out.write_text("".join(lines), encoding="utf-8")
        rows = read_rows_from_plot_lines(lines)
        samples = rows_to_samples(
            rows,
            gravity_tolerance_mps2=args.gravity_tolerance_mps2,
            mag_norm_min_uT=args.mag_norm_min_uT,
            mag_norm_max_uT=args.mag_norm_max_uT,
            max_q_norm_error=args.max_q_norm_error,
        )
    else:
        if not args.input:
            raise SystemExit("Provide at least one input file or --serial-port.")
        samples = read_samples(
            args.input,
            args.input_format,
            gravity_tolerance_mps2=args.gravity_tolerance_mps2,
            mag_norm_min_uT=args.mag_norm_min_uT,
            mag_norm_max_uT=args.mag_norm_max_uT,
            max_q_norm_error=args.max_q_norm_error,
        )
    if args.max_rows is not None:
        samples = samples[: args.max_rows]
    if not samples:
        raise SystemExit("No usable heading samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"ready_count={summary['ready_count']}")
    print(f"ready_fraction={summary['ready_fraction']:.3f}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

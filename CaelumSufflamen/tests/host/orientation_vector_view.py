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


G_MPS2 = 9.80665
WARN_BITS = {
    3: "lis_hw",
    6: "aux_invalid",
    12: "mag_fault",
    13: "sd_fault",
}
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
class OrientationSample:
    t_s: float
    valid_mask: int | None = None
    warn_mask: int | None = None
    aux_ax_mps2: float = math.nan
    aux_ay_mps2: float = math.nan
    aux_az_mps2: float = math.nan
    aux_a_norm_mps2: float = math.nan
    accel_roll_deg: float = math.nan
    accel_pitch_deg: float = math.nan
    mag_x_uT: float = math.nan
    mag_y_uT: float = math.nan
    mag_z_uT: float = math.nan
    mag_norm_uT: float = math.nan
    mag_heading_deg: float = math.nan
    mag_interference: bool | None = None
    aux_age_ms: float = math.nan
    mag_age_ms: float = math.nan
    aux_valid: bool | None = None
    mag_valid: bool | None = None


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


def bool_cell(row: dict[str, str], *names: str) -> bool | None:
    value = parse_int(first_present(row, *names))
    if value is None:
        return None
    return value != 0


def accel_roll_deg(ay: float, az: float) -> float:
    if not math.isfinite(ay) or not math.isfinite(az):
        return math.nan
    return math.degrees(math.atan2(ay, az))


def accel_pitch_deg(ax: float, ay: float, az: float) -> float:
    if not math.isfinite(ax) or not math.isfinite(ay) or not math.isfinite(az):
        return math.nan
    return math.degrees(math.atan2(-ax, math.hypot(ay, az)))


def norm3(x: float, y: float, z: float) -> float:
    if not math.isfinite(x) or not math.isfinite(y) or not math.isfinite(z):
        return math.nan
    return math.sqrt(x * x + y * y + z * z)


def normalize_heading(deg: float) -> float:
    if not math.isfinite(deg):
        return math.nan
    return deg % 360.0


def sample_from_sd_row(row: dict[str, str]) -> OrientationSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    ax = parse_float(first_present(row, "lis_ax", "aux_ax_mps2"))
    ay = parse_float(first_present(row, "lis_ay", "aux_ay_mps2"))
    az = parse_float(first_present(row, "lis_az", "aux_az_mps2"))
    a_norm = parse_float(first_present(row, "aux_a_norm_mps2"))
    if not math.isfinite(a_norm):
        a_norm = norm3(ax, ay, az)

    mx = parse_float(first_present(row, "mag_x_uT", "mag_x_ut"))
    my = parse_float(first_present(row, "mag_y_uT", "mag_y_ut"))
    mz = parse_float(first_present(row, "mag_z_uT", "mag_z_ut"))
    mag_norm = parse_float(first_present(row, "mag_norm_uT", "mag_norm_ut"))
    if not math.isfinite(mag_norm):
        mag_norm = norm3(mx, my, mz)

    return OrientationSample(
        t_s=t_s,
        warn_mask=parse_int(first_present(row, "warn_mask")),
        aux_ax_mps2=ax,
        aux_ay_mps2=ay,
        aux_az_mps2=az,
        aux_a_norm_mps2=a_norm,
        accel_roll_deg=accel_roll_deg(ay, az),
        accel_pitch_deg=accel_pitch_deg(ax, ay, az),
        mag_x_uT=mx,
        mag_y_uT=my,
        mag_z_uT=mz,
        mag_norm_uT=mag_norm,
        mag_heading_deg=normalize_heading(parse_float(first_present(row, "mag_heading_deg"))),
        mag_interference=bool_cell(row, "mag_interference"),
        aux_valid=bool_cell(row, "aux_valid"),
        mag_valid=bool_cell(row, "mag_valid"),
    )


def read_sd_csv(path: Path) -> list[OrientationSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples: list[OrientationSample] = []
    for row in reader:
        sample = sample_from_sd_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def parse_plot_lines(lines: Iterable[str]) -> list[OrientationSample]:
    header: list[str] | None = None
    samples: list[OrientationSample] = []
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
        row = dict(zip(header, parts[2:]))
        t_ms = parse_float(first_present(row, "t_ms"))
        if not math.isfinite(t_ms):
            continue
        valid_mask = parse_int(first_present(row, "valid_mask"))
        ax = parse_float(first_present(row, "aux_ax_mps2"))
        ay = parse_float(first_present(row, "aux_ay_mps2"))
        az = parse_float(first_present(row, "aux_az_mps2"))
        samples.append(
            OrientationSample(
                t_s=t_ms / 1000.0,
                valid_mask=valid_mask,
                warn_mask=parse_int(first_present(row, "warn_mask")),
                aux_ax_mps2=ax,
                aux_ay_mps2=ay,
                aux_az_mps2=az,
                aux_a_norm_mps2=parse_float(first_present(row, "aux_a_norm_mps2")),
                accel_roll_deg=parse_float(first_present(row, "accel_roll_deg")),
                accel_pitch_deg=parse_float(first_present(row, "accel_pitch_deg")),
                mag_x_uT=parse_float(first_present(row, "mag_x_uT")),
                mag_y_uT=parse_float(first_present(row, "mag_y_uT")),
                mag_z_uT=parse_float(first_present(row, "mag_z_uT")),
                mag_norm_uT=parse_float(first_present(row, "mag_norm_uT")),
                mag_heading_deg=normalize_heading(parse_float(first_present(row, "mag_heading_deg"))),
                mag_interference=bool_cell(row, "mag_interference"),
                aux_age_ms=parse_float(first_present(row, "aux_age_ms")),
                mag_age_ms=parse_float(first_present(row, "mag_age_ms")),
                aux_valid=None if valid_mask is None else bool(valid_mask & (1 << 2)),
                mag_valid=None if valid_mask is None else bool(valid_mask & (1 << 4)),
            )
        )
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


def read_samples(paths: list[Path], input_format: str) -> list[OrientationSample]:
    all_samples: list[OrientationSample] = []
    for path in paths:
        if input_format == "sd":
            all_samples.extend(read_sd_csv(path))
            continue
        if input_format == "plot":
            all_samples.extend(parse_plot_lines(path.read_text(encoding="utf-8", errors="replace").splitlines()))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        if any(line.strip().startswith(("PLOT_HDR,ORIENT", "PLOT,ORIENT")) for line in lines):
            all_samples.extend(parse_plot_lines(lines))
        else:
            all_samples.extend(read_sd_csv(path))
    return sorted(all_samples, key=lambda sample: sample.t_s)


def finite_values(samples: list[OrientationSample], attr: str) -> list[float]:
    values: list[float] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            values.append(float(value))
    return values


def summarize_samples(samples: list[OrientationSample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable orientation samples",
        }

    aux_norms = finite_values(samples, "aux_a_norm_mps2")
    mag_norms = finite_values(samples, "mag_norm_uT")
    roll_values = finite_values(samples, "accel_roll_deg")
    pitch_values = finite_values(samples, "accel_pitch_deg")
    headings = finite_values(samples, "mag_heading_deg")
    warn_bit_counts = {
        name: sum(
            1
            for sample in samples
            if sample.warn_mask is not None and bool(sample.warn_mask & (1 << bit))
        )
        for bit, name in WARN_BITS.items()
    }

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "aux_valid_rows": sum(1 for sample in samples if sample.aux_valid is True),
        "mag_valid_rows": sum(1 for sample in samples if sample.mag_valid is True),
        "mag_interference_rows": sum(1 for sample in samples if sample.mag_interference is True),
        "warn_row_count": sum(1 for sample in samples if sample.warn_mask not in (None, 0)),
        "warn_bit_counts": warn_bit_counts,
        "aux_norm_min_mps2": min(aux_norms, default=math.nan),
        "aux_norm_max_mps2": max(aux_norms, default=math.nan),
        "aux_norm_mean_mps2": sum(aux_norms) / len(aux_norms) if aux_norms else math.nan,
        "aux_norm_gravity_residual_mean_mps2": (
            sum(abs(value - G_MPS2) for value in aux_norms) / len(aux_norms)
            if aux_norms
            else math.nan
        ),
        "mag_norm_min_uT": min(mag_norms, default=math.nan),
        "mag_norm_max_uT": max(mag_norms, default=math.nan),
        "mag_norm_mean_uT": sum(mag_norms) / len(mag_norms) if mag_norms else math.nan,
        "roll_span_deg": max(roll_values, default=math.nan) - min(roll_values, default=math.nan),
        "pitch_span_deg": max(pitch_values, default=math.nan) - min(pitch_values, default=math.nan),
        "heading_span_deg": max(headings, default=math.nan) - min(headings, default=math.nan),
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def polyline(samples: list[OrientationSample], attr: str, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            points.append(f"{sx(sample.t_s):.2f},{sy(float(value)):.2f}")
    return " ".join(points)


def latest_finite_sample(samples: list[OrientationSample]) -> OrientationSample:
    for sample in reversed(samples):
        if math.isfinite(sample.aux_a_norm_mps2) or math.isfinite(sample.mag_norm_uT):
            return sample
    return samples[-1]


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def component_bars(sample: OrientationSample, x: float, y: float) -> str:
    rows: list[str] = []
    values = [
        ("ax", sample.aux_ax_mps2, "#2563eb", -G_MPS2, G_MPS2, "m/s2"),
        ("ay", sample.aux_ay_mps2, "#2563eb", -G_MPS2, G_MPS2, "m/s2"),
        ("az", sample.aux_az_mps2, "#2563eb", -G_MPS2, G_MPS2, "m/s2"),
        ("mx", sample.mag_x_uT, "#0f766e", -80.0, 80.0, "uT"),
        ("my", sample.mag_y_uT, "#0f766e", -80.0, 80.0, "uT"),
        ("mz", sample.mag_z_uT, "#0f766e", -80.0, 80.0, "uT"),
    ]
    for idx, (label, value, color, lo, hi, unit) in enumerate(values):
        yy = y + idx * 28
        center = x + 128
        rows.append(f'<text x="{x}" y="{yy + 14:.2f}" class="label">{label}</text>')
        rows.append(f'<line x1="{center - 90}" y1="{yy + 9:.2f}" x2="{center + 90}" y2="{yy + 9:.2f}" stroke="#cbd5e1" stroke-width="8"/>')
        rows.append(f'<line x1="{center}" y1="{yy + 1:.2f}" x2="{center}" y2="{yy + 17:.2f}" stroke="#334155" stroke-width="1"/>')
        if math.isfinite(value):
            pos = center + clamp(value / max(abs(lo), abs(hi)), -1.0, 1.0) * 90.0
            rows.append(f'<line x1="{center:.2f}" y1="{yy + 9:.2f}" x2="{pos:.2f}" y2="{yy + 9:.2f}" stroke="{color}" stroke-width="8"/>')
            text = f"{value:.2f} {unit}"
        else:
            text = "n/a"
        rows.append(f'<text x="{center + 106}" y="{yy + 14:.2f}" class="metric">{html.escape(text)}</text>')
    return "\n".join(rows)


def render_svg(samples: list[OrientationSample], title: str = "LIS3DH + CMPS2 Vector Attitude View") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 780
    latest = latest_finite_sample(samples)
    summary = summarize_samples(samples)
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, 90, 1120)

    norm_values = finite_values(samples, "aux_a_norm_mps2")
    norm_min = min(8.5, min(norm_values, default=9.0))
    norm_max = max(11.5, max(norm_values, default=10.5))
    sy_norm = scale_fn(norm_min, norm_max, 690, 505)

    mag_values = finite_values(samples, "mag_norm_uT")
    mag_min = min(0.0, min(mag_values, default=0.0))
    mag_max = max(100.0, max(mag_values, default=80.0))
    sy_mag = scale_fn(mag_min, mag_max, 690, 505)

    roll = latest.accel_roll_deg if math.isfinite(latest.accel_roll_deg) else 0.0
    pitch = latest.accel_pitch_deg if math.isfinite(latest.accel_pitch_deg) else 0.0
    horizon_cx = 230.0
    horizon_cy = 224.0
    horizon_r = 118.0
    pitch_px = clamp(pitch, -45.0, 45.0) * 1.55

    heading = normalize_heading(latest.mag_heading_deg)
    heading_rad = math.radians(heading if math.isfinite(heading) else 0.0)
    compass_cx = 606.0
    compass_cy = 224.0
    compass_r = 118.0
    heading_x = compass_cx + math.sin(heading_rad) * 92.0
    heading_y = compass_cy - math.cos(heading_rad) * 92.0

    gx = horizon_cx + clamp(latest.aux_ax_mps2 / G_MPS2, -1.0, 1.0) * 82.0
    gy = horizon_cy - clamp(latest.aux_ay_mps2 / G_MPS2, -1.0, 1.0) * 82.0
    mx = compass_cx + clamp(latest.mag_x_uT / 80.0, -1.0, 1.0) * 82.0
    my = compass_cy - clamp(latest.mag_y_uT / 80.0, -1.0, 1.0) * 82.0

    aux_points = polyline(samples, "aux_a_norm_mps2", sx, sy_norm)
    mag_points = polyline(samples, "mag_norm_uT", sx, sy_mag)

    warning_ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            warning_ticks.append(f'<line x1="{x:.2f}" y1="500" x2="{x:.2f}" y2="695" stroke="#dc2626" stroke-width="1" opacity="0.22"/>')

    interference_ticks: list[str] = []
    for sample in samples:
        if sample.mag_interference:
            x = sx(sample.t_s)
            interference_ticks.append(f'<line x1="{x:.2f}" y1="500" x2="{x:.2f}" y2="695" stroke="#f97316" stroke-width="2" opacity="0.35"/>')

    def metric(value: float, suffix: str, precision: int = 2) -> str:
        if not math.isfinite(value):
            return "n/a"
        return f"{value:.{precision}f}{suffix}"

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .panel_title {{ font: 700 14px Arial, sans-serif; fill: #0f172a; }}
  .label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
  .grid {{ stroke: #cbd5e1; stroke-width: 1; opacity: 0.65; }}
  .axis {{ stroke: #334155; stroke-width: 1.2; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="70" y="35" class="title">{html.escape(title)}</text>
<text x="70" y="56" class="subtitle">Gravity-vector attitude, magnetic heading, vector components, freshness, and warning evidence from live sensor streams.</text>

<rect x="70" y="82" width="320" height="340" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="112" class="panel_title">gravity horizon</text>
<clipPath id="horizon_clip"><circle cx="{horizon_cx}" cy="{horizon_cy}" r="{horizon_r}"/></clipPath>
<g clip-path="url(#horizon_clip)" transform="rotate({-roll:.2f} {horizon_cx} {horizon_cy})">
  <rect x="{horizon_cx - 180}" y="{horizon_cy - 180 + pitch_px:.2f}" width="360" height="180" fill="#bfdbfe"/>
  <rect x="{horizon_cx - 180}" y="{horizon_cy + pitch_px:.2f}" width="360" height="180" fill="#fde68a"/>
  <line x1="{horizon_cx - 170}" y1="{horizon_cy + pitch_px:.2f}" x2="{horizon_cx + 170}" y2="{horizon_cy + pitch_px:.2f}" stroke="#334155" stroke-width="3"/>
</g>
<circle cx="{horizon_cx}" cy="{horizon_cy}" r="{horizon_r}" fill="none" stroke="#0f172a" stroke-width="2"/>
<line x1="{horizon_cx - 62}" y1="{horizon_cy}" x2="{horizon_cx + 62}" y2="{horizon_cy}" stroke="#0f172a" stroke-width="2"/>
<line x1="{horizon_cx}" y1="{horizon_cy - 62}" x2="{horizon_cx}" y2="{horizon_cy + 62}" stroke="#0f172a" stroke-width="1" opacity="0.45"/>
<line x1="{horizon_cx}" y1="{horizon_cy}" x2="{gx:.2f}" y2="{gy:.2f}" stroke="#1d4ed8" stroke-width="4"/>
<circle cx="{gx:.2f}" cy="{gy:.2f}" r="6" fill="#1d4ed8"/>
<text x="100" y="380" class="metric">roll={metric(latest.accel_roll_deg, ' deg')}</text>
<text x="100" y="400" class="metric">pitch={metric(latest.accel_pitch_deg, ' deg')}</text>

<rect x="446" y="82" width="320" height="340" fill="#ffffff" stroke="#cbd5e1"/>
<text x="468" y="112" class="panel_title">magnetic compass</text>
<circle cx="{compass_cx}" cy="{compass_cy}" r="{compass_r}" fill="#ffffff" stroke="#0f172a" stroke-width="2"/>
<line x1="{compass_cx}" y1="{compass_cy - compass_r}" x2="{compass_cx}" y2="{compass_cy + compass_r}" stroke="#cbd5e1"/>
<line x1="{compass_cx - compass_r}" y1="{compass_cy}" x2="{compass_cx + compass_r}" y2="{compass_cy}" stroke="#cbd5e1"/>
<text x="{compass_cx - 5}" y="{compass_cy - compass_r - 10}" class="label">N</text>
<text x="{compass_cx + compass_r + 8}" y="{compass_cy + 4}" class="label">E</text>
<text x="{compass_cx - 5}" y="{compass_cy + compass_r + 22}" class="label">S</text>
<text x="{compass_cx - compass_r - 22}" y="{compass_cy + 4}" class="label">W</text>
<line x1="{compass_cx}" y1="{compass_cy}" x2="{heading_x:.2f}" y2="{heading_y:.2f}" stroke="#dc2626" stroke-width="4"/>
<line x1="{compass_cx}" y1="{compass_cy}" x2="{mx:.2f}" y2="{my:.2f}" stroke="#0f766e" stroke-width="3" opacity="0.85"/>
<circle cx="{heading_x:.2f}" cy="{heading_y:.2f}" r="6" fill="#dc2626"/>
<text x="476" y="380" class="metric">heading={metric(latest.mag_heading_deg, ' deg')}</text>
<text x="476" y="400" class="metric">|B|={metric(latest.mag_norm_uT, ' uT')}</text>

<rect x="820" y="82" width="310" height="340" fill="#ffffff" stroke="#cbd5e1"/>
<text x="842" y="112" class="panel_title">latest vector components</text>
{component_bars(latest, 842, 138)}

<rect x="70" y="470" width="1060" height="245" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="494" class="panel_title">time history</text>
{''.join(warning_ticks)}
{''.join(interference_ticks)}
<line x1="90" y1="690" x2="1120" y2="690" class="axis"/>
<line x1="90" y1="505" x2="90" y2="690" class="axis"/>
<line x1="90" y1="{sy_norm(G_MPS2):.2f}" x2="1120" y2="{sy_norm(G_MPS2):.2f}" stroke="#2563eb" stroke-width="1.4" stroke-dasharray="6 5" opacity="0.6"/>
<polyline points="{aux_points}" fill="none" stroke="#2563eb" stroke-width="2.4"/>
<polyline points="{mag_points}" fill="none" stroke="#0f766e" stroke-width="2.0"/>
<text x="96" y="525" class="label">blue: |a| m/s2, green: |B| uT scaled</text>
<text x="96" y="710" class="label">{t_min:.2f}s</text>
<text x="1070" y="710" class="label">{t_max:.2f}s</text>

<text x="70" y="748" class="metric">samples={summary['sample_count']}  aux_valid={summary['aux_valid_rows']}  mag_valid={summary['mag_valid_rows']}  |a|mean={summary['aux_norm_mean_mps2']:.3f}m/s2  gravity_residual_mean={summary['aux_norm_gravity_residual_mean_mps2']:.3f}m/s2  |B|mean={summary['mag_norm_mean_uT']:.2f}uT  mag_interference_rows={summary['mag_interference_rows']}  warn_rows={summary['warn_row_count']}</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[OrientationSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a LIS3DH + CMPS2 vector attitude SVG from SD CSV or captured PLOT ORIENT rows."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV or captured PLOT text file.")
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
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
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="LIS3DH + CMPS2 Vector Attitude View")
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
        raise SystemExit("No usable orientation samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"aux_valid_rows={summary['aux_valid_rows']}")
    print(f"mag_valid_rows={summary['mag_valid_rows']}")
    print(f"aux_norm_mean_mps2={summary['aux_norm_mean_mps2']:.3f}")
    print(f"mag_norm_mean_uT={summary['mag_norm_mean_uT']:.3f}")
    print(f"mag_interference_rows={summary['mag_interference_rows']}")
    print(f"warn_row_count={summary['warn_row_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

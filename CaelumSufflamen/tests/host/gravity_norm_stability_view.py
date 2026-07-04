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
class GravitySample:
    t_s: float
    valid_mask: int | None = None
    warn_mask: int | None = None
    aux_ax_mps2: float = math.nan
    aux_ay_mps2: float = math.nan
    aux_az_mps2: float = math.nan
    aux_a_norm_mps2: float = math.nan
    accel_roll_deg: float = math.nan
    accel_pitch_deg: float = math.nan
    aux_age_ms: float = math.nan
    aux_valid: bool | None = None


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
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    value_i = parse_int(value)
    if value_i is None:
        return None
    return value_i != 0


def first_present(row: dict[str, str], *names: str) -> str | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    return None


def bool_cell(row: dict[str, str], *names: str) -> bool | None:
    return parse_bool(first_present(row, *names))


def norm3(x: float, y: float, z: float) -> float:
    if not math.isfinite(x) or not math.isfinite(y) or not math.isfinite(z):
        return math.nan
    return math.sqrt(x * x + y * y + z * z)


def accel_roll_deg(ay: float, az: float) -> float:
    if not math.isfinite(ay) or not math.isfinite(az):
        return math.nan
    return math.degrees(math.atan2(ay, az))


def accel_pitch_deg(ax: float, ay: float, az: float) -> float:
    if not math.isfinite(ax) or not math.isfinite(ay) or not math.isfinite(az):
        return math.nan
    return math.degrees(math.atan2(-ax, math.hypot(ay, az)))


def sample_from_sd_row(row: dict[str, str]) -> GravitySample | None:
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

    return GravitySample(
        t_s=t_s,
        warn_mask=parse_int(first_present(row, "warn_mask")),
        aux_ax_mps2=ax,
        aux_ay_mps2=ay,
        aux_az_mps2=az,
        aux_a_norm_mps2=a_norm,
        accel_roll_deg=accel_roll_deg(ay, az),
        accel_pitch_deg=accel_pitch_deg(ax, ay, az),
        aux_valid=bool_cell(row, "aux_valid"),
    )


def read_sd_csv(path: Path) -> list[GravitySample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples: list[GravitySample] = []
    for row in reader:
        sample = sample_from_sd_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def sample_from_json_row(row: dict) -> GravitySample | None:
    t_s = parse_float(row.get("t_s"))
    if not math.isfinite(t_s):
        t_ms = parse_float(row.get("t_ms"))
        if math.isfinite(t_ms):
            t_s = t_ms / 1000.0
        else:
            return None

    ax = parse_float(row.get("aux_ax_mps2", row.get("lis_ax")))
    ay = parse_float(row.get("aux_ay_mps2", row.get("lis_ay")))
    az = parse_float(row.get("aux_az_mps2", row.get("lis_az")))
    a_norm = parse_float(row.get("aux_a_norm_mps2"))
    if not math.isfinite(a_norm):
        a_norm = norm3(ax, ay, az)
    valid_mask = parse_int(row.get("valid_mask"))

    roll = parse_float(row.get("accel_roll_deg"))
    if not math.isfinite(roll):
        roll = accel_roll_deg(ay, az)
    pitch = parse_float(row.get("accel_pitch_deg"))
    if not math.isfinite(pitch):
        pitch = accel_pitch_deg(ax, ay, az)

    return GravitySample(
        t_s=t_s,
        valid_mask=valid_mask,
        warn_mask=parse_int(row.get("warn_mask")),
        aux_ax_mps2=ax,
        aux_ay_mps2=ay,
        aux_az_mps2=az,
        aux_a_norm_mps2=a_norm,
        accel_roll_deg=roll,
        accel_pitch_deg=pitch,
        aux_age_ms=parse_float(row.get("aux_age_ms")),
        aux_valid=parse_bool(row.get("aux_valid")) if "aux_valid" in row else None if valid_mask is None else bool(valid_mask & (1 << 2)),
    )


def read_renderer_json(path: Path) -> list[GravitySample]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("samples", [])
    if not isinstance(rows, list):
        return []
    samples: list[GravitySample] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        sample = sample_from_json_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def parse_plot_lines(lines: Iterable[str]) -> list[GravitySample]:
    header: list[str] | None = None
    samples: list[GravitySample] = []
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
        a_norm = parse_float(first_present(row, "aux_a_norm_mps2"))
        if not math.isfinite(a_norm):
            a_norm = norm3(ax, ay, az)
        samples.append(
            GravitySample(
                t_s=t_ms / 1000.0,
                valid_mask=valid_mask,
                warn_mask=parse_int(first_present(row, "warn_mask")),
                aux_ax_mps2=ax,
                aux_ay_mps2=ay,
                aux_az_mps2=az,
                aux_a_norm_mps2=a_norm,
                accel_roll_deg=parse_float(first_present(row, "accel_roll_deg")),
                accel_pitch_deg=parse_float(first_present(row, "accel_pitch_deg")),
                aux_age_ms=parse_float(first_present(row, "aux_age_ms")),
                aux_valid=None if valid_mask is None else bool(valid_mask & (1 << 2)),
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


def read_samples(paths: list[Path], input_format: str) -> list[GravitySample]:
    all_samples: list[GravitySample] = []
    for path in paths:
        if input_format == "sd":
            all_samples.extend(read_sd_csv(path))
            continue
        if input_format == "plot":
            all_samples.extend(parse_plot_lines(path.read_text(encoding="utf-8", errors="replace").splitlines()))
            continue
        if input_format == "json":
            all_samples.extend(read_renderer_json(path))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        if path.suffix.lower() == ".json" or text.lstrip().startswith("{"):
            all_samples.extend(read_renderer_json(path))
        elif any(line.strip().startswith(("PLOT_HDR,ORIENT", "PLOT,ORIENT")) for line in lines):
            all_samples.extend(parse_plot_lines(lines))
        else:
            all_samples.extend(read_sd_csv(path))
    return sorted(all_samples, key=lambda sample: sample.t_s)


def finite_values(samples: list[GravitySample], attr: str) -> list[float]:
    values: list[float] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            values.append(float(value))
    return values


def mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else math.nan


def stddev(values: list[float]) -> float:
    if not values:
        return math.nan
    value_mean = mean(values)
    return math.sqrt(sum((value - value_mean) ** 2 for value in values) / len(values))


def rms(values: list[float]) -> float:
    if not values:
        return math.nan
    return math.sqrt(sum(value * value for value in values) / len(values))


def diff_values(samples: list[GravitySample], attr: str) -> list[float]:
    values: list[float] = []
    previous_value: float | None = None
    for sample in samples:
        value = getattr(sample, attr)
        if not isinstance(value, (int, float)) or not math.isfinite(float(value)):
            previous_value = None
            continue
        value_f = float(value)
        if previous_value is not None:
            values.append(value_f - previous_value)
        previous_value = value_f
    return values


def sample_period_s(samples: list[GravitySample]) -> float:
    deltas = [
        samples[idx].t_s - samples[idx - 1].t_s
        for idx in range(1, len(samples))
        if samples[idx].t_s > samples[idx - 1].t_s
    ]
    return mean(deltas)


def classify_stability(norm_residual_std: float, vibration_rms: float, max_abs_residual: float) -> str:
    if not math.isfinite(norm_residual_std) or not math.isfinite(vibration_rms) or not math.isfinite(max_abs_residual):
        return "insufficient_data"
    if norm_residual_std <= 0.08 and vibration_rms <= 0.04 and max_abs_residual <= 0.35:
        return "stable_static"
    if norm_residual_std <= 0.25 and vibration_rms <= 0.15 and max_abs_residual <= 0.8:
        return "usable_bench_motion"
    return "motion_or_vibration_present"


def build_histogram(values: list[float], lo: float, hi: float, bins: int) -> list[dict]:
    items = [{"index": idx, "lo": lo + idx * (hi - lo) / bins, "hi": lo + (idx + 1) * (hi - lo) / bins, "count": 0} for idx in range(bins)]
    if hi <= lo:
        return items
    for value in values:
        if not math.isfinite(value):
            continue
        idx = int((min(max(value, lo), hi - 1.0e-12) - lo) / (hi - lo) * bins)
        idx = max(0, min(bins - 1, idx))
        items[idx]["count"] += 1
    return items


def summarize_samples(samples: list[GravitySample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable gravity samples",
        }

    norms = finite_values(samples, "aux_a_norm_mps2")
    ax_values = finite_values(samples, "aux_ax_mps2")
    ay_values = finite_values(samples, "aux_ay_mps2")
    az_values = finite_values(samples, "aux_az_mps2")
    roll_values = finite_values(samples, "accel_roll_deg")
    pitch_values = finite_values(samples, "accel_pitch_deg")
    residuals = [value - G_MPS2 for value in norms]
    norm_diffs = diff_values(samples, "aux_a_norm_mps2")
    period_s = sample_period_s(samples)
    vibration_rms = rms(norm_diffs)
    max_abs_residual = max((abs(value) for value in residuals), default=math.nan)
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
        "passed_basic_input_check": bool(norms),
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "sample_period_mean_s": period_s,
        "sample_rate_hz": (1.0 / period_s) if math.isfinite(period_s) and period_s > 0.0 else math.nan,
        "aux_valid_rows": sum(1 for sample in samples if sample.aux_valid is True),
        "aux_invalid_rows": sum(1 for sample in samples if sample.aux_valid is False),
        "warn_row_count": sum(1 for sample in samples if sample.warn_mask not in (None, 0)),
        "warn_bit_counts": warn_bit_counts,
        "aux_norm_min_mps2": min(norms, default=math.nan),
        "aux_norm_max_mps2": max(norms, default=math.nan),
        "aux_norm_mean_mps2": mean(norms),
        "aux_norm_std_mps2": stddev(norms),
        "aux_norm_span_mps2": (max(norms) - min(norms)) if norms else math.nan,
        "gravity_residual_mean_mps2": mean(residuals),
        "gravity_residual_std_mps2": stddev(residuals),
        "gravity_residual_rms_mps2": rms(residuals),
        "gravity_residual_max_abs_mps2": max_abs_residual,
        "vibration_delta_rms_mps2_per_sample": vibration_rms,
        "vibration_delta_max_abs_mps2_per_sample": max((abs(value) for value in norm_diffs), default=math.nan),
        "axis_std_ax_mps2": stddev(ax_values),
        "axis_std_ay_mps2": stddev(ay_values),
        "axis_std_az_mps2": stddev(az_values),
        "roll_span_deg": (max(roll_values) - min(roll_values)) if roll_values else math.nan,
        "pitch_span_deg": (max(pitch_values) - min(pitch_values)) if pitch_values else math.nan,
        "stability_class": classify_stability(stddev(residuals), vibration_rms, max_abs_residual),
        "residual_histogram": build_histogram(residuals, -1.0, 1.0, 24),
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def metric(value: float, suffix: str, precision: int = 3) -> str:
    if not math.isfinite(value):
        return "n/a"
    return f"{value:.{precision}f}{suffix}"


def polyline(samples: list[GravitySample], attr: str, sx, sy, transform=None) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            value_f = float(value)
            if transform is not None:
                value_f = transform(value_f)
            points.append(f"{sx(sample.t_s):.2f},{sy(value_f):.2f}")
    return " ".join(points)


def render_svg(samples: list[GravitySample], title: str = "LIS3DH Gravity-Norm Stability / Vibration Panel") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 820
    summary = summarize_samples(samples)
    residual_values = [value - G_MPS2 for value in finite_values(samples, "aux_a_norm_mps2")]
    residual_abs_max = max(0.5, max((abs(value) for value in residual_values), default=0.0))
    residual_abs_max = min(max(residual_abs_max * 1.15, 0.5), 5.0)
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, 90, 1120)
    sy_resid = scale_fn(-residual_abs_max, residual_abs_max, 330, 115)
    sy_angle = scale_fn(-20.0, 20.0, 560, 390)
    sy_norm = scale_fn(
        min(G_MPS2 - 1.0, summary["aux_norm_min_mps2"]),
        max(G_MPS2 + 1.0, summary["aux_norm_max_mps2"]),
        710,
        600,
    )

    residual_points = polyline(samples, "aux_a_norm_mps2", sx, sy_resid, lambda value: value - G_MPS2)
    norm_points = polyline(samples, "aux_a_norm_mps2", sx, sy_norm)
    roll_points = polyline(samples, "accel_roll_deg", sx, sy_angle)
    pitch_points = polyline(samples, "accel_pitch_deg", sx, sy_angle)

    warning_ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            warning_ticks.append(f'<line x1="{x:.2f}" y1="102" x2="{x:.2f}" y2="712" stroke="#dc2626" stroke-width="1" opacity="0.18"/>')

    hist = summary["residual_histogram"]
    max_hist_count = max((item["count"] for item in hist), default=1)
    hist_bars: list[str] = []
    for item in hist:
        x = 770 + item["index"] * 14
        bar_h = 110.0 * item["count"] / max(1, max_hist_count)
        color = "#2563eb" if item["lo"] <= 0.0 <= item["hi"] else "#0f766e"
        hist_bars.append(f'<rect x="{x:.2f}" y="{304 - bar_h:.2f}" width="10" height="{bar_h:.2f}" fill="{color}" opacity="0.78"/>')

    status_color = {
        "stable_static": "#16a34a",
        "usable_bench_motion": "#d97706",
        "motion_or_vibration_present": "#dc2626",
    }.get(summary["stability_class"], "#64748b")

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .panel_title {{ font: 700 14px Arial, sans-serif; fill: #0f172a; }}
  .label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
  .axis {{ stroke: #334155; stroke-width: 1.2; }}
  .grid {{ stroke: #cbd5e1; stroke-width: 1; opacity: 0.65; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="70" y="35" class="title">{html.escape(title)}</text>
<text x="70" y="56" class="subtitle">LIS3DH bench evidence: gravity norm residual, vibration proxy, roll/pitch drift, validity, freshness, and warning evidence.</text>

<rect x="70" y="82" width="640" height="275" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="112" class="panel_title">gravity residual timeline: |a| - g</text>
{''.join(warning_ticks)}
<rect x="90" y="{sy_resid(0.25):.2f}" width="1030" height="{abs(sy_resid(-0.25) - sy_resid(0.25)):.2f}" fill="#dcfce7" opacity="0.58"/>
<rect x="90" y="{sy_resid(0.5):.2f}" width="1030" height="{abs(sy_resid(-0.5) - sy_resid(0.5)):.2f}" fill="#fef3c7" opacity="0.28"/>
<line x1="90" y1="{sy_resid(0.0):.2f}" x2="690" y2="{sy_resid(0.0):.2f}" class="axis"/>
<line x1="90" y1="115" x2="90" y2="330" class="axis"/>
<polyline points="{residual_points}" fill="none" stroke="#2563eb" stroke-width="2.2"/>
<text x="96" y="344" class="label">{t_min:.2f}s</text>
<text x="636" y="344" class="label">{t_max:.2f}s</text>
<text x="96" y="135" class="label">green band: +/-0.25 m/s2, amber band: +/-0.50 m/s2</text>

<rect x="740" y="82" width="390" height="275" fill="#ffffff" stroke="#cbd5e1"/>
<text x="762" y="112" class="panel_title">residual distribution and stability score</text>
<line x1="770" y1="304" x2="1110" y2="304" class="axis"/>
<line x1="770" y1="194" x2="770" y2="304" class="axis"/>
{''.join(hist_bars)}
<rect x="762" y="130" width="185" height="34" fill="{status_color}" opacity="0.16" stroke="{status_color}"/>
<text x="775" y="152" class="metric">class={summary['stability_class']}</text>
<text x="762" y="334" class="metric">resid_std={metric(summary['gravity_residual_std_mps2'], ' m/s2')}</text>
<text x="762" y="352" class="metric">delta_rms={metric(summary['vibration_delta_rms_mps2_per_sample'], ' m/s2/sample')}</text>

<rect x="70" y="378" width="1060" height="205" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="408" class="panel_title">tilt stability from accelerometer-only roll/pitch</text>
<line x1="90" y1="{sy_angle(0.0):.2f}" x2="1120" y2="{sy_angle(0.0):.2f}" class="axis"/>
<line x1="90" y1="390" x2="90" y2="560" class="axis"/>
<polyline points="{roll_points}" fill="none" stroke="#7c3aed" stroke-width="2"/>
<polyline points="{pitch_points}" fill="none" stroke="#0f766e" stroke-width="2"/>
<text x="96" y="428" class="label">purple: roll deg, green: pitch deg</text>
<text x="96" y="575" class="label">{t_min:.2f}s</text>
<text x="1070" y="575" class="label">{t_max:.2f}s</text>

<rect x="70" y="608" width="1060" height="125" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="636" class="panel_title">absolute acceleration norm</text>
<line x1="90" y1="{sy_norm(G_MPS2):.2f}" x2="1120" y2="{sy_norm(G_MPS2):.2f}" stroke="#334155" stroke-width="1.2" stroke-dasharray="6 5"/>
<line x1="90" y1="710" x2="1120" y2="710" class="axis"/>
<line x1="90" y1="600" x2="90" y2="710" class="axis"/>
<polyline points="{norm_points}" fill="none" stroke="#2563eb" stroke-width="2"/>
<text x="96" y="656" class="label">dashed: standard gravity {G_MPS2:.5f} m/s2</text>

<text x="70" y="776" class="metric">samples={summary['sample_count']}  aux_valid={summary['aux_valid_rows']}  |a|mean={metric(summary['aux_norm_mean_mps2'], 'm/s2')}  |a|std={metric(summary['aux_norm_std_mps2'], 'm/s2')}  max_abs_resid={metric(summary['gravity_residual_max_abs_mps2'], 'm/s2')}  roll_span={metric(summary['roll_span_deg'], 'deg', 2)}  pitch_span={metric(summary['pitch_span_deg'], 'deg', 2)}  lis_hw={summary['warn_bit_counts']['lis_hw']}  aux_invalid={summary['warn_bit_counts']['aux_invalid']}  sd_fault={summary['warn_bit_counts']['sd_fault']}</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[GravitySample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a LIS3DH gravity-norm stability SVG from SD CSV, captured PLOT ORIENT rows, or orientation JSON."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV, captured PLOT ORIENT text file, or orientation renderer JSON.")
    parser.add_argument("--input-format", choices=("auto", "sd", "plot", "json"), default="auto")
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
    parser.add_argument("--title", default="LIS3DH Gravity-Norm Stability / Vibration Panel")
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
        raise SystemExit("No usable gravity samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"aux_valid_rows={summary['aux_valid_rows']}")
    print(f"aux_norm_mean_mps2={summary['aux_norm_mean_mps2']:.3f}")
    print(f"aux_norm_std_mps2={summary['aux_norm_std_mps2']:.3f}")
    print(f"gravity_residual_rms_mps2={summary['gravity_residual_rms_mps2']:.3f}")
    print(f"vibration_delta_rms_mps2_per_sample={summary['vibration_delta_rms_mps2_per_sample']:.3f}")
    print(f"stability_class={summary['stability_class']}")
    print(f"warn_row_count={summary['warn_row_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

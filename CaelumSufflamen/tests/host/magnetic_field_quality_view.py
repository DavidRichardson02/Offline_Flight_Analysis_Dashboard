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


HEADING_BIN_COUNT = 24
WARN_BITS = {
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
class MagneticSample:
    t_s: float
    valid_mask: int | None = None
    warn_mask: int | None = None
    mag_x_uT: float = math.nan
    mag_y_uT: float = math.nan
    mag_z_uT: float = math.nan
    mag_norm_uT: float = math.nan
    mag_heading_deg: float = math.nan
    mag_interference: bool | None = None
    mag_age_ms: float = math.nan
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


def parse_bool(value: object) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    value_i = parse_int(value)
    if value_i is None:
        return None
    return value_i != 0


def norm3(x: float, y: float, z: float) -> float:
    if not math.isfinite(x) or not math.isfinite(y) or not math.isfinite(z):
        return math.nan
    return math.sqrt(x * x + y * y + z * z)


def normalize_heading(deg: float) -> float:
    if not math.isfinite(deg):
        return math.nan
    return deg % 360.0


def heading_from_xy(x: float, y: float) -> float:
    if not math.isfinite(x) or not math.isfinite(y):
        return math.nan
    return normalize_heading(math.degrees(math.atan2(y, x)))


def sample_from_sd_row(row: dict[str, str]) -> MagneticSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    mx = parse_float(first_present(row, "mag_x_uT", "mag_x_ut"))
    my = parse_float(first_present(row, "mag_y_uT", "mag_y_ut"))
    mz = parse_float(first_present(row, "mag_z_uT", "mag_z_ut"))
    mag_norm = parse_float(first_present(row, "mag_norm_uT", "mag_norm_ut"))
    if not math.isfinite(mag_norm):
        mag_norm = norm3(mx, my, mz)
    heading = normalize_heading(parse_float(first_present(row, "mag_heading_deg")))
    if not math.isfinite(heading):
        heading = heading_from_xy(mx, my)

    return MagneticSample(
        t_s=t_s,
        warn_mask=parse_int(first_present(row, "warn_mask")),
        mag_x_uT=mx,
        mag_y_uT=my,
        mag_z_uT=mz,
        mag_norm_uT=mag_norm,
        mag_heading_deg=heading,
        mag_interference=bool_cell(row, "mag_interference"),
        mag_valid=bool_cell(row, "mag_valid"),
    )


def read_sd_csv(path: Path) -> list[MagneticSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples: list[MagneticSample] = []
    for row in reader:
        sample = sample_from_sd_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def sample_from_json_row(row: dict) -> MagneticSample | None:
    t_s = parse_float(row.get("t_s"))
    if not math.isfinite(t_s):
        t_ms = parse_float(row.get("t_ms"))
        if math.isfinite(t_ms):
            t_s = t_ms / 1000.0
        else:
            return None

    mx = parse_float(row.get("mag_x_uT", row.get("mag_x_ut")))
    my = parse_float(row.get("mag_y_uT", row.get("mag_y_ut")))
    mz = parse_float(row.get("mag_z_uT", row.get("mag_z_ut")))
    mag_norm = parse_float(row.get("mag_norm_uT", row.get("mag_norm_ut")))
    if not math.isfinite(mag_norm):
        mag_norm = norm3(mx, my, mz)
    heading = normalize_heading(parse_float(row.get("mag_heading_deg")))
    if not math.isfinite(heading):
        heading = heading_from_xy(mx, my)
    valid_mask = parse_int(row.get("valid_mask"))

    return MagneticSample(
        t_s=t_s,
        valid_mask=valid_mask,
        warn_mask=parse_int(row.get("warn_mask")),
        mag_x_uT=mx,
        mag_y_uT=my,
        mag_z_uT=mz,
        mag_norm_uT=mag_norm,
        mag_heading_deg=heading,
        mag_interference=parse_bool(row.get("mag_interference")),
        mag_age_ms=parse_float(row.get("mag_age_ms")),
        mag_valid=parse_bool(row.get("mag_valid")) if "mag_valid" in row else None if valid_mask is None else bool(valid_mask & (1 << 4)),
    )


def read_renderer_json(path: Path) -> list[MagneticSample]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("samples", [])
    if not isinstance(rows, list):
        return []
    samples: list[MagneticSample] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        sample = sample_from_json_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def parse_plot_lines(lines: Iterable[str]) -> list[MagneticSample]:
    header: list[str] | None = None
    samples: list[MagneticSample] = []
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
        mx = parse_float(first_present(row, "mag_x_uT"))
        my = parse_float(first_present(row, "mag_y_uT"))
        mz = parse_float(first_present(row, "mag_z_uT"))
        mag_norm = parse_float(first_present(row, "mag_norm_uT"))
        if not math.isfinite(mag_norm):
            mag_norm = norm3(mx, my, mz)
        heading = normalize_heading(parse_float(first_present(row, "mag_heading_deg")))
        if not math.isfinite(heading):
            heading = heading_from_xy(mx, my)
        samples.append(
            MagneticSample(
                t_s=t_ms / 1000.0,
                valid_mask=valid_mask,
                warn_mask=parse_int(first_present(row, "warn_mask")),
                mag_x_uT=mx,
                mag_y_uT=my,
                mag_z_uT=mz,
                mag_norm_uT=mag_norm,
                mag_heading_deg=heading,
                mag_interference=bool_cell(row, "mag_interference"),
                mag_age_ms=parse_float(first_present(row, "mag_age_ms")),
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


def read_samples(paths: list[Path], input_format: str) -> list[MagneticSample]:
    all_samples: list[MagneticSample] = []
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


def finite_values(samples: list[MagneticSample], attr: str) -> list[float]:
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


def heading_bin_index(heading_deg: float) -> int | None:
    if not math.isfinite(heading_deg):
        return None
    return min(HEADING_BIN_COUNT - 1, int((normalize_heading(heading_deg) / 360.0) * HEADING_BIN_COUNT))


def build_heading_bins(samples: list[MagneticSample]) -> list[dict]:
    bins: list[dict] = []
    for idx in range(HEADING_BIN_COUNT):
        bins.append(
            {
                "index": idx,
                "center_deg": (idx + 0.5) * (360.0 / HEADING_BIN_COUNT),
                "count": 0,
                "mean_norm_uT": math.nan,
                "min_norm_uT": math.nan,
                "max_norm_uT": math.nan,
                "interference_count": 0,
            }
        )

    values_by_bin: list[list[float]] = [[] for _ in range(HEADING_BIN_COUNT)]
    for sample in samples:
        idx = heading_bin_index(sample.mag_heading_deg)
        if idx is None:
            continue
        bins[idx]["count"] += 1
        if sample.mag_interference:
            bins[idx]["interference_count"] += 1
        if math.isfinite(sample.mag_norm_uT):
            values_by_bin[idx].append(sample.mag_norm_uT)

    for idx, values in enumerate(values_by_bin):
        if not values:
            continue
        bins[idx]["mean_norm_uT"] = mean(values)
        bins[idx]["min_norm_uT"] = min(values)
        bins[idx]["max_norm_uT"] = max(values)
    return bins


def summarize_samples(samples: list[MagneticSample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable magnetic samples",
        }

    mx_values = finite_values(samples, "mag_x_uT")
    my_values = finite_values(samples, "mag_y_uT")
    mz_values = finite_values(samples, "mag_z_uT")
    norm_values = finite_values(samples, "mag_norm_uT")
    heading_bins = build_heading_bins(samples)
    nonempty_bins = [item for item in heading_bins if item["count"] > 0]
    center_x = mean(mx_values)
    center_y = mean(my_values)
    center_z = mean(mz_values)
    centered_xy_radii = [
        math.hypot(sample.mag_x_uT - center_x, sample.mag_y_uT - center_y)
        for sample in samples
        if math.isfinite(sample.mag_x_uT)
        and math.isfinite(sample.mag_y_uT)
        and math.isfinite(center_x)
        and math.isfinite(center_y)
    ]
    warn_bit_counts = {
        name: sum(
            1
            for sample in samples
            if sample.warn_mask is not None and bool(sample.warn_mask & (1 << bit))
        )
        for bit, name in WARN_BITS.items()
    }
    heading_coverage_bins = len(nonempty_bins)

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": bool(norm_values or mx_values or my_values),
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "mag_valid_rows": sum(1 for sample in samples if sample.mag_valid is True),
        "mag_invalid_rows": sum(1 for sample in samples if sample.mag_valid is False),
        "mag_interference_rows": sum(1 for sample in samples if sample.mag_interference is True),
        "warn_row_count": sum(1 for sample in samples if sample.warn_mask not in (None, 0)),
        "warn_bit_counts": warn_bit_counts,
        "mag_norm_min_uT": min(norm_values, default=math.nan),
        "mag_norm_max_uT": max(norm_values, default=math.nan),
        "mag_norm_mean_uT": mean(norm_values),
        "mag_norm_std_uT": stddev(norm_values),
        "mag_norm_span_uT": (max(norm_values) - min(norm_values)) if norm_values else math.nan,
        "hard_iron_offset_x_uT": center_x,
        "hard_iron_offset_y_uT": center_y,
        "hard_iron_offset_z_uT": center_z,
        "hard_iron_offset_xy_uT": math.hypot(center_x, center_y) if math.isfinite(center_x) and math.isfinite(center_y) else math.nan,
        "centered_xy_radius_mean_uT": mean(centered_xy_radii),
        "centered_xy_radius_std_uT": stddev(centered_xy_radii),
        "heading_bin_count": HEADING_BIN_COUNT,
        "heading_coverage_bins": heading_coverage_bins,
        "heading_coverage_deg": heading_coverage_bins * (360.0 / HEADING_BIN_COUNT),
        "calibration_estimate_quality": (
            "usable_sweep" if heading_coverage_bins >= HEADING_BIN_COUNT * 0.75 else "insufficient_heading_coverage"
        ),
        "heading_bins": heading_bins,
        "hard_iron_estimate_note": "Bench-estimated centroid only; do not commit as calibration without a controlled sweep and residual review.",
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


def metric(value: float, suffix: str, precision: int = 2) -> str:
    if not math.isfinite(value):
        return "n/a"
    return f"{value:.{precision}f}{suffix}"


def heat_color(value: float, low: float, high: float) -> str:
    if not math.isfinite(value):
        return "#e2e8f0"
    ratio = clamp((value - low) / max(high - low, 1.0e-9), 0.0, 1.0)
    if ratio < 0.5:
        local = ratio / 0.5
        r = int(37 + local * (245 - 37))
        g = int(99 + local * (158 - 99))
        b = int(235 + local * (11 - 235))
    else:
        local = (ratio - 0.5) / 0.5
        r = int(245 + local * (220 - 245))
        g = int(158 + local * (38 - 158))
        b = int(11 + local * (38 - 11))
    return f"#{r:02x}{g:02x}{b:02x}"


def polar_xy(cx: float, cy: float, radius: float, deg_clockwise_from_north: float) -> tuple[float, float]:
    rad = math.radians(deg_clockwise_from_north)
    return cx + math.sin(rad) * radius, cy - math.cos(rad) * radius


def annular_sector_path(cx: float, cy: float, r0: float, r1: float, a0: float, a1: float) -> str:
    x1, y1 = polar_xy(cx, cy, r1, a0)
    x2, y2 = polar_xy(cx, cy, r1, a1)
    x3, y3 = polar_xy(cx, cy, r0, a1)
    x4, y4 = polar_xy(cx, cy, r0, a0)
    large_arc = 1 if abs(a1 - a0) > 180.0 else 0
    return (
        f"M {x1:.2f} {y1:.2f} "
        f"A {r1:.2f} {r1:.2f} 0 {large_arc} 1 {x2:.2f} {y2:.2f} "
        f"L {x3:.2f} {y3:.2f} "
        f"A {r0:.2f} {r0:.2f} 0 {large_arc} 0 {x4:.2f} {y4:.2f} Z"
    )


def polyline(samples: list[MagneticSample], attr: str, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            points.append(f"{sx(sample.t_s):.2f},{sy(float(value)):.2f}")
    return " ".join(points)


def render_svg(samples: list[MagneticSample], title: str = "CMPS2 Magnetic Field Quality / Interference Map") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 820
    summary = summarize_samples(samples)
    mag_norms = finite_values(samples, "mag_norm_uT")
    mx_values = finite_values(samples, "mag_x_uT")
    my_values = finite_values(samples, "mag_y_uT")
    max_abs_xy = max([20.0] + [abs(value) for value in mx_values + my_values])
    scatter_pad = max_abs_xy * 0.12
    sx_scatter = scale_fn(-max_abs_xy - scatter_pad, max_abs_xy + scatter_pad, 100, 525)
    sy_scatter = scale_fn(-max_abs_xy - scatter_pad, max_abs_xy + scatter_pad, 410, 120)
    norm_min = min(mag_norms, default=0.0)
    norm_max = max(mag_norms, default=100.0)
    if norm_max - norm_min < 1.0:
        norm_min -= 0.5
        norm_max += 0.5

    scatter_points: list[str] = []
    for sample in samples:
        if not math.isfinite(sample.mag_x_uT) or not math.isfinite(sample.mag_y_uT):
            continue
        color = "#dc2626" if sample.mag_interference else heat_color(sample.mag_norm_uT, norm_min, norm_max)
        scatter_points.append(
            f'<circle cx="{sx_scatter(sample.mag_x_uT):.2f}" cy="{sy_scatter(sample.mag_y_uT):.2f}" r="3.2" fill="{color}" opacity="0.72"/>'
        )

    center_x = summary["hard_iron_offset_x_uT"]
    center_y = summary["hard_iron_offset_y_uT"]
    centroid_x = sx_scatter(center_x) if math.isfinite(center_x) else sx_scatter(0.0)
    centroid_y = sy_scatter(center_y) if math.isfinite(center_y) else sy_scatter(0.0)
    origin_x = sx_scatter(0.0)
    origin_y = sy_scatter(0.0)

    bin_paths: list[str] = []
    for item in summary["heading_bins"]:
        start_deg = item["index"] * (360.0 / HEADING_BIN_COUNT)
        end_deg = (item["index"] + 1) * (360.0 / HEADING_BIN_COUNT) - 1.0
        fill = heat_color(item["mean_norm_uT"], norm_min, norm_max)
        opacity = 0.18 if item["count"] == 0 else clamp(0.35 + item["count"] / max(1.0, max(bin_item["count"] for bin_item in summary["heading_bins"])) * 0.55, 0.35, 0.9)
        stroke = "#dc2626" if item["interference_count"] else "#ffffff"
        bin_paths.append(
            f'<path d="{annular_sector_path(805, 250, 78, 136, start_deg, end_deg)}" fill="{fill}" opacity="{opacity:.2f}" stroke="{stroke}" stroke-width="1.2"/>'
        )

    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx_time = scale_fn(t_min, t_max, 90, 1120)
    sy_norm = scale_fn(min(norm_min, summary["mag_norm_mean_uT"] - 5.0), max(norm_max, summary["mag_norm_mean_uT"] + 5.0), 710, 520)
    norm_points = polyline(samples, "mag_norm_uT", sx_time, sy_norm)
    mean_y = sy_norm(summary["mag_norm_mean_uT"]) if math.isfinite(summary["mag_norm_mean_uT"]) else 615

    warning_ticks: list[str] = []
    interference_ticks: list[str] = []
    for sample in samples:
        x = sx_time(sample.t_s)
        if sample.warn_mask not in (None, 0):
            warning_ticks.append(f'<line x1="{x:.2f}" y1="515" x2="{x:.2f}" y2="715" stroke="#dc2626" stroke-width="1" opacity="0.22"/>')
        if sample.mag_interference:
            interference_ticks.append(f'<line x1="{x:.2f}" y1="515" x2="{x:.2f}" y2="715" stroke="#f97316" stroke-width="2" opacity="0.45"/>')

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
<text x="70" y="56" class="subtitle">CMPS2 magnetic vector evidence: XY scatter, heading-bin norm map, interference ticks, freshness, and bench-estimated hard-iron centroid.</text>

<rect x="70" y="82" width="500" height="360" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="112" class="panel_title">XY magnetic scatter</text>
<line x1="{origin_x:.2f}" y1="120" x2="{origin_x:.2f}" y2="410" class="grid"/>
<line x1="100" y1="{origin_y:.2f}" x2="525" y2="{origin_y:.2f}" class="grid"/>
<circle cx="{origin_x:.2f}" cy="{origin_y:.2f}" r="5" fill="#0f172a"/>
{''.join(scatter_points)}
<line x1="{origin_x:.2f}" y1="{origin_y:.2f}" x2="{centroid_x:.2f}" y2="{centroid_y:.2f}" stroke="#7c3aed" stroke-width="3"/>
<circle cx="{centroid_x:.2f}" cy="{centroid_y:.2f}" r="7" fill="#7c3aed"/>
<text x="92" y="392" class="metric">bench hard-iron centroid: x={metric(center_x, ' uT')} y={metric(center_y, ' uT')} xy={metric(summary['hard_iron_offset_xy_uT'], ' uT')}</text>
<text x="92" y="416" class="label">Centroid is evidence only; controlled calibration still requires a deliberate full sweep.</text>

<rect x="610" y="82" width="390" height="360" fill="#ffffff" stroke="#cbd5e1"/>
<text x="632" y="112" class="panel_title">heading-binned |B| heat/ring map</text>
<circle cx="805" cy="250" r="136" fill="none" stroke="#cbd5e1"/>
<circle cx="805" cy="250" r="78" fill="#ffffff" stroke="#cbd5e1"/>
{''.join(bin_paths)}
<line x1="805" y1="104" x2="805" y2="134" stroke="#0f172a" stroke-width="2"/>
<line x1="951" y1="250" x2="921" y2="250" stroke="#0f172a" stroke-width="2"/>
<text x="799" y="99" class="label">N</text>
<text x="959" y="254" class="label">E</text>
<text x="799" y="410" class="label">S</text>
<text x="632" y="392" class="metric">coverage={summary['heading_coverage_bins']}/{summary['heading_bin_count']} bins ({summary['heading_coverage_deg']:.0f} deg)  quality={summary['calibration_estimate_quality']}</text>
<text x="632" y="416" class="label">Red sector outlines mark bins containing firmware interference flags.</text>

<rect x="1025" y="82" width="105" height="360" fill="#ffffff" stroke="#cbd5e1"/>
<text x="1042" y="112" class="panel_title">scale</text>
<rect x="1050" y="140" width="28" height="30" fill="{heat_color(norm_min, norm_min, norm_max)}"/>
<rect x="1050" y="170" width="28" height="30" fill="{heat_color((norm_min + norm_max) * 0.5, norm_min, norm_max)}"/>
<rect x="1050" y="200" width="28" height="30" fill="{heat_color(norm_max, norm_min, norm_max)}"/>
<text x="1088" y="160" class="label">{metric(norm_min, '')}</text>
<text x="1088" y="190" class="label">uT</text>
<text x="1088" y="220" class="label">{metric(norm_max, '')}</text>
<text x="1042" y="272" class="metric">valid</text>
<text x="1042" y="292" class="metric">{summary['mag_valid_rows']}</text>
<text x="1042" y="324" class="metric">warn</text>
<text x="1042" y="344" class="metric">{summary['warn_row_count']}</text>
<text x="1042" y="376" class="metric">interf</text>
<text x="1042" y="396" class="metric">{summary['mag_interference_rows']}</text>

<rect x="70" y="485" width="1060" height="250" fill="#ffffff" stroke="#cbd5e1"/>
<text x="92" y="512" class="panel_title">magnetic norm timeline</text>
{''.join(warning_ticks)}
{''.join(interference_ticks)}
<line x1="90" y1="710" x2="1120" y2="710" class="axis"/>
<line x1="90" y1="520" x2="90" y2="710" class="axis"/>
<line x1="90" y1="{mean_y:.2f}" x2="1120" y2="{mean_y:.2f}" stroke="#7c3aed" stroke-width="1.4" stroke-dasharray="6 5" opacity="0.7"/>
<polyline points="{norm_points}" fill="none" stroke="#0f766e" stroke-width="2.3"/>
<text x="96" y="538" class="label">green: |B| uT, purple dashed: mean, red ticks: warning mask, orange ticks: mag_interference</text>
<text x="96" y="732" class="label">{t_min:.2f}s</text>
<text x="1070" y="732" class="label">{t_max:.2f}s</text>

<text x="70" y="776" class="metric">samples={summary['sample_count']}  |B|mean={metric(summary['mag_norm_mean_uT'], 'uT')}  |B|std={metric(summary['mag_norm_std_uT'], 'uT')}  |B|span={metric(summary['mag_norm_span_uT'], 'uT')}  centered_xy_radius_std={metric(summary['centered_xy_radius_std_uT'], 'uT')}  mag_fault_rows={summary['warn_bit_counts']['mag_fault']}  sd_fault_rows={summary['warn_bit_counts']['sd_fault']}</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[MagneticSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a CMPS2 magnetic field quality SVG from SD CSV or captured PLOT ORIENT rows."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV, captured PLOT ORIENT text file, or renderer JSON.")
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
    parser.add_argument("--title", default="CMPS2 Magnetic Field Quality / Interference Map")
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
        raise SystemExit("No usable magnetic samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"mag_valid_rows={summary['mag_valid_rows']}")
    print(f"mag_norm_mean_uT={summary['mag_norm_mean_uT']:.3f}")
    print(f"mag_norm_std_uT={summary['mag_norm_std_uT']:.3f}")
    print(f"heading_coverage_bins={summary['heading_coverage_bins']}")
    print(f"hard_iron_offset_xy_uT={summary['hard_iron_offset_xy_uT']:.3f}")
    print(f"mag_interference_rows={summary['mag_interference_rows']}")
    print(f"warn_row_count={summary['warn_row_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

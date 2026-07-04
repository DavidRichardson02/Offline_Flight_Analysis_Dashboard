from __future__ import annotations

import argparse
import csv
import html
import json
import math
import statistics
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


SCHEMA_NAME = "wind-relative-landing-footprint-v1"


@dataclass
class LandingSample:
    log_path: str
    log_index: int
    t_s: float
    h_m: float
    v_z_mps: float
    x_m: float
    y_m: float
    z_m: float
    vx_mps: float
    vy_mps: float
    vz_mps: float
    sigma_x_m: float
    sigma_y_m: float
    sigma_z_m: float
    phase: int | None
    warn_mask: int | None
    horizontal_position_source: str
    horizontal_velocity_source: str
    vertical_source: str


@dataclass
class WindEstimate:
    speed_mps: float
    direction_deg: float
    direction_convention: str
    vx_mps: float
    vy_mps: float
    sigma_mps: float
    source: str


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


def finite(value: float) -> bool:
    return math.isfinite(value)


def first_present(row: dict[str, str], *names: str) -> tuple[str | None, str | None]:
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name], name
    return None, None


def float_cell(row: dict[str, str], *names: str) -> tuple[float, str]:
    value, name = first_present(row, *names)
    return parse_float(value), name or "unavailable"


def int_cell(row: dict[str, str], *names: str) -> int | None:
    value, _ = first_present(row, *names)
    return parse_int(value)


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    if reader.fieldnames is None:
        raise ValueError(f"{path} does not contain a readable CSV header")
    return list(reader)


def row_time_s(row: dict[str, str], fallback_index: int) -> float:
    value, _ = float_cell(row, "t_s", "time_s")
    if finite(value):
        return value
    value, _ = float_cell(row, "t_us")
    if finite(value):
        return value / 1_000_000.0
    value, _ = float_cell(row, "t_ms", "time_ms")
    if finite(value):
        return value / 1000.0
    return float(fallback_index)


def choose_altitude(row: dict[str, str]) -> tuple[float, str]:
    for names in (
        ("est_h", "est_h_m"),
        ("kf_h", "kf_alt", "kf_alt_m"),
        ("altitude_m", "h_m", "bmp_alt_rel", "baro_alt_rel_m"),
        ("gps_z", "z_m", "est_z"),
    ):
        value, name = float_cell(row, *names)
        if finite(value):
            return value, name
    return math.nan, "unavailable"


def choose_vertical_velocity(row: dict[str, str]) -> tuple[float, str]:
    for names in (
        ("est_v", "est_v_mps"),
        ("kf_v", "kf_vz", "vertical_velocity_mps"),
        ("gps_vz", "vz_mps", "est_vz"),
    ):
        value, name = float_cell(row, *names)
        if finite(value):
            return value, name
    return math.nan, "unavailable"


def nonnegative_sigma(value: float) -> float:
    if finite(value) and value >= 0.0:
        return math.sqrt(value)
    return math.nan


def read_samples(paths: list[Path]) -> list[LandingSample]:
    samples: list[LandingSample] = []
    for path in paths:
        rows = read_csv_rows(path)
        for row_index, row in enumerate(rows):
            t_s = row_time_s(row, row_index)
            h_m, vertical_source = choose_altitude(row)
            v_z_mps, vertical_velocity_source = choose_vertical_velocity(row)
            if vertical_source == "unavailable":
                vertical_source = vertical_velocity_source

            x_m, x_source = float_cell(row, "x_m", "est_x", "gps_x", "pos_x_m", "north_m", "enu_x_m")
            y_m, y_source = float_cell(row, "y_m", "est_y", "gps_y", "pos_y_m", "east_m", "enu_y_m")
            z_m, _ = float_cell(row, "z_m", "est_z", "gps_z")
            vx_mps, vx_source = float_cell(row, "vx_mps", "est_vx", "gps_vx", "fusedgnd_vx", "ground_vx_mps")
            vy_mps, vy_source = float_cell(row, "vy_mps", "est_vy", "gps_vy", "fusedgnd_vy", "ground_vy_mps")
            vz_mps, _ = float_cell(row, "vz_mps", "est_vz", "gps_vz")

            sx, _ = float_cell(row, "sigma_x", "sigma_x_m", "pos_sigma_x_m", "gps_sigma_x_m")
            sy, _ = float_cell(row, "sigma_y", "sigma_y_m", "pos_sigma_y_m", "gps_sigma_y_m")
            sz, _ = float_cell(row, "sigma_z", "sigma_z_m", "pos_sigma_z_m", "gps_sigma_z_m")
            if not finite(sz):
                p00, _ = float_cell(row, "P00", "p00")
                sz = nonnegative_sigma(p00)

            samples.append(
                LandingSample(
                    log_path=str(path),
                    log_index=len(samples),
                    t_s=t_s,
                    h_m=h_m,
                    v_z_mps=v_z_mps,
                    x_m=x_m,
                    y_m=y_m,
                    z_m=z_m,
                    vx_mps=vx_mps,
                    vy_mps=vy_mps,
                    vz_mps=vz_mps,
                    sigma_x_m=sx,
                    sigma_y_m=sy,
                    sigma_z_m=sz,
                    phase=int_cell(row, "phase", "flight_phase"),
                    warn_mask=int_cell(row, "warn_mask", "warning_mask"),
                    horizontal_position_source=x_source if finite(x_m) and finite(y_m) else "unavailable",
                    horizontal_velocity_source=vx_source if finite(vx_mps) and finite(vy_mps) else "unavailable",
                    vertical_source=vertical_source,
                )
            )
    return samples


def wind_from_components(
    *,
    speed_mps: float,
    direction_deg: float,
    direction_convention: str,
    sigma_mps: float,
    source: str,
) -> WindEstimate | None:
    if not finite(speed_mps) or not finite(direction_deg):
        return None
    convention = direction_convention.lower().strip()
    if convention not in ("toward", "from"):
        convention = "toward"
    theta = math.radians(direction_deg)
    sign = -1.0 if convention == "from" else 1.0
    return WindEstimate(
        speed_mps=speed_mps,
        direction_deg=direction_deg,
        direction_convention=convention,
        vx_mps=sign * speed_mps * math.cos(theta),
        vy_mps=sign * speed_mps * math.sin(theta),
        sigma_mps=max(0.0, sigma_mps) if finite(sigma_mps) else 0.0,
        source=source,
    )


def nested_value(data: dict[str, object], keys: list[str]) -> object | None:
    cursor: object = data
    for key in keys:
        if not isinstance(cursor, dict) or key not in cursor:
            return None
        cursor = cursor[key]
    return cursor


def load_wind_metadata(path: Path | None, sigma_mps: float) -> WindEstimate | None:
    if path is None:
        return None
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return None

    speed = parse_float(
        nested_value(data, ["wind", "speed_mps"])
        or nested_value(data, ["wind", "speed"])
        or data.get("wind_speed_mps")
    )
    direction = parse_float(
        nested_value(data, ["wind", "direction_deg"])
        or nested_value(data, ["wind", "direction"])
        or data.get("wind_direction_deg")
    )
    convention = (
        nested_value(data, ["wind", "direction_convention"])
        or data.get("wind_direction_convention")
        or "toward"
    )
    wind_sigma = parse_float(nested_value(data, ["wind", "sigma_mps"]) or data.get("wind_sigma_mps"))
    if not finite(wind_sigma):
        wind_sigma = sigma_mps
    return wind_from_components(
        speed_mps=speed,
        direction_deg=direction,
        direction_convention=str(convention),
        sigma_mps=wind_sigma,
        source=str(path),
    )


def finite_mean(values: list[float]) -> float:
    finite_values = [value for value in values if finite(value)]
    return statistics.fmean(finite_values) if finite_values else math.nan


def select_final_sample(samples: list[LandingSample]) -> LandingSample | None:
    candidates = [sample for sample in samples if finite(sample.t_s)]
    if not candidates:
        return None
    return max(candidates, key=lambda item: item.t_s)


def select_projection_sample(samples: list[LandingSample]) -> LandingSample | None:
    full_state = [
        sample
        for sample in samples
        if finite(sample.t_s)
        and finite(sample.h_m)
        and finite(sample.x_m)
        and finite(sample.y_m)
        and finite(sample.vx_mps)
        and finite(sample.vy_mps)
    ]
    if full_state:
        return max(full_state, key=lambda item: item.t_s)

    horizontal_position = [
        sample
        for sample in samples
        if finite(sample.t_s) and finite(sample.h_m) and finite(sample.x_m) and finite(sample.y_m)
    ]
    if horizontal_position:
        return max(horizontal_position, key=lambda item: item.t_s)

    return select_final_sample(samples)


def estimate_descent_time(
    sample: LandingSample,
    *,
    configured_descent_rate_mps: float,
    min_descent_rate_mps: float,
    max_descent_time_s: float,
    descent_time_sigma_frac: float,
) -> tuple[float, float, float, str]:
    if not finite(sample.h_m):
        return math.nan, math.nan, math.nan, "altitude_unavailable"

    height_m = max(0.0, sample.h_m)
    measured_rate = math.nan
    if finite(sample.v_z_mps) and sample.v_z_mps < -min_descent_rate_mps:
        measured_rate = abs(sample.v_z_mps)
    elif finite(sample.vz_mps) and sample.vz_mps < -min_descent_rate_mps:
        measured_rate = abs(sample.vz_mps)

    if finite(measured_rate):
        descent_rate_mps = measured_rate
        source = "measured_vertical_velocity"
    else:
        descent_rate_mps = configured_descent_rate_mps
        source = "configured_descent_rate"

    if not finite(descent_rate_mps) or descent_rate_mps < min_descent_rate_mps:
        return math.nan, math.nan, math.nan, "descent_rate_unavailable"

    descent_time_s = height_m / descent_rate_mps
    if finite(max_descent_time_s):
        descent_time_s = min(descent_time_s, max_descent_time_s)
    time_sigma_s = max(0.25, abs(descent_time_s) * max(0.0, descent_time_sigma_frac))
    return descent_time_s, time_sigma_s, descent_rate_mps, source


def build_summary(
    samples: list[LandingSample],
    *,
    wind: WindEstimate | None,
    configured_descent_rate_mps: float,
    min_descent_rate_mps: float,
    max_descent_time_s: float,
    descent_time_sigma_frac: float,
    assumed_horizontal_position_sigma_m: float,
    horizontal_velocity_sigma_mps: float,
    max_state_age_s: float,
) -> dict[str, object]:
    sample_count = len(samples)
    horizontal_position_rows = sum(1 for s in samples if finite(s.x_m) and finite(s.y_m))
    horizontal_velocity_rows = sum(1 for s in samples if finite(s.vx_mps) and finite(s.vy_mps))
    descent_state_rows = sum(1 for s in samples if finite(s.h_m))
    warning_rows = sum(1 for s in samples if s.warn_mask not in (None, 0))
    finite_times = [s.t_s for s in samples if finite(s.t_s)]

    final_log_sample = select_final_sample(samples)
    final_sample = select_projection_sample(samples)
    summary: dict[str, object] = {
        "schema": SCHEMA_NAME,
        "sample_count": sample_count,
        "time_start_s": min(finite_times) if finite_times else None,
        "time_end_s": max(finite_times) if finite_times else None,
        "horizontal_position_rows": horizontal_position_rows,
        "horizontal_velocity_rows": horizontal_velocity_rows,
        "descent_state_rows": descent_state_rows,
        "warning_rows": warning_rows,
        "wind_available": wind is not None,
        "wind_source": wind.source if wind is not None else "unavailable",
    }

    if final_sample is None:
        summary.update({"final_label": "telemetry_empty", "final_rationale": "No readable telemetry samples were available."})
        return summary

    selected_state_age_s = math.nan
    if final_log_sample is not None and finite(final_log_sample.t_s) and finite(final_sample.t_s):
        selected_state_age_s = max(0.0, final_log_sample.t_s - final_sample.t_s)

    descent_time_s, time_sigma_s, descent_rate_mps, descent_source = estimate_descent_time(
        final_sample,
        configured_descent_rate_mps=configured_descent_rate_mps,
        min_descent_rate_mps=min_descent_rate_mps,
        max_descent_time_s=max_descent_time_s,
        descent_time_sigma_frac=descent_time_sigma_frac,
    )

    has_horizontal_position = finite(final_sample.x_m) and finite(final_sample.y_m)
    has_horizontal_velocity = finite(final_sample.vx_mps) and finite(final_sample.vy_mps)
    has_descent_time = finite(descent_time_s)
    has_wind = wind is not None
    state_is_fresh = not finite(selected_state_age_s) or not finite(max_state_age_s) or selected_state_age_s <= max_state_age_s

    final_label = "wind_relative_footprint_supported"
    rationale = "Horizontal position, ground velocity, descent time, and wind vector were all available."
    if not has_horizontal_position:
        final_label = "horizontal_state_unavailable"
        rationale = "Current log does not contain finite horizontal position fields; a landing footprint is not observable."
    elif not state_is_fresh:
        final_label = "horizontal_state_stale"
        rationale = "Latest finite horizontal state is older than the configured freshness limit."
    elif not has_descent_time:
        final_label = "descent_state_unavailable"
        rationale = "Current log does not contain enough altitude/descent-rate evidence to project time-to-ground."
    elif not has_horizontal_velocity:
        final_label = "horizontal_velocity_unavailable"
        rationale = "Horizontal position exists, but ground-relative horizontal velocity is missing."
    elif not has_wind:
        final_label = "wind_vector_unavailable"
        rationale = "Ground footprint can be extrapolated, but wind-relative decomposition is unavailable without wind metadata."

    sigma_x_source = "telemetry"
    sigma_y_source = "telemetry"
    sigma_x_m = final_sample.sigma_x_m
    sigma_y_m = final_sample.sigma_y_m
    if not finite(sigma_x_m):
        sigma_x_m = assumed_horizontal_position_sigma_m
        sigma_x_source = "assumed"
    if not finite(sigma_y_m):
        sigma_y_m = assumed_horizontal_position_sigma_m
        sigma_y_source = "assumed"

    summary.update(
        {
            "final_label": final_label,
            "final_rationale": rationale,
            "final_time_s": final_sample.t_s if finite(final_sample.t_s) else None,
            "latest_log_time_s": final_log_sample.t_s if final_log_sample is not None and finite(final_log_sample.t_s) else None,
            "selected_state_age_s": selected_state_age_s if finite(selected_state_age_s) else None,
            "max_state_age_s": max_state_age_s if finite(max_state_age_s) else None,
            "current_x_m": final_sample.x_m if finite(final_sample.x_m) else None,
            "current_y_m": final_sample.y_m if finite(final_sample.y_m) else None,
            "current_h_m": final_sample.h_m if finite(final_sample.h_m) else None,
            "current_vz_mps": final_sample.v_z_mps if finite(final_sample.v_z_mps) else None,
            "current_ground_vx_mps": final_sample.vx_mps if finite(final_sample.vx_mps) else None,
            "current_ground_vy_mps": final_sample.vy_mps if finite(final_sample.vy_mps) else None,
            "horizontal_position_source": final_sample.horizontal_position_source,
            "horizontal_velocity_source": final_sample.horizontal_velocity_source,
            "vertical_source": final_sample.vertical_source,
            "descent_time_s": descent_time_s if finite(descent_time_s) else None,
            "descent_time_sigma_s": time_sigma_s if finite(time_sigma_s) else None,
            "descent_rate_mps": descent_rate_mps if finite(descent_rate_mps) else None,
            "descent_time_source": descent_source,
            "sigma_x_m": sigma_x_m if finite(sigma_x_m) else None,
            "sigma_y_m": sigma_y_m if finite(sigma_y_m) else None,
            "sigma_x_source": sigma_x_source,
            "sigma_y_source": sigma_y_source,
            "horizontal_velocity_sigma_mps": horizontal_velocity_sigma_mps,
        }
    )

    if has_horizontal_position and has_horizontal_velocity and has_descent_time and state_is_fresh:
        predicted_x = final_sample.x_m + final_sample.vx_mps * descent_time_s
        predicted_y = final_sample.y_m + final_sample.vy_mps * descent_time_s
        ground_speed_mps = math.hypot(final_sample.vx_mps, final_sample.vy_mps)
        wind_vx = wind.vx_mps if wind is not None else math.nan
        wind_vy = wind.vy_mps if wind is not None else math.nan
        wind_speed_mps = wind.speed_mps if wind is not None else math.nan
        air_vx = final_sample.vx_mps - wind_vx if wind is not None else math.nan
        air_vy = final_sample.vy_mps - wind_vy if wind is not None else math.nan
        no_wind_x = final_sample.x_m + air_vx * descent_time_s if wind is not None else math.nan
        no_wind_y = final_sample.y_m + air_vy * descent_time_s if wind is not None else math.nan
        wind_drift_x = wind_vx * descent_time_s if wind is not None else math.nan
        wind_drift_y = wind_vy * descent_time_s if wind is not None else math.nan

        wind_sigma_mps = wind.sigma_mps if wind is not None else 0.0
        vx_time_term = abs(final_sample.vx_mps) * time_sigma_s
        vy_time_term = abs(final_sample.vy_mps) * time_sigma_s
        sigma_landing_x = math.sqrt(
            max(0.0, sigma_x_m) ** 2
            + (descent_time_s * max(0.0, horizontal_velocity_sigma_mps)) ** 2
            + (descent_time_s * wind_sigma_mps) ** 2
            + vx_time_term**2
        )
        sigma_landing_y = math.sqrt(
            max(0.0, sigma_y_m) ** 2
            + (descent_time_s * max(0.0, horizontal_velocity_sigma_mps)) ** 2
            + (descent_time_s * wind_sigma_mps) ** 2
            + vy_time_term**2
        )
        footprint_range_m = math.hypot(predicted_x - final_sample.x_m, predicted_y - final_sample.y_m)
        cone_half_angle_deg = (
            math.degrees(math.atan2(2.0 * max(sigma_landing_x, sigma_landing_y), footprint_range_m))
            if footprint_range_m > 1.0e-9
            else 90.0
        )
        summary.update(
            {
                "predicted_landing_x_m": predicted_x,
                "predicted_landing_y_m": predicted_y,
                "predicted_ground_range_m": footprint_range_m,
                "ground_speed_mps": ground_speed_mps,
                "air_relative_vx_mps": air_vx if finite(air_vx) else None,
                "air_relative_vy_mps": air_vy if finite(air_vy) else None,
                "air_relative_speed_mps": math.hypot(air_vx, air_vy) if finite(air_vx) and finite(air_vy) else None,
                "wind_vx_mps": wind_vx if finite(wind_vx) else None,
                "wind_vy_mps": wind_vy if finite(wind_vy) else None,
                "wind_speed_mps": wind_speed_mps if finite(wind_speed_mps) else None,
                "no_wind_landing_x_m": no_wind_x if finite(no_wind_x) else None,
                "no_wind_landing_y_m": no_wind_y if finite(no_wind_y) else None,
                "wind_drift_x_m": wind_drift_x if finite(wind_drift_x) else None,
                "wind_drift_y_m": wind_drift_y if finite(wind_drift_y) else None,
                "sigma_landing_x_m": sigma_landing_x,
                "sigma_landing_y_m": sigma_landing_y,
                "ellipse_2sigma_area_m2": math.pi * (2.0 * sigma_landing_x) * (2.0 * sigma_landing_y),
                "uncertainty_cone_half_angle_deg": cone_half_angle_deg,
            }
        )

    return summary


def svg_escape(value: object) -> str:
    return html.escape(str(value), quote=True)


def fmt(value: object, digits: int = 2) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        if not finite(value):
            return "n/a"
        return f"{value:.{digits}f}"
    return str(value)


def data_bounds(points: list[tuple[float, float]]) -> tuple[float, float, float, float]:
    finite_points = [(x, y) for x, y in points if finite(x) and finite(y)]
    if not finite_points:
        return -10.0, 10.0, -10.0, 10.0
    xs = [p[0] for p in finite_points]
    ys = [p[1] for p in finite_points]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span = max(max_x - min_x, max_y - min_y, 10.0)
    pad = 0.18 * span
    return min_x - pad, max_x + pad, min_y - pad, max_y + pad


def polyline(points: list[tuple[float, float]], scale_x, scale_y, **attrs: object) -> str:
    mapped = [f"{scale_x(x):.2f},{scale_y(y):.2f}" for x, y in points if finite(x) and finite(y)]
    if len(mapped) < 2:
        return ""
    attr = " ".join(f'{key.replace("_", "-")}="{svg_escape(value)}"' for key, value in attrs.items())
    return f'<polyline points="{" ".join(mapped)}" {attr}/>'


def circle(cx: float, cy: float, r: float, fill: str, stroke: str = "none") -> str:
    return f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{r:.2f}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>'


def line(x1: float, y1: float, x2: float, y2: float, stroke: str, width: float = 1.5, extra: str = "") -> str:
    return (
        f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" '
        f'stroke="{stroke}" stroke-width="{width:.2f}" {extra}/>'
    )


def panel_rect(x: float, y: float, w: float, h: float, title: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="#cbd5e1" stroke-width="1.2"/>'
        f'<text x="{x + 16}" y="{y + 28}" class="panel-title">{svg_escape(title)}</text>'
    )


def render_grid(x: float, y: float, w: float, h: float, x_label: str, y_label: str) -> str:
    parts: list[str] = []
    for i in range(6):
        gx = x + w * i / 5.0
        gy = y + h * i / 5.0
        parts.append(line(gx, y, gx, y + h, "#e2e8f0", 0.8))
        parts.append(line(x, gy, x + w, gy, "#e2e8f0", 0.8))
    parts.append(f'<text x="{x + w / 2}" y="{y + h + 36}" text-anchor="middle" class="axis-label">{x_label}</text>')
    parts.append(
        f'<text transform="translate({x - 46},{y + h / 2}) rotate(-90)" text-anchor="middle" class="axis-label">{y_label}</text>'
    )
    return "\n".join(parts)


def render_map_panel(samples: list[LandingSample], summary: dict[str, object], x: int, y: int, w: int, h: int) -> str:
    plot_x, plot_y, plot_w, plot_h = x + 54, y + 52, w - 86, h - 104
    trajectory = [(s.x_m, s.y_m) for s in samples if finite(s.x_m) and finite(s.y_m)]
    points = list(trajectory)
    for key_x, key_y in (
        ("current_x_m", "current_y_m"),
        ("predicted_landing_x_m", "predicted_landing_y_m"),
        ("no_wind_landing_x_m", "no_wind_landing_y_m"),
    ):
        px = parse_float(summary.get(key_x))
        py = parse_float(summary.get(key_y))
        if finite(px) and finite(py):
            points.append((px, py))
    pred_x = parse_float(summary.get("predicted_landing_x_m"))
    pred_y = parse_float(summary.get("predicted_landing_y_m"))
    sig_x = parse_float(summary.get("sigma_landing_x_m"))
    sig_y = parse_float(summary.get("sigma_landing_y_m"))
    if finite(pred_x) and finite(pred_y) and finite(sig_x) and finite(sig_y):
        points.extend([(pred_x - 2 * sig_x, pred_y - 2 * sig_y), (pred_x + 2 * sig_x, pred_y + 2 * sig_y)])

    min_x, max_x, min_y, max_y = data_bounds(points)

    def sx(value: float) -> float:
        return plot_x + (value - min_x) / (max_x - min_x) * plot_w

    def sy(value: float) -> float:
        return plot_y + plot_h - (value - min_y) / (max_y - min_y) * plot_h

    parts = [panel_rect(x, y, w, h, "wind-relative landing footprint / uncertainty cone")]
    parts.append(render_grid(plot_x, plot_y, plot_w, plot_h, "x [m]", "y [m]"))
    if len(trajectory) >= 2:
        parts.append(polyline(trajectory, sx, sy, fill="none", stroke="#2563eb", stroke_width="2.0"))

    cur_x = parse_float(summary.get("current_x_m"))
    cur_y = parse_float(summary.get("current_y_m"))
    no_wind_x = parse_float(summary.get("no_wind_landing_x_m"))
    no_wind_y = parse_float(summary.get("no_wind_landing_y_m"))
    if finite(cur_x) and finite(cur_y):
        parts.append(circle(sx(cur_x), sy(cur_y), 5.0, "#111827", "#ffffff"))
        if finite(pred_x) and finite(pred_y):
            parts.append(line(sx(cur_x), sy(cur_y), sx(pred_x), sy(pred_y), "#7c3aed", 2.0, 'stroke-dasharray="5 4"'))
        if finite(no_wind_x) and finite(no_wind_y):
            parts.append(line(sx(cur_x), sy(cur_y), sx(no_wind_x), sy(no_wind_y), "#059669", 2.0, 'stroke-dasharray="3 4"'))
            parts.append(line(sx(no_wind_x), sy(no_wind_y), sx(pred_x), sy(pred_y), "#f97316", 2.5))
            parts.append(circle(sx(no_wind_x), sy(no_wind_y), 4.5, "#059669", "#ffffff"))

    if finite(pred_x) and finite(pred_y):
        parts.append(circle(sx(pred_x), sy(pred_y), 6.0, "#dc2626", "#ffffff"))
        if finite(sig_x) and finite(sig_y):
            rx = abs(sx(pred_x + 2.0 * sig_x) - sx(pred_x))
            ry = abs(sy(pred_y + 2.0 * sig_y) - sy(pred_y))
            parts.append(
                f'<ellipse cx="{sx(pred_x):.2f}" cy="{sy(pred_y):.2f}" rx="{rx:.2f}" ry="{ry:.2f}" '
                'fill="#a855f733" stroke="#7c3aed" stroke-width="2.0"/>'
            )

    if not trajectory:
        parts.append(
            f'<text x="{plot_x + plot_w / 2}" y="{plot_y + plot_h / 2 - 10}" text-anchor="middle" class="missing">'
            "horizontal position unavailable</text>"
        )
        parts.append(
            f'<text x="{plot_x + plot_w / 2}" y="{plot_y + plot_h / 2 + 16}" text-anchor="middle" class="small">'
            "No finite x/y telemetry field was found in this log.</text>"
        )

    legend_x = x + w - 255
    legend_y = y + 48
    legend = [
        ("#2563eb", "trajectory"),
        ("#111827", "current state"),
        ("#059669", "air-relative no-wind endpoint"),
        ("#f97316", "wind drift vector"),
        ("#dc2626", "predicted landing"),
        ("#7c3aed", "2-sigma ellipse / cone"),
    ]
    parts.append(f'<rect x="{legend_x}" y="{legend_y}" width="235" height="146" fill="#ffffffdd" stroke="#cbd5e1"/>')
    for idx, (color, label) in enumerate(legend):
        yy = legend_y + 22 + idx * 20
        parts.append(line(legend_x + 12, yy - 4, legend_x + 34, yy - 4, color, 2.4))
        parts.append(f'<text x="{legend_x + 42}" y="{yy}" class="legend">{svg_escape(label)}</text>')

    return "\n".join(parts)


def render_status_panel(summary: dict[str, object], x: int, y: int, w: int, h: int) -> str:
    status_rows = [
        ("horizontal position", summary.get("horizontal_position_rows", 0), "x/y state samples"),
        ("horizontal velocity", summary.get("horizontal_velocity_rows", 0), "ground vxy samples"),
        ("descent state", summary.get("descent_state_rows", 0), "altitude/time-to-ground"),
        ("wind vector", 1 if summary.get("wind_available") else 0, str(summary.get("wind_source", "unavailable"))),
        ("uncertainty inputs", 1 if summary.get("sigma_x_m") is not None and summary.get("sigma_y_m") is not None else 0, "position, velocity, wind, descent-time sigma"),
        ("warning rows", 0 if summary.get("warning_rows", 0) else 1, f"{summary.get('warning_rows', 0)} warned"),
    ]
    parts = [panel_rect(x, y, w, h, "observability gate")]
    max_rows = max(1, int(summary.get("sample_count", 0) or 0))
    for idx, (name, value, detail) in enumerate(status_rows):
        yy = y + 58 + idx * 31
        ok = value > 0 if name != "warning rows" else value == 1
        fill = "#16a34a" if ok else "#dc2626"
        parts.append(f'<circle cx="{x + 24}" cy="{yy - 6}" r="6" fill="{fill}"/>')
        parts.append(f'<text x="{x + 42}" y="{yy - 2}" class="status-name">{svg_escape(name)}</text>')
        if isinstance(value, int) and name not in ("wind vector", "warning rows", "uncertainty inputs"):
            text = f"{value}/{max_rows} rows"
        else:
            text = str(detail)
        parts.append(f'<text x="{x + 210}" y="{yy - 2}" class="small">{svg_escape(text)}</text>')
    return "\n".join(parts)


def render_vertical_panel(samples: list[LandingSample], summary: dict[str, object], x: int, y: int, w: int, h: int) -> str:
    plot_x, plot_y, plot_w, plot_h = x + 58, y + 48, w - 88, h - 82
    parts = [panel_rect(x, y, w, h, "descent-time evidence")]
    parts.append(render_grid(plot_x, plot_y, plot_w, plot_h, "t [s]", "altitude [m]"))
    series = [(s.t_s, s.h_m) for s in samples if finite(s.t_s) and finite(s.h_m)]
    if not series:
        parts.append(f'<text x="{plot_x + plot_w / 2}" y="{plot_y + plot_h / 2}" text-anchor="middle" class="missing">altitude unavailable</text>')
        return "\n".join(parts)
    min_t = min(t for t, _ in series)
    max_t = max(t for t, _ in series)
    min_h = min(0.0, min(hh for _, hh in series))
    max_h = max(hh for _, hh in series)
    if max_t <= min_t:
        max_t = min_t + 1.0
    if max_h <= min_h:
        max_h = min_h + 1.0

    def sx(value: float) -> float:
        return plot_x + (value - min_t) / (max_t - min_t) * plot_w

    def sy(value: float) -> float:
        return plot_y + plot_h - (value - min_h) / (max_h - min_h) * plot_h

    parts.append(polyline(series, sx, sy, fill="none", stroke="#2563eb", stroke_width="2.0"))
    parts.append(line(plot_x, sy(0.0), plot_x + plot_w, sy(0.0), "#64748b", 1.2, 'stroke-dasharray="5 4"'))
    descent = summary.get("descent_time_s")
    source = summary.get("descent_time_source")
    parts.append(
        f'<text x="{x + 18}" y="{y + h - 24}" class="small">descent time={fmt(descent)} s, source={svg_escape(source)}</text>'
    )
    return "\n".join(parts)


def render_summary_panel(summary: dict[str, object], x: int, y: int, w: int, h: int) -> str:
    parts = [panel_rect(x, y, w, h, "engineering summary")]
    lines = [
        f"label={summary.get('final_label')} | rationale={summary.get('final_rationale')}",
        (
            "current: "
            f"x={fmt(summary.get('current_x_m'))} m, y={fmt(summary.get('current_y_m'))} m, "
            f"h={fmt(summary.get('current_h_m'))} m, vz={fmt(summary.get('current_vz_mps'))} m/s"
        ),
        (
            "projection: "
            f"t_ground={fmt(summary.get('descent_time_s'))} s, "
            f"ground_v=({fmt(summary.get('current_ground_vx_mps'))}, {fmt(summary.get('current_ground_vy_mps'))}) m/s, "
            f"landing=({fmt(summary.get('predicted_landing_x_m'))}, {fmt(summary.get('predicted_landing_y_m'))}) m"
        ),
        (
            "wind decomposition: "
            f"wind_v=({fmt(summary.get('wind_vx_mps'))}, {fmt(summary.get('wind_vy_mps'))}) m/s, "
            f"air_v=({fmt(summary.get('air_relative_vx_mps'))}, {fmt(summary.get('air_relative_vy_mps'))}) m/s, "
            f"wind_drift=({fmt(summary.get('wind_drift_x_m'))}, {fmt(summary.get('wind_drift_y_m'))}) m"
        ),
        (
            "uncertainty: "
            f"sigma_xy=({fmt(summary.get('sigma_landing_x_m'))}, {fmt(summary.get('sigma_landing_y_m'))}) m, "
            f"2sigma_area={fmt(summary.get('ellipse_2sigma_area_m2'), 1)} m^2, "
            f"cone_half_angle={fmt(summary.get('uncertainty_cone_half_angle_deg'))} deg"
        ),
        (
            "sources: "
            f"pos={summary.get('horizontal_position_source')}, velocity={summary.get('horizontal_velocity_source')}, "
            f"vertical={summary.get('vertical_source')}, wind={summary.get('wind_source')}, "
            f"sigma=({summary.get('sigma_x_source')}, {summary.get('sigma_y_source')})"
        ),
    ]
    for idx, text in enumerate(lines):
        parts.append(f'<text x="{x + 18}" y="{y + 58 + idx * 23}" class="mono">{svg_escape(text)}</text>')
    return "\n".join(parts)


def render_svg(samples: list[LandingSample], summary: dict[str, object], title: str) -> str:
    width, height = 1200, 900
    parts: list[str] = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        "<style>",
        "text { font-family: Arial, Helvetica, sans-serif; fill: #0f172a; }",
        ".title { font-size: 27px; font-weight: 700; }",
        ".subtitle { font-size: 14px; fill: #334155; }",
        ".panel-title { font-size: 15px; font-weight: 700; }",
        ".axis-label { font-size: 12px; fill: #334155; }",
        ".small { font-size: 12px; fill: #334155; }",
        ".legend { font-size: 12px; fill: #0f172a; }",
        ".mono { font-family: Consolas, Menlo, monospace; font-size: 12px; }",
        ".missing { font-size: 17px; font-weight: 700; fill: #dc2626; }",
        ".status-name { font-size: 13px; font-weight: 700; }",
        "</style>",
        '<rect x="0" y="0" width="1200" height="900" fill="#f8fafc"/>',
        f'<text x="70" y="42" class="title">{svg_escape(title)}</text>',
        (
            '<text x="70" y="64" class="subtitle">'
            "Wind-relative landing projection with explicit observability, source, and uncertainty evidence.</text>"
        ),
    ]
    parts.append(render_map_panel(samples, summary, 70, 92, 690, 500))
    parts.append(render_status_panel(summary, 790, 92, 340, 236))
    parts.append(render_vertical_panel(samples, summary, 790, 356, 340, 236))
    parts.append(render_summary_panel(summary, 70, 630, 1060, 210))
    parts.append("</svg>")
    return "\n".join(parts)


def json_safe(value: object) -> object:
    if isinstance(value, float):
        return value if finite(value) else None
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    return value


def write_json(path: Path, samples: list[LandingSample], summary: dict[str, object], wind: WindEstimate | None) -> None:
    payload = {
        "schema": SCHEMA_NAME,
        "summary": summary,
        "wind": asdict(wind) if wind is not None else None,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(json_safe(payload), indent=2, sort_keys=True), encoding="utf-8")


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Render a wind-relative landing footprint and uncertainty-cone evidence view.")
    parser.add_argument("input_csv", nargs="+", type=Path, help="Input current-schema or legacy GPS-bearing CSV log.")
    parser.add_argument("--metadata-json", type=Path, default=None, help="Optional metadata JSON with wind.speed_mps and wind.direction_deg.")
    parser.add_argument("--wind-speed-mps", type=float, default=math.nan, help="Wind speed override in m/s.")
    parser.add_argument("--wind-direction-deg", type=float, default=math.nan, help="Wind direction in local x/y degrees.")
    parser.add_argument("--wind-direction-convention", choices=("toward", "from"), default="toward")
    parser.add_argument("--wind-sigma-mps", type=float, default=1.5)
    parser.add_argument("--descent-rate-mps", type=float, default=8.0)
    parser.add_argument("--min-descent-rate-mps", type=float, default=1.0)
    parser.add_argument("--descent-time-sigma-frac", type=float, default=0.35)
    parser.add_argument("--max-descent-time-s", type=float, default=600.0)
    parser.add_argument("--max-state-age-s", type=float, default=2.0)
    parser.add_argument("--horizontal-position-sigma-m", type=float, default=5.0)
    parser.add_argument("--horizontal-velocity-sigma-mps", type=float, default=1.0)
    parser.add_argument("--svg-out", type=Path, default=None)
    parser.add_argument("--json-out", type=Path, default=None)
    parser.add_argument("--title", default="Wind-Relative Landing Footprint / Uncertainty Cone")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    wind = None
    if finite(args.wind_speed_mps) and finite(args.wind_direction_deg):
        wind = wind_from_components(
            speed_mps=args.wind_speed_mps,
            direction_deg=args.wind_direction_deg,
            direction_convention=args.wind_direction_convention,
            sigma_mps=args.wind_sigma_mps,
            source="cli",
        )
    if wind is None:
        wind = load_wind_metadata(args.metadata_json, args.wind_sigma_mps)

    samples = read_samples(args.input_csv)
    summary = build_summary(
        samples,
        wind=wind,
        configured_descent_rate_mps=args.descent_rate_mps,
        min_descent_rate_mps=args.min_descent_rate_mps,
        max_descent_time_s=args.max_descent_time_s,
        descent_time_sigma_frac=args.descent_time_sigma_frac,
        assumed_horizontal_position_sigma_m=args.horizontal_position_sigma_m,
        horizontal_velocity_sigma_mps=args.horizontal_velocity_sigma_mps,
        max_state_age_s=args.max_state_age_s,
    )

    if args.svg_out is not None:
        args.svg_out.parent.mkdir(parents=True, exist_ok=True)
        args.svg_out.write_text(render_svg(samples, summary, args.title), encoding="utf-8")
    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        write_json(args.json_out, samples, summary, wind)

    print(f"samples={summary.get('sample_count')}")
    print(f"horizontal_position_rows={summary.get('horizontal_position_rows')}")
    print(f"horizontal_velocity_rows={summary.get('horizontal_velocity_rows')}")
    print(f"wind_available={summary.get('wind_available')}")
    print(f"final_label={summary.get('final_label')}")
    print(f"final_rationale={summary.get('final_rationale')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

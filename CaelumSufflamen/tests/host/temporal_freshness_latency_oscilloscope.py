from __future__ import annotations

import argparse
import csv
import html
import json
import math
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable


UINT32_MAX = 4294967295
DEFAULT_STALE_AGE_MS = 200.0
DEFAULT_SD_PERIOD_MS = 20.0
DEFAULT_PLOT_PERIOD_MS = 200.0

CHANNELS = [
    {
        "key": "baro",
        "label": "barometer",
        "age": "baro_age_ms",
        "valid": "baro_valid",
        "updated": "baro_updated",
        "seq": "baro_seq",
        "color": "#2563eb",
    },
    {
        "key": "imu",
        "label": "IMU",
        "age": "imu_age_ms",
        "valid": "imu_valid",
        "updated": "imu_updated",
        "seq": "imu_seq",
        "color": "#dc2626",
    },
    {
        "key": "aux",
        "label": "aux accel",
        "age": "aux_age_ms",
        "valid": "aux_valid",
        "updated": "aux_updated",
        "seq": "aux_seq",
        "color": "#16a34a",
    },
    {
        "key": "pmod",
        "label": "Pmod accel",
        "age": "pmod_age_ms",
        "valid": "pmod_accel_valid",
        "valid_alias": "pmod_valid",
        "updated": "pmod_accel_updated",
        "seq": "pmod_accel_seq",
        "color": "#f59e0b",
    },
    {
        "key": "mag",
        "label": "magnetometer",
        "age": "mag_age_ms",
        "valid": "mag_valid",
        "updated": "mag_updated",
        "seq": "mag_seq",
        "color": "#7c3aed",
    },
    {
        "key": "att",
        "label": "attitude",
        "age": "att_age_ms",
        "valid": "att_valid",
        "updated": "att_updated",
        "seq": "att_seq",
        "color": "#0891b2",
    },
    {
        "key": "auxvz",
        "label": "vertical accel",
        "age": "auxvz_age_ms",
        "valid": "auxvz_valid",
        "updated": "auxvz_updated",
        "seq": "auxvz_seq",
        "color": "#ea580c",
    },
    {
        "key": "est",
        "label": "estimator",
        "age": "est_age_ms",
        "valid": "est_valid",
        "updated": "est_updated",
        "seq": "est_seq",
        "color": "#0f766e",
    },
    {
        "key": "phase",
        "label": "phase diag",
        "age": "phase_diag_age_ms",
        "valid": "phase_diag_valid",
        "updated": "phase_diag_updated",
        "seq": "phase_diag_seq",
        "color": "#9333ea",
    },
]

PLOT_HEALTH_HEADER = [
    "t_ms",
    "valid_mask",
    "warn_mask",
    "bmp_ok",
    "bmi_accel_ok",
    "bmi_gyro_ok",
    "lis_ok",
    "pmod_accel_ok",
    "mag_ok",
    "baro_valid",
    "imu_valid",
    "aux_valid",
    "pmod_valid",
    "mag_valid",
    "att_valid",
    "auxvz_valid",
    "est_valid",
    "policy_valid",
    "cfg_valid",
    "baro_age_ms",
    "imu_age_ms",
    "aux_age_ms",
    "pmod_age_ms",
    "mag_age_ms",
    "att_age_ms",
    "auxvz_age_ms",
    "est_age_ms",
    "phase_diag_age_ms",
    "sd_card_ok",
    "sd_runtime_failed",
    "sd_fail_count",
]


@dataclass
class TemporalSample:
    t_s: float
    source: str
    row_seq: int | None = None
    warn_mask: int | None = None
    sd_runtime_failed: bool | None = None
    ages_ms: dict[str, float] = field(default_factory=dict)
    valid: dict[str, bool | None] = field(default_factory=dict)
    updated: dict[str, bool | None] = field(default_factory=dict)
    seq: dict[str, int | None] = field(default_factory=dict)
    dt_ms: float = math.nan
    timebase_gap: bool = False
    row_seq_gap: bool = False
    seq_gap_channels: list[str] = field(default_factory=list)


def parse_float(value: object) -> float:
    if value is None:
        return math.nan
    text = str(value).strip()
    if not text:
        return math.nan
    try:
        value_f = float(text)
    except ValueError:
        return math.nan
    if value_f >= UINT32_MAX:
        return math.nan
    return value_f


def parse_int(value: object) -> int | None:
    value_f = parse_float(value)
    if not math.isfinite(value_f):
        return None
    return int(round(value_f))


def bool_cell(row: dict[str, str], *names: str) -> bool | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            value = parse_int(row[name])
            if value is None:
                return None
            return value != 0
    return None


def float_cell(row: dict[str, str], *names: str) -> float:
    for name in names:
        if name in row and row[name] not in ("", None):
            return parse_float(row[name])
    return math.nan


def int_cell(row: dict[str, str], *names: str) -> int | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            return parse_int(row[name])
    return None


def time_from_row(row: dict[str, str]) -> float:
    t_us = float_cell(row, "t_us")
    if math.isfinite(t_us):
        return t_us / 1_000_000.0
    t_ms = float_cell(row, "t_ms")
    if math.isfinite(t_ms):
        return t_ms / 1000.0
    return math.nan


def sample_from_row(row: dict[str, str], source: str) -> TemporalSample | None:
    t_s = time_from_row(row)
    if not math.isfinite(t_s):
        return None

    sample = TemporalSample(
        t_s=t_s,
        source=source,
        row_seq=int_cell(row, "row_seq"),
        warn_mask=int_cell(row, "warn_mask"),
        sd_runtime_failed=bool_cell(row, "sd_runtime_failed"),
    )
    for channel in CHANNELS:
        key = channel["key"]
        sample.ages_ms[key] = float_cell(row, channel["age"])
        valid_names = [channel["valid"]]
        if "valid_alias" in channel:
            valid_names.append(channel["valid_alias"])
        sample.valid[key] = bool_cell(row, *valid_names)
        sample.updated[key] = bool_cell(row, channel["updated"])
        sample.seq[key] = int_cell(row, channel["seq"])
    return sample


def read_sd_csv(path: Path) -> list[TemporalSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    return [sample for row in reader if (sample := sample_from_row(row, "sd")) is not None]


def parse_plot_lines(lines: Iterable[str]) -> list[TemporalSample]:
    header: list[str] | None = None
    mode: str | None = None
    samples: list[TemporalSample] = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR":
            mode = parts[1] if len(parts) > 1 else None
            header = parts[2:]
            continue
        if parts[0] != "PLOT":
            continue
        if header is None:
            if len(parts) >= 2 and parts[1] == "HEALTH":
                mode = "HEALTH"
                header = PLOT_HEALTH_HEADER
            else:
                continue
        if mode is not None and len(parts) >= 2 and parts[1] != mode:
            continue
        if len(parts) - 2 < len(header):
            continue
        sample = sample_from_row(dict(zip(header, parts[2:])), "plot")
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


def read_samples(paths: list[Path], input_format: str) -> list[TemporalSample]:
    samples: list[TemporalSample] = []
    for path in paths:
        if input_format == "sd":
            samples.extend(read_sd_csv(path))
            continue
        if input_format == "plot":
            samples.extend(parse_plot_lines(path.read_text(encoding="utf-8", errors="replace").splitlines()))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        first_line = next((line.strip() for line in text.splitlines() if line.strip()), "")
        if first_line.startswith("PLOT_HDR") or first_line.startswith("PLOT,"):
            samples.extend(parse_plot_lines(text.splitlines()))
        else:
            samples.extend(read_sd_csv(path))
    return enrich_samples(sorted(samples, key=lambda sample: sample.t_s))


def enrich_samples(samples: list[TemporalSample]) -> list[TemporalSample]:
    last_update_t_s: dict[str, float] = {}
    previous_seq: dict[str, int] = {}
    previous_row_seq: int | None = None
    previous_t_s: float | None = None
    for sample in samples:
        if previous_t_s is not None:
            sample.dt_ms = (sample.t_s - previous_t_s) * 1000.0
        previous_t_s = sample.t_s

        if previous_row_seq is not None and sample.row_seq is not None:
            sample.row_seq_gap = sample.row_seq != previous_row_seq + 1
        if sample.row_seq is not None:
            previous_row_seq = sample.row_seq

        for channel in CHANNELS:
            key = channel["key"]
            updated = sample.updated.get(key)
            seq = sample.seq.get(key)
            if seq is not None:
                previous = previous_seq.get(key)
                if previous is not None:
                    delta = seq - previous
                    if delta < 0 or delta > 1:
                        sample.seq_gap_channels.append(key)
                previous_seq[key] = seq

            if updated is True:
                last_update_t_s[key] = sample.t_s
            age = sample.ages_ms.get(key, math.nan)
            if not math.isfinite(age) and key in last_update_t_s:
                sample.ages_ms[key] = max(0.0, (sample.t_s - last_update_t_s[key]) * 1000.0)
    return samples


def resolve_expected_period_ms(samples: list[TemporalSample], expected_period_ms: float | None) -> float:
    if expected_period_ms is not None and expected_period_ms > 0.0:
        return expected_period_ms
    sources = {sample.source for sample in samples}
    if sources == {"plot"}:
        return DEFAULT_PLOT_PERIOD_MS
    if sources == {"sd"}:
        return DEFAULT_SD_PERIOD_MS
    dts = sorted(sample.dt_ms for sample in samples if math.isfinite(sample.dt_ms) and sample.dt_ms > 0.0)
    if not dts:
        return DEFAULT_SD_PERIOD_MS
    return dts[len(dts) // 2]


def channel_is_observed(samples: list[TemporalSample], key: str, required: set[str]) -> bool:
    if key in required:
        return True
    for sample in samples:
        if math.isfinite(sample.ages_ms.get(key, math.nan)):
            return True
        if sample.valid.get(key) is True or sample.updated.get(key) is True:
            return True
        if sample.seq.get(key) not in (None, 0):
            return True
    return False


def finite_values(values: Iterable[float]) -> list[float]:
    return [float(value) for value in values if math.isfinite(float(value))]


def summarize_samples(
    samples: list[TemporalSample],
    *,
    stale_age_ms: float,
    expected_period_ms: float | None,
    gap_factor: float,
    jitter_fraction: float,
    required_channels: set[str],
) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "final_label": "no_samples",
            "final_rationale": "No temporal samples were available.",
        }

    expected_ms = resolve_expected_period_ms(samples, expected_period_ms)
    gap_threshold_ms = expected_ms * gap_factor
    jitter_threshold_ms = max(1.0, expected_ms * jitter_fraction)

    for sample in samples:
        if math.isfinite(sample.dt_ms):
            sample.timebase_gap = sample.dt_ms > gap_threshold_ms

    observed_channels = [
        channel for channel in CHANNELS if channel_is_observed(samples, channel["key"], required_channels)
    ]
    observed_keys = [channel["key"] for channel in observed_channels]

    dts = finite_values(sample.dt_ms for sample in samples)
    warn_rows = sum(1 for sample in samples if sample.warn_mask not in (None, 0))
    sd_failed_rows = sum(1 for sample in samples if sample.sd_runtime_failed is True)
    timebase_gap_rows = sum(1 for sample in samples if sample.timebase_gap)
    timebase_jitter_rows = sum(
        1 for sample in samples if math.isfinite(sample.dt_ms) and abs(sample.dt_ms - expected_ms) > jitter_threshold_ms
    )
    row_seq_gap_rows = sum(1 for sample in samples if sample.row_seq_gap)

    channel_stats: dict[str, dict] = {}
    stale_rows_total = 0
    unavailable_required = 0
    seq_gap_total = 0
    for channel in observed_channels:
        key = channel["key"]
        ages = finite_values(sample.ages_ms.get(key, math.nan) for sample in samples)
        valid_values = [sample.valid.get(key) for sample in samples if sample.valid.get(key) is not None]
        update_count = sum(1 for sample in samples if sample.updated.get(key) is True)
        stale_rows = sum(1 for sample in samples if math.isfinite(sample.ages_ms.get(key, math.nan)) and sample.ages_ms[key] > stale_age_ms)
        unavailable_rows = len(samples) - len(ages)
        seq_gap_count = sum(1 for sample in samples if key in sample.seq_gap_channels)
        seq_gap_total += seq_gap_count
        stale_rows_total += stale_rows
        if key in required_channels and len(ages) == 0 and not any(value is True for value in valid_values):
            unavailable_required += 1
        span_s = max(0.0, samples[-1].t_s - samples[0].t_s)
        channel_stats[key] = {
            "label": channel["label"],
            "observed": True,
            "required": key in required_channels,
            "max_age_ms": max(ages, default=math.nan),
            "mean_age_ms": (sum(ages) / len(ages)) if ages else math.nan,
            "stale_rows": stale_rows,
            "unavailable_rows": unavailable_rows,
            "fresh_fraction": (sum(1 for age in ages if age <= stale_age_ms) / len(ages)) if ages else math.nan,
            "valid_fraction": (sum(1 for value in valid_values if value is True) / len(valid_values)) if valid_values else math.nan,
            "update_count": update_count,
            "update_rate_hz": (update_count / span_s) if span_s > 0.0 else math.nan,
            "seq_gap_count": seq_gap_count,
        }

    if timebase_gap_rows > 0 or row_seq_gap_rows > 0:
        final_label = "timebase_gap_detected"
        rationale = "Sample spacing or row sequence continuity shows a timing/logging gap."
    elif unavailable_required > 0:
        final_label = "required_channel_unavailable"
        rationale = "At least one required channel had no freshness evidence."
    elif seq_gap_total > 0:
        final_label = "channel_sequence_gap_detected"
        rationale = "At least one observed channel sequence counter skipped or reset unexpectedly."
    elif stale_rows_total > 0 or warn_rows > 0 or sd_failed_rows > 0:
        final_label = "freshness_warning_limited"
        rationale = "Timing cadence is continuous, but stale channel ages, warnings, or SD runtime faults are present."
    elif not observed_channels:
        final_label = "freshness_evidence_unavailable"
        rationale = "Rows are present, but no channel freshness, update, age, or sequence evidence was observed."
    else:
        final_label = "temporal_contract_nominal"
        rationale = "Timebase cadence, observed channel freshness, update continuity, and warnings are nominal."

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "source_kinds": sorted({sample.source for sample in samples}),
        "expected_period_ms": expected_ms,
        "gap_threshold_ms": gap_threshold_ms,
        "jitter_threshold_ms": jitter_threshold_ms,
        "mean_dt_ms": (sum(dts) / len(dts)) if dts else math.nan,
        "max_dt_ms": max(dts, default=math.nan),
        "min_dt_ms": min(dts, default=math.nan),
        "timebase_gap_rows": timebase_gap_rows,
        "timebase_jitter_rows": timebase_jitter_rows,
        "row_seq_gap_rows": row_seq_gap_rows,
        "warn_row_count": warn_rows,
        "sd_runtime_failed_rows": sd_failed_rows,
        "stale_rows_total": stale_rows_total,
        "channel_sequence_gap_rows": sum(1 for sample in samples if sample.seq_gap_channels),
        "channel_sequence_gap_total": seq_gap_total,
        "observed_channels": observed_keys,
        "required_channels": sorted(required_channels),
        "unavailable_required_channels": unavailable_required,
        "channel_stats": channel_stats,
        "parameters": {
            "stale_age_ms": stale_age_ms,
            "expected_period_ms": expected_ms,
            "gap_factor": gap_factor,
            "jitter_fraction": jitter_fraction,
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
    pad = 0.10 * span
    center = 0.5 * (lo + hi)
    return min(lo - pad, center - span / 2.0), max(hi + pad, center + span / 2.0)


def panel(x: float, y: float, w: float, h: float, title: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="#cbd5e1"/>'
        f'<text x="{x + 12}" y="{y + 24}" class="panel-title">{html.escape(title)}</text>'
    )


def polyline(samples: list[TemporalSample], attr_fn, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = attr_fn(sample)
        if math.isfinite(value):
            points.append(f"{sx(sample.t_s):.2f},{sy(value):.2f}")
    return " ".join(points)


def horizontal_line(y: float, x0: float, x1: float, label: str = "") -> str:
    text = f'<text x="{x1 - 54:.2f}" y="{y - 4:.2f}" class="tiny">{html.escape(label)}</text>' if label else ""
    return f'<line x1="{x0:.2f}" y1="{y:.2f}" x2="{x1:.2f}" y2="{y:.2f}" stroke="#94a3b8" stroke-width="1" stroke-dasharray="5 5"/>{text}'


def warning_ticks(samples: list[TemporalSample], sx, y0: float, y1: float) -> str:
    pieces: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            pieces.append(f'<line x1="{x:.2f}" y1="{y0:.2f}" x2="{x:.2f}" y2="{y1:.2f}" stroke="#dc2626" stroke-width="1" opacity="0.18"/>')
    return "\n".join(pieces)


def status_color(label: str) -> str:
    if label == "temporal_contract_nominal":
        return "#16a34a"
    if label in {"freshness_warning_limited", "freshness_evidence_unavailable"}:
        return "#f59e0b"
    return "#dc2626"


def raster_color(sample: TemporalSample, key: str, stale_age_ms: float) -> str:
    age = sample.ages_ms.get(key, math.nan)
    if math.isfinite(age):
        if age > stale_age_ms:
            return "#ef4444"
        if sample.updated.get(key) is True:
            return "#22c55e"
        return "#60a5fa"
    if sample.valid.get(key) is False:
        return "#fca5a5"
    return "#cbd5e1"


def render_channel_raster(
    samples: list[TemporalSample],
    observed_channels: list[dict],
    sx,
    x: float,
    y: float,
    w: float,
    row_h: float,
    stale_age_ms: float,
) -> str:
    pieces: list[str] = []
    for row_index, channel in enumerate(observed_channels):
        y0 = y + row_index * row_h
        pieces.append(f'<text x="{x}" y="{y0 + row_h - 4:.2f}" class="tiny">{html.escape(channel["label"])}</text>')
        pieces.append(f'<line x1="{x + 104}" y1="{y0 + row_h - 2:.2f}" x2="{x + w}" y2="{y0 + row_h - 2:.2f}" stroke="#e2e8f0"/>')
    for left, right in zip(samples, samples[1:]):
        x0 = sx(left.t_s)
        width = max(1.0, sx(right.t_s) - x0)
        for row_index, channel in enumerate(observed_channels):
            color = raster_color(left, channel["key"], stale_age_ms)
            pieces.append(
                f'<rect x="{x0:.2f}" y="{y + row_index * row_h:.2f}" width="{width:.2f}" height="{row_h - 2:.2f}" fill="{color}" opacity="0.78"/>'
            )
    return "\n".join(pieces)


def render_event_raster(samples: list[TemporalSample], sx, x: float, y: float, w: float, row_h: float) -> str:
    rows = [
        ("time gap", lambda sample: sample.timebase_gap, "#dc2626"),
        ("row gap", lambda sample: sample.row_seq_gap, "#ea580c"),
        ("seq gap", lambda sample: bool(sample.seq_gap_channels), "#f59e0b"),
        ("warn", lambda sample: sample.warn_mask not in (None, 0), "#7c3aed"),
        ("SD fail", lambda sample: sample.sd_runtime_failed is True, "#991b1b"),
    ]
    pieces: list[str] = []
    for row_index, (label, _, _) in enumerate(rows):
        y0 = y + row_index * row_h
        pieces.append(f'<text x="{x}" y="{y0 + row_h - 4:.2f}" class="tiny">{html.escape(label)}</text>')
        pieces.append(f'<line x1="{x + 74}" y1="{y0 + row_h - 2:.2f}" x2="{x + w}" y2="{y0 + row_h - 2:.2f}" stroke="#e2e8f0"/>')
    for left, right in zip(samples, samples[1:]):
        x0 = sx(left.t_s)
        width = max(1.0, sx(right.t_s) - x0)
        for row_index, (_, predicate, color) in enumerate(rows):
            if predicate(left):
                pieces.append(
                    f'<rect x="{x0:.2f}" y="{y + row_index * row_h:.2f}" width="{width:.2f}" height="{row_h - 2:.2f}" fill="{color}" opacity="0.78"/>'
                )
    return "\n".join(pieces)


def legend_item(x: int, y: int, color: str, label: str) -> str:
    return (
        f'<line x1="{x}" y1="{y}" x2="{x + 26}" y2="{y}" stroke="{color}" stroke-width="3"/>'
        f'<text x="{x + 34}" y="{y + 4}" class="legend">{html.escape(label)}</text>'
    )


def render_svg(samples: list[TemporalSample], summary: dict, title: str = "Temporal Freshness / Latency Oscilloscope") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1220
    height = 910
    time_panel = (84.0, 84.0, 1036.0, 185.0)
    age_panel = (84.0, 304.0, 650.0, 230.0)
    event_panel = (774.0, 304.0, 346.0, 230.0)
    raster_panel = (84.0, 570.0, 1036.0, 214.0)

    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx_time = scale_fn(t_min, t_max, time_panel[0] + 44, time_panel[0] + time_panel[2] - 24)
    sx_age = scale_fn(t_min, t_max, age_panel[0] + 44, age_panel[0] + age_panel[2] - 24)
    sx_event = scale_fn(t_min, t_max, event_panel[0] + 92, event_panel[0] + event_panel[2] - 20)
    sx_raster = scale_fn(t_min, t_max, raster_panel[0] + 128, raster_panel[0] + raster_panel[2] - 22)

    dts = finite_values(sample.dt_ms for sample in samples)
    dt_min, dt_max = bounds(dts + [summary["expected_period_ms"]], max(10.0, summary["expected_period_ms"] * 0.5), include_zero=True)
    sy_time = scale_fn(dt_min, dt_max, time_panel[1] + time_panel[3] - 34, time_panel[1] + 42)

    observed_channels = [channel for channel in CHANNELS if channel["key"] in summary["observed_channels"]]
    age_values: list[float] = []
    for channel in observed_channels:
        age_values.extend(finite_values(sample.ages_ms.get(channel["key"], math.nan) for sample in samples))
    age_min, age_max = bounds(age_values + [summary["parameters"]["stale_age_ms"]], 100.0, include_zero=True)
    age_max = max(age_max, summary["parameters"]["stale_age_ms"] * 1.2)
    sy_age = scale_fn(age_min, age_max, age_panel[1] + age_panel[3] - 34, age_panel[1] + 42)

    expected_y = sy_time(summary["expected_period_ms"])
    stale_y = sy_age(summary["parameters"]["stale_age_ms"])
    age_lines = []
    for channel in observed_channels:
        key = channel["key"]
        points = polyline(samples, lambda sample, key=key: sample.ages_ms.get(key, math.nan), sx_age, sy_age)
        if points:
            age_lines.append(f'<polyline points="{points}" fill="none" stroke="{channel["color"]}" stroke-width="1.8"/>')

    legend = []
    for index, channel in enumerate(observed_channels[:6]):
        legend.append(legend_item(820, 95 + index * 18, channel["color"], channel["label"]))
    verdict = summary["final_label"]
    verdict_color = status_color(verdict)
    metric_text = (
        f"samples={summary['sample_count']} mean_dt={summary['mean_dt_ms']:.2f}ms "
        f"max_dt={summary['max_dt_ms']:.2f}ms time_gaps={summary['timebase_gap_rows']} "
        f"row_gaps={summary['row_seq_gap_rows']} seq_gap_rows={summary['channel_sequence_gap_rows']} "
        f"stale_rows={summary['stale_rows_total']} warn={summary['warn_row_count']}"
    )

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .panel-title {{ font: 700 14px Arial, sans-serif; fill: #0f172a; }}
  .axis {{ font: 11px Arial, sans-serif; fill: #334155; }}
  .tiny {{ font: 10px Consolas, monospace; fill: #0f172a; }}
  .legend {{ font: 11px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
</style>
<rect width="{width}" height="{height}" fill="#f8fafc"/>
<text x="84" y="40" class="title">{html.escape(title)}</text>
<text x="84" y="60" class="subtitle">Timebase jitter, update cadence, derived channel age, sequence gaps, warnings, and SD runtime timing evidence.</text>
{''.join(legend)}
{panel(*time_panel, "sample period / timebase jitter")}
{panel(*age_panel, "channel freshness ages")}
{panel(*event_panel, "gap / warning events")}
{panel(*raster_panel, "freshness and update raster")}
{warning_ticks(samples, sx_time, time_panel[1] + 34, time_panel[1] + time_panel[3] - 24)}
{horizontal_line(expected_y, time_panel[0] + 44, time_panel[0] + time_panel[2] - 24, "expected")}
<polyline points="{polyline(samples, lambda sample: sample.dt_ms, sx_time, sy_time)}" fill="none" stroke="#2563eb" stroke-width="2.1"/>
<text x="{time_panel[0] + 10}" y="{time_panel[1] + time_panel[3] - 10}" class="axis">t {samples[0].t_s:.2f}s .. {samples[-1].t_s:.2f}s</text>
<text x="{time_panel[0] + 10}" y="{time_panel[1] + 44}" class="axis">dt ms</text>
{horizontal_line(stale_y, age_panel[0] + 44, age_panel[0] + age_panel[2] - 24, "stale")}
{warning_ticks(samples, sx_age, age_panel[1] + 34, age_panel[1] + age_panel[3] - 24)}
{''.join(age_lines)}
<text x="{age_panel[0] + 10}" y="{age_panel[1] + age_panel[3] - 10}" class="axis">t</text>
<text x="{age_panel[0] + 10}" y="{age_panel[1] + 44}" class="axis">age ms</text>
{render_event_raster(samples, sx_event, event_panel[0] + 12, event_panel[1] + 48, event_panel[2] - 24, 27)}
<text x="{event_panel[0] + 18}" y="{event_panel[1] + 198}" class="tiny">red/orange: timing continuity fault; purple: warning-mask evidence</text>
{render_channel_raster(samples, observed_channels, sx_raster, raster_panel[0] + 12, raster_panel[1] + 42, raster_panel[2] - 26, 17, summary['parameters']['stale_age_ms'])}
<text x="{raster_panel[0] + 18}" y="{raster_panel[1] + 198}" class="tiny">green=updated, blue=fresh/held, red=stale or invalid, gray=unavailable</text>
<rect x="84" y="812" width="1036" height="56" fill="#ffffff" stroke="#cbd5e1"/>
<rect x="100" y="828" width="18" height="18" fill="{verdict_color}"/>
<text x="128" y="842" class="metric">final_label={html.escape(verdict)} | {html.escape(summary['final_rationale'])}</text>
<text x="100" y="862" class="metric">{html.escape(metric_text)}</text>
</svg>
'''


def write_json(path: Path, samples: list[TemporalSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "temporal-freshness-latency-oscilloscope-v1",
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_channels(text: str) -> set[str]:
    values = {value.strip().lower() for value in text.split(",") if value.strip()}
    valid = {channel["key"] for channel in CHANNELS}
    unknown = values - valid
    if unknown:
        raise argparse.ArgumentTypeError(f"Unknown channel(s): {', '.join(sorted(unknown))}")
    return values


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a temporal freshness and latency oscilloscope from current-schema SD CSV or captured PLOT HEALTH rows."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input current-schema SD CSV or captured PLOT HEALTH text file.")
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
    parser.add_argument("--stale-age-ms", type=float, default=DEFAULT_STALE_AGE_MS)
    parser.add_argument("--expected-period-ms", type=float, default=None)
    parser.add_argument("--gap-factor", type=float, default=1.5)
    parser.add_argument("--jitter-fraction", type=float, default=0.35)
    parser.add_argument("--required-channels", type=parse_channels, default=set())
    parser.add_argument("--serial-port", help="Optional live serial port. Requires pyserial.")
    parser.add_argument(
        "--serial-command",
        action="append",
        default=[],
        help="Command to send after opening the serial port before capture. Repeatable, for example HDR 0 then PLOT HEALTH.",
    )
    parser.add_argument("--serial-settle-ms", type=int, default=250)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration-s", type=float, default=10.0)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--raw-out", type=Path)
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Temporal Freshness / Latency Oscilloscope")
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
        samples = enrich_samples(parse_plot_lines(lines))
    else:
        if not args.input:
            raise SystemExit("Provide at least one input file or --serial-port.")
        samples = read_samples(args.input, args.input_format)

    if args.max_rows is not None:
        samples = enrich_samples(samples[: args.max_rows])
    if not samples:
        raise SystemExit("No usable temporal freshness samples found.")

    summary = summarize_samples(
        samples,
        stale_age_ms=args.stale_age_ms,
        expected_period_ms=args.expected_period_ms,
        gap_factor=args.gap_factor,
        jitter_fraction=args.jitter_fraction,
        required_channels=args.required_channels,
    )
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, summary, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"source_kinds={','.join(summary['source_kinds'])}")
    print(f"expected_period_ms={summary['expected_period_ms']:.3f}")
    print(f"mean_dt_ms={summary['mean_dt_ms']:.3f}")
    print(f"max_dt_ms={summary['max_dt_ms']:.3f}")
    print(f"timebase_gap_rows={summary['timebase_gap_rows']}")
    print(f"row_seq_gap_rows={summary['row_seq_gap_rows']}")
    print(f"channel_sequence_gap_rows={summary['channel_sequence_gap_rows']}")
    print(f"stale_rows_total={summary['stale_rows_total']}")
    print(f"warn_row_count={summary['warn_row_count']}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

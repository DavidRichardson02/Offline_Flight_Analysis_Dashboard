from __future__ import annotations

import argparse
import html
import json
import math
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_HEADING_BIN_COUNT = 24


@dataclass
class HeadingRecord:
    t_s: float
    roll_deg: float
    pitch_deg: float
    planar_heading_deg: float
    tilt_heading_deg: float
    heading_delta_deg: float
    gravity_residual_mps2: float
    mag_norm_uT: float
    attitude_ready: bool
    gravity_ready: bool
    magnetic_ready: bool
    heading_ready: bool
    quality_label: str
    warn_mask: int | None
    mag_interference: bool


@dataclass
class PoseSegment:
    index: int
    label: str
    start_s: float
    end_s: float
    sample_count: int
    ready_count: int
    ready_fraction: float
    mean_roll_deg: float
    mean_pitch_deg: float
    roll_span_deg: float
    pitch_span_deg: float
    mean_planar_heading_deg: float
    mean_tilt_heading_deg: float
    mean_heading_delta_deg: float
    tilt_heading_span_deg: float
    planar_heading_span_deg: float
    mean_gravity_residual_mps2: float
    mean_mag_norm_uT: float
    accepted: bool


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


def parse_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return False
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() in {"1", "true", "yes", "y"}


def parse_int(value: object) -> int | None:
    value_f = parse_float(value)
    if not math.isfinite(value_f):
        return None
    return int(round(value_f))


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


def finite_values(values: Iterable[float]) -> list[float]:
    result: list[float] = []
    for value in values:
        value_f = float(value)
        if math.isfinite(value_f):
            result.append(value_f)
    return result


def mean(values: Iterable[float]) -> float:
    vals = finite_values(values)
    return sum(vals) / len(vals) if vals else math.nan


def stdev(values: Iterable[float]) -> float:
    vals = finite_values(values)
    if len(vals) < 2:
        return 0.0 if vals else math.nan
    avg = sum(vals) / len(vals)
    return math.sqrt(sum((value - avg) ** 2 for value in vals) / (len(vals) - 1))


def angle_mean_deg(values: Iterable[float]) -> float:
    vals = finite_values(values)
    if not vals:
        return math.nan
    sin_sum = sum(math.sin(math.radians(value)) for value in vals)
    cos_sum = sum(math.cos(math.radians(value)) for value in vals)
    if abs(sin_sum) < 1.0e-12 and abs(cos_sum) < 1.0e-12:
        return math.nan
    return wrap360(math.degrees(math.atan2(sin_sum, cos_sum)))


def angle_span_deg(values: Iterable[float]) -> float:
    vals = finite_values(values)
    if len(vals) < 2:
        return 0.0 if vals else math.nan
    center = angle_mean_deg(vals)
    if not math.isfinite(center):
        return math.nan
    deltas = [signed_angle_delta_deg(value, center) for value in vals]
    return max(deltas) - min(deltas)


def read_heading_json(path: Path) -> tuple[list[HeadingRecord], dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    raw_samples = payload.get("samples", [])
    records: list[HeadingRecord] = []
    for row in raw_samples:
        if not isinstance(row, dict):
            continue
        t_s = parse_float(row.get("t_s"))
        if not math.isfinite(t_s):
            continue
        records.append(
            HeadingRecord(
                t_s=t_s,
                roll_deg=parse_float(row.get("roll_deg")),
                pitch_deg=parse_float(row.get("pitch_deg")),
                planar_heading_deg=wrap360(parse_float(row.get("planar_heading_deg"))),
                tilt_heading_deg=wrap360(parse_float(row.get("tilt_heading_deg"))),
                heading_delta_deg=parse_float(row.get("heading_delta_deg")),
                gravity_residual_mps2=parse_float(row.get("gravity_residual_mps2")),
                mag_norm_uT=parse_float(row.get("mag_norm_uT")),
                attitude_ready=parse_bool(row.get("attitude_ready")),
                gravity_ready=parse_bool(row.get("gravity_ready")),
                magnetic_ready=parse_bool(row.get("magnetic_ready")),
                heading_ready=parse_bool(row.get("heading_ready")),
                quality_label=str(row.get("quality_label", "")),
                warn_mask=parse_int(row.get("warn_mask")),
                mag_interference=parse_bool(row.get("mag_interference")),
            )
        )
    return sorted(records, key=lambda sample: sample.t_s), payload.get("summary", {})


def usable_for_pose(sample: HeadingRecord) -> bool:
    return (
        math.isfinite(sample.roll_deg)
        and math.isfinite(sample.pitch_deg)
        and math.isfinite(sample.planar_heading_deg)
        and math.isfinite(sample.tilt_heading_deg)
    )


def summarize_segment(index: int, rows: list[HeadingRecord], min_pose_samples: int) -> PoseSegment:
    ready_count = sum(1 for sample in rows if sample.heading_ready)
    return PoseSegment(
        index=index,
        label="unlabeled",
        start_s=rows[0].t_s,
        end_s=rows[-1].t_s,
        sample_count=len(rows),
        ready_count=ready_count,
        ready_fraction=ready_count / len(rows),
        mean_roll_deg=angle_mean_deg(sample.roll_deg for sample in rows),
        mean_pitch_deg=mean(sample.pitch_deg for sample in rows),
        roll_span_deg=angle_span_deg(sample.roll_deg for sample in rows),
        pitch_span_deg=max(finite_values(sample.pitch_deg for sample in rows), default=math.nan)
        - min(finite_values(sample.pitch_deg for sample in rows), default=math.nan),
        mean_planar_heading_deg=angle_mean_deg(sample.planar_heading_deg for sample in rows),
        mean_tilt_heading_deg=angle_mean_deg(sample.tilt_heading_deg for sample in rows),
        mean_heading_delta_deg=angle_mean_deg(sample.heading_delta_deg for sample in rows),
        tilt_heading_span_deg=angle_span_deg(sample.tilt_heading_deg for sample in rows),
        planar_heading_span_deg=angle_span_deg(sample.planar_heading_deg for sample in rows),
        mean_gravity_residual_mps2=mean(sample.gravity_residual_mps2 for sample in rows),
        mean_mag_norm_uT=mean(sample.mag_norm_uT for sample in rows),
        accepted=len(rows) >= min_pose_samples,
    )


def segment_pose_runs(
    samples: list[HeadingRecord],
    *,
    pose_change_deg: float,
    min_pose_samples: int,
) -> list[PoseSegment]:
    usable = [sample for sample in samples if usable_for_pose(sample)]
    if not usable:
        return []

    raw_segments: list[list[HeadingRecord]] = []
    current: list[HeadingRecord] = []
    for sample in usable:
        if not current:
            current.append(sample)
            continue
        roll_mean = angle_mean_deg(row.roll_deg for row in current)
        pitch_mean = mean(row.pitch_deg for row in current)
        roll_step = abs(signed_angle_delta_deg(sample.roll_deg, roll_mean))
        pitch_step = abs(sample.pitch_deg - pitch_mean) if math.isfinite(pitch_mean) else math.inf
        if roll_step > pose_change_deg or pitch_step > pose_change_deg:
            raw_segments.append(current)
            current = [sample]
        else:
            current.append(sample)
    if current:
        raw_segments.append(current)

    segments = [
        summarize_segment(index, rows, min_pose_samples)
        for index, rows in enumerate(raw_segments)
        if rows
    ]
    label_pose_segments(segments)
    return segments


def label_pose_segments(segments: list[PoseSegment], min_pose_tilt_deg: float = 8.0) -> None:
    accepted = [segment for segment in segments if segment.accepted]
    if not accepted:
        return
    reference = accepted[0]
    reference.label = "level_reference"
    for segment in segments:
        if segment is reference:
            continue
        droll = signed_angle_delta_deg(segment.mean_roll_deg, reference.mean_roll_deg)
        dpitch = segment.mean_pitch_deg - reference.mean_pitch_deg
        if not math.isfinite(droll) or not math.isfinite(dpitch):
            segment.label = "unusable"
        elif max(abs(droll), abs(dpitch)) < min_pose_tilt_deg:
            segment.label = "near_reference"
        elif abs(droll) >= abs(dpitch):
            segment.label = "+roll" if droll > 0.0 else "-roll"
        else:
            segment.label = "+pitch" if dpitch > 0.0 else "-pitch"


def heading_bins(samples: list[HeadingRecord], bin_count: int) -> list[dict]:
    bins = [
        {
            "index": index,
            "center_deg": (index + 0.5) * 360.0 / bin_count,
            "count": 0,
            "ready_count": 0,
        }
        for index in range(bin_count)
    ]
    for sample in samples:
        heading = sample.planar_heading_deg
        if not math.isfinite(heading):
            continue
        index = int((wrap360(heading) / 360.0) * bin_count) % bin_count
        bins[index]["count"] += 1
        if sample.magnetic_ready:
            bins[index]["ready_count"] += 1
    return bins


def label_counts(samples: list[HeadingRecord]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for sample in samples:
        label = sample.quality_label or "unlabeled"
        counts[label] = counts.get(label, 0) + 1
    return counts


def pair_metric(
    segments: list[PoseSegment],
    positive_label: str,
    negative_label: str,
    reference_delta: float,
) -> dict:
    positive = next((segment for segment in segments if segment.accepted and segment.label == positive_label), None)
    negative = next((segment for segment in segments if segment.accepted and segment.label == negative_label), None)
    if positive is None or negative is None or not math.isfinite(reference_delta):
        return {
            "available": False,
            "positive_offset_deg": math.nan,
            "negative_offset_deg": math.nan,
            "opposes_reference": False,
        }
    pos_offset = signed_angle_delta_deg(positive.mean_heading_delta_deg, reference_delta)
    neg_offset = signed_angle_delta_deg(negative.mean_heading_delta_deg, reference_delta)
    return {
        "available": True,
        "positive_offset_deg": pos_offset,
        "negative_offset_deg": neg_offset,
        "opposes_reference": math.isfinite(pos_offset)
        and math.isfinite(neg_offset)
        and abs(pos_offset) >= 1.0
        and abs(neg_offset) >= 1.0
        and (pos_offset * neg_offset) < 0.0,
    }


def summarize_validation(
    samples: list[HeadingRecord],
    source_summary: dict,
    *,
    pose_change_deg: float,
    min_pose_samples: int,
    min_ready_fraction: float,
    max_tilt_heading_span_deg: float,
    heading_bin_count: int,
    min_calibration_bins: int,
    min_partial_calibration_bins: int,
    max_static_mag_norm_std_uT: float,
) -> tuple[dict, list[PoseSegment], list[dict]]:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "final_label": "no_samples",
            "final_rationale": "No heading samples were available.",
        }, [], []

    segments = segment_pose_runs(samples, pose_change_deg=pose_change_deg, min_pose_samples=min_pose_samples)
    accepted = [segment for segment in segments if segment.accepted]
    bins = heading_bins(samples, heading_bin_count)
    ready_count = sum(1 for sample in samples if sample.heading_ready)
    magnetic_ready_count = sum(1 for sample in samples if sample.magnetic_ready)
    mag_interference_count = sum(1 for sample in samples if sample.mag_interference)

    accepted_tilt_span = angle_span_deg(segment.mean_tilt_heading_deg for segment in accepted)
    accepted_planar_span = angle_span_deg(segment.mean_planar_heading_deg for segment in accepted)
    covered_bins = sum(1 for item in bins if item["ready_count"] > 0)
    mag_norm_std = stdev(sample.mag_norm_uT for sample in samples if sample.magnetic_ready)
    max_gravity_residual = max(
        finite_values(abs(sample.gravity_residual_mps2) for sample in samples),
        default=math.nan,
    )

    reference = next((segment for segment in accepted if segment.label == "level_reference"), accepted[0] if accepted else None)
    reference_delta = reference.mean_heading_delta_deg if reference is not None else math.nan
    roll_pair = pair_metric(accepted, "+roll", "-roll", reference_delta)
    pitch_pair = pair_metric(accepted, "+pitch", "-pitch", reference_delta)
    has_roll_pair = roll_pair["available"]
    has_pitch_pair = pitch_pair["available"]
    has_any_pose_pair = has_roll_pair or has_pitch_pair
    pair_opposes = bool(roll_pair["opposes_reference"] or pitch_pair["opposes_reference"])

    ready_fraction = ready_count / len(samples)
    magnetic_ready_fraction = magnetic_ready_count / len(samples)

    if ready_fraction < min_ready_fraction:
        sign_state = "prerequisites_not_ready"
        sign_rationale = "Heading readiness fraction is below the configured sign-validation threshold."
    elif len(accepted) < 3 or not has_any_pose_pair:
        sign_state = "insufficient_pose_coverage"
        sign_rationale = "Capture does not include enough accepted roll/pitch pose coverage."
    elif math.isfinite(accepted_tilt_span) and accepted_tilt_span <= max_tilt_heading_span_deg and pair_opposes:
        sign_state = "sign_convention_supported"
        sign_rationale = "Tilt-compensated heading stayed bounded and at least one opposing pose pair changed correction sign."
    elif math.isfinite(accepted_tilt_span) and accepted_tilt_span <= max_tilt_heading_span_deg:
        sign_state = "heading_stable_pair_sign_inconclusive"
        sign_rationale = "Tilt-compensated heading stayed bounded, but opposing-pair correction sign evidence is weak."
    else:
        sign_state = "sign_convention_suspect"
        sign_rationale = "Tilt-compensated heading did not remain stable across accepted poses."

    if magnetic_ready_fraction < min_ready_fraction or mag_interference_count > 0:
        calibration_state = "magnetic_prerequisites_not_ready"
    elif covered_bins >= min_calibration_bins and math.isfinite(mag_norm_std) and mag_norm_std <= max_static_mag_norm_std_uT:
        calibration_state = "calibration_sweep_supported"
    elif covered_bins >= min_partial_calibration_bins:
        calibration_state = "partial_heading_coverage"
    else:
        calibration_state = "insufficient_heading_coverage"

    final_label = sign_state if sign_state != "sign_convention_supported" else calibration_state
    if sign_state == "sign_convention_supported" and calibration_state == "calibration_sweep_supported":
        final_label = "sign_and_calibration_supported"

    summary = {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "source_summary": source_summary,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "ready_count": ready_count,
        "ready_fraction": ready_fraction,
        "magnetic_ready_fraction": magnetic_ready_fraction,
        "pose_segment_count": len(segments),
        "accepted_pose_count": len(accepted),
        "accepted_pose_labels": [segment.label for segment in accepted],
        "accepted_tilt_heading_span_deg": accepted_tilt_span,
        "accepted_planar_heading_span_deg": accepted_planar_span,
        "max_abs_gravity_residual_mps2": max_gravity_residual,
        "mag_norm_std_uT": mag_norm_std,
        "mag_interference_rows": mag_interference_count,
        "heading_bin_count": heading_bin_count,
        "heading_coverage_bins": covered_bins,
        "label_counts": label_counts(samples),
        "roll_pair": roll_pair,
        "pitch_pair": pitch_pair,
        "sign_state": sign_state,
        "sign_rationale": sign_rationale,
        "calibration_state": calibration_state,
        "final_label": final_label,
        "final_rationale": (
            f"{sign_rationale} Magnetic coverage state: {calibration_state} "
            f"({covered_bins}/{heading_bin_count} heading bins)."
        ),
    }
    return summary, segments, bins


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def polyline(samples: list[HeadingRecord], sx, sy, attr: str, color: str, width: float = 2.0, dash: str = "") -> str:
    chunks: list[str] = []
    current: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if math.isfinite(value):
            current.append(f"{sx(sample.t_s):.2f},{sy(value):.2f}")
        elif current:
            chunks.append(" ".join(current))
            current = []
    if current:
        chunks.append(" ".join(current))
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return "\n".join(
        f'<polyline points="{points}" fill="none" stroke="{color}" stroke-width="{width}"{dash_attr}/>'
        for points in chunks
    )


def panel(x: float, y: float, w: float, h: float, title: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="#cbd5e1"/>'
        f'<text x="{x + 14}" y="{y + 25}" class="panel_title">{html.escape(title)}</text>'
    )


def verdict_color(label: str) -> str:
    if label in {"sign_and_calibration_supported", "sign_convention_supported", "calibration_sweep_supported"}:
        return "#16a34a"
    if label in {"heading_stable_pair_sign_inconclusive", "partial_heading_coverage", "insufficient_heading_coverage"}:
        return "#f59e0b"
    return "#dc2626"


def summary_cards(summary: dict, x: float, y: float) -> str:
    cards = [
        ("sign", summary["sign_state"], summary["ready_fraction"]),
        ("calibration", summary["calibration_state"], summary["heading_coverage_bins"] / max(1, summary["heading_bin_count"])),
        ("poses", f"{summary['accepted_pose_count']} accepted", summary["accepted_pose_count"] / max(1, 5)),
    ]
    pieces: list[str] = []
    for index, (title, value, fraction) in enumerate(cards):
        cx = x + index * 240
        color = verdict_color(str(value))
        pieces.append(f'<rect x="{cx}" y="{y}" width="220" height="78" fill="#f8fafc" stroke="{color}" stroke-width="2"/>')
        pieces.append(f'<text x="{cx + 14}" y="{y + 25}" class="label">{html.escape(title)}</text>')
        pieces.append(f'<text x="{cx + 14}" y="{y + 50}" class="metric">{html.escape(str(value))}</text>')
        pieces.append(f'<rect x="{cx + 14}" y="{y + 60}" width="180" height="7" fill="#e2e8f0"/>')
        pieces.append(f'<rect x="{cx + 14}" y="{y + 60}" width="{max(0.0, min(1.0, fraction)) * 180:.2f}" height="7" fill="{color}"/>')
    return "\n".join(pieces)


def pose_table(segments: list[PoseSegment], x: float, y: float) -> str:
    rows = [
        '<text x="{:.2f}" y="{:.2f}" class="metric">idx label n ready roll pitch tilt planar delta</text>'.format(x, y)
    ]
    for idx, segment in enumerate(segments[:9]):
        color = "#16a34a" if segment.accepted else "#94a3b8"
        text = (
            f"{segment.index:02d} {segment.label:<15} {segment.sample_count:3d} "
            f"{segment.ready_fraction:4.2f} {segment.mean_roll_deg:7.2f} "
            f"{segment.mean_pitch_deg:7.2f} {segment.mean_tilt_heading_deg:7.2f} "
            f"{segment.mean_planar_heading_deg:7.2f} {segment.mean_heading_delta_deg:7.2f}"
        )
        rows.append(f'<circle cx="{x + 5}" cy="{y + 22 + idx * 18:.2f}" r="4" fill="{color}"/>')
        rows.append(f'<text x="{x + 16}" y="{y + 26 + idx * 18:.2f}" class="metric">{html.escape(text)}</text>')
    return "\n".join(rows)


def heading_bin_chart(bins: list[dict], x: float, y: float, w: float, h: float) -> str:
    if not bins:
        return ""
    max_count = max((item["ready_count"] for item in bins), default=1)
    max_count = max(1, max_count)
    bar_w = w / len(bins)
    pieces: list[str] = []
    for item in bins:
        bar_h = (item["ready_count"] / max_count) * (h - 28)
        bx = x + item["index"] * bar_w
        by = y + h - bar_h - 18
        fill = "#2563eb" if item["ready_count"] > 0 else "#e2e8f0"
        pieces.append(f'<rect x="{bx:.2f}" y="{by:.2f}" width="{max(1.0, bar_w - 2):.2f}" height="{bar_h:.2f}" fill="{fill}"/>')
    pieces.append(f'<line x1="{x}" y1="{y + h - 18}" x2="{x + w}" y2="{y + h - 18}" class="axis"/>')
    pieces.append(f'<text x="{x}" y="{y + h - 2}" class="label">0 deg</text>')
    pieces.append(f'<text x="{x + w - 42}" y="{y + h - 2}" class="label">360</text>')
    return "\n".join(pieces)


def pose_scatter(samples: list[HeadingRecord], sx, sy) -> str:
    pieces: list[str] = []
    for sample in samples:
        if not math.isfinite(sample.roll_deg) or not math.isfinite(sample.pitch_deg):
            continue
        fill = "#16a34a" if sample.heading_ready else "#dc2626"
        pieces.append(f'<circle cx="{sx(sample.roll_deg):.2f}" cy="{sy(sample.pitch_deg):.2f}" r="2.2" fill="{fill}" opacity="0.72"/>')
    return "\n".join(pieces)


def render_svg(
    samples: list[HeadingRecord],
    segments: list[PoseSegment],
    bins: list[dict],
    summary: dict,
    title: str,
) -> str:
    if not samples:
        raise ValueError("Cannot render an empty validation set")

    width = 1280
    height = 920
    left = 84
    right = 1200
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx_time = scale_fn(t_min, t_max, left, right)
    sy_heading = scale_fn(0.0, 360.0, 410.0, 180.0)

    roll_vals = finite_values(sample.roll_deg for sample in samples)
    pitch_vals = finite_values(sample.pitch_deg for sample in samples)
    roll_min = min(roll_vals, default=-45.0)
    roll_max = max(roll_vals, default=45.0)
    pitch_min = min(pitch_vals, default=-45.0)
    pitch_max = max(pitch_vals, default=45.0)
    roll_pad = max(5.0, (roll_max - roll_min) * 0.15)
    pitch_pad = max(5.0, (pitch_max - pitch_min) * 0.15)
    sx_roll = scale_fn(roll_min - roll_pad, roll_max + roll_pad, 735.0, 1190.0)
    sy_pitch = scale_fn(pitch_min - pitch_pad, pitch_max + pitch_pad, 670.0, 480.0)

    heading_grid = "\n".join(
        f'<line x1="{left}" y1="{sy_heading(v):.2f}" x2="{right}" y2="{sy_heading(v):.2f}" stroke="#e2e8f0"/>'
        f'<text x="{left - 38}" y="{sy_heading(v) + 4:.2f}" class="label">{int(v)}</text>'
        for v in (0.0, 90.0, 180.0, 270.0, 360.0)
    )
    segment_marks = "\n".join(
        f'<line x1="{sx_time(segment.start_s):.2f}" y1="178" x2="{sx_time(segment.start_s):.2f}" y2="412" stroke="#64748b" stroke-dasharray="3 4" opacity="0.55"/>'
        for segment in segments
    )
    pose_axis = (
        f'<line x1="{sx_roll(0.0):.2f}" y1="480" x2="{sx_roll(0.0):.2f}" y2="670" stroke="#cbd5e1"/>'
        f'<line x1="735" y1="{sy_pitch(0.0):.2f}" x2="1190" y2="{sy_pitch(0.0):.2f}" stroke="#cbd5e1"/>'
    )
    metric_lines = [
        f"samples={summary['sample_count']} ready={summary['ready_count']} ({summary['ready_fraction']:.3f})",
        f"poses={summary['accepted_pose_count']}/{summary['pose_segment_count']} labels={','.join(summary['accepted_pose_labels'])}",
        f"tilt span={summary['accepted_tilt_heading_span_deg']:.2f} deg planar span={summary['accepted_planar_heading_span_deg']:.2f} deg",
        f"mag bins={summary['heading_coverage_bins']}/{summary['heading_bin_count']} mag std={summary['mag_norm_std_uT']:.3f} uT",
        f"max |g resid|={summary['max_abs_gravity_residual_mps2']:.3f} m/s2",
        str(summary["final_rationale"]),
    ]
    metric_svg = "\n".join(
        f'<text x="84" y="{760 + idx * 19}" class="metric">{html.escape(line)}</text>'
        for idx, line in enumerate(metric_lines)
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
<text x="{left}" y="57" class="subtitle">Engineering validator: pose-segmented tilt-compass evidence for sign convention, magnetic coverage, and calibration readiness.</text>
{summary_cards(summary, left, 80)}
{panel(left, 150, right - left, 285, "heading stability across pose sequence")}
{heading_grid}
{segment_marks}
{polyline(samples, sx_time, sy_heading, "tilt_heading_deg", "#2563eb", 2.3)}
{polyline(samples, sx_time, sy_heading, "planar_heading_deg", "#f97316", 1.8, "5 5")}
<line x1="{left}" y1="412" x2="{right}" y2="412" class="axis"/>
<text x="{left}" y="430" class="label">{t_min:.2f}s</text>
<text x="{right - 58}" y="430" class="label">{t_max:.2f}s</text>
<text x="{right - 360}" y="174" class="label">blue: tilt-compensated heading | orange: planar magnetic heading</text>
{panel(left, 462, 600, 242, "pose segment table")}
{pose_table(segments, left + 16, 502)}
{panel(710, 462, 500, 242, "roll/pitch pose map")}
{pose_axis}
{pose_scatter(samples, sx_roll, sy_pitch)}
<text x="735" y="690" class="label">roll [deg]</text>
<text x="1126" y="690" class="label">green ready, red blocked</text>
{panel(left, 730, 700, 152, "validator summary")}
{metric_svg}
{panel(820, 730, 390, 152, "magnetic heading-bin coverage")}
{heading_bin_chart(bins, 842, 770, 340, 88)}
</svg>
"""
    return svg


def write_json(path: Path, source: Path, summary: dict, segments: list[PoseSegment], bins: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "heading-sign-calibration-validator-v1",
        "source_heading_json": str(source),
        "summary": summary,
        "pose_segments": [asdict(segment) for segment in segments],
        "heading_bins": bins,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate tilt-compensated heading sign convention and CMPS2 heading coverage from heading SVG/JSON samples."
    )
    parser.add_argument("heading_json", type=Path, help="JSON emitted by tilt_compensated_heading_view.py.")
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Tilt-Compensated Heading Sign / Calibration Validator")
    parser.add_argument("--pose-change-deg", type=float, default=8.0)
    parser.add_argument("--min-pose-samples", type=int, default=8)
    parser.add_argument("--min-ready-fraction", type=float, default=0.80)
    parser.add_argument("--max-tilt-heading-span-deg", type=float, default=15.0)
    parser.add_argument("--heading-bin-count", type=int, default=DEFAULT_HEADING_BIN_COUNT)
    parser.add_argument("--min-calibration-bins", type=int, default=18)
    parser.add_argument("--min-partial-calibration-bins", type=int, default=8)
    parser.add_argument("--max-static-mag-norm-std-uT", type=float, default=2.0)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    samples, source_summary = read_heading_json(args.heading_json)
    summary, segments, bins = summarize_validation(
        samples,
        source_summary,
        pose_change_deg=args.pose_change_deg,
        min_pose_samples=args.min_pose_samples,
        min_ready_fraction=args.min_ready_fraction,
        max_tilt_heading_span_deg=args.max_tilt_heading_span_deg,
        heading_bin_count=args.heading_bin_count,
        min_calibration_bins=args.min_calibration_bins,
        min_partial_calibration_bins=args.min_partial_calibration_bins,
        max_static_mag_norm_std_uT=args.max_static_mag_norm_std_uT,
    )
    if not samples:
        raise SystemExit("No usable heading samples found.")

    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, segments, bins, summary, args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, args.heading_json, summary, segments, bins)

    print(f"samples={summary['sample_count']}")
    print(f"accepted_pose_count={summary['accepted_pose_count']}")
    print(f"sign_state={summary['sign_state']}")
    print(f"calibration_state={summary['calibration_state']}")
    print(f"heading_coverage_bins={summary['heading_coverage_bins']}/{summary['heading_bin_count']}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

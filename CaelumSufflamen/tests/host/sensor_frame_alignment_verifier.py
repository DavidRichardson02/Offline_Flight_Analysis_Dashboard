from __future__ import annotations

import argparse
import html
import json
import math
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import orientation_vector_view as orientation_view


G_MPS2 = 9.80665
FACE_ORDER = ["+X", "-X", "+Y", "-Y", "+Z", "-Z"]


@dataclass
class FrameSample:
    t_s: float
    valid_mask: int | None
    warn_mask: int | None
    ax_mps2: float
    ay_mps2: float
    az_mps2: float
    accel_norm_mps2: float
    accel_roll_deg: float
    accel_pitch_deg: float
    mag_x_uT: float
    mag_y_uT: float
    mag_z_uT: float
    mag_norm_uT: float
    mag_heading_deg: float
    mag_interference: bool | None
    aux_valid: bool | None
    mag_valid: bool | None


@dataclass
class FaceSummary:
    face: str
    sample_count: int
    accepted: bool
    mean_ax_mps2: float
    mean_ay_mps2: float
    mean_az_mps2: float
    mean_norm_mps2: float
    gravity_residual_mean_mps2: float
    dominant_ratio_mean: float
    roll_formula_rmse_deg: float
    pitch_formula_rmse_deg: float
    mag_norm_mean_uT: float


@dataclass
class FaceRun:
    index: int
    face: str
    start_s: float
    end_s: float
    sample_count: int
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


def parse_bool(value: object) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    text = str(value).strip().lower()
    if text in {"1", "true", "yes", "y"}:
        return True
    if text in {"0", "false", "no", "n"}:
        return False
    return None


def parse_int(value: object) -> int | None:
    value_f = parse_float(value)
    if not math.isfinite(value_f):
        return None
    return int(round(value_f))


def norm3(x: float, y: float, z: float) -> float:
    if not all(math.isfinite(value) for value in (x, y, z)):
        return math.nan
    return math.sqrt(x * x + y * y + z * z)


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


def rmse(values: Iterable[float]) -> float:
    vals = finite_values(values)
    if not vals:
        return math.nan
    return math.sqrt(sum(value * value for value in vals) / len(vals))


def stdev(values: Iterable[float]) -> float:
    vals = finite_values(values)
    if len(vals) < 2:
        return 0.0 if vals else math.nan
    avg = sum(vals) / len(vals)
    return math.sqrt(sum((value - avg) ** 2 for value in vals) / (len(vals) - 1))


def signed_angle_delta_deg(a_deg: float, b_deg: float) -> float:
    if not math.isfinite(a_deg) or not math.isfinite(b_deg):
        return math.nan
    return ((a_deg - b_deg + 180.0) % 360.0) - 180.0


def accel_roll_deg(ay: float, az: float) -> float:
    if not math.isfinite(ay) or not math.isfinite(az):
        return math.nan
    return math.degrees(math.atan2(ay, az))


def accel_pitch_deg(ax: float, ay: float, az: float) -> float:
    if not all(math.isfinite(value) for value in (ax, ay, az)):
        return math.nan
    return math.degrees(math.atan2(-ax, math.hypot(ay, az)))


def classify_face(sample: FrameSample, min_dominance_ratio: float) -> str:
    components = [
        ("X", sample.ax_mps2),
        ("Y", sample.ay_mps2),
        ("Z", sample.az_mps2),
    ]
    if not all(math.isfinite(value) for _, value in components):
        return "unknown"
    axis, value = max(components, key=lambda item: abs(item[1]))
    vector_norm = norm3(sample.ax_mps2, sample.ay_mps2, sample.az_mps2)
    if not math.isfinite(vector_norm) or vector_norm <= 1.0e-9:
        return "unknown"
    if abs(value) / vector_norm < min_dominance_ratio:
        return "mixed"
    return f"{'+' if value >= 0.0 else '-'}{axis}"


def dominant_ratio(sample: FrameSample) -> float:
    values = [sample.ax_mps2, sample.ay_mps2, sample.az_mps2]
    if not all(math.isfinite(value) for value in values):
        return math.nan
    vector_norm = norm3(sample.ax_mps2, sample.ay_mps2, sample.az_mps2)
    if not math.isfinite(vector_norm) or vector_norm <= 1.0e-9:
        return math.nan
    return max(abs(value) for value in values) / vector_norm


def from_orientation_sample(sample: object) -> FrameSample:
    ax = parse_float(getattr(sample, "aux_ax_mps2", math.nan))
    ay = parse_float(getattr(sample, "aux_ay_mps2", math.nan))
    az = parse_float(getattr(sample, "aux_az_mps2", math.nan))
    accel_norm = parse_float(getattr(sample, "aux_a_norm_mps2", math.nan))
    if not math.isfinite(accel_norm):
        accel_norm = norm3(ax, ay, az)
    return FrameSample(
        t_s=parse_float(getattr(sample, "t_s", math.nan)),
        valid_mask=parse_int(getattr(sample, "valid_mask", None)),
        warn_mask=parse_int(getattr(sample, "warn_mask", None)),
        ax_mps2=ax,
        ay_mps2=ay,
        az_mps2=az,
        accel_norm_mps2=accel_norm,
        accel_roll_deg=parse_float(getattr(sample, "accel_roll_deg", math.nan)),
        accel_pitch_deg=parse_float(getattr(sample, "accel_pitch_deg", math.nan)),
        mag_x_uT=parse_float(getattr(sample, "mag_x_uT", math.nan)),
        mag_y_uT=parse_float(getattr(sample, "mag_y_uT", math.nan)),
        mag_z_uT=parse_float(getattr(sample, "mag_z_uT", math.nan)),
        mag_norm_uT=parse_float(getattr(sample, "mag_norm_uT", math.nan)),
        mag_heading_deg=parse_float(getattr(sample, "mag_heading_deg", math.nan)),
        mag_interference=parse_bool(getattr(sample, "mag_interference", None)),
        aux_valid=parse_bool(getattr(sample, "aux_valid", None)),
        mag_valid=parse_bool(getattr(sample, "mag_valid", None)),
    )


def sample_from_json_row(row: dict) -> FrameSample | None:
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
    accel_norm = parse_float(row.get("aux_a_norm_mps2"))
    if not math.isfinite(accel_norm):
        accel_norm = norm3(ax, ay, az)
    valid_mask = parse_int(row.get("valid_mask"))
    aux_valid = parse_bool(row.get("aux_valid"))
    mag_valid = parse_bool(row.get("mag_valid"))
    if aux_valid is None and valid_mask is not None:
        aux_valid = bool(valid_mask & (1 << 2))
    if mag_valid is None and valid_mask is not None:
        mag_valid = bool(valid_mask & (1 << 4))
    return FrameSample(
        t_s=t_s,
        valid_mask=valid_mask,
        warn_mask=parse_int(row.get("warn_mask")),
        ax_mps2=ax,
        ay_mps2=ay,
        az_mps2=az,
        accel_norm_mps2=accel_norm,
        accel_roll_deg=parse_float(row.get("accel_roll_deg")),
        accel_pitch_deg=parse_float(row.get("accel_pitch_deg")),
        mag_x_uT=parse_float(row.get("mag_x_uT")),
        mag_y_uT=parse_float(row.get("mag_y_uT")),
        mag_z_uT=parse_float(row.get("mag_z_uT")),
        mag_norm_uT=parse_float(row.get("mag_norm_uT")),
        mag_heading_deg=parse_float(row.get("mag_heading_deg")),
        mag_interference=parse_bool(row.get("mag_interference")),
        aux_valid=aux_valid,
        mag_valid=mag_valid,
    )


def read_renderer_json(path: Path) -> list[FrameSample]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("samples", [])
    if not isinstance(rows, list):
        return []
    samples: list[FrameSample] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        sample = sample_from_json_row(row)
        if sample is not None:
            samples.append(sample)
    return sorted(samples, key=lambda sample: sample.t_s)


def read_samples(paths: list[Path], input_format: str) -> list[FrameSample]:
    samples: list[FrameSample] = []
    for path in paths:
        if input_format == "json" or (input_format == "auto" and path.suffix.lower() == ".json"):
            samples.extend(read_renderer_json(path))
        else:
            samples.extend(from_orientation_sample(sample) for sample in orientation_view.read_samples([path], input_format))
    return sorted((sample for sample in samples if math.isfinite(sample.t_s)), key=lambda sample: sample.t_s)


def build_face_runs(samples: list[FrameSample], min_dominance_ratio: float, min_face_samples: int) -> list[FaceRun]:
    runs: list[FaceRun] = []
    current_face = ""
    current_start = 0
    classified = [(sample, classify_face(sample, min_dominance_ratio)) for sample in samples]
    for index, (_, face) in enumerate(classified):
        if not current_face:
            current_face = face
            current_start = index
            continue
        if face != current_face:
            rows = classified[current_start:index]
            runs.append(
                FaceRun(
                    index=len(runs),
                    face=current_face,
                    start_s=rows[0][0].t_s,
                    end_s=rows[-1][0].t_s,
                    sample_count=len(rows),
                    accepted=len(rows) >= min_face_samples and current_face in FACE_ORDER,
                )
            )
            current_face = face
            current_start = index
    if classified:
        rows = classified[current_start:]
        runs.append(
            FaceRun(
                index=len(runs),
                face=current_face,
                start_s=rows[0][0].t_s,
                end_s=rows[-1][0].t_s,
                sample_count=len(rows),
                accepted=len(rows) >= min_face_samples and current_face in FACE_ORDER,
            )
        )
    return runs


def summarize_face(face: str, rows: list[FrameSample], min_face_samples: int) -> FaceSummary:
    roll_errors = [signed_angle_delta_deg(sample.accel_roll_deg, accel_roll_deg(sample.ay_mps2, sample.az_mps2)) for sample in rows]
    pitch_errors = [signed_angle_delta_deg(sample.accel_pitch_deg, accel_pitch_deg(sample.ax_mps2, sample.ay_mps2, sample.az_mps2)) for sample in rows]
    return FaceSummary(
        face=face,
        sample_count=len(rows),
        accepted=len(rows) >= min_face_samples,
        mean_ax_mps2=mean(sample.ax_mps2 for sample in rows),
        mean_ay_mps2=mean(sample.ay_mps2 for sample in rows),
        mean_az_mps2=mean(sample.az_mps2 for sample in rows),
        mean_norm_mps2=mean(sample.accel_norm_mps2 for sample in rows),
        gravity_residual_mean_mps2=mean(sample.accel_norm_mps2 - G_MPS2 for sample in rows),
        dominant_ratio_mean=mean(dominant_ratio(sample) for sample in rows),
        roll_formula_rmse_deg=rmse(roll_errors),
        pitch_formula_rmse_deg=rmse(pitch_errors),
        mag_norm_mean_uT=mean(sample.mag_norm_uT for sample in rows if sample.mag_valid is not False),
    )


def summarize_alignment(
    samples: list[FrameSample],
    *,
    min_face_samples: int,
    min_dominance_ratio: float,
    max_gravity_rms_mps2: float,
    max_angle_formula_rmse_deg: float,
    expected_sequence: list[str],
) -> tuple[dict, list[FaceSummary], list[FaceRun]]:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "final_label": "no_samples",
            "final_rationale": "No orientation samples were available.",
        }, [], []

    face_rows: dict[str, list[FrameSample]] = {face: [] for face in FACE_ORDER}
    unknown_count = 0
    mixed_count = 0
    for sample in samples:
        face = classify_face(sample, min_dominance_ratio)
        if face in face_rows:
            face_rows[face].append(sample)
        elif face == "mixed":
            mixed_count += 1
        else:
            unknown_count += 1

    face_summaries = [summarize_face(face, face_rows[face], min_face_samples) for face in FACE_ORDER]
    accepted_faces = [summary.face for summary in face_summaries if summary.accepted]
    runs = build_face_runs(samples, min_dominance_ratio, min_face_samples)
    accepted_run_faces = [run.face for run in runs if run.accepted]

    gravity_residual_rms = rmse(sample.accel_norm_mps2 - G_MPS2 for sample in samples)
    roll_formula_rmse = rmse(
        signed_angle_delta_deg(sample.accel_roll_deg, accel_roll_deg(sample.ay_mps2, sample.az_mps2))
        for sample in samples
    )
    pitch_formula_rmse = rmse(
        signed_angle_delta_deg(sample.accel_pitch_deg, accel_pitch_deg(sample.ax_mps2, sample.ay_mps2, sample.az_mps2))
        for sample in samples
    )
    aux_valid_rows = sum(1 for sample in samples if sample.aux_valid is True)
    mag_valid_rows = sum(1 for sample in samples if sample.mag_valid is True)
    mag_interference_rows = sum(1 for sample in samples if sample.mag_interference is True)
    warn_row_count = sum(1 for sample in samples if sample.warn_mask not in (None, 0))
    mag_norm_std = stdev(sample.mag_norm_uT for sample in samples if sample.mag_valid is not False)
    sequence_matches = None
    if expected_sequence:
        compact_runs: list[str] = []
        for face in accepted_run_faces:
            if not compact_runs or compact_runs[-1] != face:
                compact_runs.append(face)
        sequence_matches = compact_runs[: len(expected_sequence)] == expected_sequence

    if aux_valid_rows == 0:
        final_label = "aux_unavailable"
        rationale = "No valid auxiliary accelerometer rows were available."
    elif math.isfinite(gravity_residual_rms) and gravity_residual_rms > max_gravity_rms_mps2:
        final_label = "gravity_norm_out_of_family"
        rationale = "Acceleration norm residual is too large for static frame-alignment evidence."
    elif math.isfinite(roll_formula_rmse) and roll_formula_rmse > max_angle_formula_rmse_deg:
        final_label = "roll_formula_mismatch"
        rationale = "Logged accelerometer roll disagrees with host recomputation from raw axes."
    elif math.isfinite(pitch_formula_rmse) and pitch_formula_rmse > max_angle_formula_rmse_deg:
        final_label = "pitch_formula_mismatch"
        rationale = "Logged accelerometer pitch disagrees with host recomputation from raw axes."
    elif len(accepted_faces) < len(FACE_ORDER):
        final_label = "insufficient_face_coverage"
        rationale = "Capture does not include all six dominant gravity-axis faces."
    elif sequence_matches is False:
        final_label = "expected_sequence_mismatch"
        rationale = "Observed accepted face sequence does not match the configured expected sequence."
    else:
        final_label = "frame_alignment_supported"
        rationale = "All six gravity-axis faces are present and roll/pitch formulas match raw axes."

    summary = {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "aux_valid_rows": aux_valid_rows,
        "mag_valid_rows": mag_valid_rows,
        "mag_interference_rows": mag_interference_rows,
        "warn_row_count": warn_row_count,
        "unknown_face_rows": unknown_count,
        "mixed_face_rows": mixed_count,
        "accepted_face_count": len(accepted_faces),
        "accepted_faces": accepted_faces,
        "accepted_run_faces": accepted_run_faces,
        "expected_sequence": expected_sequence,
        "expected_sequence_matches": sequence_matches,
        "gravity_residual_rms_mps2": gravity_residual_rms,
        "roll_formula_rmse_deg": roll_formula_rmse,
        "pitch_formula_rmse_deg": pitch_formula_rmse,
        "mag_norm_std_uT": mag_norm_std,
        "final_label": final_label,
        "final_rationale": rationale,
    }
    return summary, face_summaries, runs


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def panel(x: float, y: float, w: float, h: float, title: str) -> str:
    return (
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="#ffffff" stroke="#cbd5e1"/>'
        f'<text x="{x + 14}" y="{y + 25}" class="panel_title">{html.escape(title)}</text>'
    )


def status_color(label: str) -> str:
    if label == "frame_alignment_supported":
        return "#16a34a"
    if label in {"insufficient_face_coverage", "expected_sequence_mismatch"}:
        return "#f59e0b"
    return "#dc2626"


def face_matrix(face_summaries: list[FaceSummary], x: float, y: float) -> str:
    pieces: list[str] = []
    for index, face in enumerate(FACE_ORDER):
        summary = next(item for item in face_summaries if item.face == face)
        col = index % 3
        row = index // 3
        bx = x + col * 160
        by = y + row * 86
        fill = "#dcfce7" if summary.accepted else "#fee2e2"
        stroke = "#16a34a" if summary.accepted else "#dc2626"
        pieces.append(f'<rect x="{bx}" y="{by}" width="138" height="64" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
        pieces.append(f'<text x="{bx + 12}" y="{by + 22}" class="panel_title">{face}</text>')
        pieces.append(f'<text x="{bx + 12}" y="{by + 42}" class="metric">n={summary.sample_count} dom={summary.dominant_ratio_mean:.2f}</text>')
        pieces.append(f'<text x="{bx + 12}" y="{by + 57}" class="metric">|a|-g={summary.gravity_residual_mean_mps2:.2f}</text>')
    return "\n".join(pieces)


def face_run_timeline(runs: list[FaceRun], x: float, y: float, w: float, h: float) -> str:
    if not runs:
        return ""
    t_min = runs[0].start_s
    t_max = max(run.end_s for run in runs)
    sx = scale_fn(t_min, t_max if t_max > t_min else t_min + 1.0, x, x + w)
    colors = {
        "+X": "#2563eb",
        "-X": "#93c5fd",
        "+Y": "#16a34a",
        "-Y": "#86efac",
        "+Z": "#f59e0b",
        "-Z": "#fbbf24",
        "mixed": "#cbd5e1",
        "unknown": "#94a3b8",
    }
    pieces: list[str] = []
    for run in runs:
        x0 = sx(run.start_s)
        x1 = sx(run.end_s)
        pieces.append(
            f'<rect x="{x0:.2f}" y="{y}" width="{max(2.0, x1 - x0):.2f}" height="{h}" fill="{colors.get(run.face, "#94a3b8")}" opacity="0.82"/>'
        )
        if x1 - x0 > 28:
            pieces.append(f'<text x="{x0 + 4:.2f}" y="{y + h - 7}" class="label">{html.escape(run.face)}</text>')
    pieces.append(f'<line x1="{x}" y1="{y + h}" x2="{x + w}" y2="{y + h}" class="axis"/>')
    pieces.append(f'<text x="{x}" y="{y + h + 18}" class="label">{t_min:.2f}s</text>')
    pieces.append(f'<text x="{x + w - 58}" y="{y + h + 18}" class="label">{t_max:.2f}s</text>')
    return "\n".join(pieces)


def component_chart(samples: list[FrameSample], x: float, y: float, w: float, h: float) -> str:
    if not samples:
        return ""
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, x, x + w)
    sy = scale_fn(-G_MPS2 * 1.2, G_MPS2 * 1.2, y + h - 20, y + 12)
    pieces = [
        f'<line x1="{x}" y1="{sy(0.0):.2f}" x2="{x + w}" y2="{sy(0.0):.2f}" stroke="#cbd5e1"/>',
        f'<line x1="{x}" y1="{sy(G_MPS2):.2f}" x2="{x + w}" y2="{sy(G_MPS2):.2f}" stroke="#e2e8f0" stroke-dasharray="4 4"/>',
        f'<line x1="{x}" y1="{sy(-G_MPS2):.2f}" x2="{x + w}" y2="{sy(-G_MPS2):.2f}" stroke="#e2e8f0" stroke-dasharray="4 4"/>',
    ]
    for attr, color in (("ax_mps2", "#2563eb"), ("ay_mps2", "#16a34a"), ("az_mps2", "#f97316")):
        points = []
        for sample in samples:
            value = getattr(sample, attr)
            if math.isfinite(value):
                points.append(f"{sx(sample.t_s):.2f},{sy(value):.2f}")
        if points:
            pieces.append(f'<polyline points="{" ".join(points)}" fill="none" stroke="{color}" stroke-width="2"/>')
    pieces.append(f'<line x1="{x}" y1="{y + h - 20}" x2="{x + w}" y2="{y + h - 20}" class="axis"/>')
    pieces.append(f'<text x="{x + w - 180}" y="{y + 18}" class="label">blue ax, green ay, orange az</text>')
    return "\n".join(pieces)


def render_svg(
    samples: list[FrameSample],
    summary: dict,
    face_summaries: list[FaceSummary],
    runs: list[FaceRun],
    title: str,
) -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")
    width = 1220
    height = 820
    verdict = summary["final_label"]
    color = status_color(verdict)
    metrics = [
        f"samples={summary['sample_count']} aux_valid={summary['aux_valid_rows']} mag_valid={summary['mag_valid_rows']}",
        f"faces={summary['accepted_face_count']}/6 accepted={','.join(summary['accepted_faces'])}",
        f"gravity_rms={summary['gravity_residual_rms_mps2']:.3f} m/s2 roll_rmse={summary['roll_formula_rmse_deg']:.3f} deg pitch_rmse={summary['pitch_formula_rmse_deg']:.3f} deg",
        f"mag_std={summary['mag_norm_std_uT']:.3f} uT mag_interference={summary['mag_interference_rows']}",
        str(summary["final_rationale"]),
    ]
    metric_svg = "\n".join(
        f'<text x="92" y="{612 + index * 20}" class="metric">{html.escape(text)}</text>'
        for index, text in enumerate(metrics)
    )
    face_table = "\n".join(
        f'<text x="710" y="{158 + index * 20}" class="metric">{item.face:>2} n={item.sample_count:3d} ax={item.mean_ax_mps2:6.2f} ay={item.mean_ay_mps2:6.2f} az={item.mean_az_mps2:6.2f} rollE={item.roll_formula_rmse_deg:5.2f} pitchE={item.pitch_formula_rmse_deg:5.2f}</text>'
        for index, item in enumerate(face_summaries)
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
  .panel_title {{ font: 700 13px Arial, sans-serif; fill: #0f172a; }}
  .axis {{ stroke: #334155; stroke-width: 1.2; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="84" y="35" class="title">{html.escape(title)}</text>
<text x="84" y="57" class="subtitle">Engineering verifier for LIS3DH body-frame axis convention, accelerometer roll/pitch formulas, gravity norm, and CMPS2 validity.</text>
<rect x="84" y="78" width="1050" height="66" fill="#ffffff" stroke="{color}" stroke-width="3"/>
<text x="104" y="116" class="title">{html.escape(verdict)}</text>
<text x="510" y="116" class="metric">expected_sequence={html.escape(','.join(summary['expected_sequence']) if summary['expected_sequence'] else 'not configured')}</text>
{panel(84, 170, 560, 220, "six-face gravity coverage")}
{face_matrix(face_summaries, 104, 215)}
{panel(680, 170, 454, 220, "per-face mean vectors / formula error")}
{face_table}
{panel(84, 420, 1050, 125, "observed face-run timeline")}
{face_run_timeline(runs, 104, 462, 990, 44)}
{panel(84, 575, 1050, 156, "validator summary")}
{metric_svg}
{panel(84, 748, 1050, 55, "raw acceleration components")}
{component_chart(samples, 104, 763, 990, 34)}
</svg>
"""


def write_json(path: Path, source_paths: list[Path], summary: dict, face_summaries: list[FaceSummary], runs: list[FaceRun]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "sensor-frame-alignment-verifier-v1",
        "source_inputs": [str(source_path) for source_path in source_paths],
        "summary": summary,
        "faces": [asdict(item) for item in face_summaries],
        "face_runs": [asdict(item) for item in runs],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_expected_sequence(text: str) -> list[str]:
    if not text:
        return []
    result = []
    for item in text.split(","):
        face = item.strip().upper()
        if face:
            result.append(face)
    invalid = [face for face in result if face not in FACE_ORDER]
    if invalid:
        raise ValueError(f"Invalid expected face labels: {', '.join(invalid)}")
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify LIS3DH/CMPS2 sensor-frame axis convention from SD CSV, PLOT ORIENT capture, or orientation JSON."
    )
    parser.add_argument("input", nargs="+", type=Path)
    parser.add_argument("--input-format", choices=("auto", "sd", "plot", "json"), default="auto")
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Sensor Frame Alignment / Axis Convention Verifier")
    parser.add_argument("--min-face-samples", type=int, default=8)
    parser.add_argument("--min-dominance-ratio", type=float, default=0.82)
    parser.add_argument("--max-gravity-rms-mps2", type=float, default=1.0)
    parser.add_argument("--max-angle-formula-rmse-deg", type=float, default=2.0)
    parser.add_argument("--expected-sequence", default="")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    expected_sequence = parse_expected_sequence(args.expected_sequence)
    samples = read_samples(args.input, args.input_format)
    if not samples:
        raise SystemExit("No usable frame-alignment samples found.")
    summary, face_summaries, runs = summarize_alignment(
        samples,
        min_face_samples=args.min_face_samples,
        min_dominance_ratio=args.min_dominance_ratio,
        max_gravity_rms_mps2=args.max_gravity_rms_mps2,
        max_angle_formula_rmse_deg=args.max_angle_formula_rmse_deg,
        expected_sequence=expected_sequence,
    )

    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, summary, face_summaries, runs, args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, args.input, summary, face_summaries, runs)

    print(f"samples={summary['sample_count']}")
    print(f"accepted_face_count={summary['accepted_face_count']}")
    print(f"accepted_faces={','.join(summary['accepted_faces'])}")
    print(f"gravity_residual_rms_mps2={summary['gravity_residual_rms_mps2']:.3f}")
    print(f"roll_formula_rmse_deg={summary['roll_formula_rmse_deg']:.3f}")
    print(f"pitch_formula_rmse_deg={summary['pitch_formula_rmse_deg']:.3f}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

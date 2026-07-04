from __future__ import annotations

import argparse
import csv
import html
import json
import math
import statistics
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from policy_aero_empirical_fit import (  # noqa: E402
    DEFAULT_BODY_CDA_M2,
    DEFAULT_BRAKE_CDA_M2,
    DEFAULT_MASS_KG,
    DEFAULT_MIN_ALT_M,
    DEFAULT_MIN_VZ_MPS,
    DEFAULT_RHO_KGPM3,
    PHASE_BOOST,
    PHASE_BRAKE,
    PHASE_COAST,
    PHASE_DESCENT,
    clamp01,
    predict_apogee_m,
    solve_drag_k_from_apogee_delta,
)


PHASE_NAMES = {
    0: "IDLE",
    PHASE_BOOST: "BOOST",
    PHASE_COAST: "COAST",
    PHASE_BRAKE: "BRAKE",
    PHASE_DESCENT: "DESCENT",
}


@dataclass
class AeroSample:
    log_path: str
    log_index: int
    t_s: float
    phase: int | None
    est_h_m: float
    est_v_mps: float
    policy_valid: bool | None
    command01: float
    command_source: str
    brake_measured: bool
    warn_mask: int | None
    p00_m2: float
    p11_m2ps2: float
    actual_apogee_m: float
    delta_h_m: float = math.nan
    qbar_proxy_pa: float = math.nan
    equiv_cda_m2: float = math.nan
    current_prediction_error_m: float = math.nan
    classification: str = "rejected"
    fit_eligible: bool = False
    reject_reasons: list[str] = field(default_factory=list)


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


def bool_cell(row: dict[str, str], *names: str) -> bool | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            value = parse_int(row[name])
            if value is None:
                return None
            return value != 0
    return None


def first_present(row: dict[str, str], *names: str) -> str | None:
    for name in names:
        if name in row and row[name] not in ("", None):
            return row[name]
    return None


def float_cell(row: dict[str, str], *names: str) -> float:
    return parse_float(first_present(row, *names))


def int_cell(row: dict[str, str], *names: str) -> int | None:
    return parse_int(first_present(row, *names))


def mean(values: list[float]) -> float:
    return statistics.fmean(values) if values else math.nan


def median(values: list[float]) -> float:
    return statistics.median(values) if values else math.nan


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    if reader.fieldnames is None:
        raise ValueError(f"{path} does not contain a readable CSV header")
    return list(reader)


def row_time_s(row: dict[str, str]) -> float:
    t_us = float_cell(row, "t_us")
    if math.isfinite(t_us):
        return t_us / 1_000_000.0
    t_ms = float_cell(row, "t_ms")
    if math.isfinite(t_ms):
        return t_ms / 1000.0
    return math.nan


def select_command(row: dict[str, str]) -> tuple[float, str, bool]:
    brake_pos_valid = bool_cell(row, "brake_pos_valid")
    brake_pos = float_cell(row, "brake_pos01_meas", "brake_pos01")
    if brake_pos_valid is True and math.isfinite(brake_pos):
        return clamp01(brake_pos), "brake_pos01_meas", True

    for name in ("policy_cmd_applied", "actuator01", "policy_cmd_slewed", "policy_cmd"):
        value = float_cell(row, name)
        if math.isfinite(value):
            return clamp01(value), name, False

    actuator_us = float_cell(row, "actuator_us")
    if math.isfinite(actuator_us):
        return clamp01((actuator_us - 1000.0) / 1000.0), "actuator_us_proxy", False

    return math.nan, "unavailable", False


def actual_apogee_from_rows(rows: list[dict[str, str]]) -> float:
    candidates: list[float] = []
    for row in rows:
        phase = int_cell(row, "phase")
        h_m = float_cell(row, "est_h", "est_h_m")
        if phase in (PHASE_BOOST, PHASE_COAST, PHASE_BRAKE, PHASE_DESCENT) and math.isfinite(h_m):
            candidates.append(h_m)
    return max(candidates, default=math.nan)


def classify_sample(
    sample: AeroSample,
    *,
    mass_kg: float,
    rho_kgpm3: float,
    current_body_cda_m2: float,
    current_brake_cda_m2: float,
    closed_cmd_threshold: float,
    open_cmd_threshold: float,
    min_alt_m: float,
    min_vz_mps: float,
    min_delta_h_m: float,
    reject_warned_rows: bool,
) -> None:
    reasons: list[str] = []
    if sample.phase not in (PHASE_COAST, PHASE_BRAKE):
        reasons.append("phase")
    if not math.isfinite(sample.est_h_m) or not math.isfinite(sample.est_v_mps):
        reasons.append("state")
    if math.isfinite(sample.est_h_m) and sample.est_h_m < min_alt_m:
        reasons.append("altitude")
    if math.isfinite(sample.est_v_mps) and sample.est_v_mps < min_vz_mps:
        reasons.append("velocity")
    if not math.isfinite(sample.command01):
        reasons.append("command")
    if reject_warned_rows and sample.warn_mask not in (None, 0):
        reasons.append("warning")

    if math.isfinite(sample.actual_apogee_m) and math.isfinite(sample.est_h_m):
        sample.delta_h_m = sample.actual_apogee_m - sample.est_h_m
        if sample.delta_h_m <= min_delta_h_m:
            reasons.append("apogee_leverage")
    else:
        reasons.append("apogee")

    if math.isfinite(sample.est_v_mps):
        sample.qbar_proxy_pa = 0.5 * rho_kgpm3 * sample.est_v_mps * sample.est_v_mps

    if not reasons:
        k_inv_m = solve_drag_k_from_apogee_delta(sample.delta_h_m, sample.est_v_mps)
        if k_inv_m is None:
            reasons.append("model")
        else:
            sample.equiv_cda_m2 = (2.0 * mass_kg * k_inv_m) / rho_kgpm3
            predicted = predict_apogee_m(
                sample.est_h_m,
                sample.est_v_mps,
                sample.command01,
                body_cda_m2=current_body_cda_m2,
                brake_cda_m2=current_brake_cda_m2,
                mass_kg=mass_kg,
                rho_kgpm3=rho_kgpm3,
            )
            if math.isfinite(predicted):
                sample.current_prediction_error_m = predicted - sample.actual_apogee_m

    sample.reject_reasons = reasons
    sample.fit_eligible = not reasons
    if not sample.fit_eligible:
        sample.classification = "rejected"
    elif sample.command01 <= closed_cmd_threshold:
        sample.classification = "body"
    elif sample.command01 >= open_cmd_threshold:
        sample.classification = "brake"
    else:
        sample.classification = "transition"


def read_samples(
    paths: list[Path],
    *,
    mass_kg: float,
    rho_kgpm3: float,
    current_body_cda_m2: float,
    current_brake_cda_m2: float,
    closed_cmd_threshold: float,
    open_cmd_threshold: float,
    min_alt_m: float,
    min_vz_mps: float,
    min_delta_h_m: float,
    reject_warned_rows: bool,
) -> list[AeroSample]:
    samples: list[AeroSample] = []
    for log_index, path in enumerate(paths):
        rows = read_csv_rows(path)
        actual_apogee_m = actual_apogee_from_rows(rows)
        for row in rows:
            t_s = row_time_s(row)
            if not math.isfinite(t_s):
                continue
            command01, command_source, brake_measured = select_command(row)
            sample = AeroSample(
                log_path=str(path),
                log_index=log_index,
                t_s=t_s,
                phase=int_cell(row, "phase"),
                est_h_m=float_cell(row, "est_h", "est_h_m"),
                est_v_mps=float_cell(row, "est_v", "est_v_mps"),
                policy_valid=bool_cell(row, "policy_valid"),
                command01=command01,
                command_source=command_source,
                brake_measured=brake_measured,
                warn_mask=int_cell(row, "warn_mask"),
                p00_m2=float_cell(row, "P00", "P00_m2"),
                p11_m2ps2=float_cell(row, "P11", "P11_m2ps2"),
                actual_apogee_m=actual_apogee_m,
            )
            classify_sample(
                sample,
                mass_kg=mass_kg,
                rho_kgpm3=rho_kgpm3,
                current_body_cda_m2=current_body_cda_m2,
                current_brake_cda_m2=current_brake_cda_m2,
                closed_cmd_threshold=closed_cmd_threshold,
                open_cmd_threshold=open_cmd_threshold,
                min_alt_m=min_alt_m,
                min_vz_mps=min_vz_mps,
                min_delta_h_m=min_delta_h_m,
                reject_warned_rows=reject_warned_rows,
            )
            samples.append(sample)
    return sorted(samples, key=lambda item: (item.log_index, item.t_s))


def condition_number_for_commands(commands: list[float]) -> float:
    if len(commands) < 2:
        return math.inf
    a = float(len(commands))
    b = sum(commands)
    d = sum(command * command for command in commands)
    trace = a + d
    disc = math.sqrt(max(0.0, (a - d) * (a - d) + 4.0 * b * b))
    lambda_min = 0.5 * (trace - disc)
    lambda_max = 0.5 * (trace + disc)
    if lambda_min <= 1.0e-12 or lambda_max <= 0.0:
        return math.inf
    return math.sqrt(lambda_max / lambda_min)


def summarize_samples(
    samples: list[AeroSample],
    *,
    min_body_samples: int,
    min_brake_samples: int,
    min_total_samples: int,
    min_command_span: float,
    max_condition_number: float,
) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "final_label": "no_samples",
            "final_rationale": "No SD samples were available.",
        }

    eligible = [sample for sample in samples if sample.fit_eligible]
    body = [sample for sample in eligible if sample.classification == "body"]
    brake = [sample for sample in eligible if sample.classification == "brake"]
    transition = [sample for sample in eligible if sample.classification == "transition"]
    commands = [sample.command01 for sample in eligible if math.isfinite(sample.command01)]
    command_span = max(commands, default=math.nan) - min(commands, default=math.nan) if commands else math.nan
    condition_number = condition_number_for_commands(commands)
    measured_brake_rows = sum(1 for sample in eligible if sample.brake_measured)
    command_proxy_rows = sum(1 for sample in eligible if not sample.brake_measured)
    warned_rejections = sum(1 for sample in samples if "warning" in sample.reject_reasons)
    body_cda_values = [sample.equiv_cda_m2 for sample in body if math.isfinite(sample.equiv_cda_m2)]
    body_cda_median = median(body_cda_values)
    brake_increment_values = []
    if math.isfinite(body_cda_median):
        for sample in brake:
            if math.isfinite(sample.equiv_cda_m2) and sample.command01 > 0.0:
                brake_increment_values.append((sample.equiv_cda_m2 - body_cda_median) / sample.command01)

    reject_reason_counts: dict[str, int] = {}
    for sample in samples:
        for reason in sample.reject_reasons:
            reject_reason_counts[reason] = reject_reason_counts.get(reason, 0) + 1

    if len(eligible) < min_total_samples:
        final_label = "insufficient_eligible_samples"
        rationale = "Too few coast/brake samples pass state, health, command, and apogee-leverage gates."
    elif len(body) < min_body_samples:
        final_label = "no_body_baseline"
        rationale = "Near-closed coast/brake samples are insufficient to identify body drag."
    elif len(brake) < min_brake_samples:
        final_label = "no_brake_excitation"
        rationale = "Open-command samples are insufficient to identify incremental brake drag."
    elif not math.isfinite(command_span) or command_span < min_command_span:
        final_label = "command_excitation_low"
        rationale = "Command variation is too small for a stable two-coefficient design matrix."
    elif not math.isfinite(condition_number) or condition_number > max_condition_number:
        final_label = "ill_conditioned_design"
        rationale = "The [1, command] fit matrix is poorly conditioned."
    elif measured_brake_rows == 0:
        final_label = "command_proxy_observable"
        rationale = "Body/brake excitation is observable, but brake position is inferred from command or actuator pulse."
    else:
        final_label = "coefficient_observability_supported"
        rationale = "Body baseline, brake excitation, command span, conditioning, and measured brake-position evidence are present."

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": min(sample.t_s for sample in samples),
        "time_end_s": max(sample.t_s for sample in samples),
        "log_count": len({sample.log_path for sample in samples}),
        "eligible_sample_count": len(eligible),
        "body_sample_count": len(body),
        "brake_sample_count": len(brake),
        "transition_sample_count": len(transition),
        "rejected_sample_count": len(samples) - len(eligible),
        "warned_rejection_count": warned_rejections,
        "measured_brake_rows": measured_brake_rows,
        "command_proxy_rows": command_proxy_rows,
        "command_source_counts": {
            source: sum(1 for sample in eligible if sample.command_source == source)
            for source in sorted({sample.command_source for sample in eligible})
        },
        "reject_reason_counts": reject_reason_counts,
        "command_min": min(commands, default=math.nan),
        "command_max": max(commands, default=math.nan),
        "command_span": command_span,
        "condition_number": condition_number,
        "max_qbar_proxy_pa": max((sample.qbar_proxy_pa for sample in eligible if math.isfinite(sample.qbar_proxy_pa)), default=math.nan),
        "max_velocity_mps": max((sample.est_v_mps for sample in eligible if math.isfinite(sample.est_v_mps)), default=math.nan),
        "mean_current_prediction_error_m": mean([sample.current_prediction_error_m for sample in eligible if math.isfinite(sample.current_prediction_error_m)]),
        "body_equiv_cda_m2_median": body_cda_median,
        "brake_increment_cda_m2_median": median(brake_increment_values),
        "parameters": {
            "min_body_samples": min_body_samples,
            "min_brake_samples": min_brake_samples,
            "min_total_samples": min_total_samples,
            "min_command_span": min_command_span,
            "max_condition_number": max_condition_number,
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


def finite_values(values) -> list[float]:
    return [float(value) for value in values if math.isfinite(float(value))]


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


def class_color(classification: str) -> str:
    return {
        "body": "#2563eb",
        "brake": "#dc2626",
        "transition": "#f59e0b",
        "rejected": "#94a3b8",
    }.get(classification, "#94a3b8")


def status_color(label: str) -> str:
    if label == "coefficient_observability_supported":
        return "#16a34a"
    if label == "command_proxy_observable":
        return "#f59e0b"
    return "#dc2626"


def scatter(samples: list[AeroSample], sx, sy, x_attr: str, y_attr: str, radius: float = 3.0) -> str:
    circles: list[str] = []
    for sample in samples:
        x_value = getattr(sample, x_attr)
        y_value = getattr(sample, y_attr)
        if math.isfinite(x_value) and math.isfinite(y_value):
            opacity = "0.75" if sample.fit_eligible else "0.30"
            circles.append(
                f'<circle cx="{sx(x_value):.2f}" cy="{sy(y_value):.2f}" r="{radius}" fill="{class_color(sample.classification)}" opacity="{opacity}"/>'
            )
    return "\n".join(circles)


def polyline(samples: list[AeroSample], attr: str, sx, sy, classification: str | None = None) -> str:
    points: list[str] = []
    for sample in samples:
        if classification is not None and sample.classification != classification:
            continue
        value = getattr(sample, attr)
        if math.isfinite(sample.t_s) and math.isfinite(value):
            points.append(f"{sx(sample.t_s):.2f},{sy(value):.2f}")
    return " ".join(points)


def gate_raster(samples: list[AeroSample], sx, x: float, y: float, w: float, row_h: float) -> str:
    gates = [
        ("phase", lambda sample: "phase" not in sample.reject_reasons),
        ("state", lambda sample: "state" not in sample.reject_reasons),
        ("velocity", lambda sample: "velocity" not in sample.reject_reasons),
        ("apogee", lambda sample: "apogee_leverage" not in sample.reject_reasons and "apogee" not in sample.reject_reasons),
        ("health", lambda sample: "warning" not in sample.reject_reasons),
        ("model", lambda sample: "model" not in sample.reject_reasons),
    ]
    pieces: list[str] = []
    for row_index, (label, _) in enumerate(gates):
        y0 = y + row_index * row_h
        pieces.append(f'<text x="{x}" y="{y0 + row_h - 4:.2f}" class="tiny">{html.escape(label)}</text>')
        pieces.append(f'<line x1="{x + 70}" y1="{y0 + row_h - 2:.2f}" x2="{x + w}" y2="{y0 + row_h - 2:.2f}" stroke="#e2e8f0"/>')
    for left, right in zip(samples, samples[1:]):
        x0 = sx(left.t_s)
        width = max(1.0, sx(right.t_s) - x0)
        for row_index, (_, predicate) in enumerate(gates):
            color = "#22c55e" if predicate(left) else "#ef4444"
            pieces.append(
                f'<rect x="{x0:.2f}" y="{y + row_index * row_h:.2f}" width="{width:.2f}" height="{row_h - 2:.2f}" fill="{color}" opacity="0.66"/>'
            )
    return "\n".join(pieces)


def legend_item(x: int, y: int, color: str, label: str) -> str:
    return f'<circle cx="{x}" cy="{y}" r="5" fill="{color}"/><text x="{x + 12}" y="{y + 4}" class="legend">{html.escape(label)}</text>'


def render_svg(samples: list[AeroSample], summary: dict, title: str = "Aerodynamic Coefficient Observability Map") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1220
    height = 900
    timeline_panel = (84.0, 84.0, 1036.0, 200.0)
    command_panel = (84.0, 322.0, 500.0, 220.0)
    cda_panel = (620.0, 322.0, 500.0, 220.0)
    gate_panel = (84.0, 580.0, 1036.0, 170.0)

    t_min = min(sample.t_s for sample in samples)
    t_max = max(sample.t_s for sample in samples)
    if t_max <= t_min:
        t_max = t_min + 1.0
    sx_t = scale_fn(t_min, t_max, timeline_panel[0] + 44, timeline_panel[0] + timeline_panel[2] - 24)
    alt_min, alt_max = bounds(finite_values(sample.est_h_m for sample in samples), 50.0, include_zero=True)
    sy_alt = scale_fn(alt_min, alt_max, timeline_panel[1] + timeline_panel[3] - 34, timeline_panel[1] + 42)
    sy_cmd = scale_fn(0.0, 1.0, timeline_panel[1] + timeline_panel[3] - 34, timeline_panel[1] + 42)

    command_values = finite_values(sample.command01 for sample in samples)
    qbar_values = finite_values(sample.qbar_proxy_pa for sample in samples)
    cmd_min, cmd_max = bounds(command_values, 0.25, include_zero=True)
    cmd_min = min(0.0, cmd_min)
    cmd_max = max(1.0, cmd_max)
    qbar_min, qbar_max = bounds(qbar_values, 100.0, include_zero=True)
    sx_cmd = scale_fn(cmd_min, cmd_max, command_panel[0] + 48, command_panel[0] + command_panel[2] - 24)
    sy_qbar = scale_fn(qbar_min, qbar_max, command_panel[1] + command_panel[3] - 36, command_panel[1] + 42)

    cda_values = finite_values(sample.equiv_cda_m2 for sample in samples)
    cda_min, cda_max = bounds(cda_values, 0.02, include_zero=True)
    sx_cda = scale_fn(cmd_min, cmd_max, cda_panel[0] + 48, cda_panel[0] + cda_panel[2] - 24)
    sy_cda = scale_fn(cda_min, cda_max, cda_panel[1] + cda_panel[3] - 36, cda_panel[1] + 42)

    sx_gate = scale_fn(t_min, t_max, gate_panel[0] + 100, gate_panel[0] + gate_panel[2] - 24)
    verdict = summary["final_label"]
    verdict_color = status_color(verdict)
    metrics = (
        f"eligible={summary['eligible_sample_count']} body={summary['body_sample_count']} "
        f"brake={summary['brake_sample_count']} span={summary['command_span']:.3f} "
        f"cond={summary['condition_number']:.2f} proxy={summary['command_proxy_rows']} measured={summary['measured_brake_rows']}"
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
<text x="84" y="60" class="subtitle">Pre-fit evidence for body/brake CDA identifiability: phase gates, command excitation, dynamic-pressure leverage, health, and design conditioning.</text>
{legend_item(790, 38, "#2563eb", "body baseline")}
{legend_item(910, 38, "#dc2626", "brake excitation")}
{legend_item(1040, 38, "#f59e0b", "transition")}
{legend_item(1140, 38, "#94a3b8", "rejected")}
{panel(*timeline_panel, "altitude and command excitation over time")}
{panel(*command_panel, "command vs dynamic-pressure proxy")}
{panel(*cda_panel, "inferred equivalent CDA vs command")}
{panel(*gate_panel, "observability gate raster")}
<polyline points="{polyline(samples, "est_h_m", sx_t, sy_alt)}" fill="none" stroke="#0f172a" stroke-width="1.6"/>
<polyline points="{polyline(samples, "command01", sx_t, sy_cmd)}" fill="none" stroke="#7c3aed" stroke-width="1.8"/>
{scatter(samples, sx_t, sy_alt, "t_s", "est_h_m", radius=2.8)}
<text x="{timeline_panel[0] + 12}" y="{timeline_panel[1] + timeline_panel[3] - 10}" class="axis">t {t_min:.2f}s..{t_max:.2f}s</text>
<text x="{timeline_panel[0] + 12}" y="{timeline_panel[1] + 44}" class="axis">h m / cmd</text>
{scatter(samples, sx_cmd, sy_qbar, "command01", "qbar_proxy_pa", radius=3.6)}
<text x="{command_panel[0] + 52}" y="{command_panel[1] + command_panel[3] - 10}" class="axis">command / measured brake position</text>
<text x="{command_panel[0] + 10}" y="{command_panel[1] + 50}" class="axis">qbar proxy Pa</text>
{scatter(samples, sx_cda, sy_cda, "command01", "equiv_cda_m2", radius=3.6)}
<text x="{cda_panel[0] + 52}" y="{cda_panel[1] + cda_panel[3] - 10}" class="axis">command / measured brake position</text>
<text x="{cda_panel[0] + 10}" y="{cda_panel[1] + 50}" class="axis">equiv CDA m2</text>
{gate_raster(samples, sx_gate, gate_panel[0] + 14, gate_panel[1] + 44, gate_panel[2] - 28, 19)}
<text x="{gate_panel[0] + 18}" y="{gate_panel[1] + 152}" class="tiny">green=gate passes; red=rejected by phase/state/velocity/apogee/health/model evidence</text>
<rect x="84" y="786" width="1036" height="64" fill="#ffffff" stroke="#cbd5e1"/>
<rect x="100" y="804" width="18" height="18" fill="{verdict_color}"/>
<text x="128" y="818" class="metric">final_label={html.escape(verdict)} | {html.escape(summary['final_rationale'])}</text>
<text x="100" y="840" class="metric">{html.escape(metrics)}</text>
<text x="100" y="862" class="metric">body_CDA_median={summary['body_equiv_cda_m2_median']:.6g} brake_increment_CDA_median={summary['brake_increment_cda_m2_median']:.6g} rejected={summary['rejected_sample_count']} warned_rejected={summary['warned_rejection_count']}</text>
</svg>
'''


def write_json(path: Path, samples: list[AeroSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "aero-coefficient-observability-map-v1",
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a pre-fit aerodynamic coefficient observability map from current-schema SD logs."
    )
    parser.add_argument("logs", nargs="+", type=Path, help="One or more current-schema SD LOG###.CSV files.")
    parser.add_argument("--mass-kg", type=float, default=DEFAULT_MASS_KG)
    parser.add_argument("--rho-kgpm3", type=float, default=DEFAULT_RHO_KGPM3)
    parser.add_argument("--current-body-cda-m2", type=float, default=DEFAULT_BODY_CDA_M2)
    parser.add_argument("--current-brake-cda-m2", type=float, default=DEFAULT_BRAKE_CDA_M2)
    parser.add_argument("--closed-cmd-threshold", type=float, default=0.05)
    parser.add_argument("--open-cmd-threshold", type=float, default=0.20)
    parser.add_argument("--min-alt-m", type=float, default=DEFAULT_MIN_ALT_M)
    parser.add_argument("--min-vz-mps", type=float, default=DEFAULT_MIN_VZ_MPS)
    parser.add_argument("--min-delta-h-m", type=float, default=5.0)
    parser.add_argument("--min-body-samples", type=int, default=5)
    parser.add_argument("--min-brake-samples", type=int, default=5)
    parser.add_argument("--min-total-samples", type=int, default=20)
    parser.add_argument("--min-command-span", type=float, default=0.20)
    parser.add_argument("--max-condition-number", type=float, default=25.0)
    parser.add_argument("--allow-warned-rows", action="store_true")
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Aerodynamic Coefficient Observability Map")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    missing = [path for path in args.logs if not path.exists()]
    if missing:
        raise SystemExit(f"Missing input log(s): {', '.join(str(path) for path in missing)}")

    samples = read_samples(
        args.logs,
        mass_kg=args.mass_kg,
        rho_kgpm3=args.rho_kgpm3,
        current_body_cda_m2=args.current_body_cda_m2,
        current_brake_cda_m2=args.current_brake_cda_m2,
        closed_cmd_threshold=args.closed_cmd_threshold,
        open_cmd_threshold=args.open_cmd_threshold,
        min_alt_m=args.min_alt_m,
        min_vz_mps=args.min_vz_mps,
        min_delta_h_m=args.min_delta_h_m,
        reject_warned_rows=not args.allow_warned_rows,
    )
    if not samples:
        raise SystemExit("No usable SD rows found.")
    summary = summarize_samples(
        samples,
        min_body_samples=args.min_body_samples,
        min_brake_samples=args.min_brake_samples,
        min_total_samples=args.min_total_samples,
        min_command_span=args.min_command_span,
        max_condition_number=args.max_condition_number,
    )

    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, summary, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"logs={summary['log_count']}")
    print(f"eligible_sample_count={summary['eligible_sample_count']}")
    print(f"body_sample_count={summary['body_sample_count']}")
    print(f"brake_sample_count={summary['brake_sample_count']}")
    print(f"command_span={summary['command_span']:.6g}")
    print(f"condition_number={summary['condition_number']:.6g}")
    print(f"measured_brake_rows={summary['measured_brake_rows']}")
    print(f"command_proxy_rows={summary['command_proxy_rows']}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

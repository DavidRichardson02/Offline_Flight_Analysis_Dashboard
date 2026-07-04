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
from typing import Iterable, TextIO


PHASE_NAMES = {
    0: "IDLE",
    1: "BOOST",
    2: "COAST",
    3: "BRAKE",
    4: "DESCENT",
}


@dataclass
class EvidenceSample:
    t_s: float
    phase: int | None = None
    est_h_m: float = math.nan
    est_v_mps: float = math.nan
    baro_alt_m: float = math.nan
    pred_no_brake_m: float = math.nan
    pred_full_brake_m: float = math.nan
    target_effective_m: float = math.nan
    target_nominal_m: float = math.nan
    target_margin_m: float = math.nan
    apogee_error_m: float = math.nan
    brake_authority_m: float = math.nan
    cmd01: float = math.nan
    actuator_us: float = math.nan
    p00_m2: float = math.nan
    p11_m2: float = math.nan
    sigma_h_m: float = math.nan
    baro_age_ms: float = math.nan
    imu_age_ms: float = math.nan
    est_age_ms: float = math.nan
    policy_valid: bool | None = None
    valid_mask: int | None = None
    warn_mask: int | None = None


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
    v = parse_float(value)
    if not math.isfinite(v):
        return None
    return int(round(v))


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


def estimate_actuator01(actuator_us: float) -> float:
    if not math.isfinite(actuator_us):
        return math.nan
    return max(0.0, min(1.0, (actuator_us - 1000.0) / 1000.0))


def sample_from_sd_row(row: dict[str, str]) -> EvidenceSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    est_h_m = parse_float(first_present(row, "est_h", "est_h_m", "kf_h"))
    p00 = parse_float(first_present(row, "P00", "P00_m2", "p00_m2"))
    sigma_h = math.sqrt(p00) if math.isfinite(p00) and p00 >= 0.0 else math.nan
    target_effective = parse_float(first_present(row, "target_effective", "target_apogee", "target_effective_m"))
    target_nominal = parse_float(first_present(row, "target_nominal", "target_nominal_m"))
    pred_no_brake = parse_float(first_present(row, "apogee_no_brake", "pred_no_brake_m"))
    pred_full_brake = parse_float(first_present(row, "apogee_full_brake", "pred_full_brake_m"))
    brake_authority = parse_float(first_present(row, "brake_authority_m"))
    if not math.isfinite(brake_authority) and math.isfinite(pred_no_brake) and math.isfinite(pred_full_brake):
        brake_authority = pred_no_brake - pred_full_brake

    target_margin = parse_float(first_present(row, "target_margin_m"))
    if not math.isfinite(target_margin) and math.isfinite(target_effective) and math.isfinite(est_h_m):
        target_margin = target_effective - est_h_m

    return EvidenceSample(
        t_s=t_s,
        phase=parse_int(first_present(row, "phase")),
        est_h_m=est_h_m,
        est_v_mps=parse_float(first_present(row, "est_v", "est_v_mps", "kf_v")),
        baro_alt_m=parse_float(first_present(row, "bmp_alt", "baro_alt_m", "bmp_alt_rel")),
        pred_no_brake_m=pred_no_brake,
        pred_full_brake_m=pred_full_brake,
        target_effective_m=target_effective,
        target_nominal_m=target_nominal,
        target_margin_m=target_margin,
        apogee_error_m=parse_float(first_present(row, "apogee_error", "apogee_error_m")),
        brake_authority_m=brake_authority,
        cmd01=parse_float(first_present(row, "policy_cmd", "cmd01")),
        actuator_us=parse_float(first_present(row, "actuator_us")),
        p00_m2=p00,
        p11_m2=parse_float(first_present(row, "P11", "P11_m2", "p11_m2")),
        sigma_h_m=sigma_h,
        policy_valid=bool_cell(row, "policy_valid"),
        warn_mask=parse_int(first_present(row, "warn_mask")),
    )


def read_sd_csv(path: Path) -> list[EvidenceSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples: list[EvidenceSample] = []
    for row in reader:
        sample = sample_from_sd_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def parse_plot_lines(lines: Iterable[str]) -> list[EvidenceSample]:
    header: list[str] | None = None
    samples: list[EvidenceSample] = []

    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "APOGEE":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "APOGEE" or header is None:
            continue

        row = dict(zip(header, parts[2:]))
        t_ms = parse_float(first_present(row, "t_ms"))
        if not math.isfinite(t_ms):
            continue
        samples.append(
            EvidenceSample(
                t_s=t_ms / 1000.0,
                phase=parse_int(first_present(row, "phase")),
                est_h_m=parse_float(first_present(row, "est_h_m")),
                est_v_mps=parse_float(first_present(row, "est_v_mps")),
                baro_alt_m=parse_float(first_present(row, "baro_alt_m")),
                pred_no_brake_m=parse_float(first_present(row, "pred_no_brake_m")),
                pred_full_brake_m=parse_float(first_present(row, "pred_full_brake_m")),
                target_effective_m=parse_float(first_present(row, "target_effective_m")),
                target_nominal_m=parse_float(first_present(row, "target_nominal_m")),
                target_margin_m=parse_float(first_present(row, "target_margin_m")),
                apogee_error_m=parse_float(first_present(row, "apogee_error_m")),
                brake_authority_m=parse_float(first_present(row, "brake_authority_m")),
                cmd01=parse_float(first_present(row, "cmd01")),
                actuator_us=parse_float(first_present(row, "actuator_us")),
                p00_m2=parse_float(first_present(row, "P00_m2")),
                p11_m2=parse_float(first_present(row, "P11_m2")),
                sigma_h_m=parse_float(first_present(row, "sigma_h_m")),
                baro_age_ms=parse_float(first_present(row, "baro_age_ms")),
                imu_age_ms=parse_float(first_present(row, "imu_age_ms")),
                est_age_ms=parse_float(first_present(row, "est_age_ms")),
                policy_valid=bool_cell(row, "policy_valid"),
                valid_mask=parse_int(first_present(row, "valid_mask")),
                warn_mask=parse_int(first_present(row, "warn_mask")),
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


def read_samples(paths: list[Path], input_format: str) -> list[EvidenceSample]:
    all_samples: list[EvidenceSample] = []
    for path in paths:
        if input_format == "sd":
            all_samples.extend(read_sd_csv(path))
            continue
        if input_format == "plot":
            all_samples.extend(parse_plot_lines(path.read_text(encoding="utf-8").splitlines()))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        first_line = next((line for line in text.splitlines() if line.strip()), "")
        if first_line.startswith("PLOT_HDR") or first_line.startswith("PLOT,"):
            all_samples.extend(parse_plot_lines(text.splitlines()))
        else:
            all_samples.extend(read_sd_csv(path))
    return sorted(all_samples, key=lambda sample: sample.t_s)


def finite_values(samples: list[EvidenceSample], attr: str) -> list[float]:
    values: list[float] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            values.append(float(value))
    return values


def summarize_samples(samples: list[EvidenceSample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable apogee evidence samples",
        }

    warn_rows = [sample for sample in samples if sample.warn_mask not in (None, 0)]
    stale_est_rows = [
        sample
        for sample in samples
        if math.isfinite(sample.est_age_ms) and sample.est_age_ms > 200.0
    ]
    phase_counts: dict[str, int] = {}
    for sample in samples:
        key = PHASE_NAMES.get(sample.phase, str(sample.phase))
        phase_counts[key] = phase_counts.get(key, 0) + 1

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "max_est_h_m": max(finite_values(samples, "est_h_m"), default=math.nan),
        "max_pred_no_brake_m": max(finite_values(samples, "pred_no_brake_m"), default=math.nan),
        "max_pred_full_brake_m": max(finite_values(samples, "pred_full_brake_m"), default=math.nan),
        "max_brake_authority_m": max(finite_values(samples, "brake_authority_m"), default=math.nan),
        "max_cmd01": max(finite_values(samples, "cmd01"), default=math.nan),
        "max_sigma_h_m": max(finite_values(samples, "sigma_h_m"), default=math.nan),
        "warn_row_count": len(warn_rows),
        "stale_est_row_count": len(stale_est_rows),
        "phase_counts": phase_counts,
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def polyline(samples: list[EvidenceSample], attr: str, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            points.append(f"{sx(sample.t_s):.2f},{sy(float(value)):.2f}")
    return " ".join(points)


def uncertainty_polygon(samples: list[EvidenceSample], sx, sy) -> str:
    upper: list[str] = []
    lower: list[str] = []
    for sample in samples:
        if math.isfinite(sample.est_h_m) and math.isfinite(sample.sigma_h_m):
            upper.append(f"{sx(sample.t_s):.2f},{sy(sample.est_h_m + sample.sigma_h_m):.2f}")
            lower.append(f"{sx(sample.t_s):.2f},{sy(sample.est_h_m - sample.sigma_h_m):.2f}")
    return " ".join(upper + list(reversed(lower)))


def authority_polygon(samples: list[EvidenceSample], sx, sy) -> str:
    upper: list[str] = []
    lower: list[str] = []
    for sample in samples:
        if math.isfinite(sample.pred_no_brake_m) and math.isfinite(sample.pred_full_brake_m):
            top = max(sample.pred_no_brake_m, sample.pred_full_brake_m)
            bottom = min(sample.pred_no_brake_m, sample.pred_full_brake_m)
            upper.append(f"{sx(sample.t_s):.2f},{sy(top):.2f}")
            lower.append(f"{sx(sample.t_s):.2f},{sy(bottom):.2f}")
    return " ".join(upper + list(reversed(lower)))


def phase_segments(samples: list[EvidenceSample], sx, y: float, height: float) -> str:
    colors = {
        0: "#94a3b8",
        1: "#ef4444",
        2: "#f97316",
        3: "#7c3aed",
        4: "#2563eb",
    }
    rects: list[str] = []
    for left, right in zip(samples, samples[1:]):
        if left.phase is None:
            continue
        x0 = sx(left.t_s)
        x1 = sx(right.t_s)
        width = max(1.0, x1 - x0)
        color = colors.get(left.phase, "#64748b")
        rects.append(f'<rect x="{x0:.2f}" y="{y:.2f}" width="{width:.2f}" height="{height:.2f}" fill="{color}" opacity="0.28"/>')
    return "\n".join(rects)


def render_svg(samples: list[EvidenceSample], title: str = "Apogee Control Evidence View") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 760
    left = 84
    right = 1138
    top = 70
    altitude_bottom = 470
    command_top = 535
    command_bottom = 690

    altitude_values: list[float] = []
    for attr in ("est_h_m", "baro_alt_m", "pred_no_brake_m", "pred_full_brake_m", "target_effective_m", "target_nominal_m"):
        altitude_values.extend(finite_values(samples, attr))
    for sample in samples:
        if math.isfinite(sample.est_h_m) and math.isfinite(sample.sigma_h_m):
            altitude_values.append(sample.est_h_m + sample.sigma_h_m)
            altitude_values.append(sample.est_h_m - sample.sigma_h_m)

    y_min = min(0.0, min(altitude_values, default=0.0))
    y_max = max(1.0, max(altitude_values, default=1.0))
    padding = max(10.0, 0.05 * (y_max - y_min))
    y_min -= padding
    y_max += padding

    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, left, right)
    sy = scale_fn(y_min, y_max, altitude_bottom, top)
    scmd = scale_fn(0.0, 1.05, command_bottom, command_top)

    target_values = finite_values(samples, "target_effective_m")
    target_y = sy(target_values[-1]) if target_values else None
    sigma_poly = uncertainty_polygon(samples, sx, sy)
    authority_poly = authority_polygon(samples, sx, sy)
    est_line = polyline(samples, "est_h_m", sx, sy)
    baro_line = polyline(samples, "baro_alt_m", sx, sy)
    no_brake_line = polyline(samples, "pred_no_brake_m", sx, sy)
    full_brake_line = polyline(samples, "pred_full_brake_m", sx, sy)
    cmd_points = polyline(samples, "cmd01", sx, scmd)

    actuator_samples: list[EvidenceSample] = []
    for sample in samples:
        actuator01 = estimate_actuator01(sample.actuator_us)
        actuator_samples.append(EvidenceSample(t_s=sample.t_s, cmd01=actuator01))
    actuator_points = polyline(actuator_samples, "cmd01", sx, scmd)

    warning_ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            warning_ticks.append(f'<line x1="{x:.2f}" y1="{top}" x2="{x:.2f}" y2="{command_bottom}" stroke="#dc2626" stroke-width="1" opacity="0.35"/>')

    summary = summarize_samples(samples)
    target_line = ""
    if target_y is not None:
        target_line = f'<line x1="{left}" y1="{target_y:.2f}" x2="{right}" y2="{target_y:.2f}" stroke="#15803d" stroke-width="2" stroke-dasharray="7 5"/>'

    def legend_item(x: int, y: int, color: str, label: str, dashed: bool = False) -> str:
        dash = ' stroke-dasharray="7 5"' if dashed else ""
        return (
            f'<line x1="{x}" y1="{y}" x2="{x + 28}" y2="{y}" stroke="{color}" stroke-width="3"{dash}/>'
            f'<text x="{x + 36}" y="{y + 4}" class="legend">{html.escape(label)}</text>'
        )

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .axis {{ stroke: #334155; stroke-width: 1.2; }}
  .grid {{ stroke: #cbd5e1; stroke-width: 1; opacity: 0.65; }}
  .label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .legend {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="{left}" y="35" class="title">{html.escape(title)}</text>
<text x="{left}" y="55" class="subtitle">Estimator, apogee prediction envelope, brake authority, command, actuator, and health evidence.</text>
<rect x="{left}" y="{top}" width="{right - left}" height="{altitude_bottom - top}" fill="#ffffff" stroke="#cbd5e1"/>
<rect x="{left}" y="{command_top}" width="{right - left}" height="{command_bottom - command_top}" fill="#ffffff" stroke="#cbd5e1"/>
<line x1="{left}" y1="{altitude_bottom}" x2="{right}" y2="{altitude_bottom}" class="axis"/>
<line x1="{left}" y1="{top}" x2="{left}" y2="{altitude_bottom}" class="axis"/>
<line x1="{left}" y1="{command_bottom}" x2="{right}" y2="{command_bottom}" class="axis"/>
<line x1="{left}" y1="{command_top}" x2="{left}" y2="{command_bottom}" class="axis"/>
{phase_segments(samples, sx, command_top - 25, 16)}
{''.join(warning_ticks)}
{'<polygon points="' + authority_poly + '" fill="#f59e0b" opacity="0.16"/>' if authority_poly else ''}
{'<polygon points="' + sigma_poly + '" fill="#2563eb" opacity="0.13"/>' if sigma_poly else ''}
{target_line}
<polyline points="{baro_line}" fill="none" stroke="#94a3b8" stroke-width="1.4" stroke-dasharray="4 5" opacity="0.85"/>
<polyline points="{est_line}" fill="none" stroke="#1d4ed8" stroke-width="2.5"/>
<polyline points="{no_brake_line}" fill="none" stroke="#dc2626" stroke-width="2"/>
<polyline points="{full_brake_line}" fill="none" stroke="#ea580c" stroke-width="2"/>
<polyline points="{cmd_points}" fill="none" stroke="#7c3aed" stroke-width="2.5"/>
<polyline points="{actuator_points}" fill="none" stroke="#0f766e" stroke-width="2" stroke-dasharray="6 5"/>
<text x="18" y="{(top + altitude_bottom) / 2:.0f}" class="label" transform="rotate(-90 18 {(top + altitude_bottom) / 2:.0f})">altitude / predicted apogee [m]</text>
<text x="24" y="{(command_top + command_bottom) / 2:.0f}" class="label" transform="rotate(-90 24 {(command_top + command_bottom) / 2:.0f})">command / actuator [0..1]</text>
<text x="{(left + right) / 2:.0f}" y="732" class="label">time [s]</text>
<text x="{left}" y="{altitude_bottom + 20}" class="label">{t_min:.2f}s</text>
<text x="{right - 50}" y="{altitude_bottom + 20}" class="label">{t_max:.2f}s</text>
<text x="{left - 70}" y="{top + 5}" class="label">{y_max:.0f}</text>
<text x="{left - 70}" y="{altitude_bottom}" class="label">{y_min:.0f}</text>
<text x="{left - 45}" y="{command_top + 5}" class="label">1.0</text>
<text x="{left - 45}" y="{command_bottom}" class="label">0.0</text>
{legend_item(790, 30, "#1d4ed8", "est altitude")}
{legend_item(790, 50, "#94a3b8", "baro altitude", True)}
{legend_item(930, 30, "#dc2626", "no-brake apogee")}
{legend_item(930, 50, "#ea580c", "full-brake apogee")}
{legend_item(790, 70, "#7c3aed", "policy cmd")}
{legend_item(930, 70, "#0f766e", "actuator est.", True)}
<text x="{left}" y="510" class="metric">samples={summary['sample_count']}  max_est_h={summary['max_est_h_m']:.2f}m  max_no_brake={summary['max_pred_no_brake_m']:.2f}m  max_authority={summary['max_brake_authority_m']:.2f}m  max_cmd={summary['max_cmd01']:.3f}  warn_rows={summary['warn_row_count']}</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[EvidenceSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render an apogee-control evidence SVG from current-schema SD CSV or captured PLOT APOGEE rows."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV or captured PLOT text file.")
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
    parser.add_argument("--serial-port", help="Optional live serial port. Requires pyserial.")
    parser.add_argument(
        "--serial-command",
        action="append",
        default=[],
        help="Command to send after opening the serial port before capture. Repeatable, for example HDR 0 then PLOT APOGEE.",
    )
    parser.add_argument("--serial-settle-ms", type=int, default=250)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration-s", type=float, default=10.0)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Apogee Control Evidence View")
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
        raise SystemExit("No usable apogee evidence samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"max_est_h_m={summary['max_est_h_m']:.3f}")
    print(f"max_brake_authority_m={summary['max_brake_authority_m']:.3f}")
    print(f"max_cmd01={summary['max_cmd01']:.3f}")
    print(f"warn_row_count={summary['warn_row_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

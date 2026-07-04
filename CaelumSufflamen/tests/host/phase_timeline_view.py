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


PHASE_NAMES = {
    0: "IDLE",
    1: "BOOST",
    2: "COAST",
    3: "BRAKE",
    4: "DESCENT",
}

PHASE_COLORS = {
    0: "#94a3b8",
    1: "#ef4444",
    2: "#f97316",
    3: "#7c3aed",
    4: "#2563eb",
}


@dataclass
class PhaseSample:
    t_s: float
    phase: int | None = None
    est_h_m: float = math.nan
    est_v_mps: float = math.nan
    imu_a_norm: float = math.nan
    cmd01: float = math.nan
    actuator_us: float = math.nan
    launch_latched: bool | None = None
    burnout_latched: bool | None = None
    descent_latched: bool | None = None
    launch_candidate: bool | None = None
    burnout_candidate: bool | None = None
    descent_candidate: bool | None = None
    boost_dwell_met: bool | None = None
    coast_dwell_met: bool | None = None
    brake_active: bool | None = None
    launch_confirm_ms: float = math.nan
    burnout_confirm_ms: float = math.nan
    descent_confirm_ms: float = math.nan
    since_launch_ms: float = math.nan
    since_burnout_ms: float = math.nan
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


def norm3(x: float, y: float, z: float) -> float:
    if not (math.isfinite(x) and math.isfinite(y) and math.isfinite(z)):
        return math.nan
    return math.sqrt(x * x + y * y + z * z)


def sample_from_sd_row(row: dict[str, str]) -> PhaseSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    imu_norm = parse_float(first_present(row, "imu_a_norm", "a_norm"))
    if not math.isfinite(imu_norm):
        imu_norm = norm3(
            parse_float(first_present(row, "ax")),
            parse_float(first_present(row, "ay")),
            parse_float(first_present(row, "az")),
        )

    return PhaseSample(
        t_s=t_s,
        phase=parse_int(first_present(row, "phase")),
        est_h_m=parse_float(first_present(row, "est_h", "est_h_m", "kf_h")),
        est_v_mps=parse_float(first_present(row, "est_v", "est_v_mps", "kf_v")),
        imu_a_norm=imu_norm,
        cmd01=parse_float(first_present(row, "policy_cmd", "cmd01")),
        actuator_us=parse_float(first_present(row, "actuator_us")),
        launch_latched=bool_cell(row, "phase_launch_latched", "launch_latched"),
        burnout_latched=bool_cell(row, "phase_burnout_latched", "burnout_latched"),
        descent_latched=bool_cell(row, "phase_descent_latched", "descent_latched"),
        launch_candidate=bool_cell(row, "phase_launch_candidate", "launch_candidate"),
        burnout_candidate=bool_cell(row, "phase_burnout_candidate", "burnout_candidate"),
        descent_candidate=bool_cell(row, "phase_descent_candidate", "descent_candidate"),
        boost_dwell_met=bool_cell(row, "phase_boost_dwell_met", "boost_dwell_met"),
        coast_dwell_met=bool_cell(row, "phase_coast_dwell_met", "coast_dwell_met"),
        brake_active=bool_cell(row, "phase_brake_active", "brake_active"),
        launch_confirm_ms=parse_float(first_present(row, "phase_launch_confirm_ms", "launch_confirm_ms")),
        burnout_confirm_ms=parse_float(first_present(row, "phase_burnout_confirm_ms", "burnout_confirm_ms")),
        descent_confirm_ms=parse_float(first_present(row, "phase_descent_confirm_ms", "descent_confirm_ms")),
        since_launch_ms=parse_float(first_present(row, "phase_since_launch_ms", "since_launch_ms")),
        since_burnout_ms=parse_float(first_present(row, "phase_since_burnout_ms", "since_burnout_ms")),
        warn_mask=parse_int(first_present(row, "warn_mask")),
    )


def read_sd_csv(path: Path) -> list[PhaseSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples: list[PhaseSample] = []
    for row in reader:
        sample = sample_from_sd_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def parse_plot_lines(lines: Iterable[str]) -> list[PhaseSample]:
    header: list[str] | None = None
    samples: list[PhaseSample] = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "PHASE":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "PHASE" or header is None:
            continue
        row = dict(zip(header, parts[2:]))
        t_ms = parse_float(first_present(row, "t_ms"))
        if not math.isfinite(t_ms):
            continue
        samples.append(
            PhaseSample(
                t_s=t_ms / 1000.0,
                phase=parse_int(first_present(row, "phase")),
                est_h_m=parse_float(first_present(row, "est_h_m")),
                est_v_mps=parse_float(first_present(row, "est_v_mps")),
                imu_a_norm=parse_float(first_present(row, "imu_a_norm")),
                cmd01=parse_float(first_present(row, "cmd01")),
                actuator_us=parse_float(first_present(row, "actuator_us")),
                launch_latched=bool_cell(row, "launch_latched"),
                burnout_latched=bool_cell(row, "burnout_latched"),
                descent_latched=bool_cell(row, "descent_latched"),
                launch_candidate=bool_cell(row, "launch_candidate"),
                burnout_candidate=bool_cell(row, "burnout_candidate"),
                descent_candidate=bool_cell(row, "descent_candidate"),
                boost_dwell_met=bool_cell(row, "boost_dwell_met"),
                coast_dwell_met=bool_cell(row, "coast_dwell_met"),
                brake_active=bool_cell(row, "brake_active"),
                launch_confirm_ms=parse_float(first_present(row, "launch_confirm_ms")),
                burnout_confirm_ms=parse_float(first_present(row, "burnout_confirm_ms")),
                descent_confirm_ms=parse_float(first_present(row, "descent_confirm_ms")),
                since_launch_ms=parse_float(first_present(row, "since_launch_ms")),
                since_burnout_ms=parse_float(first_present(row, "since_burnout_ms")),
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


def read_samples(paths: list[Path], input_format: str) -> list[PhaseSample]:
    all_samples: list[PhaseSample] = []
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


def finite_values(samples: list[PhaseSample], attr: str) -> list[float]:
    values: list[float] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            values.append(float(value))
    return values


def summarize_samples(samples: list[PhaseSample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable phase samples",
        }

    phase_counts: dict[str, int] = {}
    transitions: list[dict[str, object]] = []
    previous_phase = samples[0].phase
    for sample in samples:
        key = PHASE_NAMES.get(sample.phase, str(sample.phase))
        phase_counts[key] = phase_counts.get(key, 0) + 1
        if sample.phase != previous_phase:
            transitions.append(
                {
                    "t_s": sample.t_s,
                    "from": PHASE_NAMES.get(previous_phase, str(previous_phase)),
                    "to": PHASE_NAMES.get(sample.phase, str(sample.phase)),
                }
            )
            previous_phase = sample.phase

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "phase_counts": phase_counts,
        "transition_count": len(transitions),
        "transitions": transitions,
        "max_est_h_m": max(finite_values(samples, "est_h_m"), default=math.nan),
        "max_est_v_mps": max(finite_values(samples, "est_v_mps"), default=math.nan),
        "max_imu_a_norm": max(finite_values(samples, "imu_a_norm"), default=math.nan),
        "max_cmd01": max(finite_values(samples, "cmd01"), default=math.nan),
        "warn_row_count": sum(1 for sample in samples if sample.warn_mask not in (None, 0)),
        "launch_latched_rows": sum(1 for sample in samples if sample.launch_latched),
        "burnout_latched_rows": sum(1 for sample in samples if sample.burnout_latched),
        "descent_latched_rows": sum(1 for sample in samples if sample.descent_latched),
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def polyline(samples: list[PhaseSample], attr: str, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            points.append(f"{sx(sample.t_s):.2f},{sy(float(value)):.2f}")
    return " ".join(points)


def phase_rects(samples: list[PhaseSample], sx, y: float, height: float) -> str:
    rects: list[str] = []
    for left, right in zip(samples, samples[1:]):
        if left.phase is None:
            continue
        x0 = sx(left.t_s)
        x1 = sx(right.t_s)
        rects.append(
            f'<rect x="{x0:.2f}" y="{y:.2f}" width="{max(1.0, x1 - x0):.2f}" height="{height:.2f}" '
            f'fill="{PHASE_COLORS.get(left.phase, "#64748b")}" opacity="0.78"/>'
        )
    return "\n".join(rects)


def bool_lane(samples: list[PhaseSample], attr: str, sx, y: float, color: str, label: str) -> str:
    rects: list[str] = [f'<text x="84" y="{y + 12:.2f}" class="label">{html.escape(label)}</text>']
    for left, right in zip(samples, samples[1:]):
        if getattr(left, attr) is True:
            x0 = sx(left.t_s)
            x1 = sx(right.t_s)
            rects.append(
                f'<rect x="{x0:.2f}" y="{y:.2f}" width="{max(1.0, x1 - x0):.2f}" height="14" fill="{color}" opacity="0.75"/>'
            )
    return "\n".join(rects)


def event_lines(samples: list[PhaseSample], sx, top: float, bottom: float) -> str:
    lines: list[str] = []
    latch_fields = [
        ("launch_latched", "#ef4444", "launch"),
        ("burnout_latched", "#f97316", "burnout"),
        ("descent_latched", "#2563eb", "descent"),
    ]
    for attr, color, label in latch_fields:
        seen = False
        for sample in samples:
            if getattr(sample, attr) is True and not seen:
                x = sx(sample.t_s)
                lines.append(f'<line x1="{x:.2f}" y1="{top}" x2="{x:.2f}" y2="{bottom}" stroke="{color}" stroke-width="2" stroke-dasharray="4 4"/>')
                lines.append(f'<text x="{x + 4:.2f}" y="{top + 14:.2f}" class="label">{html.escape(label)}</text>')
                seen = True
    return "\n".join(lines)


def render_svg(samples: list[PhaseSample], title: str = "Flight Phase Timeline View") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 760
    left = 150
    right = 1138
    timeline_top = 82
    timeline_height = 55
    lane_top = 165
    plot_top = 360
    plot_bottom = 675
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, left, right)

    trace_values: list[float] = []
    for attr in ("est_h_m", "est_v_mps", "imu_a_norm"):
        trace_values.extend(finite_values(samples, attr))
    y_min = min(0.0, min(trace_values, default=0.0))
    y_max = max(1.0, max(trace_values, default=1.0))
    padding = max(5.0, 0.08 * (y_max - y_min))
    sy = scale_fn(y_min - padding, y_max + padding, plot_bottom, plot_top)
    scmd = scale_fn(0.0, 1.05, plot_bottom, plot_top)

    warn_ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            warn_ticks.append(f'<line x1="{x:.2f}" y1="{timeline_top}" x2="{x:.2f}" y2="{plot_bottom}" stroke="#dc2626" stroke-width="1" opacity="0.35"/>')

    summary = summarize_samples(samples)

    def legend(x: int, y: int, color: str, label: str, dashed: bool = False) -> str:
        dash = ' stroke-dasharray="6 5"' if dashed else ""
        return f'<line x1="{x}" y1="{y}" x2="{x + 28}" y2="{y}" stroke="{color}" stroke-width="3"{dash}/><text x="{x + 36}" y="{y + 4}" class="legend">{html.escape(label)}</text>'

    phase_rect_svg = phase_rects(samples, sx, timeline_top, timeline_height)
    event_line_svg = event_lines(samples, sx, timeline_top, plot_bottom)
    launch_candidate_svg = bool_lane(samples, "launch_candidate", sx, lane_top, "#ef4444", "launch cand")
    burnout_candidate_svg = bool_lane(samples, "burnout_candidate", sx, lane_top + 24, "#f97316", "burnout cand")
    descent_candidate_svg = bool_lane(samples, "descent_candidate", sx, lane_top + 48, "#2563eb", "descent cand")
    boost_dwell_svg = bool_lane(samples, "boost_dwell_met", sx, lane_top + 84, "#16a34a", "boost dwell")
    coast_dwell_svg = bool_lane(samples, "coast_dwell_met", sx, lane_top + 108, "#0d9488", "coast dwell")
    brake_active_svg = bool_lane(samples, "brake_active", sx, lane_top + 132, "#7c3aed", "brake active")
    warn_tick_svg = "".join(warn_ticks)
    est_h_points = polyline(samples, "est_h_m", sx, sy)
    est_v_points = polyline(samples, "est_v_mps", sx, sy)
    imu_norm_points = polyline(samples, "imu_a_norm", sx, sy)
    cmd_points = polyline(samples, "cmd01", sx, scmd)
    legend_altitude = legend(790, 30, "#1d4ed8", "est altitude")
    legend_velocity = legend(790, 50, "#ea580c", "est velocity")
    legend_imu = legend(930, 30, "#dc2626", "IMU norm")
    legend_cmd = legend(930, 50, "#7c3aed", "cmd01", True)

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .axis {{ stroke: #334155; stroke-width: 1.2; }}
  .label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .legend {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="84" y="35" class="title">{html.escape(title)}</text>
<text x="84" y="55" class="subtitle">Phase state, transition latches, candidates, dwell gates, acceleration, velocity, command, and warning evidence.</text>
<rect x="{left}" y="{timeline_top}" width="{right - left}" height="{timeline_height}" fill="#ffffff" stroke="#cbd5e1"/>
{phase_rect_svg}
{event_line_svg}
<text x="84" y="{timeline_top + 34}" class="label">phase</text>
{launch_candidate_svg}
{burnout_candidate_svg}
{descent_candidate_svg}
{boost_dwell_svg}
{coast_dwell_svg}
{brake_active_svg}
<rect x="{left}" y="{plot_top}" width="{right - left}" height="{plot_bottom - plot_top}" fill="#ffffff" stroke="#cbd5e1"/>
{warn_tick_svg}
<polyline points="{est_h_points}" fill="none" stroke="#1d4ed8" stroke-width="2.4"/>
<polyline points="{est_v_points}" fill="none" stroke="#ea580c" stroke-width="2"/>
<polyline points="{imu_norm_points}" fill="none" stroke="#dc2626" stroke-width="1.8" opacity="0.9"/>
<polyline points="{cmd_points}" fill="none" stroke="#7c3aed" stroke-width="2.2" stroke-dasharray="6 5"/>
<line x1="{left}" y1="{plot_bottom}" x2="{right}" y2="{plot_bottom}" class="axis"/>
<line x1="{left}" y1="{plot_top}" x2="{left}" y2="{plot_bottom}" class="axis"/>
<text x="{left}" y="{plot_bottom + 22}" class="label">{t_min:.2f}s</text>
<text x="{right - 48}" y="{plot_bottom + 22}" class="label">{t_max:.2f}s</text>
<text x="{(left + right) / 2:.0f}" y="730" class="label">time [s]</text>
{legend_altitude}
{legend_velocity}
{legend_imu}
{legend_cmd}
<text x="84" y="706" class="metric">samples={summary['sample_count']} transitions={summary['transition_count']} max_h={summary['max_est_h_m']:.2f}m max_a_norm={summary['max_imu_a_norm']:.2f} warn_rows={summary['warn_row_count']}</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[PhaseSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a phase state-machine timeline SVG from current-schema SD CSV or captured PLOT PHASE rows."
    )
    parser.add_argument("input", nargs="*", type=Path)
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
    parser.add_argument("--serial-port")
    parser.add_argument(
        "--serial-command",
        action="append",
        default=[],
        help="Command to send after opening the serial port before capture. Repeatable, for example HDR 0 then PLOT PHASE.",
    )
    parser.add_argument("--serial-settle-ms", type=int, default=250)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration-s", type=float, default=10.0)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Flight Phase Timeline View")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.serial_port:
        samples = parse_plot_lines(
            read_serial_lines(
                args.serial_port,
                args.baud,
                args.duration_s,
                args.max_rows,
                args.serial_command,
                max(0.0, args.serial_settle_ms / 1000.0),
            )
        )
    else:
        if not args.input:
            raise SystemExit("Provide at least one input file or --serial-port.")
        samples = read_samples(args.input, args.input_format)
    if args.max_rows is not None:
        samples = samples[: args.max_rows]
    if not samples:
        raise SystemExit("No usable phase samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"transition_count={summary['transition_count']}")
    print(f"phase_counts={summary['phase_counts']}")
    print(f"max_imu_a_norm={summary['max_imu_a_norm']:.3f}")
    print(f"warn_row_count={summary['warn_row_count']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

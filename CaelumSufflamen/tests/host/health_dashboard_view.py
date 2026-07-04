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


CHANNELS = [
    ("baro_valid", "barometer"),
    ("imu_valid", "IMU"),
    ("aux_valid", "aux accel"),
    ("pmod_valid", "Pmod accel"),
    ("mag_valid", "magnetometer"),
    ("att_valid", "attitude"),
    ("auxvz_valid", "vertical accel"),
    ("est_valid", "estimator"),
    ("policy_valid", "policy"),
    ("cfg_valid", "config"),
]

AGE_FIELDS = [
    ("baro_age_ms", "barometer"),
    ("imu_age_ms", "IMU"),
    ("aux_age_ms", "aux"),
    ("pmod_age_ms", "Pmod"),
    ("mag_age_ms", "mag"),
    ("att_age_ms", "attitude"),
    ("auxvz_age_ms", "auxvz"),
    ("est_age_ms", "estimator"),
    ("phase_diag_age_ms", "phase diag"),
]

WARN_BITS = {
    0: "bmp_hw",
    1: "bmi_accel_hw",
    2: "bmi_gyro_hw",
    3: "lis_hw",
    4: "baro_invalid",
    5: "imu_invalid",
    6: "aux_invalid",
    7: "auxvz_invalid",
    8: "att_invalid",
    9: "est_invalid",
    10: "cfg_invalid",
    11: "pmod_fault",
    12: "mag_fault",
    13: "sd_fault",
}


@dataclass
class HealthSample:
    t_s: float
    valid_mask: int | None = None
    warn_mask: int | None = None
    bmp_ok: bool | None = None
    bmi_accel_ok: bool | None = None
    bmi_gyro_ok: bool | None = None
    lis_ok: bool | None = None
    pmod_accel_ok: bool | None = None
    mag_ok: bool | None = None
    baro_valid: bool | None = None
    imu_valid: bool | None = None
    aux_valid: bool | None = None
    pmod_valid: bool | None = None
    mag_valid: bool | None = None
    att_valid: bool | None = None
    auxvz_valid: bool | None = None
    est_valid: bool | None = None
    policy_valid: bool | None = None
    cfg_valid: bool | None = None
    baro_age_ms: float = math.nan
    imu_age_ms: float = math.nan
    aux_age_ms: float = math.nan
    pmod_age_ms: float = math.nan
    mag_age_ms: float = math.nan
    att_age_ms: float = math.nan
    auxvz_age_ms: float = math.nan
    est_age_ms: float = math.nan
    phase_diag_age_ms: float = math.nan
    sd_card_ok: bool | None = None
    sd_runtime_failed: bool | None = None
    sd_fail_count: float = math.nan


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


def sample_from_sd_row(row: dict[str, str]) -> HealthSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    return HealthSample(
        t_s=t_s,
        warn_mask=parse_int(first_present(row, "warn_mask")),
        baro_valid=bool_cell(row, "baro_valid"),
        imu_valid=bool_cell(row, "imu_valid"),
        aux_valid=bool_cell(row, "aux_valid"),
        pmod_valid=bool_cell(row, "pmod_accel_valid", "pmod_valid"),
        mag_valid=bool_cell(row, "mag_valid"),
        att_valid=bool_cell(row, "att_valid"),
        auxvz_valid=bool_cell(row, "auxvz_valid"),
        est_valid=bool_cell(row, "est_valid"),
        policy_valid=bool_cell(row, "policy_valid"),
        cfg_valid=True,
        phase_diag_age_ms=parse_float(first_present(row, "phase_diag_age_ms")),
        sd_runtime_failed=bool_cell(row, "sd_runtime_failed"),
    )


def read_sd_csv(path: Path) -> list[HealthSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples: list[HealthSample] = []
    for row in reader:
        sample = sample_from_sd_row(row)
        if sample is not None:
            samples.append(sample)
    return samples


def parse_plot_lines(lines: Iterable[str]) -> list[HealthSample]:
    header: list[str] | None = None
    samples: list[HealthSample] = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "HEALTH":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "HEALTH" or header is None:
            continue
        row = dict(zip(header, parts[2:]))
        t_ms = parse_float(first_present(row, "t_ms"))
        if not math.isfinite(t_ms):
            continue
        samples.append(
            HealthSample(
                t_s=t_ms / 1000.0,
                valid_mask=parse_int(first_present(row, "valid_mask")),
                warn_mask=parse_int(first_present(row, "warn_mask")),
                bmp_ok=bool_cell(row, "bmp_ok"),
                bmi_accel_ok=bool_cell(row, "bmi_accel_ok"),
                bmi_gyro_ok=bool_cell(row, "bmi_gyro_ok"),
                lis_ok=bool_cell(row, "lis_ok"),
                pmod_accel_ok=bool_cell(row, "pmod_accel_ok"),
                mag_ok=bool_cell(row, "mag_ok"),
                baro_valid=bool_cell(row, "baro_valid"),
                imu_valid=bool_cell(row, "imu_valid"),
                aux_valid=bool_cell(row, "aux_valid"),
                pmod_valid=bool_cell(row, "pmod_valid"),
                mag_valid=bool_cell(row, "mag_valid"),
                att_valid=bool_cell(row, "att_valid"),
                auxvz_valid=bool_cell(row, "auxvz_valid"),
                est_valid=bool_cell(row, "est_valid"),
                policy_valid=bool_cell(row, "policy_valid"),
                cfg_valid=bool_cell(row, "cfg_valid"),
                baro_age_ms=parse_float(first_present(row, "baro_age_ms")),
                imu_age_ms=parse_float(first_present(row, "imu_age_ms")),
                aux_age_ms=parse_float(first_present(row, "aux_age_ms")),
                pmod_age_ms=parse_float(first_present(row, "pmod_age_ms")),
                mag_age_ms=parse_float(first_present(row, "mag_age_ms")),
                att_age_ms=parse_float(first_present(row, "att_age_ms")),
                auxvz_age_ms=parse_float(first_present(row, "auxvz_age_ms")),
                est_age_ms=parse_float(first_present(row, "est_age_ms")),
                phase_diag_age_ms=parse_float(first_present(row, "phase_diag_age_ms")),
                sd_card_ok=bool_cell(row, "sd_card_ok"),
                sd_runtime_failed=bool_cell(row, "sd_runtime_failed"),
                sd_fail_count=parse_float(first_present(row, "sd_fail_count")),
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


def read_samples(paths: list[Path], input_format: str) -> list[HealthSample]:
    all_samples: list[HealthSample] = []
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


def is_bad(value: bool | None) -> bool:
    return value is False


def is_good(value: bool | None) -> bool:
    return value is True


def summarize_samples(samples: list[HealthSample]) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "reason": "no usable health samples",
        }

    invalid_counts = {
        name: sum(1 for sample in samples if is_bad(getattr(sample, attr)))
        for attr, name in CHANNELS
    }
    known_counts = {
        name: sum(1 for sample in samples if getattr(sample, attr) is not None)
        for attr, name in CHANNELS
    }
    age_max_ms = {}
    for attr, name in AGE_FIELDS:
        values = [
            float(getattr(sample, attr))
            for sample in samples
            if math.isfinite(float(getattr(sample, attr)))
        ]
        age_max_ms[name] = max(values) if values else math.nan

    warn_bit_counts = {}
    for bit, name in WARN_BITS.items():
        warn_bit_counts[name] = sum(
            1 for sample in samples if sample.warn_mask is not None and bool(sample.warn_mask & (1 << bit))
        )

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "warn_row_count": sum(1 for sample in samples if sample.warn_mask not in (None, 0)),
        "invalid_counts": invalid_counts,
        "known_counts": known_counts,
        "age_max_ms": age_max_ms,
        "warn_bit_counts": warn_bit_counts,
        "sd_runtime_failed_rows": sum(1 for sample in samples if sample.sd_runtime_failed is True),
    }


def scale_fn(domain_min: float, domain_max: float, pixel_min: float, pixel_max: float):
    span = domain_max - domain_min
    if not math.isfinite(span) or abs(span) < 1.0e-9:
        span = 1.0

    def scale(value: float) -> float:
        return pixel_min + ((value - domain_min) / span) * (pixel_max - pixel_min)

    return scale


def status_color(value: bool | None) -> str:
    if value is True:
        return "#16a34a"
    if value is False:
        return "#dc2626"
    return "#cbd5e1"


def timeline_row(samples: list[HealthSample], attr: str, sx, y: float, label: str) -> str:
    pieces = [f'<text x="88" y="{y + 12:.2f}" class="label">{html.escape(label)}</text>']
    for left, right in zip(samples, samples[1:]):
        value = getattr(left, attr)
        x0 = sx(left.t_s)
        x1 = sx(right.t_s)
        pieces.append(
            f'<rect x="{x0:.2f}" y="{y:.2f}" width="{max(1.0, x1 - x0):.2f}" height="14" fill="{status_color(value)}" opacity="0.78"/>'
        )
    return "\n".join(pieces)


def warning_ticks(samples: list[HealthSample], sx, top: float, bottom: float) -> str:
    ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            ticks.append(f'<line x1="{x:.2f}" y1="{top}" x2="{x:.2f}" y2="{bottom}" stroke="#dc2626" stroke-width="1" opacity="0.32"/>')
    return "\n".join(ticks)


def age_bars(summary: dict, x: float, y: float) -> str:
    rows: list[str] = []
    values = [
        value for value in summary["age_max_ms"].values()
        if isinstance(value, (int, float)) and math.isfinite(float(value))
    ]
    max_age = max(values, default=1.0)
    for idx, (name, value) in enumerate(summary["age_max_ms"].items()):
        yy = y + idx * 22
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            width = 180.0 * min(1.0, float(value) / max(1.0, max_age))
            text = f"{float(value):.0f} ms"
        else:
            width = 0.0
            text = "n/a"
        rows.append(f'<text x="{x}" y="{yy + 12:.2f}" class="label">{html.escape(name)}</text>')
        rows.append(f'<rect x="{x + 82}" y="{yy:.2f}" width="180" height="14" fill="#e2e8f0"/>')
        rows.append(f'<rect x="{x + 82}" y="{yy:.2f}" width="{width:.2f}" height="14" fill="#2563eb" opacity="0.75"/>')
        rows.append(f'<text x="{x + 270}" y="{yy + 12:.2f}" class="label">{text}</text>')
    return "\n".join(rows)


def warn_bit_table(summary: dict, x: float, y: float) -> str:
    rows = [f'<text x="{x}" y="{y - 10}" class="panel_title">warning bit counts</text>']
    shown = 0
    for name, count in summary["warn_bit_counts"].items():
        if count <= 0:
            continue
        yy = y + shown * 20
        rows.append(f'<text x="{x}" y="{yy:.2f}" class="metric">{html.escape(name)}={count}</text>')
        shown += 1
    if shown == 0:
        rows.append(f'<text x="{x}" y="{y}" class="metric">none</text>')
    return "\n".join(rows)


def render_svg(samples: list[HealthSample], title: str = "Sensor Health Dashboard View") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1200
    height = 780
    left = 210
    right = 1128
    row_top = 90
    row_step = 27
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, left, right)
    summary = summarize_samples(samples)
    timeline_bottom = row_top + len(CHANNELS) * row_step + 20

    rows = [
        timeline_row(samples, attr, sx, row_top + idx * row_step, label)
        for idx, (attr, label) in enumerate(CHANNELS)
    ]

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
<text x="84" y="35" class="title">{html.escape(title)}</text>
<text x="84" y="55" class="subtitle">Validity, freshness, warning bits, and SD logger health as display evidence, not flight-control input.</text>
<rect x="{left}" y="{row_top - 12}" width="{right - left}" height="{timeline_bottom - row_top + 16}" fill="#ffffff" stroke="#cbd5e1"/>
{warning_ticks(samples, sx, row_top - 12, timeline_bottom + 4)}
{''.join(rows)}
<line x1="{left}" y1="{timeline_bottom + 9}" x2="{right}" y2="{timeline_bottom + 9}" class="axis"/>
<text x="{left}" y="{timeline_bottom + 28}" class="label">{t_min:.2f}s</text>
<text x="{right - 50}" y="{timeline_bottom + 28}" class="label">{t_max:.2f}s</text>
<rect x="84" y="{timeline_bottom + 56}" width="492" height="290" fill="#ffffff" stroke="#cbd5e1"/>
<text x="104" y="{timeline_bottom + 82}" class="panel_title">max snapshot ages</text>
{age_bars(summary, 104, timeline_bottom + 102)}
<rect x="620" y="{timeline_bottom + 56}" width="508" height="290" fill="#ffffff" stroke="#cbd5e1"/>
<text x="640" y="{timeline_bottom + 82}" class="panel_title">summary</text>
<text x="640" y="{timeline_bottom + 110}" class="metric">samples={summary['sample_count']}</text>
<text x="640" y="{timeline_bottom + 130}" class="metric">warn_rows={summary['warn_row_count']}</text>
<text x="640" y="{timeline_bottom + 150}" class="metric">sd_runtime_failed_rows={summary['sd_runtime_failed_rows']}</text>
{warn_bit_table(summary, 640, timeline_bottom + 190)}
<rect x="910" y="{timeline_bottom + 96}" width="16" height="16" fill="#16a34a"/><text x="934" y="{timeline_bottom + 109}" class="label">valid/ok</text>
<rect x="910" y="{timeline_bottom + 120}" width="16" height="16" fill="#dc2626"/><text x="934" y="{timeline_bottom + 133}" class="label">invalid/fault</text>
<rect x="910" y="{timeline_bottom + 144}" width="16" height="16" fill="#cbd5e1"/><text x="934" y="{timeline_bottom + 157}" class="label">not logged</text>
</svg>
"""
    return svg


def write_json(path: Path, samples: list[HealthSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render a sensor health dashboard SVG from current-schema SD CSV or captured PLOT HEALTH rows."
    )
    parser.add_argument("input", nargs="*", type=Path)
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
    parser.add_argument("--serial-port")
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
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="Sensor Health Dashboard View")
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
        raise SystemExit("No usable health samples found.")

    summary = summarize_samples(samples)
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"warn_row_count={summary['warn_row_count']}")
    print(f"invalid_counts={summary['invalid_counts']}")
    print(f"sd_runtime_failed_rows={summary['sd_runtime_failed_rows']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

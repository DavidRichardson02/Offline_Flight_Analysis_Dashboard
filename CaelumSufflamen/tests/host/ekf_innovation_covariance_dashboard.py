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


UINT32_MAX = 4294967295.0
DEFAULT_STALE_AGE_MS = 200.0
DEFAULT_MEASUREMENT_VARIANCE_M2 = 5.71e-03

PLOT_ESTIMATOR_HEADER = [
    "t_ms",
    "valid_mask",
    "warn_mask",
    "baro_age_ms",
    "imu_age_ms",
    "att_age_ms",
    "auxvz_age_ms",
    "est_age_ms",
    "baro_alt_m",
    "est_h_m",
    "est_v_mps",
    "est_a_mps2",
    "P00",
    "P01",
    "P10",
    "P11",
    "sigma_h_m",
    "sigma_v_mps",
    "est_seeded",
]

VALID_BITS = {
    "baro": 0,
    "imu": 1,
    "aux": 2,
    "pmod": 3,
    "mag": 4,
    "att": 5,
    "auxvz": 6,
    "est": 7,
    "policy": 8,
    "cfg": 9,
}

GATE_ORDER = [
    "covariance_finite",
    "covariance_symmetric",
    "covariance_psd",
    "sigma_h_matches",
    "sigma_v_matches",
    "alt_residual_ok",
    "velocity_residual_ok",
    "baro_fresh",
    "auxvz_fresh",
    "est_fresh",
]

GATE_LABELS = {
    "covariance_finite": "finite P",
    "covariance_symmetric": "symmetric",
    "covariance_psd": "PSD",
    "sigma_h_matches": "sigma h",
    "sigma_v_matches": "sigma v",
    "alt_residual_ok": "alt resid",
    "velocity_residual_ok": "vel resid",
    "baro_fresh": "baro fresh",
    "auxvz_fresh": "auxvz fresh",
    "est_fresh": "est fresh",
}


@dataclass
class EkfSample:
    t_s: float
    valid_mask: int | None = None
    warn_mask: int | None = None
    baro_age_ms: float = math.nan
    imu_age_ms: float = math.nan
    att_age_ms: float = math.nan
    auxvz_age_ms: float = math.nan
    est_age_ms: float = math.nan
    baro_alt_m: float = math.nan
    est_h_m: float = math.nan
    est_v_mps: float = math.nan
    est_a_mps2: float = math.nan
    auxvz_a_vertical_mps2: float = math.nan
    baro_v_proxy_mps: float = math.nan
    alt_residual_m: float = math.nan
    velocity_residual_mps: float = math.nan
    accel_residual_mps2: float = math.nan
    p00_m2: float = math.nan
    p01_m2ps: float = math.nan
    p10_m2ps: float = math.nan
    p11_m2ps2: float = math.nan
    sigma_h_m: float = math.nan
    sigma_v_mps: float = math.nan
    est_seeded: bool | None = None
    baro_valid: bool | None = None
    auxvz_valid: bool | None = None
    est_valid: bool | None = None
    covariance_symmetry_abs: float = math.nan
    covariance_det: float = math.nan
    covariance_corr: float = math.nan
    norm_alt_residual: float = math.nan
    norm_velocity_residual: float = math.nan


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


def valid_mask_bool(valid_mask: int | None, key: str) -> bool | None:
    if valid_mask is None:
        return None
    bit = VALID_BITS[key]
    return (valid_mask & (1 << bit)) != 0


def finite_or_none(value: float) -> float | None:
    return float(value) if math.isfinite(value) else None


def json_safe(value: object) -> object:
    if isinstance(value, float):
        return finite_or_none(value)
    if isinstance(value, dict):
        return {str(key): json_safe(child) for key, child in value.items()}
    if isinstance(value, list):
        return [json_safe(child) for child in value]
    return value


def finite_difference(a: float, b: float) -> float:
    if math.isfinite(a) and math.isfinite(b):
        return a - b
    return math.nan


def age_fresh(age_ms: float, stale_age_ms: float) -> bool | None:
    if not math.isfinite(age_ms):
        return None
    if age_ms >= UINT32_MAX:
        return False
    return age_ms <= stale_age_ms


def sample_from_row(row: dict[str, str], *, measurement_variance_m2: float) -> EkfSample | None:
    t_us = parse_float(first_present(row, "t_us"))
    t_ms = parse_float(first_present(row, "t_ms"))
    if math.isfinite(t_us):
        t_s = t_us / 1_000_000.0
    elif math.isfinite(t_ms):
        t_s = t_ms / 1000.0
    else:
        return None

    valid_mask = parse_int(first_present(row, "valid_mask"))
    p00 = parse_float(first_present(row, "P00", "P00_m2", "p00_m2"))
    p01 = parse_float(first_present(row, "P01", "P01_m2ps", "p01_m2ps"))
    p10 = parse_float(first_present(row, "P10", "P10_m2ps", "p10_m2ps"))
    p11 = parse_float(first_present(row, "P11", "P11_m2ps2", "p11_m2ps2"))
    sigma_h = parse_float(first_present(row, "sigma_h_m"))
    sigma_v = parse_float(first_present(row, "sigma_v_mps"))
    if not math.isfinite(sigma_h) and math.isfinite(p00) and p00 >= 0.0:
        sigma_h = math.sqrt(p00)
    if not math.isfinite(sigma_v) and math.isfinite(p11) and p11 >= 0.0:
        sigma_v = math.sqrt(p11)

    est_h = parse_float(first_present(row, "est_h", "est_h_m", "kf_h"))
    est_v = parse_float(first_present(row, "est_v", "est_v_mps", "kf_v"))
    est_a = parse_float(first_present(row, "est_a", "est_a_mps2"))
    baro_alt = parse_float(first_present(row, "bmp_alt", "baro_alt_m", "bmp_alt_rel"))
    alt_residual = parse_float(first_present(row, "alt_residual_m"))
    if not math.isfinite(alt_residual):
        alt_residual = finite_difference(est_h, baro_alt)

    baro_v_proxy = parse_float(first_present(row, "baro_v_proxy_mps"))
    velocity_residual = parse_float(first_present(row, "velocity_residual_mps"))
    if not math.isfinite(velocity_residual):
        velocity_residual = finite_difference(est_v, baro_v_proxy)

    auxvz_a = parse_float(first_present(row, "a_vertical", "auxvz_a_vertical_mps2"))
    accel_residual = parse_float(first_present(row, "accel_residual_mps2"))
    if not math.isfinite(accel_residual):
        accel_residual = finite_difference(est_a, auxvz_a)

    sym_abs = abs(p01 - p10) if math.isfinite(p01) and math.isfinite(p10) else math.nan
    det = p00 * p11 - p01 * p10 if all(math.isfinite(value) for value in (p00, p01, p10, p11)) else math.nan
    corr = math.nan
    if all(math.isfinite(value) for value in (p00, p01, p11)) and p00 > 0.0 and p11 > 0.0:
        corr = p01 / math.sqrt(p00 * p11)
    norm_alt = math.nan
    if math.isfinite(alt_residual) and math.isfinite(p00) and p00 + measurement_variance_m2 > 0.0:
        norm_alt = alt_residual / math.sqrt(p00 + measurement_variance_m2)
    norm_vel = math.nan
    if math.isfinite(velocity_residual) and math.isfinite(sigma_v) and sigma_v > 0.0:
        norm_vel = velocity_residual / sigma_v

    baro_valid = bool_cell(row, "baro_valid")
    if baro_valid is None:
        baro_valid = valid_mask_bool(valid_mask, "baro")
    auxvz_valid = bool_cell(row, "auxvz_valid")
    if auxvz_valid is None:
        auxvz_valid = valid_mask_bool(valid_mask, "auxvz")
    est_valid = bool_cell(row, "est_valid")
    if est_valid is None:
        est_valid = valid_mask_bool(valid_mask, "est")

    return EkfSample(
        t_s=t_s,
        valid_mask=valid_mask,
        warn_mask=parse_int(first_present(row, "warn_mask")),
        baro_age_ms=parse_float(first_present(row, "baro_age_ms")),
        imu_age_ms=parse_float(first_present(row, "imu_age_ms")),
        att_age_ms=parse_float(first_present(row, "att_age_ms")),
        auxvz_age_ms=parse_float(first_present(row, "auxvz_age_ms")),
        est_age_ms=parse_float(first_present(row, "est_age_ms")),
        baro_alt_m=baro_alt,
        est_h_m=est_h,
        est_v_mps=est_v,
        est_a_mps2=est_a,
        auxvz_a_vertical_mps2=auxvz_a,
        baro_v_proxy_mps=baro_v_proxy,
        alt_residual_m=alt_residual,
        velocity_residual_mps=velocity_residual,
        accel_residual_mps2=accel_residual,
        p00_m2=p00,
        p01_m2ps=p01,
        p10_m2ps=p10,
        p11_m2ps2=p11,
        sigma_h_m=sigma_h,
        sigma_v_mps=sigma_v,
        est_seeded=bool_cell(row, "est_seeded"),
        baro_valid=baro_valid,
        auxvz_valid=auxvz_valid,
        est_valid=est_valid,
        covariance_symmetry_abs=sym_abs,
        covariance_det=det,
        covariance_corr=corr,
        norm_alt_residual=norm_alt,
        norm_velocity_residual=norm_vel,
    )


def enrich_derived(samples: list[EkfSample], measurement_variance_m2: float) -> list[EkfSample]:
    previous_baro_alt = math.nan
    previous_t_s = math.nan
    previous_valid = False
    for sample in sorted(samples, key=lambda item: item.t_s):
        baro_valid = sample.baro_valid is not False and math.isfinite(sample.baro_alt_m)
        if not math.isfinite(sample.baro_v_proxy_mps) and previous_valid and baro_valid:
            dt_s = sample.t_s - previous_t_s
            if dt_s > 0.0:
                sample.baro_v_proxy_mps = (sample.baro_alt_m - previous_baro_alt) / dt_s
        if baro_valid:
            previous_baro_alt = sample.baro_alt_m
            previous_t_s = sample.t_s
            previous_valid = True
        else:
            previous_valid = False
        if not math.isfinite(sample.velocity_residual_mps):
            sample.velocity_residual_mps = finite_difference(sample.est_v_mps, sample.baro_v_proxy_mps)
        if not math.isfinite(sample.norm_alt_residual) and math.isfinite(sample.alt_residual_m) and math.isfinite(sample.p00_m2):
            denom = sample.p00_m2 + measurement_variance_m2
            if denom > 0.0:
                sample.norm_alt_residual = sample.alt_residual_m / math.sqrt(denom)
        if not math.isfinite(sample.norm_velocity_residual) and math.isfinite(sample.velocity_residual_mps):
            if math.isfinite(sample.sigma_v_mps) and sample.sigma_v_mps > 0.0:
                sample.norm_velocity_residual = sample.velocity_residual_mps / sample.sigma_v_mps
    return samples


def read_sd_csv(path: Path, measurement_variance_m2: float) -> list[EkfSample]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    reader = csv.DictReader(lines)
    samples = [sample for row in reader if (sample := sample_from_row(row, measurement_variance_m2=measurement_variance_m2)) is not None]
    return enrich_derived(samples, measurement_variance_m2)


def parse_plot_lines(lines: Iterable[str], measurement_variance_m2: float) -> list[EkfSample]:
    header: list[str] | None = None
    samples: list[EkfSample] = []
    for raw_line in lines:
        line = raw_line.strip()
        if not line:
            continue
        parts = [cell.strip() for cell in line.split(",")]
        if len(parts) < 2:
            continue
        if parts[0] == "PLOT_HDR" and parts[1] == "ESTIMATOR":
            header = parts[2:]
            continue
        if parts[0] != "PLOT" or parts[1] != "ESTIMATOR":
            continue
        active_header = header or PLOT_ESTIMATOR_HEADER
        if len(parts) - 2 < len(active_header):
            continue
        sample = sample_from_row(dict(zip(active_header, parts[2:])), measurement_variance_m2=measurement_variance_m2)
        if sample is not None:
            samples.append(sample)
    return enrich_derived(samples, measurement_variance_m2)


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


def read_samples(paths: list[Path], input_format: str, measurement_variance_m2: float) -> list[EkfSample]:
    all_samples: list[EkfSample] = []
    for path in paths:
        if input_format == "sd":
            all_samples.extend(read_sd_csv(path, measurement_variance_m2))
            continue
        if input_format == "plot":
            all_samples.extend(parse_plot_lines(path.read_text(encoding="utf-8", errors="replace").splitlines(), measurement_variance_m2))
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        first_line = next((line for line in text.splitlines() if line.strip()), "")
        if first_line.startswith("PLOT_HDR") or first_line.startswith("PLOT,"):
            all_samples.extend(parse_plot_lines(text.splitlines(), measurement_variance_m2))
        else:
            all_samples.extend(read_sd_csv(path, measurement_variance_m2))
    return enrich_derived(sorted(all_samples, key=lambda sample: sample.t_s), measurement_variance_m2)


def finite_values(samples: list[EkfSample], attr: str) -> list[float]:
    values: list[float] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            values.append(float(value))
    return values


def max_abs(values: list[float]) -> float:
    return max((abs(value) for value in values), default=math.nan)


def gate_states(
    sample: EkfSample,
    *,
    stale_age_ms: float,
    symmetry_tolerance: float,
    sigma_tolerance: float,
    max_norm_residual: float,
) -> dict[str, bool | None]:
    covariance_values = (sample.p00_m2, sample.p01_m2ps, sample.p10_m2ps, sample.p11_m2ps2)
    covariance_finite = all(math.isfinite(value) for value in covariance_values)
    covariance_symmetric = abs(sample.p01_m2ps - sample.p10_m2ps) <= symmetry_tolerance if covariance_finite else None
    covariance_psd = None
    if covariance_finite:
        covariance_psd = sample.p00_m2 >= -symmetry_tolerance and sample.p11_m2ps2 >= -symmetry_tolerance and sample.covariance_det >= -symmetry_tolerance
    sigma_h_matches = None
    if math.isfinite(sample.sigma_h_m) and math.isfinite(sample.p00_m2) and sample.p00_m2 >= 0.0:
        sigma_h_matches = abs(sample.sigma_h_m - math.sqrt(sample.p00_m2)) <= sigma_tolerance
    sigma_v_matches = None
    if math.isfinite(sample.sigma_v_mps) and math.isfinite(sample.p11_m2ps2) and sample.p11_m2ps2 >= 0.0:
        sigma_v_matches = abs(sample.sigma_v_mps - math.sqrt(sample.p11_m2ps2)) <= sigma_tolerance
    alt_ok = abs(sample.norm_alt_residual) <= max_norm_residual if math.isfinite(sample.norm_alt_residual) else None
    vel_ok = abs(sample.norm_velocity_residual) <= max_norm_residual if math.isfinite(sample.norm_velocity_residual) else None
    return {
        "covariance_finite": covariance_finite,
        "covariance_symmetric": covariance_symmetric,
        "covariance_psd": covariance_psd,
        "sigma_h_matches": sigma_h_matches,
        "sigma_v_matches": sigma_v_matches,
        "alt_residual_ok": alt_ok,
        "velocity_residual_ok": vel_ok,
        "baro_fresh": age_fresh(sample.baro_age_ms, stale_age_ms),
        "auxvz_fresh": age_fresh(sample.auxvz_age_ms, stale_age_ms),
        "est_fresh": age_fresh(sample.est_age_ms, stale_age_ms),
    }


def summarize_samples(
    samples: list[EkfSample],
    *,
    stale_age_ms: float,
    measurement_variance_m2: float,
    symmetry_tolerance: float,
    sigma_tolerance: float,
    max_norm_residual: float,
) -> dict:
    if not samples:
        return {
            "sample_count": 0,
            "passed_basic_input_check": False,
            "final_label": "no_samples",
            "final_rationale": "No estimator samples were available.",
        }

    gate_counts = {name: {"pass": 0, "fail": 0, "unknown": 0} for name in GATE_ORDER}
    warn_rows = 0
    stale_est_rows = 0
    seeded_rows = 0
    covariance_invalid_rows = 0
    residual_outlier_rows = 0
    finite_alt_residual_rows = 0
    finite_velocity_residual_rows = 0

    for sample in samples:
        if sample.warn_mask not in (None, 0):
            warn_rows += 1
        if age_fresh(sample.est_age_ms, stale_age_ms) is False:
            stale_est_rows += 1
        if sample.est_seeded is True:
            seeded_rows += 1
        states = gate_states(
            sample,
            stale_age_ms=stale_age_ms,
            symmetry_tolerance=symmetry_tolerance,
            sigma_tolerance=sigma_tolerance,
            max_norm_residual=max_norm_residual,
        )
        if states["covariance_finite"] is not True or states["covariance_symmetric"] is False or states["covariance_psd"] is False:
            covariance_invalid_rows += 1
        if math.isfinite(sample.norm_alt_residual):
            finite_alt_residual_rows += 1
        if math.isfinite(sample.norm_velocity_residual):
            finite_velocity_residual_rows += 1
        if states["alt_residual_ok"] is False or states["velocity_residual_ok"] is False:
            residual_outlier_rows += 1
        for name in GATE_ORDER:
            state = states[name]
            if state is True:
                gate_counts[name]["pass"] += 1
            elif state is False:
                gate_counts[name]["fail"] += 1
            else:
                gate_counts[name]["unknown"] += 1

    if seeded_rows == 0:
        final_label = "estimator_unseeded"
        rationale = "No rows report a seeded estimator."
    elif covariance_invalid_rows > 0:
        final_label = "covariance_inconsistent"
        rationale = "At least one covariance row is non-finite, asymmetric, or not positive semidefinite."
    elif gate_counts["sigma_h_matches"]["fail"] > 0 or gate_counts["sigma_v_matches"]["fail"] > 0:
        final_label = "sigma_contract_mismatch"
        rationale = "Published sigma values do not match sqrt(P00/P11)."
    elif residual_outlier_rows > 0:
        final_label = "innovation_residual_outlier"
        rationale = "One or more residual proxies exceed the configured normalized residual limit."
    elif stale_est_rows > 0 or warn_rows > 0:
        final_label = "freshness_or_warning_limited"
        rationale = "Covariance is algebraically consistent, but stale estimator rows or warnings are present."
    elif finite_alt_residual_rows == 0:
        final_label = "residual_evidence_unavailable"
        rationale = "Covariance is available, but no barometer residual proxy could be computed."
    else:
        final_label = "innovation_covariance_consistent"
        rationale = "Residual proxies, covariance symmetry/PSD, sigma contract, and freshness checks are consistent."

    return {
        "sample_count": len(samples),
        "passed_basic_input_check": True,
        "time_start_s": samples[0].t_s,
        "time_end_s": samples[-1].t_s,
        "seeded_rows": seeded_rows,
        "baro_valid_rows": sum(1 for sample in samples if sample.baro_valid is True),
        "auxvz_valid_rows": sum(1 for sample in samples if sample.auxvz_valid is True),
        "est_valid_rows": sum(1 for sample in samples if sample.est_valid is True),
        "finite_alt_residual_rows": finite_alt_residual_rows,
        "finite_velocity_residual_rows": finite_velocity_residual_rows,
        "covariance_invalid_rows": covariance_invalid_rows,
        "residual_outlier_rows": residual_outlier_rows,
        "warn_row_count": warn_rows,
        "stale_est_row_count": stale_est_rows,
        "max_abs_alt_residual_m": max_abs(finite_values(samples, "alt_residual_m")),
        "max_abs_norm_alt_residual": max_abs(finite_values(samples, "norm_alt_residual")),
        "max_abs_velocity_residual_mps": max_abs(finite_values(samples, "velocity_residual_mps")),
        "max_abs_norm_velocity_residual": max_abs(finite_values(samples, "norm_velocity_residual")),
        "max_abs_accel_residual_mps2": max_abs(finite_values(samples, "accel_residual_mps2")),
        "max_sigma_h_m": max(finite_values(samples, "sigma_h_m"), default=math.nan),
        "max_sigma_v_mps": max(finite_values(samples, "sigma_v_mps"), default=math.nan),
        "max_covariance_symmetry_abs": max(finite_values(samples, "covariance_symmetry_abs"), default=math.nan),
        "min_covariance_det": min(finite_values(samples, "covariance_det"), default=math.nan),
        "max_abs_covariance_corr": max_abs(finite_values(samples, "covariance_corr")),
        "gate_counts": gate_counts,
        "parameters": {
            "stale_age_ms": stale_age_ms,
            "measurement_variance_m2": measurement_variance_m2,
            "symmetry_tolerance": symmetry_tolerance,
            "sigma_tolerance": sigma_tolerance,
            "max_norm_residual": max_norm_residual,
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


def polyline(samples: list[EkfSample], attr: str, sx, sy) -> str:
    points: list[str] = []
    for sample in samples:
        value = getattr(sample, attr)
        if isinstance(value, (int, float)) and math.isfinite(float(value)):
            points.append(f"{sx(sample.t_s):.2f},{sy(float(value)):.2f}")
    return " ".join(points)


def warning_ticks(samples: list[EkfSample], sx, y0: float, y1: float) -> str:
    ticks: list[str] = []
    for sample in samples:
        if sample.warn_mask not in (None, 0):
            x = sx(sample.t_s)
            ticks.append(f'<line x1="{x:.2f}" y1="{y0:.2f}" x2="{x:.2f}" y2="{y1:.2f}" stroke="#dc2626" stroke-width="1" opacity="0.20"/>')
    return "\n".join(ticks)


def horizontal_line(y: float, x0: float, x1: float, label: str = "") -> str:
    text = f'<text x="{x1 - 38:.2f}" y="{y - 3:.2f}" class="tiny">{html.escape(label)}</text>' if label else ""
    return f'<line x1="{x0:.2f}" y1="{y:.2f}" x2="{x1:.2f}" y2="{y:.2f}" stroke="#94a3b8" stroke-width="1" stroke-dasharray="4 4"/>{text}'


def gate_raster(
    samples: list[EkfSample],
    sx,
    x: float,
    y: float,
    w: float,
    row_h: float,
    *,
    stale_age_ms: float,
    symmetry_tolerance: float,
    sigma_tolerance: float,
    max_norm_residual: float,
) -> str:
    pieces: list[str] = []
    for row_index, gate in enumerate(GATE_ORDER):
        y0 = y + row_index * row_h
        pieces.append(f'<text x="{x}" y="{y0 + row_h - 4:.2f}" class="tiny">{html.escape(GATE_LABELS[gate])}</text>')
        pieces.append(f'<line x1="{x + 104}" y1="{y0 + row_h - 2:.2f}" x2="{x + w}" y2="{y0 + row_h - 2:.2f}" stroke="#e2e8f0"/>')
    for left, right in zip(samples, samples[1:]):
        states = gate_states(
            left,
            stale_age_ms=stale_age_ms,
            symmetry_tolerance=symmetry_tolerance,
            sigma_tolerance=sigma_tolerance,
            max_norm_residual=max_norm_residual,
        )
        x0 = sx(left.t_s)
        width = max(1.0, sx(right.t_s) - x0)
        for row_index, gate in enumerate(GATE_ORDER):
            state = states[gate]
            color = "#22c55e" if state is True else "#ef4444" if state is False else "#cbd5e1"
            opacity = "0.72" if state is not None else "0.50"
            pieces.append(
                f'<rect x="{x0:.2f}" y="{y + row_index * row_h:.2f}" width="{width:.2f}" height="{row_h - 2:.2f}" fill="{color}" opacity="{opacity}"/>'
            )
    return "\n".join(pieces)


def covariance_scatter(samples: list[EkfSample], x: float, y: float, w: float, h: float) -> str:
    values_x = finite_values(samples, "p00_m2")
    values_y = finite_values(samples, "p11_m2ps2")
    if not values_x or not values_y:
        return ""
    x_min, x_max = bounds(values_x, 1.0, include_zero=True)
    y_min, y_max = bounds(values_y, 1.0, include_zero=True)
    sx = scale_fn(x_min, x_max, x + 34, x + w - 18)
    sy = scale_fn(y_min, y_max, y + h - 28, y + 40)
    circles: list[str] = []
    for sample in samples:
        if math.isfinite(sample.p00_m2) and math.isfinite(sample.p11_m2ps2):
            color = "#2563eb" if math.isfinite(sample.covariance_det) and sample.covariance_det >= -1.0e-9 else "#dc2626"
            circles.append(f'<circle cx="{sx(sample.p00_m2):.2f}" cy="{sy(sample.p11_m2ps2):.2f}" r="2.4" fill="{color}" opacity="0.62"/>')
    return "\n".join(circles + [
        f'<text x="{x + 38}" y="{y + h - 8}" class="tiny">P00</text>',
        f'<text x="{x + 6}" y="{y + h / 2:.2f}" class="tiny" transform="rotate(-90 {x + 6} {y + h / 2:.2f})">P11</text>',
    ])


def legend_item(x: int, y: int, color: str, label: str, dashed: bool = False) -> str:
    dash = ' stroke-dasharray="6 5"' if dashed else ""
    return (
        f'<line x1="{x}" y1="{y}" x2="{x + 28}" y2="{y}" stroke="{color}" stroke-width="3"{dash}/>'
        f'<text x="{x + 36}" y="{y + 4}" class="legend">{html.escape(label)}</text>'
    )


def status_color(label: str) -> str:
    if label == "innovation_covariance_consistent":
        return "#16a34a"
    if label in {"freshness_or_warning_limited", "residual_evidence_unavailable"}:
        return "#f59e0b"
    return "#dc2626"


def render_svg(samples: list[EkfSample], summary: dict, title: str = "EKF Innovation / Covariance Consistency Dashboard") -> str:
    if not samples:
        raise ValueError("Cannot render an empty sample set")

    width = 1220
    height = 860
    residual_panel = (84.0, 82.0, 1036.0, 210.0)
    covariance_panel = (84.0, 322.0, 650.0, 210.0)
    scatter_panel = (770.0, 322.0, 350.0, 210.0)
    gate_panel = (84.0, 570.0, 1036.0, 168.0)
    t_min = samples[0].t_s
    t_max = samples[-1].t_s if samples[-1].t_s > t_min else t_min + 1.0
    sx = scale_fn(t_min, t_max, residual_panel[0] + 42, residual_panel[0] + residual_panel[2] - 22)
    residual_values = finite_values(samples, "norm_alt_residual") + finite_values(samples, "norm_velocity_residual")
    res_min, res_max = bounds(residual_values, 4.0, include_zero=True)
    res_min = min(res_min, -2.5)
    res_max = max(res_max, 2.5)
    sy_res = scale_fn(res_min, res_max, residual_panel[1] + residual_panel[3] - 32, residual_panel[1] + 42)
    cov_values = finite_values(samples, "sigma_h_m") + finite_values(samples, "sigma_v_mps") + finite_values(samples, "covariance_symmetry_abs")
    cov_min, cov_max = bounds(cov_values, 1.0, include_zero=True)
    sy_cov = scale_fn(cov_min, cov_max, covariance_panel[1] + covariance_panel[3] - 32, covariance_panel[1] + 42)
    sx_cov = scale_fn(t_min, t_max, covariance_panel[0] + 42, covariance_panel[0] + covariance_panel[2] - 22)
    sx_gate = scale_fn(t_min, t_max, gate_panel[0] + 116, gate_panel[0] + gate_panel[2] - 18)
    parameters = summary["parameters"]
    y_plus1 = sy_res(1.0)
    y_minus1 = sy_res(-1.0)
    y_plus2 = sy_res(2.0)
    y_minus2 = sy_res(-2.0)
    verdict = summary["final_label"]
    verdict_color = status_color(verdict)
    gate_summary = " ".join(
        f"{GATE_LABELS[name]}={summary['gate_counts'][name]['pass']}/{summary['gate_counts'][name]['fail']}/{summary['gate_counts'][name]['unknown']}"
        for name in ("covariance_psd", "sigma_h_matches", "alt_residual_ok", "velocity_residual_ok", "est_fresh")
    )

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<style>
  .title {{ font: 700 24px Arial, sans-serif; fill: #0f172a; }}
  .subtitle {{ font: 13px Arial, sans-serif; fill: #475569; }}
  .panel-title {{ font: 700 14px Arial, sans-serif; fill: #0f172a; }}
  .axis-label {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .legend {{ font: 12px Arial, sans-serif; fill: #334155; }}
  .metric {{ font: 12px Consolas, monospace; fill: #0f172a; }}
  .tiny {{ font: 11px Arial, sans-serif; fill: #334155; }}
</style>
<rect x="0" y="0" width="{width}" height="{height}" fill="#f8fafc"/>
<text x="84" y="35" class="title">{html.escape(title)}</text>
<text x="84" y="56" class="subtitle">Post-update residual proxies, normalized residuals, covariance symmetry/PSD, sigma contract, freshness, and warning evidence.</text>
{panel(*residual_panel, "normalized residual proxy timeline")}
{panel(*covariance_panel, "covariance and sigma contract")}
{panel(*scatter_panel, "P00/P11 covariance scatter")}
{panel(*gate_panel, "consistency and freshness raster")}
{warning_ticks(samples, sx, residual_panel[1] + 34, residual_panel[1] + residual_panel[3] - 28)}
{horizontal_line(y_plus1, residual_panel[0] + 42, residual_panel[0] + residual_panel[2] - 22, "+1")}
{horizontal_line(y_minus1, residual_panel[0] + 42, residual_panel[0] + residual_panel[2] - 22, "-1")}
{horizontal_line(y_plus2, residual_panel[0] + 42, residual_panel[0] + residual_panel[2] - 22, "+2")}
{horizontal_line(y_minus2, residual_panel[0] + 42, residual_panel[0] + residual_panel[2] - 22, "-2")}
<polyline points="{polyline(samples, "norm_alt_residual", sx, sy_res)}" fill="none" stroke="#2563eb" stroke-width="2.3"/>
<polyline points="{polyline(samples, "norm_velocity_residual", sx, sy_res)}" fill="none" stroke="#ea580c" stroke-width="2"/>
<polyline points="{polyline(samples, "sigma_h_m", sx_cov, sy_cov)}" fill="none" stroke="#2563eb" stroke-width="2.2"/>
<polyline points="{polyline(samples, "sigma_v_mps", sx_cov, sy_cov)}" fill="none" stroke="#0f766e" stroke-width="2"/>
<polyline points="{polyline(samples, "covariance_symmetry_abs", sx_cov, sy_cov)}" fill="none" stroke="#9333ea" stroke-width="1.8"/>
{covariance_scatter(samples, *scatter_panel)}
{gate_raster(samples, sx_gate, gate_panel[0] + 12.0, gate_panel[1] + 40.0, gate_panel[2] - 30.0, 12.5, stale_age_ms=parameters['stale_age_ms'], symmetry_tolerance=parameters['symmetry_tolerance'], sigma_tolerance=parameters['sigma_tolerance'], max_norm_residual=parameters['max_norm_residual'])}
<rect x="84" y="766" width="1036" height="36" fill="#ffffff" stroke="{verdict_color}" stroke-width="3"/>
<text x="104" y="790" class="metric">final={html.escape(verdict)} | {html.escape(summary['final_rationale'])}</text>
<text x="96" y="824" class="metric">samples={summary['sample_count']} seeded={summary['seeded_rows']} max|n_alt|={summary['max_abs_norm_alt_residual']:.2f} max|n_vel|={summary['max_abs_norm_velocity_residual']:.2f} min_det={summary['min_covariance_det']:.4g} max_sym={summary['max_covariance_symmetry_abs']:.4g} warn={summary['warn_row_count']} stale_est={summary['stale_est_row_count']}</text>
<text x="96" y="844" class="metric">{html.escape(gate_summary)}</text>
<text x="32" y="190" class="axis-label" transform="rotate(-90 32 190)">normalized residual</text>
<text x="32" y="426" class="axis-label" transform="rotate(-90 32 426)">sigma / |P01-P10|</text>
<text x="560" y="306" class="axis-label">time [s]</text>
{legend_item(770, 32, "#2563eb", "alt normalized residual / sigma_h")}
{legend_item(770, 52, "#ea580c", "velocity normalized residual / sigma_v")}
{legend_item(1000, 32, "#0f766e", "sigma_v")}
{legend_item(1000, 52, "#9333ea", "|P01-P10|")}
</svg>
"""


def write_json(path: Path, samples: list[EkfSample], summary: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "ekf-innovation-covariance-dashboard-v1",
        "summary": summary,
        "samples": [asdict(sample) for sample in samples],
    }
    path.write_text(json.dumps(json_safe(payload), indent=2, sort_keys=True, allow_nan=False), encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render EKF/Kalman innovation residual and covariance consistency evidence from current-schema SD CSV or captured PLOT ESTIMATOR rows."
    )
    parser.add_argument("input", nargs="*", type=Path, help="Input SD CSV or captured PLOT ESTIMATOR text file.")
    parser.add_argument("--input-format", choices=("auto", "sd", "plot"), default="auto")
    parser.add_argument("--serial-port", help="Optional live serial port. Requires pyserial.")
    parser.add_argument("--serial-command", action="append", default=[], help="Command to send after opening serial. Repeatable.")
    parser.add_argument("--serial-settle-ms", type=int, default=250)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--duration-s", type=float, default=10.0)
    parser.add_argument("--max-rows", type=int, default=None)
    parser.add_argument("--measurement-variance-m2", type=float, default=DEFAULT_MEASUREMENT_VARIANCE_M2)
    parser.add_argument("--stale-age-ms", type=float, default=DEFAULT_STALE_AGE_MS)
    parser.add_argument("--symmetry-tolerance", type=float, default=1.0e-5)
    parser.add_argument("--sigma-tolerance", type=float, default=1.0e-4)
    parser.add_argument("--max-norm-residual", type=float, default=4.0)
    parser.add_argument("--svg-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--title", default="EKF Innovation / Covariance Consistency Dashboard")
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
        samples = parse_plot_lines(lines, args.measurement_variance_m2)
    else:
        if not args.input:
            raise SystemExit("Provide at least one input file or --serial-port.")
        samples = read_samples(args.input, args.input_format, args.measurement_variance_m2)

    if args.max_rows is not None:
        samples = samples[: args.max_rows]
    if not samples:
        raise SystemExit("No usable estimator samples found.")

    summary = summarize_samples(
        samples,
        stale_age_ms=args.stale_age_ms,
        measurement_variance_m2=args.measurement_variance_m2,
        symmetry_tolerance=args.symmetry_tolerance,
        sigma_tolerance=args.sigma_tolerance,
        max_norm_residual=args.max_norm_residual,
    )
    args.svg_out.parent.mkdir(parents=True, exist_ok=True)
    args.svg_out.write_text(render_svg(samples, summary, title=args.title), encoding="utf-8")
    if args.json_out is not None:
        write_json(args.json_out, samples, summary)

    print(f"samples={summary['sample_count']}")
    print(f"time_start_s={summary['time_start_s']:.3f}")
    print(f"time_end_s={summary['time_end_s']:.3f}")
    print(f"seeded_rows={summary['seeded_rows']}")
    print(f"max_abs_norm_alt_residual={summary['max_abs_norm_alt_residual']:.3f}")
    print(f"max_covariance_symmetry_abs={summary['max_covariance_symmetry_abs']:.6g}")
    print(f"min_covariance_det={summary['min_covariance_det']:.6g}")
    print(f"final_label={summary['final_label']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

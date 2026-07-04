from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
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
    analyze_logs,
    predict_apogee_m,
    read_sd_log,
)


def is_finite(value: float | None) -> bool:
    return value is not None and math.isfinite(value)


def mean(values: list[float]) -> float | None:
    if not values:
        return None
    return statistics.fmean(values)


def median(values: list[float]) -> float | None:
    if not values:
        return None
    return statistics.median(values)


def rmse(values: list[float]) -> float | None:
    if not values:
        return None
    return math.sqrt(sum(value * value for value in values) / float(len(values)))


def max_abs(values: list[float]) -> float | None:
    if not values:
        return None
    return max(abs(value) for value in values)


def classify_command(command01: float, closed_cmd_threshold: float, open_cmd_threshold: float) -> str:
    if not math.isfinite(command01):
        return "invalid"
    if command01 <= closed_cmd_threshold:
        return "body"
    if command01 >= open_cmd_threshold:
        return "brake"
    return "transition"


def summarize_residuals(records: list[dict], model_name: str, subset: str) -> dict:
    selected = [
        record["residual_m"]
        for record in records
        if record["model"] == model_name and record["subset"] == subset and is_finite(record["residual_m"])
    ]

    return {
        "model": model_name,
        "subset": subset,
        "count": len(selected),
        "bias_m": mean(selected),
        "median_error_m": median(selected),
        "rmse_m": rmse(selected),
        "max_abs_error_m": max_abs(selected),
    }


def residual_records_for_log(
    log_path: Path,
    *,
    mass_kg: float,
    rho_kgpm3: float,
    current_body_cda_m2: float,
    current_brake_cda_m2: float,
    fitted_body_cda_m2: float | None,
    fitted_brake_cda_m2: float | None,
    closed_cmd_threshold: float,
    open_cmd_threshold: float,
    min_alt_m: float,
    min_vz_mps: float,
) -> list[dict]:
    rows = read_sd_log(log_path)
    apogee_candidates = [
        row.est_h_m
        for row in rows
        if row.phase in (PHASE_BOOST, PHASE_COAST, PHASE_BRAKE, PHASE_DESCENT)
        and math.isfinite(row.est_h_m)
    ]

    if not apogee_candidates:
        raise ValueError(f"{log_path} does not contain usable in-flight altitude samples")

    observed_apogee_m = max(apogee_candidates)
    models = [
        ("current", current_body_cda_m2, current_brake_cda_m2),
    ]

    if fitted_body_cda_m2 is not None and fitted_brake_cda_m2 is not None:
        models.append(("fitted", fitted_body_cda_m2, fitted_brake_cda_m2))

    records: list[dict] = []
    for row in rows:
        if row.phase not in (PHASE_COAST, PHASE_BRAKE):
            continue
        if not math.isfinite(row.est_h_m) or not math.isfinite(row.est_v_mps):
            continue
        if row.est_h_m < min_alt_m or row.est_v_mps < min_vz_mps or row.est_h_m >= observed_apogee_m:
            continue

        subset = classify_command(row.policy_cmd, closed_cmd_threshold, open_cmd_threshold)
        if subset == "transition":
            continue

        for model_name, body_cda_m2, brake_cda_m2 in models:
            predicted_apogee_m = predict_apogee_m(
                row.est_h_m,
                row.est_v_mps,
                row.policy_cmd,
                body_cda_m2=body_cda_m2,
                brake_cda_m2=brake_cda_m2,
                mass_kg=mass_kg,
                rho_kgpm3=rho_kgpm3,
            )
            residual_m = predicted_apogee_m - observed_apogee_m if math.isfinite(predicted_apogee_m) else math.nan

            records.append(
                {
                    "log_path": str(log_path),
                    "model": model_name,
                    "subset": subset,
                    "t_us": row.t_us,
                    "phase": row.phase,
                    "est_h_m": row.est_h_m,
                    "est_v_mps": row.est_v_mps,
                    "policy_cmd": row.policy_cmd,
                    "observed_apogee_m": observed_apogee_m,
                    "predicted_apogee_m": predicted_apogee_m,
                    "residual_m": residual_m,
                }
            )

    return records


def build_report(
    log_paths: list[Path],
    *,
    mass_kg: float,
    rho_kgpm3: float,
    current_body_cda_m2: float,
    current_brake_cda_m2: float,
    closed_cmd_threshold: float,
    open_cmd_threshold: float,
    min_alt_m: float,
    min_vz_mps: float,
    max_residual_rows: int,
) -> dict:
    fit_result = analyze_logs(
        log_paths,
        mass_kg=mass_kg,
        rho_kgpm3=rho_kgpm3,
        current_body_cda_m2=current_body_cda_m2,
        current_brake_cda_m2=current_brake_cda_m2,
        closed_cmd_threshold=closed_cmd_threshold,
        open_cmd_threshold=open_cmd_threshold,
        min_alt_m=min_alt_m,
        min_vz_mps=min_vz_mps,
    )

    fitted_body_cda_m2 = fit_result["aggregate"]["recommended_body_cda_m2"]
    fitted_brake_cda_m2 = fit_result["aggregate"]["recommended_brake_cda_m2"]

    residuals: list[dict] = []
    for log_path in log_paths:
        residuals.extend(
            residual_records_for_log(
                log_path,
                mass_kg=mass_kg,
                rho_kgpm3=rho_kgpm3,
                current_body_cda_m2=current_body_cda_m2,
                current_brake_cda_m2=current_brake_cda_m2,
                fitted_body_cda_m2=fitted_body_cda_m2,
                fitted_brake_cda_m2=fitted_brake_cda_m2,
                closed_cmd_threshold=closed_cmd_threshold,
                open_cmd_threshold=open_cmd_threshold,
                min_alt_m=min_alt_m,
                min_vz_mps=min_vz_mps,
            )
        )

    summaries = [
        summarize_residuals(residuals, model_name, subset)
        for model_name in ("current", "fitted")
        for subset in ("body", "brake")
        if any(record["model"] == model_name for record in residuals)
    ]

    result = {
        "inputs": {
            "logs": [str(path) for path in log_paths],
            "mass_kg": mass_kg,
            "rho_kgpm3": rho_kgpm3,
            "current_body_cda_m2": current_body_cda_m2,
            "current_brake_cda_m2": current_brake_cda_m2,
            "closed_cmd_threshold": closed_cmd_threshold,
            "open_cmd_threshold": open_cmd_threshold,
            "min_alt_m": min_alt_m,
            "min_vz_mps": min_vz_mps,
        },
        "fit": fit_result,
        "residual_summaries": summaries,
        "residuals": residuals,
        "markdown": render_markdown(fit_result, summaries, residuals, max_residual_rows=max_residual_rows),
    }
    return result


def format_value(value: object, precision: int = 6) -> str:
    if isinstance(value, float):
        if math.isfinite(value):
            return f"{value:.{precision}f}"
        return "nan"
    if value is None:
        return "n/a"
    return str(value)


def render_markdown(
    fit_result: dict,
    residual_summaries: list[dict],
    residuals: list[dict],
    *,
    max_residual_rows: int,
) -> str:
    aggregate = fit_result["aggregate"]
    lines: list[str] = []

    lines.append("# Coefficient Identification Report")
    lines.append("")
    lines.append("## Scope")
    lines.append("")
    lines.append(
        "This report fits the current quadratic-drag policy coefficients from SD-style logs. "
        "Body drag is identified from near-closed command samples; brake drag is identified "
        "from nonzero brake-command samples after subtracting the fitted body contribution."
    )
    lines.append("")
    lines.append("## Aggregate Fit")
    lines.append("")
    lines.append("| Quantity | Value |")
    lines.append("| --- | ---: |")
    lines.append(f"| Logs | {aggregate['log_count']} |")
    lines.append(f"| Eligible samples | {aggregate['total_eligible_sample_count']} |")
    lines.append(f"| Recommended body CDA [m^2] | {format_value(aggregate['recommended_body_cda_m2'])} |")
    lines.append(f"| Recommended brake CDA [m^2] | {format_value(aggregate['recommended_brake_cda_m2'])} |")
    lines.append(
        f"| Median current prediction RMSE [m] | {format_value(aggregate['median_current_prediction_rmse_m'], 3)} |"
    )
    lines.append(
        f"| Median fitted prediction RMSE [m] | {format_value(aggregate['median_fitted_prediction_rmse_m'], 3)} |"
    )
    lines.append("")
    lines.append("## Per-Log Fit")
    lines.append("")
    lines.append("| Log | Apogee m | Body samples | Brake samples | Body CDA m^2 | Brake CDA m^2 | Current RMSE m | Fitted RMSE m |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for summary in fit_result["per_log"]:
        lines.append(
            "| "
            + " | ".join(
                [
                    summary["log_path"],
                    format_value(summary["actual_apogee_m"], 3),
                    str(summary["body_fit_sample_count"]),
                    str(summary["brake_fit_sample_count"]),
                    format_value(summary["recommended_body_cda_m2"]),
                    format_value(summary["recommended_brake_cda_m2"]),
                    format_value(summary["current_prediction_rmse_m"], 3),
                    format_value(summary["fitted_prediction_rmse_m"], 3),
                ]
            )
            + " |"
        )

    lines.append("")
    lines.append("## Residual Summary")
    lines.append("")
    lines.append("| Model | Subset | Count | Bias m | Median m | RMSE m | Max Abs m |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    for summary in residual_summaries:
        lines.append(
            "| "
            + " | ".join(
                [
                    summary["model"],
                    summary["subset"],
                    str(summary["count"]),
                    format_value(summary["bias_m"], 3),
                    format_value(summary["median_error_m"], 3),
                    format_value(summary["rmse_m"], 3),
                    format_value(summary["max_abs_error_m"], 3),
                ]
            )
            + " |"
        )

    lines.append("")
    lines.append("## Residual Samples")
    lines.append("")
    lines.append("| Model | Subset | t_us | h_m | v_mps | cmd | observed apogee m | predicted apogee m | residual m |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for record in residuals[:max_residual_rows]:
        lines.append(
            "| "
            + " | ".join(
                [
                    record["model"],
                    record["subset"],
                    str(record["t_us"]),
                    format_value(record["est_h_m"], 3),
                    format_value(record["est_v_mps"], 3),
                    format_value(record["policy_cmd"], 3),
                    format_value(record["observed_apogee_m"], 3),
                    format_value(record["predicted_apogee_m"], 3),
                    format_value(record["residual_m"], 3),
                ]
            )
            + " |"
        )

    lines.append("")
    lines.append("## Review Notes")
    lines.append("")
    lines.append("- Do not update firmware coefficients unless the logs are real current-branch flights with documented vehicle mass, density assumption, and anomalies.")
    lines.append("- Brake CDA estimates are lower confidence without measured airbrake position feedback; command is only a proxy for physical deployment.")
    lines.append("- Residuals are signed as predicted apogee minus observed apogee.")
    lines.append("")

    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a documented body/brake drag coefficient report.")
    parser.add_argument("logs", nargs="+", type=Path, help="One or more SD LOG###.CSV files")
    parser.add_argument("--mass-kg", type=float, default=DEFAULT_MASS_KG)
    parser.add_argument("--rho-kgpm3", type=float, default=DEFAULT_RHO_KGPM3)
    parser.add_argument("--current-body-cda-m2", type=float, default=DEFAULT_BODY_CDA_M2)
    parser.add_argument("--current-brake-cda-m2", type=float, default=DEFAULT_BRAKE_CDA_M2)
    parser.add_argument("--closed-cmd-threshold", type=float, default=0.05)
    parser.add_argument("--open-cmd-threshold", type=float, default=0.20)
    parser.add_argument("--min-alt-m", type=float, default=DEFAULT_MIN_ALT_M)
    parser.add_argument("--min-vz-mps", type=float, default=DEFAULT_MIN_VZ_MPS)
    parser.add_argument("--max-residual-rows", type=int, default=40)
    parser.add_argument("--report-out", type=Path, required=True)
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def missing_paths(paths: list[Path]) -> list[Path]:
    return [path for path in paths if not path.exists()]


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    missing = missing_paths(args.logs)
    if missing:
        joined = "\n  ".join(str(path) for path in missing)
        raise SystemExit(
            "Missing input log file(s):\n"
            f"  {joined}\n"
            "Copy current-schema SD logs into validation/data/<flight_id>/ or pass the actual LOG###.CSV paths."
        )

    result = build_report(
        args.logs,
        mass_kg=args.mass_kg,
        rho_kgpm3=args.rho_kgpm3,
        current_body_cda_m2=args.current_body_cda_m2,
        current_brake_cda_m2=args.current_brake_cda_m2,
        closed_cmd_threshold=args.closed_cmd_threshold,
        open_cmd_threshold=args.open_cmd_threshold,
        min_alt_m=args.min_alt_m,
        min_vz_mps=args.min_vz_mps,
        max_residual_rows=args.max_residual_rows,
    )

    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    args.report_out.write_text(result["markdown"], encoding="utf-8")

    if args.json_out is not None:
        json_result = dict(result)
        json_result.pop("markdown", None)
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(json_result, indent=2, sort_keys=True), encoding="utf-8")

    print(f"Wrote report: {args.report_out}")
    if args.json_out is not None:
        print(f"Wrote JSON: {args.json_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

from __future__ import annotations

import argparse
import json
import math
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
    analyze_logs,
)
from replay_policy_validation import validate_logs  # noqa: E402


def finite_or_none(value: object) -> float | None:
    if isinstance(value, (float, int)) and math.isfinite(float(value)):
        return float(value)
    return None


def validate_heldout(
    *,
    fit_logs: list[Path],
    heldout_logs: list[Path],
    mass_kg: float,
    rho_kgpm3: float,
    current_body_cda_m2: float,
    current_brake_cda_m2: float,
    closed_cmd_threshold: float,
    open_cmd_threshold: float,
    min_alt_m: float,
    min_vz_mps: float,
    max_rmse_m: float,
    max_abs_error_m: float,
    require_improvement: bool,
) -> dict:
    fit_result = analyze_logs(
        fit_logs,
        mass_kg=mass_kg,
        rho_kgpm3=rho_kgpm3,
        current_body_cda_m2=current_body_cda_m2,
        current_brake_cda_m2=current_brake_cda_m2,
        closed_cmd_threshold=closed_cmd_threshold,
        open_cmd_threshold=open_cmd_threshold,
        min_alt_m=min_alt_m,
        min_vz_mps=min_vz_mps,
    )

    fitted_body_cda_m2 = finite_or_none(fit_result["aggregate"]["recommended_body_cda_m2"])
    fitted_brake_cda_m2 = finite_or_none(fit_result["aggregate"]["recommended_brake_cda_m2"])

    current_replay = validate_logs(
        heldout_logs,
        mass_kg=mass_kg,
        rho_kgpm3=rho_kgpm3,
        body_cda_m2=current_body_cda_m2,
        brake_cda_m2=current_brake_cda_m2,
        min_alt_m=min_alt_m,
        min_vz_mps=min_vz_mps,
        max_rmse_m=max_rmse_m,
        max_abs_error_m=max_abs_error_m,
    )

    fitted_replay = None
    if fitted_body_cda_m2 is not None and fitted_brake_cda_m2 is not None:
        fitted_replay = validate_logs(
            heldout_logs,
            mass_kg=mass_kg,
            rho_kgpm3=rho_kgpm3,
            body_cda_m2=fitted_body_cda_m2,
            brake_cda_m2=fitted_brake_cda_m2,
            min_alt_m=min_alt_m,
            min_vz_mps=min_vz_mps,
            max_rmse_m=max_rmse_m,
            max_abs_error_m=max_abs_error_m,
        )

    current_rmse_m = finite_or_none(current_replay["aggregate"]["median_prediction_rmse_m"])
    fitted_rmse_m = (
        finite_or_none(fitted_replay["aggregate"]["median_prediction_rmse_m"])
        if fitted_replay is not None
        else None
    )

    rmse_delta_m = (
        current_rmse_m - fitted_rmse_m
        if current_rmse_m is not None and fitted_rmse_m is not None
        else None
    )

    fitted_passed = bool(fitted_replay and fitted_replay["aggregate"]["passed"])
    improvement_passed = (
        True
        if not require_improvement
        else rmse_delta_m is not None and rmse_delta_m >= 0.0
    )

    return {
        "inputs": {
            "fit_logs": [str(path) for path in fit_logs],
            "heldout_logs": [str(path) for path in heldout_logs],
            "mass_kg": mass_kg,
            "rho_kgpm3": rho_kgpm3,
            "current_body_cda_m2": current_body_cda_m2,
            "current_brake_cda_m2": current_brake_cda_m2,
            "closed_cmd_threshold": closed_cmd_threshold,
            "open_cmd_threshold": open_cmd_threshold,
            "min_alt_m": min_alt_m,
            "min_vz_mps": min_vz_mps,
            "max_rmse_m": max_rmse_m,
            "max_abs_error_m": max_abs_error_m,
            "require_improvement": require_improvement,
        },
        "fit": fit_result,
        "current_replay": current_replay,
        "fitted_replay": fitted_replay,
        "comparison": {
            "fitted_body_cda_m2": fitted_body_cda_m2,
            "fitted_brake_cda_m2": fitted_brake_cda_m2,
            "current_heldout_rmse_m": current_rmse_m,
            "fitted_heldout_rmse_m": fitted_rmse_m,
            "rmse_improvement_m": rmse_delta_m,
            "passed": fitted_passed and improvement_passed,
        },
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fit aerodynamic constants on training logs and replay separate held-out logs."
    )
    parser.add_argument("--fit-log", action="append", type=Path, required=True)
    parser.add_argument("--heldout-log", action="append", type=Path, required=True)
    parser.add_argument("--mass-kg", type=float, default=DEFAULT_MASS_KG)
    parser.add_argument("--rho-kgpm3", type=float, default=DEFAULT_RHO_KGPM3)
    parser.add_argument("--current-body-cda-m2", type=float, default=DEFAULT_BODY_CDA_M2)
    parser.add_argument("--current-brake-cda-m2", type=float, default=DEFAULT_BRAKE_CDA_M2)
    parser.add_argument("--closed-cmd-threshold", type=float, default=0.05)
    parser.add_argument("--open-cmd-threshold", type=float, default=0.20)
    parser.add_argument("--min-alt-m", type=float, default=DEFAULT_MIN_ALT_M)
    parser.add_argument("--min-vz-mps", type=float, default=DEFAULT_MIN_VZ_MPS)
    parser.add_argument("--max-rmse-m", type=float, default=50.0)
    parser.add_argument("--max-abs-error-m", type=float, default=100.0)
    parser.add_argument("--require-improvement", action="store_true")
    parser.add_argument("--json-out", type=Path)
    return parser.parse_args(argv)


def missing_paths(paths: list[Path]) -> list[Path]:
    return [path for path in paths if not path.exists()]


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    missing_fit = missing_paths(args.fit_log)
    missing_heldout = missing_paths(args.heldout_log)
    if missing_fit or missing_heldout:
        lines: list[str] = []
        if missing_fit:
            lines.append("Missing fit log file(s):")
            lines.extend(f"  {path}" for path in missing_fit)
        if missing_heldout:
            lines.append("Missing held-out log file(s):")
            lines.extend(f"  {path}" for path in missing_heldout)
        lines.append("Copy current-schema SD logs into validation/data/<flight_id>/ or pass the actual LOG###.CSV paths.")
        raise SystemExit("\n".join(lines))

    result = validate_heldout(
        fit_logs=args.fit_log,
        heldout_logs=args.heldout_log,
        mass_kg=args.mass_kg,
        rho_kgpm3=args.rho_kgpm3,
        current_body_cda_m2=args.current_body_cda_m2,
        current_brake_cda_m2=args.current_brake_cda_m2,
        closed_cmd_threshold=args.closed_cmd_threshold,
        open_cmd_threshold=args.open_cmd_threshold,
        min_alt_m=args.min_alt_m,
        min_vz_mps=args.min_vz_mps,
        max_rmse_m=args.max_rmse_m,
        max_abs_error_m=args.max_abs_error_m,
        require_improvement=args.require_improvement,
    )

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(result, indent=2, sort_keys=True), encoding="utf-8")

    comparison = result["comparison"]
    print(f"fit_logs={len(args.fit_log)}")
    print(f"heldout_logs={len(args.heldout_log)}")
    print(f"fitted_body_cda_m2={comparison['fitted_body_cda_m2']}")
    print(f"fitted_brake_cda_m2={comparison['fitted_brake_cda_m2']}")
    print(f"current_heldout_rmse_m={comparison['current_heldout_rmse_m']}")
    print(f"fitted_heldout_rmse_m={comparison['fitted_heldout_rmse_m']}")
    print(f"rmse_improvement_m={comparison['rmse_improvement_m']}")
    print(f"passed={comparison['passed']}")

    return 0 if comparison["passed"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

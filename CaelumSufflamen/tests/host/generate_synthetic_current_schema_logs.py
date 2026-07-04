from __future__ import annotations

import csv
import json
import math
import re
import sys
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
ROOT = THIS_DIR.parents[1]
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from policy_aero_empirical_fit import (  # noqa: E402
    DEFAULT_BODY_CDA_M2,
    DEFAULT_BRAKE_CDA_M2,
    DEFAULT_MASS_KG,
    DEFAULT_RHO_KGPM3,
    K_G,
    PHASE_BRAKE,
    PHASE_COAST,
    PHASE_DESCENT,
    predict_apogee_m,
)


SCHEMA_VERSION = "CS_AERO_ID_LOG_V1"


def extract_sd_header_fields() -> list[str]:
    sd_logger_cpp = (ROOT / "utils" / "sd_logger.cpp").read_text(encoding="utf-8")
    match = re.search(
        r"static void sd_write_header\(File &f\).*?f\.println\((.*?)\);",
        sd_logger_cpp,
        re.DOTALL,
    )
    if match is None:
        raise RuntimeError("Could not extract SD logger header from utils/sd_logger.cpp")

    header = "".join(re.findall(r'"([^"]*)"', match.group(1)))
    fields = [field for field in header.split(",") if field]
    if not fields:
        raise RuntimeError("Extracted SD logger header was empty")
    return fields


def required_velocity_for_apogee_delta(delta_h_m: float, command01: float) -> float:
    cda_m2 = DEFAULT_BODY_CDA_M2 + command01 * DEFAULT_BRAKE_CDA_M2
    k_inv_m = (DEFAULT_RHO_KGPM3 * cda_m2) / (2.0 * DEFAULT_MASS_KG)
    if k_inv_m < 1.0e-9:
        return math.sqrt(2.0 * K_G * delta_h_m)
    return math.sqrt((K_G / k_inv_m) * (math.exp(2.0 * k_inv_m * delta_h_m) - 1.0))


def base_row(fields: list[str], row_seq: int, t_us: int) -> dict[str, object]:
    row: dict[str, object] = {field: "nan" for field in fields}

    row.update(
        {
            "row_seq": row_seq,
            "t_us": t_us,
            "baro_valid": 1,
            "baro_updated": 1,
            "baro_seq": row_seq + 1,
            "bmp_T": 20.0,
            "bmp_P": 1013.25,
            "imu_valid": 1,
            "imu_updated": 1,
            "imu_seq": row_seq + 1,
            "ax": 0.0,
            "ay": 0.0,
            "az": 9.80665,
            "gx": 0.0,
            "gy": 0.0,
            "gz": 0.0,
            "aux_valid": 1,
            "aux_updated": 1,
            "aux_seq": row_seq + 1,
            "lis_ax": 0.0,
            "lis_ay": 0.0,
            "lis_az": 9.80665,
            "pmod_accel_valid": 0,
            "pmod_accel_updated": 0,
            "pmod_accel_seq": 0,
            "pmod_accel_kind": 0,
            "pmod_raw_x": 0,
            "pmod_raw_y": 0,
            "pmod_raw_z": 0,
            "pmod_ax": "nan",
            "pmod_ay": "nan",
            "pmod_az": "nan",
            "pmod_a_norm": "nan",
            "mag_valid": 0,
            "mag_updated": 0,
            "mag_seq": 0,
            "mag_raw_x": "nan",
            "mag_raw_y": "nan",
            "mag_raw_z": "nan",
            "mag_x_uT": "nan",
            "mag_y_uT": "nan",
            "mag_z_uT": "nan",
            "mag_norm_uT": "nan",
            "mag_heading_deg": "nan",
            "mag_interference": 0,
            "att_valid": 1,
            "att_updated": 1,
            "att_seq": row_seq + 1,
            "q0": 1.0,
            "q1": 0.0,
            "q2": 0.0,
            "q3": 0.0,
            "auxvz_valid": 1,
            "auxvz_updated": 1,
            "auxvz_seq": row_seq + 1,
            "a_vertical": -9.80665,
            "est_valid": 1,
            "est_updated": 1,
            "est_seeded": 1,
            "est_seq": row_seq + 1,
            "est_a": -9.80665,
            "P00": 1.0,
            "P01": 0.0,
            "P10": 0.0,
            "P11": 1.0,
            "arm_state": 2,
            "policy_runtime_enabled": 1,
            "software_arm_token": 1,
            "phase_diag_valid": 1,
            "phase_diag_updated": 1,
            "phase_diag_seq": row_seq + 1,
            "phase_diag_t_ms": t_us // 1000,
            "phase_diag_age_ms": 0,
            "phase_launch_latched": 1,
            "phase_burnout_latched": 1,
            "phase_descent_latched": 0,
            "phase_launch_candidate": 0,
            "phase_burnout_candidate": 0,
            "phase_descent_candidate": 0,
            "phase_boost_dwell_met": 1,
            "phase_coast_dwell_met": 1,
            "phase_brake_active": 0,
            "phase_launch_confirm_ms": 60,
            "phase_burnout_confirm_ms": 120,
            "phase_descent_confirm_ms": 0,
            "phase_since_launch_ms": t_us // 1000,
            "phase_since_burnout_ms": max(0, t_us // 1000 - 250),
            "target_nominal": 3048.0,
            "target_effective": 3047.0,
            "uncertainty_margin": 1.0,
            "warn_mask": 0,
        }
    )
    return row


def make_log_rows(fields: list[str], actual_apogee_m: float, samples: list[tuple[float, float, int]]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    t_us = 0

    for row_seq, (h_m, command01, phase) in enumerate(samples):
        delta_h_m = actual_apogee_m - h_m
        v_mps = required_velocity_for_apogee_delta(delta_h_m, command01)
        row = base_row(fields, row_seq, t_us)
        row.update(
            {
                "bmp_alt": h_m,
                "est_h": h_m,
                "est_v": v_mps,
                "phase": phase,
                "actuator_us": int(round(1000.0 + command01 * 1000.0)),
                "phase_brake_active": 1 if phase == PHASE_BRAKE else 0,
                "policy_valid": 1 if command01 > 0.0 else 0,
                "policy_cmd": command01,
                "apogee_no_brake": predict_apogee_m(
                    h_m,
                    v_mps,
                    0.0,
                    body_cda_m2=DEFAULT_BODY_CDA_M2,
                    brake_cda_m2=DEFAULT_BRAKE_CDA_M2,
                    mass_kg=DEFAULT_MASS_KG,
                    rho_kgpm3=DEFAULT_RHO_KGPM3,
                ),
                "apogee_full_brake": predict_apogee_m(
                    h_m,
                    v_mps,
                    1.0,
                    body_cda_m2=DEFAULT_BODY_CDA_M2,
                    brake_cda_m2=DEFAULT_BRAKE_CDA_M2,
                    mass_kg=DEFAULT_MASS_KG,
                    rho_kgpm3=DEFAULT_RHO_KGPM3,
                ),
                "target_apogee": 3047.0,
                "apogee_error": actual_apogee_m - 3047.0,
            }
        )
        rows.append(row)
        t_us += 20000

    descent = base_row(fields, len(rows), t_us)
    descent.update(
        {
            "bmp_alt": actual_apogee_m,
            "est_h": actual_apogee_m,
            "est_v": -5.0,
            "phase": PHASE_DESCENT,
            "phase_descent_latched": 1,
            "phase_descent_confirm_ms": 300,
            "policy_valid": 0,
            "policy_cmd": 0.0,
            "actuator_us": 1000,
            "apogee_no_brake": actual_apogee_m,
            "apogee_full_brake": actual_apogee_m,
            "target_apogee": 3047.0,
            "apogee_error": actual_apogee_m - 3047.0,
        }
    )
    rows.append(descent)
    return rows


def write_flight_fixture(
    *,
    flight_id: str,
    actual_apogee_m: float,
    samples: list[tuple[float, float, int]],
    fields: list[str],
) -> None:
    flight_dir = ROOT / "validation" / "data" / flight_id
    flight_dir.mkdir(parents=True, exist_ok=True)

    log_path = flight_dir / "LOG000.CSV"
    rows = make_log_rows(fields, actual_apogee_m, samples)
    with log_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)

    metadata = {
        "schema_version": SCHEMA_VERSION,
        "flight_id": flight_id,
        "synthetic": True,
        "synthetic_purpose": "Theoretical current-schema fixture for tool checkout only; not real flight evidence.",
        "vehicle": {
            "mass_kg": DEFAULT_MASS_KG,
            "airbrake_geometry_revision": "synthetic",
        },
        "environment": {
            "rho_assumed_kgpm3": DEFAULT_RHO_KGPM3,
        },
        "firmware": {
            "policy_cda_body_m2_config": DEFAULT_BODY_CDA_M2,
            "policy_cda_brake_m2_config": DEFAULT_BRAKE_CDA_M2,
        },
        "data_quality": {
            "usable_for_body_cda_fit": False,
            "usable_for_brake_cda_fit": False,
            "review_status": "synthetic_fixture_only",
            "notes": [
                "Generated analytically so fitted constants should reproduce configured constants.",
                "Do not use this artifact to justify firmware aerodynamic coefficient updates.",
            ],
        },
    }
    (flight_dir / "flight_metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    with (flight_dir / "events.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["event_name", "t_us", "source", "confidence", "est_h_m", "est_v_mps", "notes"])
        writer.writeheader()
        writer.writerow(
            {
                "event_name": "apogee",
                "t_us": rows[-1]["t_us"],
                "source": "synthetic",
                "confidence": "high",
                "est_h_m": actual_apogee_m,
                "est_v_mps": -5.0,
                "notes": "Analytic fixture apogee, not observed flight data.",
            }
        )

    (flight_dir / "README.md").write_text(
        "\n".join(
            [
                f"# {flight_id}",
                "",
                "This directory contains a synthetic/theoretical current-schema SD log fixture.",
                "It exists only so coefficient-report and held-out replay tooling can be exercised end-to-end.",
                "",
                "Do not treat this as flight evidence, and do not use it to justify changes to `utils/config.h`.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main() -> int:
    fields = extract_sd_header_fields()
    fixtures = [
        (
            "flight_2026_001",
            300.0,
            [
                (50.0, 0.00, PHASE_COAST),
                (90.0, 0.00, PHASE_COAST),
                (130.0, 0.25, PHASE_BRAKE),
                (170.0, 0.50, PHASE_BRAKE),
                (210.0, 0.75, PHASE_BRAKE),
                (250.0, 1.00, PHASE_BRAKE),
            ],
        ),
        (
            "flight_2026_002",
            340.0,
            [
                (70.0, 0.00, PHASE_COAST),
                (115.0, 0.00, PHASE_COAST),
                (160.0, 0.30, PHASE_BRAKE),
                (205.0, 0.55, PHASE_BRAKE),
                (250.0, 0.80, PHASE_BRAKE),
                (295.0, 1.00, PHASE_BRAKE),
            ],
        ),
        (
            "flight_2026_003",
            320.0,
            [
                (60.0, 0.00, PHASE_COAST),
                (100.0, 0.00, PHASE_COAST),
                (145.0, 0.20, PHASE_BRAKE),
                (190.0, 0.45, PHASE_BRAKE),
                (235.0, 0.70, PHASE_BRAKE),
                (280.0, 0.95, PHASE_BRAKE),
            ],
        ),
    ]

    for flight_id, actual_apogee_m, samples in fixtures:
        write_flight_fixture(
            flight_id=flight_id,
            actual_apogee_m=actual_apogee_m,
            samples=samples,
            fields=fields,
        )
        print(f"Wrote validation/data/{flight_id}/LOG000.CSV")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

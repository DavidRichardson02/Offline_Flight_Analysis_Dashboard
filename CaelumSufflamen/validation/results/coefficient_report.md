# Coefficient Identification Report

## Scope

This report fits the current quadratic-drag policy coefficients from SD-style logs. Body drag is identified from near-closed command samples; brake drag is identified from nonzero brake-command samples after subtracting the fitted body contribution.

## Aggregate Fit

| Quantity | Value |
| --- | ---: |
| Logs | 2 |
| Eligible samples | 12 |
| Recommended body CDA [m^2] | 0.004000 |
| Recommended brake CDA [m^2] | 0.020000 |
| Median current prediction RMSE [m] | 0.000 |
| Median fitted prediction RMSE [m] | 0.000 |

## Per-Log Fit

| Log | Apogee m | Body samples | Brake samples | Body CDA m^2 | Brake CDA m^2 | Current RMSE m | Fitted RMSE m |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| validation\data\flight_2026_001\LOG000.CSV | 300.000 | 2 | 4 | 0.004000 | 0.020000 | 0.000 | 0.000 |
| validation\data\flight_2026_002\LOG000.CSV | 340.000 | 2 | 4 | 0.004000 | 0.020000 | 0.000 | 0.000 |

## Residual Summary

| Model | Subset | Count | Bias m | Median m | RMSE m | Max Abs m |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| current | body | 4 | -0.000 | 0.000 | 0.000 | 0.000 |
| current | brake | 8 | -0.000 | 0.000 | 0.000 | 0.000 |
| fitted | body | 4 | 0.000 | 0.000 | 0.000 | 0.000 |
| fitted | brake | 8 | 0.000 | 0.000 | 0.000 | 0.000 |

## Residual Samples

| Model | Subset | t_us | h_m | v_mps | cmd | observed apogee m | predicted apogee m | residual m |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| current | body | 0 | 50.000 | 79.545 | 0.000 | 300.000 | 300.000 | 0.000 |
| fitted | body | 0 | 50.000 | 79.545 | 0.000 | 300.000 | 300.000 | -0.000 |
| current | body | 20000 | 90.000 | 71.385 | 0.000 | 300.000 | 300.000 | 0.000 |
| fitted | body | 20000 | 90.000 | 71.385 | 0.000 | 300.000 | 300.000 | 0.000 |
| current | brake | 40000 | 130.000 | 70.463 | 0.250 | 300.000 | 300.000 | -0.000 |
| fitted | brake | 40000 | 130.000 | 70.463 | 0.250 | 300.000 | 300.000 | 0.000 |
| current | brake | 60000 | 170.000 | 64.154 | 0.500 | 300.000 | 300.000 | 0.000 |
| fitted | brake | 60000 | 170.000 | 64.154 | 0.500 | 300.000 | 300.000 | 0.000 |
| current | brake | 80000 | 210.000 | 52.564 | 0.750 | 300.000 | 300.000 | 0.000 |
| fitted | brake | 80000 | 210.000 | 52.564 | 0.750 | 300.000 | 300.000 | 0.000 |
| current | brake | 100000 | 250.000 | 36.536 | 1.000 | 300.000 | 300.000 | 0.000 |
| fitted | brake | 100000 | 250.000 | 36.536 | 1.000 | 300.000 | 300.000 | 0.000 |
| current | body | 0 | 70.000 | 83.549 | 0.000 | 340.000 | 340.000 | -0.000 |
| fitted | body | 0 | 70.000 | 83.549 | 0.000 | 340.000 | 340.000 | 0.000 |
| current | body | 20000 | 115.000 | 74.474 | 0.000 | 340.000 | 340.000 | 0.000 |
| fitted | body | 20000 | 115.000 | 74.474 | 0.000 | 340.000 | 340.000 | 0.000 |
| current | brake | 40000 | 160.000 | 75.278 | 0.300 | 340.000 | 340.000 | 0.000 |
| fitted | brake | 40000 | 160.000 | 75.278 | 0.300 | 340.000 | 340.000 | 0.000 |
| current | brake | 60000 | 205.000 | 67.299 | 0.550 | 340.000 | 340.000 | 0.000 |
| fitted | brake | 60000 | 205.000 | 67.299 | 0.550 | 340.000 | 340.000 | 0.000 |
| current | brake | 80000 | 250.000 | 53.229 | 0.800 | 340.000 | 340.000 | 0.000 |
| fitted | brake | 80000 | 250.000 | 53.229 | 0.800 | 340.000 | 340.000 | 0.000 |
| current | brake | 100000 | 295.000 | 34.109 | 1.000 | 340.000 | 340.000 | 0.000 |
| fitted | brake | 100000 | 295.000 | 34.109 | 1.000 | 340.000 | 340.000 | 0.000 |

## Review Notes

- Do not update firmware coefficients unless the logs are real current-branch flights with documented vehicle mass, density assumption, and anomalies.
- Brake CDA estimates are lower confidence without measured airbrake position feedback; command is only a proxy for physical deployment.
- Residuals are signed as predicted apogee minus observed apogee.

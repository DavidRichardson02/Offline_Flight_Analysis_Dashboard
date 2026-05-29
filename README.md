Caelum MATLAB Flight Analysis Dashboard

Offline analysis, estimator replay, and validation tools for Caelum SD logger flight data.
This repository packages a practical MATLAB workflow for:
importing and cleaning Caelum flight logs
replaying the vertical flight estimator offline
visualizing estimator behavior with engineering dashboards
generating truth-aware synthetic logs for controlled validation
running Monte Carlo campaigns for robustness checks
exporting figures and summary tables for reports
carrying the same estimator boundaries into embedded-oriented templates
What This Project Implements
The current package is centered on a vertical flight-estimation workflow rather than a full production 3D navigation stack.
Implemented in the main workflow:
vertical EKF replay from logged acceleration and barometric altitude
launch, burnout, apogee, and landing detection
replay diagnostics such as innovation error, NIS gating, covariance growth, and state convergence
attitude replay diagnostics for gravity correction, tilt, and gyro-bias behavior
truth-aware synthetic log generation with known altitude, velocity, drag, and bias signals
Monte Carlo validation over repeatable synthetic scenarios
export of dashboard figures, overview plots, and CSV summaries
Present as research or scaffolding:
3D navigation EKF replay entry points
embedded estimator templates that mirror MATLAB state definitions and function boundaries
Repository Layout
```text
caelum_matlab_complete_package/
|-- +caelum/                  MATLAB package with analysis, replay, and plotting code
|-- embedded_templates/       Embedded-oriented headers and C++ source templates
|-- exports/                  Example exported figures and CSV summaries
|-- mc_logs/                  Monte Carlo output logs
|-- run_caelum_example.m      Basic offline-analysis example
|-- run_truth_example.m       Truth-aware synthetic example
|-- run_monte_carlo_example.m Monte Carlo validation example
|-- LOG000.CSV                Example flight log
|-- Drop1.csv                 Example flight log
|-- LOG_TRUTH_AWARE.CSV       Example synthetic truth-aware log
```
Core MATLAB Components
Analysis pipeline
`+caelum/importLog.m` - strict CSV import
`+caelum/importLogRobust.m` - salvage import for damaged logs
`+caelum/alignImportedSchema.m` - schema alignment for downstream processing
`+caelum/cleanLog.m` - timestamp cleanup and derived signal preparation
`+caelum/detectEvents.m` - launch, burnout, apogee, and landing detection
`+caelum/analyzeLog.m` - end-to-end orchestration
Estimation and replay
`+caelum/runVerticalEKF.m` - vertical EKF replay core
`+caelum/replayEstimator.m` - offline replay wrapper
`+caelum/runAttitudeReplay.m` - attitude replay with gravity-based correction diagnostics
`+caelum/runNavigationEKF3D.m` - research-branch 3D navigation scaffold
Plotting and reporting
`+caelum/plotDashboard.m` - multi-panel engineering dashboard
`+caelum/plotOverview.m` - standard overview figures
`+caelum/plotMonteCarloSummary.m` - Monte Carlo summary plots
`+caelum/exportFigures.m` - PNG/PDF export plus CSV summaries
`+caelum/exportSummary.m` - summary export helpers
Validation and synthetic data
`+caelum/generateTruthAwareCaelumLog.m` - synthetic log generator with truth channels
`+caelum/runMonteCarloValidation.m` - repeatable robustness campaign runner
Requirements
Use a recent MATLAB release with support for:
`arguments` blocks
tables
`tiledlayout`
No extra toolbox dependency is documented in this repository.
Quick Start
Add the repository root to the MATLAB path and run the full offline analysis on a recorded log:
```matlab
addpath("path/to/caelum_matlab_complete_package");

results = caelum.analyzeLog("LOG000.CSV", ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true);
```
The returned `results` struct contains:
cleaned log data
detected events
replay outputs
dashboard and overview figure handles
summary metrics
import and cleaning reports
truth and consistency metrics when available
Example Entry Points
1. Analyze a recorded flight log
```matlab
results = run_caelum_example("Drop1.csv");
```
2. Generate and analyze a truth-aware synthetic log
```matlab
[~, truth] = caelum.generateTruthAwareCaelumLog("LOG_TRUTH_AWARE.CSV");

results = caelum.analyzeLog("LOG_TRUTH_AWARE.CSV", ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true, ...
    Truth=truth);
```
When truth is provided, the package reports:
logged-vs-truth RMSE and MAE
replay-vs-truth RMSE and MAE
apogee altitude and time errors
covariance consistency metrics when valid
3. Run a Monte Carlo validation campaign
```matlab
mc = caelum.runMonteCarloValidation("mc_logs", ...
    NumRuns=50, ...
    MakePlots=false, ...
    MakeDashboard=false, ...
    SaveLogs=true, ...
    StorePerRunResults=false);

figs = caelum.plotMonteCarloSummary(mc); %#ok<NASGU>
disp(mc.aggregate);
```
Monte Carlo outputs include:
per-run RMSE, MAE, and apogee error
sampled scenario and fault settings
runtime and success/failure statistics
aggregate distribution summaries
Input Log Schema
Expected CSV columns:
```text
t_us,bmp_T,bmp_P,bmp_alt,bmp_alt_rel,ax,ay,az,gx,gy,gz,lis_ax,lis_ay,lis_az,g_bx,g_by,g_bz,a_vertical,kf_h,kf_v,P00,P01,P10,P11
```
Notes:
lines beginning with `#` are ignored by the importers
the robust importer can recover partially damaged files
the cleaner removes malformed timestamps and prepares derived channels for replay and plotting
Dashboard and Export Outputs
With `ExportFigures=true`, the package writes report-ready assets such as:
`<logname>_dashboard.png`
`<logname>_dashboard.pdf`
`<logname>_altitude_overview.png`
`<logname>_velocity_overview.png`
`<logname>_acceleration_overview.png`
`<logname>_uncertainty_overview.png`
`<logname>_sensor_health_overview.png`
`<logname>_summary.csv`
`<logname>_import_report.csv`
`<logname>_truth_metrics.csv` when truth is available
`<logname>_consistency_metrics.csv` when consistency checks are available
Example:
```matlab
results = caelum.analyzeLog("LOG000.CSV", ...
    MakePlots=true, ...
    ReplayEstimator=true, ...
    MakeDashboard=true, ...
    ExportFigures=true, ...
    ExportDir="report_assets");
```
The exported file paths are returned in `results.exportInfo`.
Embedded Templates
The `embedded_templates/` folder contains firmware-oriented scaffolding that mirrors the MATLAB package structure:
fixed-size state definitions
estimator configuration headers
step-function interfaces
matching C++ source templates for attitude, vertical EKF, and fusion steps
These templates are intended as a companion to the MATLAB workflow, not as a claim that the full embedded estimator is complete in this repository.
Project Status
This repository is strongest as an offline estimator-development and validation package for vertical flight analysis.
Best-supported areas:
vertical estimation replay
event detection
engineering dashboards
truth-aware validation
Monte Carlo robustness testing
Still evolving:
attitude-informed replay as the default vertical estimator input
research-grade 3D navigation integration
reduction from MATLAB analysis code to embedded flight code
Why This Repository Is Useful
This project is a good fit if you want to:
debug a flight estimator offline using real or synthetic Caelum logs
compare logged states against replayed states under controlled settings
quantify estimator behavior before firmware integration
generate engineering figures for post-flight review
validate tuning changes across repeatable Monte Carlo scenarios
Included Example Data
The repository includes example logs and exported assets so you can inspect the workflow before adapting it to your own data:
`LOG000.CSV`
`Drop1.csv`
`LOG_TRUTH_AWARE.CSV`
example outputs under `exports/`

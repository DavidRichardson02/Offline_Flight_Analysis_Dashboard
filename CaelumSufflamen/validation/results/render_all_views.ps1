param(
  [string]$Python = "",
  [string]$InputCsv = "",
  [string]$OutputDir = "",
  [string]$Prefix = "synthetic_nonflight_visual",
  [int]$Seed = 42,
  [double]$TargetApogeeM = 900.0,
  [double]$MaxTimeS = 12.0,
  [string[]]$Fault = @(
    "baro_dropout:3.0:3.4",
    "imu_dropout:5.0:5.3",
    "actuator_stuck:4.0:5.0"
  )
)

$ErrorActionPreference = "Stop"

function Resolve-PythonExecutable {
  param([string]$Requested)

  if ($Requested -ne "") {
    return $Requested
  }

  if ($env:PY -and (Test-Path -LiteralPath $env:PY)) {
    return $env:PY
  }

  $bundled = Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe"
  if (Test-Path -LiteralPath $bundled) {
    return $bundled
  }

  $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
  if ($pythonCommand) {
    return $pythonCommand.Source
  }

  $pyCommand = Get-Command py -ErrorAction SilentlyContinue
  if ($pyCommand) {
    return $pyCommand.Source
  }

  throw "Could not find Python. Pass -Python C:\path\to\python.exe or set `$env:PY."
}

function Invoke-CheckedPython {
  param(
    [string]$PythonExe,
    [string[]]$Arguments
  )

  & $PythonExe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Python command failed with exit code ${LASTEXITCODE}: $PythonExe $($Arguments -join ' ')"
  }
}

function ConvertTo-RepoRelativePath {
  param([string]$Path)

  $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  if ($fullPath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $fullPath.Substring($repoRoot.Length).TrimStart("\") -replace "\\", "/"
  }
  return $fullPath
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $scriptDir "..\..")).Path
$resolvedOutputDir = if ($OutputDir -ne "") {
  $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
} else {
  $scriptDir
}
New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null

$pythonExe = Resolve-PythonExecutable -Requested $Python
$isSynthetic = $false

if ($InputCsv -eq "") {
  $isSynthetic = $true
  $InputCsv = Join-Path $resolvedOutputDir "$($Prefix)_LOG000.CSV"
  $summaryJson = Join-Path $resolvedOutputDir "$($Prefix)_plant_summary.json"

  $plantArgs = @(
    (Join-Path $repoRoot "tests\host\plant_simulation.py"),
    "--seed", [string]$Seed,
    "--target-apogee-m", [string]$TargetApogeeM,
    "--max-time-s", [string]$MaxTimeS,
    "--csv-out", $InputCsv,
    "--json-out", $summaryJson
  )
  foreach ($faultSpec in $Fault) {
    if ($faultSpec -ne "") {
      $plantArgs += @("--fault", $faultSpec)
    }
  }
  Invoke-CheckedPython -PythonExe $pythonExe -Arguments $plantArgs
} else {
  $InputCsv = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InputCsv)
  if (-not (Test-Path -LiteralPath $InputCsv)) {
    throw "Input CSV not found: $InputCsv"
  }
}

$titlePrefix = if ($isSynthetic) {
  "Synthetic non-flight"
} else {
  "Recorded"
}

$apogeeSvg = Join-Path $resolvedOutputDir "$($Prefix)_apogee_evidence.svg"
$apogeeJson = Join-Path $resolvedOutputDir "$($Prefix)_apogee_evidence.json"
$apogeeResidualSvg = Join-Path $resolvedOutputDir "$($Prefix)_apogee_prediction_residual_timeline.svg"
$apogeeResidualJson = Join-Path $resolvedOutputDir "$($Prefix)_apogee_prediction_residual_timeline.json"
$estimatorPolicySvg = Join-Path $resolvedOutputDir "$($Prefix)_estimator_policy_phase_space.svg"
$estimatorPolicyJson = Join-Path $resolvedOutputDir "$($Prefix)_estimator_policy_phase_space.json"
$provenanceSvg = Join-Path $resolvedOutputDir "$($Prefix)_provenance_evidence.svg"
$provenanceJson = Join-Path $resolvedOutputDir "$($Prefix)_provenance_evidence.json"
$provenanceLayoutJson = Join-Path $resolvedOutputDir "$($Prefix)_provenance_layout.json"
$ekfSvg = Join-Path $resolvedOutputDir "$($Prefix)_ekf_innovation_covariance.svg"
$ekfJson = Join-Path $resolvedOutputDir "$($Prefix)_ekf_innovation_covariance.json"
$temporalSvg = Join-Path $resolvedOutputDir "$($Prefix)_temporal_freshness_latency.svg"
$temporalJson = Join-Path $resolvedOutputDir "$($Prefix)_temporal_freshness_latency.json"
$aeroObservabilitySvg = Join-Path $resolvedOutputDir "$($Prefix)_aero_observability_map.svg"
$aeroObservabilityJson = Join-Path $resolvedOutputDir "$($Prefix)_aero_observability_map.json"
$landingFootprintSvg = Join-Path $resolvedOutputDir "$($Prefix)_wind_relative_landing_footprint.svg"
$landingFootprintJson = Join-Path $resolvedOutputDir "$($Prefix)_wind_relative_landing_footprint.json"
$hudPagesSvg = Join-Path $resolvedOutputDir "$($Prefix)_onboard_science_hud_pages.svg"
$hudPagesJson = Join-Path $resolvedOutputDir "$($Prefix)_onboard_science_hud_pages.json"
$energySvg = Join-Path $resolvedOutputDir "$($Prefix)_energy_phase.svg"
$energyJson = Join-Path $resolvedOutputDir "$($Prefix)_energy_phase.json"
$energyLayoutJson = Join-Path $resolvedOutputDir "$($Prefix)_energy_phase_layout.json"
$phaseSvg = Join-Path $resolvedOutputDir "$($Prefix)_phase_timeline.svg"
$phaseJson = Join-Path $resolvedOutputDir "$($Prefix)_phase_timeline.json"
$healthSvg = Join-Path $resolvedOutputDir "$($Prefix)_health_dashboard.svg"
$healthJson = Join-Path $resolvedOutputDir "$($Prefix)_health_dashboard.json"
$orientationSvg = Join-Path $resolvedOutputDir "$($Prefix)_orientation_vector.svg"
$orientationJson = Join-Path $resolvedOutputDir "$($Prefix)_orientation_vector.json"
$magneticSvg = Join-Path $resolvedOutputDir "$($Prefix)_magnetic_field_quality.svg"
$magneticJson = Join-Path $resolvedOutputDir "$($Prefix)_magnetic_field_quality.json"
$gravitySvg = Join-Path $resolvedOutputDir "$($Prefix)_gravity_norm_stability.svg"
$gravityJson = Join-Path $resolvedOutputDir "$($Prefix)_gravity_norm_stability.json"
$sensorFrameSvg = Join-Path $resolvedOutputDir "$($Prefix)_sensor_frame_alignment.svg"
$sensorFrameJson = Join-Path $resolvedOutputDir "$($Prefix)_sensor_frame_alignment.json"
$readinessSvg = Join-Path $resolvedOutputDir "$($Prefix)_readiness_gate.svg"
$readinessJson = Join-Path $resolvedOutputDir "$($Prefix)_readiness_gate.json"
$headingSvg = Join-Path $resolvedOutputDir "$($Prefix)_tilt_compensated_heading.svg"
$headingJson = Join-Path $resolvedOutputDir "$($Prefix)_tilt_compensated_heading.json"
$headingValidatorSvg = Join-Path $resolvedOutputDir "$($Prefix)_heading_sign_calibration_validator.svg"
$headingValidatorJson = Join-Path $resolvedOutputDir "$($Prefix)_heading_sign_calibration_validator.json"
$manifestJson = Join-Path $resolvedOutputDir "$($Prefix)_render_manifest.json"

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\apogee_evidence_view.py"),
  $InputCsv,
  "--svg-out", $apogeeSvg,
  "--json-out", $apogeeJson,
  "--title", "$titlePrefix apogee evidence view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\apogee_prediction_residual_timeline.py"),
  $InputCsv,
  "--svg-out", $apogeeResidualSvg,
  "--json-out", $apogeeResidualJson,
  "--title", "$titlePrefix apogee prediction residual timeline"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\estimator_policy_phase_space_view.py"),
  $InputCsv,
  "--svg-out", $estimatorPolicySvg,
  "--json-out", $estimatorPolicyJson,
  "--title", "$titlePrefix estimator-policy causal phase-space"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\provenance_evidence_view.py"),
  $InputCsv,
  "--svg-out", $provenanceSvg,
  "--json-out", $provenanceJson,
  "--layout-json-out", $provenanceLayoutJson,
  "--title", "$titlePrefix raw-vs-filtered provenance view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\ekf_innovation_covariance_dashboard.py"),
  $InputCsv,
  "--svg-out", $ekfSvg,
  "--json-out", $ekfJson,
  "--title", "$titlePrefix EKF innovation / covariance dashboard"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\temporal_freshness_latency_oscilloscope.py"),
  $InputCsv,
  "--svg-out", $temporalSvg,
  "--json-out", $temporalJson,
  "--title", "$titlePrefix temporal freshness / latency oscilloscope"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\aero_observability_map.py"),
  $InputCsv,
  "--svg-out", $aeroObservabilitySvg,
  "--json-out", $aeroObservabilityJson,
  "--title", "$titlePrefix aerodynamic coefficient observability map"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\wind_relative_landing_footprint.py"),
  $InputCsv,
  "--svg-out", $landingFootprintSvg,
  "--json-out", $landingFootprintJson,
  "--title", "$titlePrefix wind-relative landing footprint / uncertainty cone"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\onboard_science_hud_pages.py"),
  $InputCsv,
  "--svg-out", $hudPagesSvg,
  "--json-out", $hudPagesJson,
  "--title", "$titlePrefix onboard minimal science HUD pages"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\energy_phase_view.py"),
  $InputCsv,
  "--svg-out", $energySvg,
  "--json-out", $energyJson,
  "--layout-json-out", $energyLayoutJson,
  "--title", "$titlePrefix energy-state phase view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\phase_timeline_view.py"),
  $InputCsv,
  "--svg-out", $phaseSvg,
  "--json-out", $phaseJson,
  "--title", "$titlePrefix phase timeline view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\health_dashboard_view.py"),
  $InputCsv,
  "--svg-out", $healthSvg,
  "--json-out", $healthJson,
  "--title", "$titlePrefix health dashboard view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\orientation_vector_view.py"),
  $InputCsv,
  "--svg-out", $orientationSvg,
  "--json-out", $orientationJson,
  "--title", "$titlePrefix orientation vector view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\magnetic_field_quality_view.py"),
  $InputCsv,
  "--svg-out", $magneticSvg,
  "--json-out", $magneticJson,
  "--title", "$titlePrefix magnetic field quality view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\gravity_norm_stability_view.py"),
  $InputCsv,
  "--svg-out", $gravitySvg,
  "--json-out", $gravityJson,
  "--title", "$titlePrefix gravity norm stability view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\sensor_frame_alignment_verifier.py"),
  $InputCsv,
  "--svg-out", $sensorFrameSvg,
  "--json-out", $sensorFrameJson,
  "--title", "$titlePrefix sensor frame alignment verifier"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\readiness_gate_view.py"),
  $InputCsv,
  "--svg-out", $readinessSvg,
  "--json-out", $readinessJson,
  "--title", "$titlePrefix readiness gate view"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\tilt_compensated_heading_view.py"),
  $InputCsv,
  "--svg-out", $headingSvg,
  "--json-out", $headingJson,
  "--title", "$titlePrefix tilt-compensated heading demonstrator"
)

Invoke-CheckedPython -PythonExe $pythonExe -Arguments @(
  (Join-Path $repoRoot "tests\host\heading_sign_calibration_validator.py"),
  $headingJson,
  "--svg-out", $headingValidatorSvg,
  "--json-out", $headingValidatorJson,
  "--title", "$titlePrefix heading sign / calibration validator"
)

$manifest = [ordered]@{
  provenance = if ($isSynthetic) { "synthetic_non_flight_plant_simulation" } else { "recorded_or_replayed_sd_log" }
  synthetic = $isSynthetic
  warning = if ($isSynthetic) { "Tool checkout only. Do not use as flight evidence or coefficient-identification evidence." } else { "Confirm source-log provenance before using as engineering evidence." }
  input_csv = ConvertTo-RepoRelativePath -Path $InputCsv
  output_prefix = $Prefix
  outputs = [ordered]@{
    apogee_svg = ConvertTo-RepoRelativePath -Path $apogeeSvg
    apogee_json = ConvertTo-RepoRelativePath -Path $apogeeJson
    apogee_prediction_residual_timeline_svg = ConvertTo-RepoRelativePath -Path $apogeeResidualSvg
    apogee_prediction_residual_timeline_json = ConvertTo-RepoRelativePath -Path $apogeeResidualJson
    estimator_policy_phase_space_svg = ConvertTo-RepoRelativePath -Path $estimatorPolicySvg
    estimator_policy_phase_space_json = ConvertTo-RepoRelativePath -Path $estimatorPolicyJson
    provenance_svg = ConvertTo-RepoRelativePath -Path $provenanceSvg
    provenance_json = ConvertTo-RepoRelativePath -Path $provenanceJson
    provenance_layout_json = ConvertTo-RepoRelativePath -Path $provenanceLayoutJson
    ekf_innovation_covariance_svg = ConvertTo-RepoRelativePath -Path $ekfSvg
    ekf_innovation_covariance_json = ConvertTo-RepoRelativePath -Path $ekfJson
    temporal_freshness_latency_svg = ConvertTo-RepoRelativePath -Path $temporalSvg
    temporal_freshness_latency_json = ConvertTo-RepoRelativePath -Path $temporalJson
    aero_observability_map_svg = ConvertTo-RepoRelativePath -Path $aeroObservabilitySvg
    aero_observability_map_json = ConvertTo-RepoRelativePath -Path $aeroObservabilityJson
    wind_relative_landing_footprint_svg = ConvertTo-RepoRelativePath -Path $landingFootprintSvg
    wind_relative_landing_footprint_json = ConvertTo-RepoRelativePath -Path $landingFootprintJson
    onboard_science_hud_pages_svg = ConvertTo-RepoRelativePath -Path $hudPagesSvg
    onboard_science_hud_pages_json = ConvertTo-RepoRelativePath -Path $hudPagesJson
    energy_phase_svg = ConvertTo-RepoRelativePath -Path $energySvg
    energy_phase_json = ConvertTo-RepoRelativePath -Path $energyJson
    energy_phase_layout_json = ConvertTo-RepoRelativePath -Path $energyLayoutJson
    phase_svg = ConvertTo-RepoRelativePath -Path $phaseSvg
    phase_json = ConvertTo-RepoRelativePath -Path $phaseJson
    health_svg = ConvertTo-RepoRelativePath -Path $healthSvg
    health_json = ConvertTo-RepoRelativePath -Path $healthJson
    orientation_svg = ConvertTo-RepoRelativePath -Path $orientationSvg
    orientation_json = ConvertTo-RepoRelativePath -Path $orientationJson
    magnetic_svg = ConvertTo-RepoRelativePath -Path $magneticSvg
    magnetic_json = ConvertTo-RepoRelativePath -Path $magneticJson
    gravity_svg = ConvertTo-RepoRelativePath -Path $gravitySvg
    gravity_json = ConvertTo-RepoRelativePath -Path $gravityJson
    sensor_frame_alignment_svg = ConvertTo-RepoRelativePath -Path $sensorFrameSvg
    sensor_frame_alignment_json = ConvertTo-RepoRelativePath -Path $sensorFrameJson
    readiness_svg = ConvertTo-RepoRelativePath -Path $readinessSvg
    readiness_json = ConvertTo-RepoRelativePath -Path $readinessJson
    tilt_compensated_heading_svg = ConvertTo-RepoRelativePath -Path $headingSvg
    tilt_compensated_heading_json = ConvertTo-RepoRelativePath -Path $headingJson
    heading_sign_calibration_validator_svg = ConvertTo-RepoRelativePath -Path $headingValidatorSvg
    heading_sign_calibration_validator_json = ConvertTo-RepoRelativePath -Path $headingValidatorJson
  }
}

if ($isSynthetic) {
  $manifest.synthetic_configuration = [ordered]@{
    seed = $Seed
    target_apogee_m = $TargetApogeeM
    max_time_s = $MaxTimeS
    faults = $Fault
  }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestJson, ($manifest | ConvertTo-Json -Depth 6), $utf8NoBom)

Write-Host "input_csv=$InputCsv"
Write-Host "apogee_svg=$apogeeSvg"
Write-Host "apogee_prediction_residual_timeline_svg=$apogeeResidualSvg"
Write-Host "estimator_policy_phase_space_svg=$estimatorPolicySvg"
Write-Host "provenance_svg=$provenanceSvg"
Write-Host "ekf_innovation_covariance_svg=$ekfSvg"
Write-Host "temporal_freshness_latency_svg=$temporalSvg"
Write-Host "aero_observability_map_svg=$aeroObservabilitySvg"
Write-Host "wind_relative_landing_footprint_svg=$landingFootprintSvg"
Write-Host "onboard_science_hud_pages_svg=$hudPagesSvg"
Write-Host "energy_phase_svg=$energySvg"
Write-Host "phase_svg=$phaseSvg"
Write-Host "health_svg=$healthSvg"
Write-Host "orientation_svg=$orientationSvg"
Write-Host "magnetic_svg=$magneticSvg"
Write-Host "gravity_svg=$gravitySvg"
Write-Host "sensor_frame_alignment_svg=$sensorFrameSvg"
Write-Host "readiness_svg=$readinessSvg"
Write-Host "tilt_compensated_heading_svg=$headingSvg"
Write-Host "heading_sign_calibration_validator_svg=$headingValidatorSvg"
Write-Host "manifest_json=$manifestJson"

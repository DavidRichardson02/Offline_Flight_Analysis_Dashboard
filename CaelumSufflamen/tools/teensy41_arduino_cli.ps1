[CmdletBinding()]
param(
    [string]$ArduinoCli = "arduino-cli",
    [string]$Fqbn = "teensy:avr:teensy41",
    [switch]$Upload,
    [string]$Port,
    [string]$BuildRoot,
    [switch]$StageOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $BuildRoot) {
    $BuildRoot = Join-Path $ProjectRoot ".build\\teensy41"
}

$StageDir = Join-Path $BuildRoot "staged_sketch"
$StageSrcDir = Join-Path $StageDir "src"
$OutputDir = Join-Path $BuildRoot "output"
$SketchPath = Join-Path $ProjectRoot "CaelumSufflamen.ino"
$StagedSketchPath = Join-Path $StageDir "$((Split-Path -Leaf $StageDir)).ino"
$IncludeDir = Join-Path $ProjectRoot "include"
$SourceDir = Join-Path $ProjectRoot "src"
$UtilsDir = Join-Path $ProjectRoot "utils"

function Require-Path([string]$PathValue, [string]$Label) {
    if (-not (Test-Path -LiteralPath $PathValue)) {
        throw "$Label not found: $PathValue"
    }
}

function Get-NormalizedFullPath([string]$PathValue) {
    return [System.IO.Path]::GetFullPath($PathValue)
}

function Assert-PathUnder([string]$PathValue, [string]$ParentValue, [string]$Label) {
    $FullPath = Get-NormalizedFullPath $PathValue
    $ParentPath = (Get-NormalizedFullPath $ParentValue).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $FullPath.StartsWith($ParentPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label must stay under build root '$ParentPath': $FullPath"
    }
}

function Copy-MatchingFiles([string]$SourceDir, [string[]]$Patterns, [string]$DestinationDir) {
    foreach ($Pattern in $Patterns) {
        Get-ChildItem -LiteralPath $SourceDir -Filter $Pattern -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $DestinationDir -Force
        }
    }
}

Require-Path $SketchPath "Sketch entry point"

$SplitDirs = @($IncludeDir, $SourceDir, $UtilsDir)
$ExistingSplitDirCount = @($SplitDirs | Where-Object { Test-Path -LiteralPath $_ }).Count
$UseSplitLayout = $false

if ($ExistingSplitDirCount -eq 3) {
    $UseSplitLayout = $true
} elseif ($ExistingSplitDirCount -ne 0) {
    throw "Partial split source layout found. Expected all or none of include/, src/, and utils/."
}

if ($Upload -and [string]::IsNullOrWhiteSpace($Port)) {
    throw "Upload requested without -Port. Provide the Teensy port reported by 'arduino-cli board list'."
}

if ($StageOnly -and $Upload) {
    throw "-StageOnly cannot be combined with -Upload."
}

Assert-PathUnder $StageDir $BuildRoot "Staged sketch directory"
Assert-PathUnder $OutputDir $BuildRoot "Output directory"

Remove-Item -LiteralPath $StageDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $OutputDir -Recurse -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
New-Item -ItemType Directory -Force -Path $StageSrcDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Copy-Item -LiteralPath $SketchPath -Destination $StagedSketchPath -Force

if ($UseSplitLayout) {
    Copy-MatchingFiles $IncludeDir @("*.h", "*.hpp") $StageDir
    Copy-MatchingFiles $UtilsDir @("*.h", "*.hpp") $StageDir
    Copy-MatchingFiles $IncludeDir @("*.h", "*.hpp") $StageSrcDir
    Copy-MatchingFiles $UtilsDir @("*.h", "*.hpp") $StageSrcDir
    Copy-MatchingFiles $SourceDir @("*.c", "*.cc", "*.cpp") $StageSrcDir
    Copy-MatchingFiles $UtilsDir @("*.c", "*.cc", "*.cpp") $StageSrcDir
    $SourceLayout = "split include/src/utils"
} else {
    Copy-MatchingFiles $ProjectRoot @("*.h", "*.hpp") $StageDir
    Copy-MatchingFiles $ProjectRoot @("*.h", "*.hpp") $StageSrcDir
    Copy-MatchingFiles $ProjectRoot @("*.c", "*.cc", "*.cpp") $StageSrcDir
    $SourceLayout = "flat sketch root"
}

if ($StageOnly) {
    Write-Host "Project root : $ProjectRoot"
    Write-Host "Source layout: $SourceLayout"
    Write-Host "Staged sketch: $StageDir"
    Write-Host "Stage only   : true"
    exit 0
}

$CliCommand = Get-Command $ArduinoCli -ErrorAction SilentlyContinue
if (-not $CliCommand) {
    throw "Could not locate arduino-cli executable '$ArduinoCli'. Install arduino-cli or pass -ArduinoCli with a full path."
}

$Args = @(
    "compile",
    "--fqbn", $Fqbn,
    "--warnings", "all",
    "--output-dir", $OutputDir
)

if ($Upload) {
    $Args += @("--upload", "--port", $Port)
}

$Args += $StageDir

Write-Host "Project root : $ProjectRoot"
Write-Host "Source layout: $SourceLayout"
Write-Host "Staged sketch: $StageDir"
Write-Host "Output dir   : $OutputDir"
Write-Host "FQBN         : $Fqbn"
if ($Upload) {
    Write-Host "Upload port  : $Port"
}

& $CliCommand.Source @Args
exit $LASTEXITCODE

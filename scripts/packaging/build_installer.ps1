# build_installer.ps1
# Helper script to compile Inno Setup installer for HermesUI.
# All characters in this file are strictly ASCII (project requirement).

[CmdletBinding()]
param(
    [string]$AppVersion = "",
    [string]$IssFile = "installer\hermes-ui.iss",
    [string]$OutputDir = "build\installer"
)

$ErrorActionPreference = "Stop"

function Log-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Log-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Log-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Log-Err {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\.."))

# Extract AppVersion from pubspec.yaml if not provided
if (-not $AppVersion) {
    $pubspecPath = Join-Path $projectRoot "pubspec.yaml"
    if (Test-Path $pubspecPath) {
        $content = Get-Content $pubspecPath -Raw
        if ($content -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
            $AppVersion = $matches[1]
            Log-Info "Extracted version from pubspec.yaml: $AppVersion"
        }
    }
}

if (-not $AppVersion) {
    $AppVersion = "0.1.17"
    Log-Warn "Could not detect version from pubspec.yaml, defaulting to $AppVersion"
}

# Resolve paths
$resolvedIssFile = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $IssFile))
$resolvedOutputDir = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $OutputDir))

if (-not (Test-Path $resolvedIssFile)) {
    Log-Err "Inno Setup script not found at: $resolvedIssFile"
    exit 1
}

if (-not (Test-Path $resolvedOutputDir)) {
    New-Item -ItemType Directory -Force -Path $resolvedOutputDir | Out-Null
}

# Locate ISCC.exe
$isccPath = $null

$candidatePaths = @(
    # 显式覆盖口（本机/CI 安装位置特殊时用）
    $env:ISCC_PATH,
    "iscc.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
    # 非管理员（per-user）安装：Inno Setup 6 默认装到 %LOCALAPPDATA%\Programs
    "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe",
    "${env:ChocolateyInstall}\bin\iscc.exe",
    "${env:ChocolateyInstall}\lib\innosetup\tools\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)

foreach ($candidate in $candidatePaths) {
    if (-not $candidate) { continue }
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($cmd) {
        $isccPath = $cmd.Source
        break
    }
    if (Test-Path $candidate) {
        $isccPath = $candidate
        break
    }
}

if (-not $isccPath) {
    Log-Err "ISCC.exe (Inno Setup Compiler) was not found."
    Log-Err "Please install Inno Setup using Chocolatey:"
    Log-Err "  choco install innosetup -y"
    Log-Err "or:"
    Log-Err "  choco install jrsoftware.iscc -y"
    exit 1
}

Log-Info "Using Inno Setup compiler: $isccPath"
Log-Info "Compiling installer for version $AppVersion..."

# Run ISCC
$isccArgs = @(
    "/DMyAppVersion=$AppVersion",
    "/O$resolvedOutputDir",
    $resolvedIssFile
)

& $isccPath $isccArgs
if ($LASTEXITCODE -ne 0) {
    Log-Err "ISCC compilation failed with exit code $LASTEXITCODE"
    exit 1
}

# Check output artifact
$expectedExe = Join-Path $resolvedOutputDir "HermesUI-$AppVersion-x64-setup.exe"
if (-not (Test-Path $expectedExe)) {
    Log-Err "Expected installer not found at: $expectedExe"
    exit 1
}

$sizeBytes = (Get-Item $expectedExe).Length
$sizeMb = [math]::Round($sizeBytes / 1MB, 2)

Log-Success "================================================="
Log-Success "Inno Setup compilation succeeded!"
Log-Success "Installer: $expectedExe"
Log-Success "Size: $sizeMb MB ($sizeBytes bytes)"
Log-Success "================================================="

exit 0

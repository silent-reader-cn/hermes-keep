# build_webui_bundle.ps1
# Build script for bundling the hermes-webui source tree (sidecar server payload).
# All characters in this file are strictly ASCII (required by project standards).
#
# #76 phase 2: the embedded Python runtime is NO LONGER bundled. The sidecar runs
# on the Hermes Agent venv interpreter only (see resolvePythonPath in
# lib/features/webui_sidecar/webui_sidecar_service.dart); when that venv is
# missing, the phase-1 gate guides the user to install Hermes Agent instead of
# silently falling back to a bundled interpreter.

[CmdletBinding()]
param(
    [string]$OutDir = "build\webui-bundle",
    [string]$WebuiRepo = "https://github.com/nesquena/hermes-webui.git",
    [string]$WebuiRef = ""
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

# Resolve destination directory
$resolvedOutDir = [System.IO.Path]::GetFullPath($OutDir)
Log-Info "Target bundle directory: $resolvedOutDir"

$serverDir = Join-Path $resolvedOutDir "server"
$versionFile = Join-Path $resolvedOutDir "webui_version.txt"

# Ensure target directory exists
if (-not (Test-Path $resolvedOutDir)) {
    New-Item -ItemType Directory -Force -Path $resolvedOutDir | Out-Null
}

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("webui_build_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    # Phase-2 hygiene: drop a stale embedded Python runtime left by earlier runs
    # of this script (the installer additionally cleans {app}\webui\python on
    # upgrade). Without this a locally re-run build would silently re-ship it.
    $stalePythonDir = Join-Path $resolvedOutDir "python"
    if (Test-Path $stalePythonDir) {
        Log-Info "Removing stale embedded python directory: $stalePythonDir"
        Get-ChildItem -Path $stalePythonDir -Recurse -Force | ForEach-Object { $_.Attributes = "Normal" }
        Remove-Item -Recurse -Force $stalePythonDir
    }

    # -------------------------------------------------------------------------
    # Step 1: Clone webui repository, write version, and strip git/tests/docs
    # -------------------------------------------------------------------------
    if (Test-Path $serverDir) {
        Log-Info "Cleaning up existing server directory..."
        Get-ChildItem -Path $serverDir -Recurse -Force | ForEach-Object { $_.Attributes = "Normal" }
        Remove-Item -Recurse -Force $serverDir
    }

    Log-Info "Cloning hermes-webui from $WebuiRepo into $serverDir..."
    $cloneSuccess = $false

    # Attempt git clone with specified ref or depth 1
    if ($WebuiRef -ne "") {
        Log-Info "Cloning specific ref: $WebuiRef"
        & git clone --depth=1 --branch $WebuiRef $WebuiRepo "$serverDir"
        if ($LASTEXITCODE -eq 0) {
            $cloneSuccess = $true
        } else {
            Log-Warn "Branch clone failed, trying generic clone and checkout..."
            & git clone $WebuiRepo "$serverDir"
            if ($LASTEXITCODE -eq 0) {
                & git -C "$serverDir" checkout $WebuiRef
                if ($LASTEXITCODE -eq 0) {
                    $cloneSuccess = $true
                }
            }
        }
    } else {
        & git clone --depth=1 $WebuiRepo "$serverDir"
        if ($LASTEXITCODE -eq 0) {
            $cloneSuccess = $true
        }
    }

    # Fallback to local repo if remote clone fails and D:\hermes-webui exists
    if (-not $cloneSuccess) {
        $localFallback = "D:\hermes-webui"
        if (Test-Path (Join-Path $localFallback "server.py")) {
            Log-Warn "Remote clone failed. Falling back to local repository at $localFallback"
            & git clone --depth=1 $localFallback "$serverDir"
            if ($LASTEXITCODE -eq 0) {
                $cloneSuccess = $true
            }
        }
    }

    if (-not $cloneSuccess) {
        Log-Err "Failed to clone hermes-webui repository"
        exit 1
    }

    # Get upstream commit sha BEFORE deleting .git
    $commitSha = (git -C "$serverDir" rev-parse HEAD).Trim()
    if (-not $commitSha) {
        Log-Err "Could not determine git commit SHA from $serverDir"
        exit 1
    }
    Log-Info "WebUI upstream commit SHA: $commitSha"

    # Write single line commit sha to webui_version.txt
    $commitSha | Set-Content $versionFile -Encoding ASCII -NoNewline
    Log-Success "Wrote version file to $versionFile"

    # Strip .git, tests, docs, and bytecode from server directory
    Log-Info "Removing .git directory from server payload..."
    $gitDir = Join-Path $serverDir ".git"
    if (Test-Path $gitDir) {
        Get-ChildItem -Path $gitDir -Recurse -Force | ForEach-Object { $_.Attributes = "Normal" }
        Remove-Item -Path $gitDir -Recurse -Force
    }

    $testsDir = Join-Path $serverDir "tests"
    if (Test-Path $testsDir) {
        Log-Info "Removing tests directory..."
        Remove-Item -Path $testsDir -Recurse -Force
    }

    $docsDir = Join-Path $serverDir "docs"
    if (Test-Path $docsDir) {
        Log-Info "Removing docs directory..."
        Remove-Item -Path $docsDir -Recurse -Force
    }

    Get-ChildItem -Path $serverDir -Recurse -Filter "__pycache__" | Remove-Item -Recurse -Force
    Get-ChildItem -Path $serverDir -Recurse -Filter "*.pyc" | Remove-Item -Force

    # -------------------------------------------------------------------------
    # Step 2: Validate bundle artifacts
    # -------------------------------------------------------------------------
    $serverCheck = Test-Path (Join-Path $serverDir "server.py")
    $verCheck = Test-Path $versionFile

    if (-not $serverCheck) {
        Log-Err "Artifact check failed: server/server.py is missing"
        exit 1
    }
    if (-not $verCheck) {
        Log-Err "Artifact check failed: webui_version.txt is missing"
        exit 1
    }

    # Measure total bundle size
    $totalSizeBytes = (Get-ChildItem -Path $resolvedOutDir -Recurse | Measure-Object -Property Length -Sum).Sum
    $totalSizeMb = [math]::Round($totalSizeBytes / 1MB, 2)

    Log-Success "================================================="
    Log-Success "WebUI sidecar bundle assembled successfully!"
    Log-Success "Artifact verification:"
    Log-Success "  [OK] webui\server\server.py"
    Log-Success "  [OK] webui_version.txt (SHA: $commitSha)"
    Log-Success "  [--] embedded python runtime: not bundled (#76 phase 2)"
    Log-Success "Total bundle size: $totalSizeMb MB ($totalSizeBytes bytes)"
    Log-Success "================================================="

    exit 0
} finally {
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}

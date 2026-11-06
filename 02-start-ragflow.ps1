<#
.SYNOPSIS
  Step 2: Clones RAGFlow, applies the offline-friendly override, and starts the
  full stack via Docker Compose. Run AFTER rebooting and launching Docker
  Desktop at least once (01-install-prereqs.ps1).

.NOTES
  Run in an elevated (Administrator) PowerShell window, from this folder.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "=== Step 2: Checking Docker is running ===" -ForegroundColor Cyan
$dockerInfo = docker info 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker does not appear to be running. Launch Docker Desktop, wait for" -ForegroundColor Red
    Write-Host "'Engine running' in the bottom-left corner, then re-run this script." -ForegroundColor Red
    exit 1
}
Write-Host "Docker is running." -ForegroundColor Green

# Where RAGFlow will live, and where the PDF library will be referenced from
$installRoot = "C:\RAGFlow"
$pdfLibraryPath = "D:\ChemLibrary"   # <-- EDIT this if his PDFs live somewhere else

Write-Host ""
Write-Host "=== Step 3: Checking for Git ===" -ForegroundColor Cyan
git --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Git not found. Installing via winget..."
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Write-Host "Git installed. You may need to restart this terminal if 'git' is still not recognized." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Step 4: Cloning RAGFlow into $installRoot ===" -ForegroundColor Cyan
if (-not (Test-Path $installRoot)) {
    New-Item -ItemType Directory -Path $installRoot | Out-Null
}

if (-not (Test-Path "$installRoot\ragflow")) {
    git clone https://github.com/infiniflow/ragflow.git "$installRoot\ragflow"
} else {
    Write-Host "RAGFlow repo already present, pulling latest stable tag info..."
}

Set-Location "$installRoot\ragflow"

# Pin to a known-good stable tag rather than a moving 'main' branch
$stableTag = "v0.25.1"
git fetch --tags
git checkout $stableTag

Write-Host ""
Write-Host "=== Step 5: Copying offline override config ===" -ForegroundColor Cyan
Copy-Item "$PSScriptRoot\docker-compose.override.yml" "$installRoot\ragflow\docker\docker-compose.override.yml" -Force

Write-Host ""
Write-Host "=== Step 6: Raising memory limits (required for Elasticsearch doc engine) ===" -ForegroundColor Cyan
$wslConfigPath = "$env:USERPROFILE\.wslconfig"
$wslConfigContent = @"
[wsl2]
memory=12GB
processors=4
"@
if (-not (Test-Path $wslConfigPath)) {
    Set-Content -Path $wslConfigPath -Value $wslConfigContent
    Write-Host "Created .wslconfig with 12GB RAM / 4 CPU allocation for WSL2."
    Write-Host "NOTE: if this is the first time this file is created, restart Docker Desktop (or run 'wsl --shutdown' then relaunch Docker) for it to take effect." -ForegroundColor Yellow
} else {
    Write-Host ".wslconfig already exists — leaving as-is. Edit manually if RAGFlow runs out of memory."
}

Write-Host ""
Write-Host "=== Step 7: Starting RAGFlow (first run pulls several GB of images — can take 15-40 min) ===" -ForegroundColor Cyan
Set-Location "$installRoot\ragflow\docker"
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

Write-Host ""
Write-Host "=== Step 8: Waiting for RAGFlow web UI to become reachable ===" -ForegroundColor Cyan
$maxAttempts = 60
$attempt = 0
$ready = $false
while ($attempt -lt $maxAttempts -and -not $ready) {
    Start-Sleep -Seconds 10
    $attempt++
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:9380" -UseBasicParsing -TimeoutSec 5
        if ($resp.StatusCode -eq 200) { $ready = $true }
    } catch {
        Write-Host "Still starting up... ($attempt/$maxAttempts)"
    }
}

if ($ready) {
    Write-Host ""
    Write-Host "=== RAGFlow is up! ===" -ForegroundColor Green
    Write-Host "Open http://localhost:9380 in a browser to create the admin account." -ForegroundColor Green
    Write-Host "Next: follow 03-configure-embedding.md, then run ingest_folder.py." -ForegroundColor Green
} else {
    Write-Host "RAGFlow did not come up within the expected time." -ForegroundColor Red
    Write-Host "Check container status with: docker compose -f docker-compose.yml -f docker-compose.override.yml ps" -ForegroundColor Yellow
    Write-Host "Check logs with: docker compose -f docker-compose.yml -f docker-compose.override.yml logs -f ragflow" -ForegroundColor Yellow
}

<#
.SYNOPSIS
  Step 1: Installs prerequisites for running RAGFlow on Windows 10/11:
  - WSL2 (required backend for Docker Desktop)
  - Docker Desktop (if not already installed)
  - Enables required Windows features

.NOTES
  Run this in an elevated (Administrator) PowerShell window.
  A REBOOT is required after this script finishes. Run 02-start-ragflow.ps1 after reboot.
#>

#Requires -RunAsAdministrator

Write-Host "=== Step 1: Checking/Enabling Windows features for WSL2 + Docker ===" -ForegroundColor Cyan

# Enable WSL and Virtual Machine Platform (needed for Docker Desktop's WSL2 backend)
$features = @(
    "Microsoft-Windows-Subsystem-Linux",
    "VirtualMachinePlatform"
)

foreach ($feature in $features) {
    $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
    if ($state -ne "Enabled") {
        Write-Host "Enabling $feature ..."
        Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
    } else {
        Write-Host "$feature already enabled."
    }
}

# Set WSL2 as the default version
Write-Host "Setting WSL 2 as default version..."
wsl --set-default-version 2 2>$null

# Install/Update WSL kernel
Write-Host "Installing/updating WSL kernel components..."
wsl --update 2>$null

# Check if Docker Desktop is already installed
$dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
if (Test-Path $dockerPath) {
    Write-Host "Docker Desktop is already installed." -ForegroundColor Green
} else {
    Write-Host "Docker Desktop not found. Downloading installer..." -ForegroundColor Yellow
    $installerUrl = "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe"
    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"

    Write-Host "Downloading from $installerUrl ..."
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing

    Write-Host "Running Docker Desktop installer (this takes a few minutes)..."
    Start-Process -FilePath $installerPath -ArgumentList "install", "--quiet", "--accept-license", "--backend=wsl-2" -Wait

    Write-Host "Docker Desktop installed." -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Prerequisite installation complete ===" -ForegroundColor Green
Write-Host "A REBOOT is required now." -ForegroundColor Yellow
Write-Host "After reboot:"
Write-Host "  1. Launch Docker Desktop manually once and let it finish its first-run setup / WSL2 integration."
Write-Host "  2. Make sure Docker Desktop shows 'Engine running' in the bottom-left corner."
Write-Host "  3. Then run 02-start-ragflow.ps1 from this same folder."
Write-Host ""
$response = Read-Host "Reboot now? (y/n)"
if ($response -eq 'y') {
    Restart-Computer
}

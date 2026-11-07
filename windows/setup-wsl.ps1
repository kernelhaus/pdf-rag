<#
 PDF Search - Windows-side setup. Run by the installer (elevated) or by hand.
 Creates a dedicated WSL2 distro "pdfsearch" on the chosen drive, then runs the
 Linux installer inside it. Safe to re-run: every step checks before acting.
 Exit codes: 0 ok, 10 reboot needed (re-run afterwards), other = failure (see log).
#>
param(
  [Parameter(Mandatory)][string]$InstallDir,     # where the distro disk lives, e.g. D:\PDFSearch
  [Parameter(Mandatory)][string]$PdfDir,         # Windows folder with the PDFs, e.g. D:\ChemLibrary
  [int]$RamGB = 12,
  [int]$Cpus = 4,
  [string]$Model = "BAAI/bge-small-en-v1.5",
  [string]$AdminPassword = "",
  [string]$AppDir = $PSScriptRoot + "\..",
  [switch]$SkipInstallStack                     # for testing the Windows half only
)
$ErrorActionPreference = "Stop"
# Defensive: strip stray quotes/whitespace that command-line quoting can leave on paths
$InstallDir = $InstallDir.Trim().Trim('"'); $PdfDir = $PdfDir.Trim().Trim('"')
$Distro = "pdfsearch"
$RootfsUrl = "https://releases.ubuntu.com/noble/ubuntu-24.04.5-wsl-amd64.wsl"
$RootfsSha = "bb415d824822c4b878125729af451a5d18fb13d1cf5cbed9a7393ad64ac6039e"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Remove-Item (Join-Path $InstallDir "last-error.txt") -ErrorAction SilentlyContinue
$Log = Join-Path $InstallDir "setup.log"
Start-Transcript -Path $Log -Append | Out-Null
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
$ProgressPreference = "SilentlyContinue"   # makes Invoke-WebRequest much faster
function Fail($m, $code = 1) {
  Write-Host "ERROR: $m" -ForegroundColor Red
  try { Set-Content -Path (Join-Path $InstallDir "last-error.txt") -Value $m -Encoding ascii } catch {}
  Write-Host "A detailed log is in $Log" -ForegroundColor Yellow
  Write-Host "To send us the details: Start menu > PDF Search > 'Collect diagnostics'." -ForegroundColor Yellow
  Stop-Transcript | Out-Null; exit $code
}
function Download($url, $out) {
  for ($i = 1; $i -le 3; $i++) {
    try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing; return } catch { Write-Warning "Download attempt $i failed: $($_.Exception.Message)"; Start-Sleep -Seconds (5 * $i) }
  }
  Fail "Could not download $url. Check the internet connection and run setup again."
}
function WslRun([string]$cmd) { & wsl.exe -d $Distro -u root -- bash -lc $cmd; if ($LASTEXITCODE -ne 0) { Fail "command failed in WSL: $cmd" } }

try {
Step "Checking Windows"
Write-Host "InstallDir=[$InstallDir] PdfDir=[$PdfDir] RamGB=$RamGB Cpus=$Cpus Model=$Model"
if ([Environment]::OSVersion.Version.Build -lt 19041) { Fail "Windows 10 2004 (build 19041) or newer is required." }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Fail "Run as Administrator." }
if ((Get-CimInstance Win32_Processor | Select-Object -First 1).Architecture -ne 9) { Fail "This version needs a 64-bit Intel/AMD PC. This PC uses a different processor type (for example ARM)." }
$cs = Get-CimInstance Win32_ComputerSystem
$vt = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
if (-not $cs.HypervisorPresent -and -not $vt) { Fail "Virtualization is switched off in this PC's BIOS/UEFI. Restart, enter BIOS setup, enable 'Intel Virtualization Technology' / 'SVM Mode', then run setup again." }
if ($cs.TotalPhysicalMemory / 1GB -lt 15) { Write-Warning "Less than 16 GB RAM: indexing will be slow; consider lowering the model/RAM settings." }
$drive = (Split-Path -Qualifier (Resolve-Path $InstallDir).Path).TrimEnd(":")
$free = (Get-PSDrive $drive).Free / 1GB
Write-Host ("Install drive {0}: has {1:N0} GB free" -f $drive, $free)
if ($free -lt 30) { Fail "Need at least 30 GB free on $drive`: for the application itself (the index grows with the library)." }
if (-not (Test-Path $PdfDir)) { Fail "PDF folder not found: $PdfDir" }

Step "Enabling WSL2"
$feat = @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform") | ForEach-Object { Get-WindowsOptionalFeature -Online -FeatureName $_ }
$need = $feat | Where-Object State -ne "Enabled"
if ($need) {
  foreach ($f in $need) { Enable-WindowsOptionalFeature -Online -FeatureName $f.FeatureName -NoRestart | Out-Null }
  Write-Host "Windows features enabled. A restart is required, then run this setup again."
  Stop-Transcript | Out-Null; exit 10
}
& wsl.exe --update 2>&1 | Out-Null
& wsl.exe --set-default-version 2 2>&1 | Out-Null

Step "Writing WSL resource limits (.wslconfig)"
$cfg = Join-Path $env:USERPROFILE ".wslconfig"
$block = "# >>> pdfsearch`r`n[wsl2]`r`nmemory=${RamGB}GB`r`nprocessors=$Cpus`r`nswap=8GB`r`n# <<< pdfsearch`r`n"
$existing = if (Test-Path $cfg) { Get-Content $cfg -Raw } else { "" }
$existing = [regex]::Replace($existing, "(?s)# >>> pdfsearch.*?# <<< pdfsearch\r?\n?", "")
if ($existing -match "(?m)^\[wsl2\]") { Write-Warning "Your .wslconfig already has a [wsl2] section; leaving your limits as they are."; $block = "" }
Set-Content -Path $cfg -Value ($existing + $block) -Encoding ascii

Step "Creating the Linux environment on $InstallDir"
$have = (& wsl.exe -l -q 2>$null) -replace "`0", "" | Where-Object { $_.Trim() -eq $Distro }
if (-not $have) {
  $tar = Join-Path $InstallDir "ubuntu.wsl"
  if (-not (Test-Path $tar)) { Write-Host "Downloading Ubuntu (~350 MB)..."; Download $RootfsUrl $tar }
  if ((Get-FileHash $tar -Algorithm SHA256).Hash.ToLower() -ne $RootfsSha) { Remove-Item $tar -Force; Fail "Ubuntu download failed its checksum; run setup again." }
  & wsl.exe --import $Distro (Join-Path $InstallDir "distro") $tar --version 2
  if ($LASTEXITCODE -ne 0) { Fail "wsl --import failed" }
  Remove-Item $tar -Force
}
# systemd is needed for Docker and the background indexer
WslRun "printf '[boot]\nsystemd=true\n[user]\ndefault=root\n' > /etc/wsl.conf"
& wsl.exe --terminate $Distro | Out-Null
Start-Sleep -Seconds 3
WslRun "systemctl is-system-running --wait >/dev/null 2>&1; true"

if ($SkipInstallStack) { Write-Host "SkipInstallStack set: stopping before the Linux install."; Stop-Transcript | Out-Null; exit 0 }

Step "Configuring"
if (-not $AdminPassword) { $AdminPassword = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) }
$wslPdf = (& wsl.exe -d $Distro -u root -- wslpath -a ($PdfDir -replace "\\", "/")).Trim()
$conf = (Get-Content (Join-Path $AppDir "linux\pdfsearch.conf.example") -Raw) `
  -replace "(?m)^TEI_MODEL=.*", "TEI_MODEL=$Model" `
  -replace "(?m)^MEM_LIMIT_GB=.*", ("MEM_LIMIT_GB=" + [Math]::Max(4, $RamGB - 3)) `
  -replace "(?m)^ADMIN_PASSWORD=.*", "ADMIN_PASSWORD=$AdminPassword" `
  -replace "(?m)^PDF_DIR=.*", "PDF_DIR=$wslPdf"
$tmp = Join-Path $InstallDir "pdfsearch.conf"
[IO.File]::WriteAllText($tmp, ($conf -replace "`r`n", "`n"))
$wslTmp = (& wsl.exe -d $Distro -u root -- wslpath -a ($tmp -replace "\\", "/")).Trim()
WslRun "mkdir -p /etc/pdfsearch && install -m 600 '$wslTmp' /etc/pdfsearch/pdfsearch.conf"
Remove-Item $tmp -Force
$credFile = Join-Path $InstallDir "login.txt"
"Address:  http://localhost`r`nEmail:    admin@pdfsearch.local`r`nPassword: $AdminPassword" | Set-Content $credFile -Encoding ascii

Step "Installing the search engine (downloads several GB, can take a while)"
$wslApp = (& wsl.exe -d $Distro -u root -- wslpath -a ((Resolve-Path $AppDir).Path -replace "\\", "/")).Trim()
WslRun "rm -rf /opt/pdfsearch-src && mkdir -p /opt/pdfsearch-src && cp -r '$wslApp/linux' '$wslApp/ingest_folder.py' /opt/pdfsearch-src/ && bash /opt/pdfsearch-src/linux/install-stack.sh"

Step "Checking that it answers from Windows"
$ok = $false
for ($i = 0; $i -lt 60 -and -not $ok; $i++) {
  try { $ok = (Invoke-WebRequest -Uri "http://localhost/api/v1/system/ping" -UseBasicParsing -TimeoutSec 5).StatusCode -lt 500 } catch { Start-Sleep -Seconds 5 }
}
if (-not $ok) { Fail "The search engine installed but does not answer at http://localhost from Windows (port forwarding or still starting). Try Start menu > PDF Search, and if it persists collect diagnostics." }

Step "Done"
Write-Host "Open http://localhost  (login details saved in $credFile)" -ForegroundColor Green
} catch { Fail $_.Exception.Message }
Stop-Transcript | Out-Null

<# Gathers logs into a zip on the Desktop to send for support. Contains no passwords or PDF content. #>
param([string]$InstallDir = "C:\PDFSearchData")
$ErrorActionPreference = "Continue"
$tmp = Join-Path $env:TEMP ("pdfsearch-diag-" + (Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Force $tmp | Out-Null
function W($name, [scriptblock]$b) { try { & $b 2>&1 | Out-String | Set-Content (Join-Path $tmp $name) } catch { $_ | Out-String | Set-Content (Join-Path $tmp $name) } }
W "windows.txt" { Get-CimInstance Win32_OperatingSystem | Select Caption,Version,OSArchitecture; Get-CimInstance Win32_ComputerSystem | Select TotalPhysicalMemory,HypervisorPresent; (Get-CimInstance Win32_Processor).VirtualizationFirmwareEnabled; Get-PSDrive -PSProvider FileSystem | Select Name,Used,Free; Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform | Select FeatureName,State }
$old = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::Unicode
W "wsl.txt" { wsl.exe --status; wsl.exe -l -v; wsl.exe --version }
[Console]::OutputEncoding = $old
W "ping.txt" { (Invoke-WebRequest -Uri "http://localhost/api/v1/system/ping" -UseBasicParsing -TimeoutSec 5) | Select StatusCode,Content }
W "linux.txt" { wsl.exe -d pdfsearch -u root -- bash -lc "free -m; df -h /; systemctl is-system-running; systemctl status docker pdfsearch-ingest --no-pager | tail -30; cd /opt/ragflow/docker && docker compose ps; docker compose logs --tail=40 2>&1 | tail -150; journalctl -u pdfsearch-ingest --no-pager | tail -40" }
foreach ($f in "setup.log") { if (Test-Path (Join-Path $InstallDir $f)) { Copy-Item (Join-Path $InstallDir $f) $tmp } }
if (Test-Path "$env:USERPROFILE\.wslconfig") { Copy-Item "$env:USERPROFILE\.wslconfig" $tmp }
$zip = Join-Path ([Environment]::GetFolderPath("Desktop")) "pdfsearch-diagnostics.zip"
Compress-Archive -Path "$tmp\*" -DestinationPath $zip -Force
Write-Host "Created $zip"

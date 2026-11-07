<# Daily launcher: makes sure the engine is running, waits until ready, opens the browser. #>
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
function Note($m) { [Windows.Forms.MessageBox]::Show($m, "PDF Search") | Out-Null }
$up = { try { (Invoke-WebRequest -Uri "http://localhost/api/v1/system/ping" -UseBasicParsing -TimeoutSec 3).StatusCode -lt 500 } catch { $false } }
if (-not (& $up)) {
  # Starting any command in the distro boots it; systemd then starts docker and the stack (restart: always)
  Start-Process -WindowStyle Hidden -FilePath wsl.exe -ArgumentList "-d pdfsearch -u root -- bash -lc `"cd /opt/ragflow/docker && docker compose up -d; sleep infinity`""
  $t = Get-Date
  while (-not (& $up)) {
    if (((Get-Date) - $t).TotalMinutes -gt 10) { Note "The search engine did not start within 10 minutes. See the Troubleshooting section of the guide."; exit 1 }
    Start-Sleep -Seconds 3
  }
}
Start-Process "http://localhost"

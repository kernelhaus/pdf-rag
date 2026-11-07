<# Fixes "email and password do not match" after the installer was run more than once.
   Creates a second admin account (admin2@pdfsearch.local) with the password that is
   currently in the installed config, and updates login.txt. Nothing is deleted. #>
$ErrorActionPreference = "Stop"
$distro = "pdfsearch"
function WslRoot($cmd) { & wsl.exe -d $distro -u root -- bash -lc $cmd; if ($LASTEXITCODE -ne 0) { throw "failed: $cmd" } }
try {
  Write-Host "Starting the search engine (can take a few minutes)..."
  $start = 'cd /opt/ragflow/docker && docker compose up -d; sleep 900'
  Start-Process -WindowStyle Hidden -FilePath wsl.exe -ArgumentList @("-d", $distro, "-u", "root", "--", "bash", "-lc", ('"' + $start + '"'))
  WslRoot "test -f /etc/pdfsearch/pdfsearch.conf || { echo 'No installed config found: the setup did not finish. Run the installer again.'; exit 1; }"
  $run = @'
sed 's/^ADMIN_EMAIL=.*/ADMIN_EMAIL=admin2@pdfsearch.local/' /etc/pdfsearch/pdfsearch.conf > /tmp/pdfsearch-admin2.conf
python3 /opt/pdfsearch/provision.py --conf /tmp/pdfsearch-admin2.conf --wait-minutes 15
rc=$?
rm -f /tmp/pdfsearch-admin2.conf
exit $rc
'@
  WslRoot ($run -replace "`r", "")
  $pw = (& wsl.exe -d $distro -u root -- bash -lc "grep -m1 '^ADMIN_PASSWORD=' /etc/pdfsearch/pdfsearch.conf | cut -d= -f2-").Trim()
  $text = "Address:  http://localhost`r`nEmail:    admin2@pdfsearch.local`r`nPassword: $pw"
  $login = Get-ChildItem C:\,D:\ -Recurse -Filter login.txt -Depth 2 -ErrorAction SilentlyContinue | Where-Object { (Get-Content $_.FullName -Raw) -match "pdfsearch.local" } | Select-Object -First 1
  if ($login) { Set-Content $login.FullName $text -Encoding ascii; Write-Host "Updated $($login.FullName)" }
  Write-Host ""
  Write-Host "SIGN IN WITH:" -ForegroundColor Green
  Write-Host "  Email:    admin2@pdfsearch.local" -ForegroundColor Green
  Write-Host "  Password: $pw" -ForegroundColor Green
} catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
Read-Host "Press Enter to close"

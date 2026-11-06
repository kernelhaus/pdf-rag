<#
.SYNOPSIS
  Step 4: Creates a desktop shortcut + Start Menu entry that opens the RAGFlow
  search UI, and registers a scheduled task so Docker Desktop (and therefore
  RAGFlow) auto-starts on login/reboot without him ever touching a terminal.

.NOTES
  Run in a normal (non-admin is fine) PowerShell window.
#>

$url = "http://localhost:9380"
$shortcutName = "Chemical Library Search.lnk"

# --- Desktop shortcut ---
$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath $shortcutName

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "$env:windir\system32\cmd.exe"
$shortcut.Arguments = "/c start $url"
$shortcut.WindowStyle = 7  # minimized, so no console flash
$shortcut.IconLocation = "$env:windir\system32\shell32.dll,14"  # magnifying-glass-ish icon
$shortcut.Description = "Search the chemical/engineering PDF library"
$shortcut.Save()

Write-Host "Desktop shortcut created: $shortcutPath" -ForegroundColor Green

# --- Start Menu entry (same shortcut, Start Menu Programs folder) ---
$startMenuPath = [Environment]::GetFolderPath("Programs")
Copy-Item $shortcutPath (Join-Path $startMenuPath $shortcutName) -Force
Write-Host "Start Menu entry created." -ForegroundColor Green

# --- Ensure Docker Desktop auto-starts on login (so RAGFlow is always ready) ---
$dockerStartupShortcut = Join-Path ([Environment]::GetFolderPath("Startup")) "Docker Desktop.lnk"
$dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
if ((Test-Path $dockerExe) -and (-not (Test-Path $dockerStartupShortcut))) {
    $dockerShortcut = $wshShell.CreateShortcut($dockerStartupShortcut)
    $dockerShortcut.TargetPath = $dockerExe
    $dockerShortcut.Save()
    Write-Host "Docker Desktop will now auto-launch at login." -ForegroundColor Green
} else {
    Write-Host "Docker Desktop autostart shortcut already present or Docker not found at expected path." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "He can now just double-click 'Chemical Library Search' on the Desktop." -ForegroundColor Cyan
Write-Host "NOTE: After a reboot, Docker Desktop + the RAGFlow containers take ~1-2 minutes" -ForegroundColor Yellow
Write-Host "to fully come up before the page will load. If he gets a 'can't connect' page," -ForegroundColor Yellow
Write-Host "wait a minute and refresh." -ForegroundColor Yellow

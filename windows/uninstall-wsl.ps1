<# Removes the Linux environment (the whole index!). Your PDFs are never touched. #>
param([switch]$Yes)
if (-not $Yes) { if ((Read-Host "This deletes the search index (not your PDFs). Type YES to continue") -ne "YES") { exit 1 } }
wsl.exe --unregister pdfsearch

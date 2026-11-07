# PDF Search - setup and daily use

Searches your PDF library (including scanned pages) completely offline. Nothing leaves your PC after installation.

## Requirements
- Windows 10 (2004+) or 11, 64-bit Intel/AMD PC (not ARM)
- 16 GB RAM or more (32 GB+ recommended for the "best quality" model)
- Virtualization enabled in BIOS (normally on by default)
- Free space for the search index on the drive you choose: roughly 5-10% of your PDF size, more for scanned documents
- Internet **only during installation** (about 10 GB of downloads)

## Install
1. Run `PDFSearch-Setup.exe`, approve the administrator prompt.
2. Pick your **PDF folder**, the **index location** (a drive with plenty of space), memory/CPU limits and the model:
   - *Fast, English* (default): start here.
   - *Best quality, multilingual*: needs 32 GB+ RAM.
3. Wait. The installer downloads and sets everything up (10-30 minutes).
4. If Windows asks to restart, restart, then open Start menu > PDF Search > **Finish setup**.
5. When it says Done, your login is saved in `login.txt` inside the index folder.

## Daily use
Double-click the **PDF Search** desktop icon. Your browser opens at http://localhost after the engine has started (the first start of the day takes a minute or two).
Sign in with the details from `login.txt`, open **Knowledge base** > **Library**, and search.

## Adding PDFs
Copy them into your PDF folder (sub-folders are fine). New and changed files are picked up automatically every 30 minutes while the PC is on.
Indexing a large library takes days or weeks; search works on whatever is already indexed. Your files are only read, never changed.

## Something is wrong
1. Start menu > PDF Search > **Collect diagnostics**, then send `pdfsearch-diagnostics.zip` from your Desktop. It contains no passwords or PDF content.
2. Installer log: `setup.log` in the index folder.
3. Stop everything: Start menu > PDF Search > **Stop PDF Search**.

## Uninstall
Windows Settings > Apps > PDF Search. To also delete the search index (never your PDFs), run `windows\uninstall-wsl.ps1`.

## "Email and password do not match" when signing in

This happens if the installer was run more than once. Open PowerShell (Start menu > type PowerShell > Enter) and paste this one line:

```
irm https://raw.githubusercontent.com/kernelhaus/pdf-rag/main/windows/fix-login.ps1 -OutFile $env:TEMP\fix-login.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\fix-login.ps1
```

It creates a second admin account and prints the new email and password on screen. Sign in with those.

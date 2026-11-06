# Full Setup Guide — Remote Session Walkthrough

Written so you can follow it step-by-step while remoted into his PC. Total
hands-on time: ~30-45 minutes, spread across two sessions (one before reboot,
one after). The big 1TB ingestion runs unattended afterward for as long as it
takes.

---

## Prerequisites checklist (confirm before you start)

- [ ] Windows 10/11, admin rights on the account you're remoted into
- [ ] At least 20GB free disk space on `C:` for Docker images/containers
- [ ] Know the drive/path where his PDF library actually lives (e.g. `D:\ChemLibrary`)
- [ ] Virtualization enabled in BIOS (usually already on; Docker/WSL will
      complain clearly if not — if so, he'll need to enable "Intel VT-x" or
      "AMD-V" in BIOS, which requires a physical reboot you can't do remotely
      if he's not present to press the key during boot)

---

## Session 1 — Install prerequisites

1. Copy this entire folder to his PC, e.g. `C:\Setup\pdf-rag\`.
2. Open PowerShell **as Administrator**.
3. ```powershell
   cd C:\Setup\pdf-rag
   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
   .\01-install-prereqs.ps1
   ```
4. This installs WSL2 + Docker Desktop and enables required Windows features.
5. **Reboot when prompted.** (The script offers to do this for you.)

If your remote session drops on reboot, that's expected — reconnect after a
couple of minutes.

---

## Session 2 — Start RAGFlow and ingest

### A. First-time Docker Desktop launch

1. Launch **Docker Desktop** manually from the Start Menu once.
2. Accept the license / skip sign-in (sign-in not required for local use).
3. Wait until the bottom-left corner shows a green **"Engine running"** indicator.

### B. Start the RAGFlow stack

```powershell
cd C:\Setup\pdf-rag
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\02-start-ragflow.ps1
```

- First run downloads several GB of Docker images — can take 15-40 minutes
  depending on connection speed (this is the ONLY step needing internet; once
  images are pulled, the system runs fully offline).
- The script edits `%USERPROFILE%\.wslconfig` to give WSL2 12GB RAM / 4 CPUs.
  If his PC has less than 16GB RAM total, open that file and lower the value
  (e.g. `memory=6GB`) before continuing, or Windows may stall from memory
  pressure.
- The script waits and tells you when `http://localhost:9380` is reachable.

### C. Install Ollama and pull bge-m3 (the actual embedding engine)

RAGFlow itself does not run embedding models — it needs Ollama (or Xinference)
as a separate inference backend reachable over HTTP. Install it on the
Windows host directly (not in Docker):

```powershell
winget install --id Ollama.Ollama -e --source winget --accept-package-agreements --accept-source-agreements
ollama pull bge-m3
```

Confirm it's serving: `curl http://localhost:11434/api/tags` should list `bge-m3`.

### D. One-time manual configuration (via browser)

Follow **`03-configure-embedding.md`** exactly. Summary:
1. Create the admin account in the browser UI.
2. Add **Ollama** as a Model Provider, base URL `http://host.docker.internal:11434`
   (this is how the Docker containers reach the host's Ollama install — plain
   `localhost` won't work from inside a container).
3. Create a Knowledge Base named `ChemEng-Library`, embedding model `bge-m3` (via Ollama).
4. If a meaningful fraction of the library is old scanned (non-text) PDFs,
   also create `ChemEng-Library-Scanned` with OCR enabled.
5. Generate an API key (Settings → API Keys). **Save it somewhere — you need
   it for the next step.**
6. Manually upload 2-3 test PDFs via the UI, confirm parsing finishes and
   "Retrieval testing" returns good highlighted results.

### E. Kick off the full 1TB ingestion

```powershell
cd C:\Setup\pdf-rag
pip install -r requirements.txt

python ingest_folder.py --root "D:\ChemLibrary" --api-key PASTE_KEY_HERE --kb-name ChemEng-Library --watch --watch-interval 60
```

- `--watch` makes this run forever: it does the initial full 1TB sweep, then
  rescans the folder tree every N minutes (here, 60) and ingests anything
  new, changed, or previously failed. This is how we cover the lack of a
  native folder-watcher in RAGFlow — RAGFlow itself has no connector that
  watches a filesystem path, it's upload/API-only, so this script's watch
  loop is what keeps the knowledge base in sync as he adds PDFs over time.
  Without `--watch` it's a one-shot run you'd need to remember to re-run.
- If you made a separate scanned-docs KB, run a **second, separate** instance
  of this script (different terminal/task) pointed at that subfolder with
  `--kb-name ChemEng-Library-Scanned` and its own `--checkpoint-db` file.
- **Safe to interrupt** (Ctrl+C, PC restart, crash) at any time — re-running
  the exact same command resumes from `ingest_checkpoint.db` and skips
  everything already ingested and unchanged.
- Expect the **first pass** to run for a long time (hours to days depending on
  file count and CPU) — that's expected and fine. Subsequent rescans are fast
  since only new/changed files get re-uploaded.
- **Run it as a Scheduled Task so it survives reboots and logoffs without you
  needing to keep a terminal open:**
  ```powershell
  $action = New-ScheduledTaskAction -Execute "python.exe" `
    -Argument '"C:\Setup\pdf-rag\ingest_folder.py" --root "D:\ChemLibrary" --api-key PASTE_KEY_HERE --kb-name ChemEng-Library --watch --watch-interval 60' `
    -WorkingDirectory "C:\Setup\pdf-rag"
  $trigger = New-ScheduledTaskTrigger -AtLogOn
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
  Register-ScheduledTask -TaskName "ChemLibrary PDF Ingestion" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest
  ```
  This starts the watcher automatically at login and lets it run indefinitely
  (`ExecutionTimeLimit` zero = no timeout). Check on it anytime with:
  ```powershell
  Get-ScheduledTask -TaskName "ChemLibrary PDF Ingestion" | Get-ScheduledTaskInfo
  ```
  To stop it: `Stop-ScheduledTask -TaskName "ChemLibrary PDF Ingestion"` (or
  just `Unregister-ScheduledTask` to remove it entirely).

### F. Give him the shortcut

```powershell
.\04-create-shortcut.ps1
```

This creates a **"Chemical Library Search"** desktop icon that opens
`http://localhost:9380` directly, and makes Docker Desktop auto-launch on
login so the search UI is always available after a reboot (takes ~1-2 min to
come back up after a fresh boot).

---

## His day-to-day experience from here on

1. Double-click **"Chemical Library Search"** on the Desktop.
2. Click into the `ChemEng-Library` knowledge base (or just use the global
   search if you configure it that way).
3. Type a query — exact terms (formulas, reagent names, standards) or plain
   English descriptions both work.
4. Click any result to see the PDF open with the matching passage highlighted.

No command line, no Docker, no terminal — ever, on his side.

---

## Maintenance / troubleshooting notes for you

- **New PDFs added later:** nothing to do — if the Scheduled Task is running
  in `--watch` mode, it picks up new/changed files on its next scheduled
  rescan automatically. If you didn't set up the watcher, just re-run the
  same `ingest_folder.py` command manually anytime.
- **Check failures:** open `ingest_checkpoint.db` with any SQLite browser (or
  `sqlite3 ingest_checkpoint.db "select * from files where status='failed';"`)
  to see which files errored and why, then re-run to retry them.
- **Stack status:**
  ```powershell
  cd C:\RAGFlow\ragflow\docker
  docker compose -f docker-compose.yml -f docker-compose.override.yml ps
  docker compose -f docker-compose.yml -f docker-compose.override.yml logs -f ragflow
  ```
- **Full restart:**
  ```powershell
  docker compose -f docker-compose.yml -f docker-compose.override.yml restart
  ```
- **If RAGFlow runs out of memory during ingestion:** lower `--batch-size` in
  the ingest command (default 20, try 5-10), and/or bump `.wslconfig` memory
  if his PC has RAM to spare.
- **Adding AI-assisted search later:** Ollama is already installed and running
  (used for embeddings). Just pull a chat model too (e.g.
  `ollama pull llama3.1:8b`), add it as a second Model Provider entry in
  RAGFlow (model type `chat` this time, same `http://host.docker.internal:11434`
  base URL), then switch a Knowledge Base's chat assistant to use it. No
  re-ingestion required — the existing chunks/embeddings are reused as-is.

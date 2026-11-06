# Chemical/Engineering PDF Search (RAGFlow, Offline, Windows)

This folder contains everything needed to stand up a local, offline, search-only
RAG system over a large PDF library (chemistry/engineering papers, patents,
scans) on a Windows 10/11 PC. No external network access required after setup
images are pulled.

## What this gives him

- A browser tab (bookmark/desktop shortcut) → type a search → get ranked
  results with the matching PDF page shown highlighted, side by side.
- Hybrid search (keyword/exact formula match + semantic/conceptual match) via
  the `bge-m3` embedding model, fully local (no API keys, no cloud calls).
- No LLM required for this phase — pure retrieval. An LLM (local Ollama) can
  be bolted on later without re-indexing anything.

## Files in this folder

| File | Purpose |
|---|---|
| `01-install-prereqs.ps1` | Installs WSL2, Docker Desktop, enables virtualization prerequisites. Run FIRST, then reboot. |
| `docker-compose.override.yml` | RAGFlow resource/network tuning for a single offline workstation. |
| `02-start-ragflow.ps1` | Pulls RAGFlow images, starts the stack, waits for health check, prints the URL. |
| `03-configure-embedding.md` | One-time manual step: set `bge-m3` as the embedding model in the RAGFlow UI (can't be scripted — it's a UI config step). |
| `ingest_folder.py` | Batch-ingests a huge folder tree of PDFs via the RAGFlow API, with a resume/checkpoint log so it survives reboots/crashes. |
| `04-create-shortcut.ps1` | Creates a desktop shortcut + Start Menu entry that opens the RAGFlow search UI in the default browser. |
| `SETUP-GUIDE.md` | Full step-by-step walkthrough in order, written for someone doing this remotely over a support session. |

## Quick path (see SETUP-GUIDE.md for detail)

```powershell
# 1. As Administrator, from this folder:
.\01-install-prereqs.ps1
# reboot when it says to

# 2. After reboot, as Administrator:
.\02-start-ragflow.ps1

# 3. Open http://localhost:9380 in a browser, follow 03-configure-embedding.md

# 4. Kick off the big ingestion job (can run for days, safe to interrupt/resume):
python ingest_folder.py --root "D:\ChemLibrary" --api-key <KEY_FROM_UI>

# 5. Create his desktop shortcut:
.\04-create-shortcut.ps1
```

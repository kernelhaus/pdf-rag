# Step 3: Configure Embedding Model + API Key (one-time, manual, via UI)

RAGFlow does **not** bundle `bge-m3` as a ready-to-run model — it only
*orchestrates* retrieval/chunking/UI. Actually running the embedding model
requires a separate inference backend that RAGFlow calls over HTTP: we use
**Ollama**, installed on the Windows host (not inside Docker), since that's
the simplest to manage and reuse later if you add chat.

This step can't be fully scripted because wiring the provider into RAGFlow
requires its web UI the first time. Total time: ~10 minutes.

## 0. Install Ollama and pull bge-m3 (on the Windows host, before anything else)

```powershell
winget install --id Ollama.Ollama -e --source winget --accept-package-agreements --accept-source-agreements
# Restart the terminal if 'ollama' isn't recognized yet, then:
ollama pull bge-m3
```

Verify it's serving:
```powershell
curl http://localhost:11434/api/tags
```
You should see `bge-m3` listed. Ollama listens on port 11434 by default and
auto-starts in the background after install — no need to keep a terminal open.

**Important — Docker-to-host networking:** RAGFlow runs inside Docker
containers, so it can't reach `localhost:11434` (that's the container's own
loopback, not the host's). Use `http://host.docker.internal:11434` as the
base URL when adding the provider in the next step — Docker Desktop on
Windows resolves this automatically to the host machine.

## 1. Create the admin account

1. Open a browser to **http://localhost:9380**
2. Register the first account (this becomes the admin — no email verification
   needed in offline mode, any email format works, e.g. `admin@local`).

## 2. Add Ollama as a model provider and select bge-m3

1. Click your avatar (top-right) → **Model Providers**.
2. Find **Ollama** in the provider list and click **Add**.
3. Fill in:
   - **Model type:** `embedding`
   - **Model name:** `bge-m3`
   - **Base URL:** `http://host.docker.internal:11434`
4. Save, then confirm it shows as available (RAGFlow does a quick ping/test
   call when you save).

## 3. Create the Knowledge Base

1. Go to **Knowledge Base** → **Create Knowledge Base**.
2. Name it e.g. `ChemEng-Library`.
3. Under **Configuration**:
   - **Embedding model:** `bge-m3` (select the Ollama-provided one you just
     added, usually shown as `bge-m3 (Ollama)` in the dropdown)
   - **Chunk method:** `General` for born-digital PDFs. If a meaningful chunk
     of the 1TB is old scanned documents, create a SECOND knowledge base named
     `ChemEng-Library-Scanned` with chunk method `General` + **OCR enabled**,
     since OCR'd scans benefit from different parsing settings and you don't
     want one bad scan slowing down the whole batch's parser profile.
   - **Layout recognition:** leave ON (needed for tables/equations/figures).
4. Save.

## 4. Generate an API key (needed for the batch ingestion script)

1. Go to your avatar → **API** (or **Settings → API Keys**).
2. Click **Create new API Key**.
3. Copy it somewhere safe — you'll pass it to `ingest_folder.py` as
   `--api-key`.
4. Also note the **Knowledge Base ID** shown in the URL when you have the KB
   open (e.g. `http://localhost:9380/knowledgebase/<THIS_PART>`), or retrieve
   it via the API as shown in `ingest_folder.py`'s `--list-kb` helper mode.

## 5. Sanity test before the big run

1. Manually drag 2-3 PDFs into the Knowledge Base via the UI.
2. Wait for them to show status "Done" (parsing + embedding complete).
3. Go to **Retrieval testing** (left sidebar within the Knowledge Base) and
   run a real query he'd actually use. Confirm:
   - Results come back ranked with relevance scores.
   - Clicking a result opens the PDF with the matching text highlighted.

Once this works, proceed to the full 1TB ingestion with `ingest_folder.py`.

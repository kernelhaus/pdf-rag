#!/usr/bin/env python3
"""
Batch-ingest a huge folder tree of PDFs into a RAGFlow Knowledge Base via its
REST API, with a resumable checkpoint so it can run unattended for days and
survive reboots, crashes, or Ctrl+C without re-uploading finished files.

Usage:
    # One-shot: scan once, ingest everything new, then exit.
    python ingest_folder.py --root "D:\\ChemLibrary" --api-key YOUR_KEY --kb-name ChemEng-Library

    # Watch mode: do the initial 1TB sweep, then keep running forever,
    # rescanning the folder tree every N minutes and ingesting anything new
    # or changed. This is the "point it at the folder and forget it" mode —
    # run it once as a background/scheduled task and it keeps the knowledge
    # base in sync indefinitely as he adds more PDFs over time.
    python ingest_folder.py --root "D:\\ChemLibrary" --api-key YOUR_KEY --kb-name ChemEng-Library --watch --watch-interval 30

    # List available knowledge bases (to find the right --kb-name / --kb-id):
    python ingest_folder.py --api-key YOUR_KEY --list-kb

Requirements:
    pip install requests tqdm

Notes:
    - RAGFlow itself has NO folder-watcher / filesystem connector — it is
      upload-only (UI drag-drop or its REST API). This script is what plays
      that role instead.
    - Safe to stop (Ctrl+C) and re-run any time; it skips files already marked
      done in the checkpoint DB and resumes exactly where it left off.
    - Change detection is by file path + modified-time + size, not just path
      existing — so if he replaces a PDF with a revised version at the same
      path, it will be detected and re-ingested as a new document.
    - Default RAGFlow host is http://localhost:9380 — change with --host if
      ingesting from a different machine on the same LAN.
    - This script only UPLOADS + triggers parsing. RAGFlow's own background
      workers do the chunking/embedding; this script polls until each batch's
      parse jobs finish before moving to the next batch, so you get accurate
      progress and don't flood the server with thousands of simultaneous jobs.
    - Deliberately uses periodic rescanning rather than a live filesystem
      watcher (e.g. watchdog/inotify): for a 1TB/100k+ file tree that may
      live on a network drive or external disk, event-based watchers are
      unreliable (missed events, driver limits) and don't survive process
      restarts. A full directory walk is cheap compared to the embedding
      work anyway, and it naturally self-heals after any crash or reboot.
"""

import argparse
import os
import sqlite3
import sys
import time
from pathlib import Path

import requests
from tqdm import tqdm

DEFAULT_HOST = "http://localhost:9380"
CHECKPOINT_DB = "ingest_checkpoint.db"
BATCH_SIZE = 20          # files per upload batch, keeps memory/requests sane
POLL_INTERVAL_SEC = 15   # how often to check parse status for a batch
MAX_POLL_MINUTES = 60    # give up waiting on a stuck batch after this long


def init_checkpoint_db(path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS files (
            path TEXT PRIMARY KEY,
            status TEXT NOT NULL,       -- pending | uploaded | parsed | failed
            doc_id TEXT,
            error TEXT,
            mtime REAL,
            size INTEGER,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
        """
    )
    # Migrate older checkpoint DBs that predate mtime/size columns
    existing_cols = {row[1] for row in conn.execute("PRAGMA table_info(files)")}
    if "mtime" not in existing_cols:
        conn.execute("ALTER TABLE files ADD COLUMN mtime REAL")
    if "size" not in existing_cols:
        conn.execute("ALTER TABLE files ADD COLUMN size INTEGER")
    conn.commit()
    return conn


def discover_pdfs(root: str) -> list[Path]:
    root_path = Path(root)
    if not root_path.exists():
        print(f"ERROR: root path does not exist: {root}", file=sys.stderr)
        sys.exit(1)
    return sorted(root_path.rglob("*.pdf"))


def needs_ingest(conn: sqlite3.Connection, path: Path) -> bool:
    """True if this file is new, previously failed, or changed since last ingest."""
    row = conn.execute(
        "SELECT status, mtime, size FROM files WHERE path = ?", (str(path),)
    ).fetchone()
    if row is None:
        return True
    status, old_mtime, old_size = row
    if status not in ("uploaded", "parsed"):
        return True
    try:
        st = path.stat()
    except OSError:
        return False  # file vanished mid-scan; skip this cycle
    if old_mtime is None or old_size is None:
        return True
    return (abs(st.st_mtime - old_mtime) > 1.0) or (st.st_size != old_size)


def mark(conn: sqlite3.Connection, path: Path, status: str, doc_id: str = None, error: str = None):
    try:
        st = path.stat()
        mtime, size = st.st_mtime, st.st_size
    except OSError:
        mtime, size = None, None
    conn.execute(
        """
        INSERT INTO files (path, status, doc_id, error, mtime, size, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(path) DO UPDATE SET
            status=excluded.status,
            doc_id=excluded.doc_id,
            error=excluded.error,
            mtime=excluded.mtime,
            size=excluded.size,
            updated_at=CURRENT_TIMESTAMP
        """,
        (str(path), status, doc_id, error, mtime, size),
    )
    conn.commit()


def get_kb_id(host: str, api_key: str, kb_name: str) -> str:
    resp = requests.get(
        f"{host}/api/v1/datasets",
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json().get("data", [])
    for kb in data:
        if kb.get("name") == kb_name:
            return kb["id"]
    print(f"ERROR: no knowledge base named '{kb_name}' found. Available:", file=sys.stderr)
    for kb in data:
        print(f"  - {kb.get('name')} (id={kb.get('id')})", file=sys.stderr)
    sys.exit(1)


def list_kbs(host: str, api_key: str):
    resp = requests.get(
        f"{host}/api/v1/datasets",
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json().get("data", [])
    if not data:
        print("No knowledge bases found. Create one in the RAGFlow UI first.")
        return
    print("Available knowledge bases:")
    for kb in data:
        print(f"  - {kb.get('name')}  (id={kb.get('id')})")


def upload_batch(host: str, api_key: str, kb_id: str, files: list[Path]) -> dict:
    """Uploads a batch of files, returns {path: doc_id} for successes."""
    url = f"{host}/api/v1/datasets/{kb_id}/documents"
    handles = []
    results = {}
    try:
        for f in files:
            handles.append(("file", (f.name, open(f, "rb"), "application/pdf")))
        resp = requests.post(
            url,
            headers={"Authorization": f"Bearer {api_key}"},
            files=handles,
            timeout=600,
        )
        resp.raise_for_status()
        body = resp.json()
        docs = body.get("data", [])
        # RAGFlow returns docs in the same order submitted
        for f, doc in zip(files, docs):
            results[str(f)] = doc.get("id")
    finally:
        for _, (_, fh, _) in handles:
            fh.close()
    return results


def trigger_parse(host: str, api_key: str, kb_id: str, doc_ids: list[str]):
    url = f"{host}/api/v1/datasets/{kb_id}/chunks"
    resp = requests.post(
        url,
        headers={"Authorization": f"Bearer {api_key}"},
        json={"document_ids": doc_ids},
        timeout=60,
    )
    resp.raise_for_status()


def poll_until_parsed(host: str, api_key: str, kb_id: str, doc_ids: list[str]) -> dict:
    """Returns {doc_id: status} once all are done/failed or timeout reached."""
    url = f"{host}/api/v1/datasets/{kb_id}/documents"
    deadline = time.time() + MAX_POLL_MINUTES * 60
    pending = set(doc_ids)
    final = {}

    while pending and time.time() < deadline:
        resp = requests.get(
            url,
            headers={"Authorization": f"Bearer {api_key}"},
            params={"id": list(pending)},
            timeout=30,
        )
        resp.raise_for_status()
        for doc in resp.json().get("data", {}).get("docs", []):
            status = doc.get("run")  # RAGFlow statuses: UNSTART/RUNNING/DONE/FAIL
            if status in ("DONE", "FAIL"):
                final[doc["id"]] = status
                pending.discard(doc["id"])
        if pending:
            time.sleep(POLL_INTERVAL_SEC)

    for doc_id in pending:
        final[doc_id] = "TIMEOUT"
    return final


def run_one_pass(conn: sqlite3.Connection, host: str, api_key: str, kb_id: str,
                  root: str, batch_size: int) -> tuple[int, int]:
    """Scans root, ingests everything new/changed. Returns (ingested, failed)."""
    print(f"Scanning {root} for PDFs (this may take a while on 1TB+ trees)...")
    all_pdfs = discover_pdfs(root)
    print(f"Found {len(all_pdfs)} PDF files.")

    todo = [p for p in all_pdfs if needs_ingest(conn, p)]
    print(f"{len(all_pdfs) - len(todo)} already up to date, {len(todo)} to ingest.")

    if not todo:
        return 0, 0

    failures = 0
    ingested = 0
    with tqdm(total=len(todo), unit="file") as pbar:
        for i in range(0, len(todo), batch_size):
            batch = todo[i : i + batch_size]
            try:
                uploaded = upload_batch(host, api_key, kb_id, batch)
            except Exception as e:
                for f in batch:
                    mark(conn, f, "failed", error=str(e))
                    failures += 1
                pbar.update(len(batch))
                continue

            for f in batch:
                doc_id = uploaded.get(str(f))
                if doc_id:
                    mark(conn, f, "uploaded", doc_id=doc_id)
                else:
                    mark(conn, f, "failed", error="no doc_id returned")
                    failures += 1

            doc_ids = [d for d in uploaded.values() if d]
            if doc_ids:
                try:
                    trigger_parse(host, api_key, kb_id, doc_ids)
                    statuses = poll_until_parsed(host, api_key, kb_id, doc_ids)
                    for f in batch:
                        doc_id = uploaded.get(str(f))
                        if not doc_id:
                            continue
                        status = statuses.get(doc_id, "UNKNOWN")
                        if status == "DONE":
                            mark(conn, f, "parsed", doc_id=doc_id)
                            ingested += 1
                        else:
                            mark(conn, f, "failed", doc_id=doc_id, error=f"parse status: {status}")
                            failures += 1
                except Exception as e:
                    for f in batch:
                        mark(conn, f, "failed", error=f"parse trigger error: {e}")
                        failures += 1

            pbar.update(len(batch))

    return ingested, failures


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", help="Root folder to recursively scan for PDFs")
    ap.add_argument("--api-key", required=True, help="RAGFlow API key")
    ap.add_argument("--kb-name", default="ChemEng-Library", help="Knowledge base name")
    ap.add_argument("--host", default=DEFAULT_HOST, help="RAGFlow host URL")
    ap.add_argument("--list-kb", action="store_true", help="List knowledge bases and exit")
    ap.add_argument("--checkpoint-db", default=CHECKPOINT_DB)
    ap.add_argument("--batch-size", type=int, default=BATCH_SIZE)
    ap.add_argument("--watch", action="store_true",
                     help="After the initial sweep, keep running and rescan "
                          "the folder periodically forever (Ctrl+C to stop).")
    ap.add_argument("--watch-interval", type=int, default=30,
                     help="Minutes between rescans in --watch mode (default: 30)")
    args = ap.parse_args()

    if args.list_kb:
        list_kbs(args.host, args.api_key)
        return

    if not args.root:
        print("ERROR: --root is required unless using --list-kb", file=sys.stderr)
        sys.exit(1)

    conn = init_checkpoint_db(args.checkpoint_db)
    kb_id = get_kb_id(args.host, args.api_key, args.kb_name)

    if not args.watch:
        ingested, failures = run_one_pass(conn, args.host, args.api_key, kb_id, args.root, args.batch_size)
        print("")
        if ingested == 0 and failures == 0:
            print("Nothing to do. All files already ingested and unchanged.")
        else:
            print(f"Done. {ingested} ingested, {failures} failed — check "
                  f"{args.checkpoint_db} (table 'files', status='failed') for details.")
            print("Re-run this exact command any time to retry failed/pending files; "
                  "successfully parsed, unchanged files are skipped automatically.")
        return

    # --watch mode: run forever, rescanning on an interval. This is the
    # "point it at the folder and forget it" mode for ongoing ingestion.
    print(f"Watch mode: initial sweep now, then rescanning every "
          f"{args.watch_interval} minutes. Press Ctrl+C to stop.")
    try:
        while True:
            start = time.time()
            ingested, failures = run_one_pass(conn, args.host, args.api_key, kb_id, args.root, args.batch_size)
            elapsed = time.time() - start
            print(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] Pass complete: "
                  f"{ingested} ingested, {failures} failed, took {elapsed/60:.1f} min.")
            print(f"Sleeping {args.watch_interval} minutes until next scan "
                  f"(Ctrl+C to stop)...\n")
            time.sleep(args.watch_interval * 60)
    except KeyboardInterrupt:
        print("\nWatch mode stopped by user. Safe to re-run anytime; "
              "already-ingested files will be skipped.")


if __name__ == "__main__":
    main()

"""End-to-end check against a live RAGFlow: register, login, API key, dataset,
upload PDFs, parse, wait, retrieval query. Exits non-zero on any failure.

Usage: python tests/e2e.py --host http://localhost --pdfs tests/samples [--embd MODEL]
"""
import argparse, json, sys, time
from pathlib import Path
import requests

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="http://localhost")
ap.add_argument("--pdfs", required=True)
ap.add_argument("--embd", default="")
ap.add_argument("--limit", type=int, default=5)
ap.add_argument("--query", default="electrode potential")
a = ap.parse_args()
H = a.host.rstrip("/")
EMAIL, PW = "ci@example.com", "ci-password-123"

def die(msg, r=None):
    print("FAIL:", msg, (r.status_code, r.text[:800]) if r is not None else "")
    sys.exit(1)

# wait for server
for i in range(120):
    try:
        if requests.get(f"{H}/api/v1/system/ping", timeout=5).status_code < 500:
            break
    except Exception:
        pass
    time.sleep(5)
else:
    die("server never came up")

r = requests.post(f"{H}/api/v1/users", json={"email": EMAIL, "nickname": "ci", "password": PW})
print("register", r.status_code, r.text[:200])
r = requests.post(f"{H}/api/v1/auth/login", json={"email": EMAIL, "password": PW})
tok = r.headers.get("Authorization")
if not tok:
    die("login", r)
r = requests.post(f"{H}/api/v1/system/tokens", headers={"Authorization": tok})
print("token", r.status_code, r.text[:300])
key = r.json()["data"]["token"]
auth = {"Authorization": f"Bearer {key}"}
Path("api_key.txt").write_text(key)

body = {"name": "ci-kb", "parse_type": 1, "parser_id": "general"}
if a.embd:
    body["embedding_model"] = a.embd
r = requests.post(f"{H}/api/v1/datasets", headers=auth, json=body)
print("dataset", r.status_code, r.text[:400])
if r.status_code != 200 or r.json().get("code") != 0:
    die("create dataset", r)
kb = r.json()["data"]["id"]

pdfs = sorted(Path(a.pdfs).glob("*.pdf"))[: a.limit]
r = requests.post(f"{H}/api/v1/datasets/{kb}/documents", headers=auth,
                  files=[("file", (p.name, p.open("rb"), "application/pdf")) for p in pdfs])
print("upload", r.status_code, r.text[:400])
ids = [d["id"] for d in r.json()["data"]]
r = requests.post(f"{H}/api/v1/datasets/{kb}/documents/parse", headers=auth, json={"document_ids": ids})
print("parse", r.status_code, r.text[:300])
if r.status_code != 200 or r.json().get("code") != 0:
    die("parse trigger", r)

deadline = time.time() + 40 * 60
while time.time() < deadline:
    r = requests.get(f"{H}/api/v1/datasets/{kb}/documents", headers=auth, params={"page_size": 100})
    docs = r.json()["data"]["docs"]
    st = {d["name"]: (d.get("run"), d.get("progress"), d.get("chunk_count")) for d in docs}
    print(json.dumps(st)[:600])
    if all(d.get("run") in ("DONE", "FAIL", "3", "4") for d in docs):
        break
    time.sleep(20)
bad = [d["name"] for d in docs if d.get("run") not in ("DONE", "3")]
if bad:
    die(f"documents not DONE: {bad}")

r = requests.post(f"{H}/api/v1/retrieval", headers=auth,
                  json={"dataset_ids": [kb], "question": a.query, "page_size": 5})
print("retrieval", r.status_code, r.text[:600])
chunks = r.json().get("data", {}).get("chunks", [])
if not chunks:
    die("retrieval returned no chunks", r)
print(f"OK: {len(docs)} docs parsed, {len(chunks)} chunks returned for {a.query!r}")

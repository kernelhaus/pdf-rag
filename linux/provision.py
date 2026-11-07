#!/usr/bin/env python3
"""Idempotent first-run setup of RAGFlow: admin account, API key, default
embedding model, and the library knowledge base. Stdlib only.

Writes the API key to /etc/pdfsearch/api_key (mode 600).
"""
import argparse, json, os, sys, time, urllib.error, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--conf", default="/etc/pdfsearch/pdfsearch.conf")
ap.add_argument("--host", default="http://localhost")
ap.add_argument("--key-file", default="/etc/pdfsearch/api_key")
ap.add_argument("--wait-minutes", type=int, default=30)
a = ap.parse_args()

conf = {}
for line in open(a.conf):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        conf[k.strip()] = v.strip()

H = a.host.rstrip("/")


def _json(raw):
    """Parse JSON if possible; plain-text bodies (e.g. ping) become {"raw": ...}."""
    try:
        v = json.loads(raw or b"{}")
        return v if isinstance(v, dict) else {"raw": v}
    except ValueError:
        return {"raw": raw[:300].decode(errors="replace")}


def call(method, path, body=None, headers=None, raw=False):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(H + path, data=data, method=method,
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return (r.status, dict(r.headers), _json(r.read()))
    except urllib.error.HTTPError as e:
        txt = e.read()
        return (e.code, dict(e.headers), _json(txt))


print("Waiting for RAGFlow to come up...")
deadline = time.time() + a.wait_minutes * 60
last = None
while True:
    try:
        if call("GET", "/api/v1/system/ping")[0] < 500:
            break
    except Exception as e:
        if str(e) != last:
            last = str(e)
            print("  not ready yet:", last, flush=True)
    if time.time() > deadline:
        sys.exit("RAGFlow did not become ready in time (check: docker compose ps in /opt/ragflow/docker)")
    time.sleep(5)

email, pw = conf["ADMIN_EMAIL"], conf["ADMIN_PASSWORD"]
st, _, body = call("POST", "/api/v1/users", {"email": email, "nickname": "admin", "password": pw})
print("register:", st, body.get("message", ""))
st, hdr, body = call("POST", "/api/v1/auth/login", {"email": email, "password": pw})
tok = {k.lower(): v for k, v in hdr.items()}.get("authorization")
if not tok:
    sys.exit(f"login failed: {body}")

key = None
if os.path.exists(a.key_file):
    cand = open(a.key_file).read().strip()
    if cand and call("GET", "/api/v1/datasets", headers={"Authorization": f"Bearer {cand}"})[0] == 200:
        key = cand
if not key:
    st, _, body = call("POST", "/api/v1/system/tokens", headers={"Authorization": tok})
    if st != 200:
        sys.exit(f"could not create API key: {st} {body}")
    key = body["data"]["token"]
    os.makedirs(os.path.dirname(a.key_file), exist_ok=True)
    with open(a.key_file, "w") as f:
        f.write(key)
    os.chmod(a.key_file, 0o600)
print("api key ready:", a.key_file)

model = conf.get("TEI_MODEL", "BAAI/bge-small-en-v1.5")
st, _, body = call("PATCH", "/api/v1/models/default", {
    "model_provider": "Builtin", "model_instance": "Local",
    "model_type": "embedding", "model_name": model}, {"Authorization": tok})
print("default embedding:", st, body.get("message", ""))

auth = {"Authorization": f"Bearer {key}"}
kb = conf.get("KB_NAME", "Library")
st, _, body = call("GET", "/api/v1/datasets", headers=auth)
names = {d.get("name") for d in (body.get("data") or [])}
if kb in names:
    print("knowledge base exists:", kb)
else:
    st, _, body = call("POST", "/api/v1/datasets", {
        "name": kb, "parse_type": 1, "parser_id": "general",
        "embedding_model": f"{model}@Local@Builtin"}, auth)
    if st != 200 or body.get("code") != 0:
        sys.exit(f"could not create knowledge base: {st} {body}")
    print("knowledge base created:", kb)
print("PROVISION OK")

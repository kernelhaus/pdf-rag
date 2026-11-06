"""Download the open-access arXiv sample PDFs listed in sample_ids.txt.

Used by CI and for local pilots. Not committed to git (licences vary).
Usage: python tests/fetch_samples.py [dest_dir]
"""
import sys, time, urllib.request
from pathlib import Path

here = Path(__file__).parent
dest = Path(sys.argv[1] if len(sys.argv) > 1 else here / "samples")
dest.mkdir(parents=True, exist_ok=True)
ok = 0
for line in (here / "sample_ids.txt").read_text().split():
    out = dest / (line.replace("/", "_") + ".pdf")
    if out.exists():
        ok += 1
        continue
    aid = line.replace("_", "/", 1) if line.startswith(("astro-ph_", "math_")) else line
    req = urllib.request.Request(f"https://arxiv.org/pdf/{aid}", headers={"User-Agent": "Mozilla/5.0"})
    try:
        data = urllib.request.urlopen(req, timeout=60).read()
    except Exception as e:
        print("skip", aid, e)
        continue
    if data[:4] == b"%PDF":
        out.write_bytes(data)
        ok += 1
    time.sleep(3)
print(f"{ok} PDFs in {dest}")

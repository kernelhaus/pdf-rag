# pdf-rag

Offline, search-only PDF library for Windows. Wraps [RAGFlow](https://github.com/infiniflow/ragflow) (pinned `v1.0.0-rc3`) with local embeddings, in a dedicated WSL2 distro installed by a small wizard.

- **Users:** download `PDFSearch-Setup.exe` from the Releases page and read `SETUP-GUIDE.md`.
- `windows/` installer (Inno Setup), WSL2 setup, launcher, diagnostics
- `linux/` stack installer, provisioning, systemd indexer (runs inside WSL)
- `ingest_folder.py` folder scanner/uploader with resume and `--watch`
- `tests/` end-to-end tests; CI runs the real stack (`e2e-ragflow`, `linux-install`) and builds the installer (`windows-installer`)

Not covered by CI (needs a real x86 Windows PC): WSL2 import/boot, localhost forwarding, restart-and-resume.

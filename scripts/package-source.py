#!/usr/bin/env python3
"""Create a source-only archive; exclude builds, local notes and signing material."""
from pathlib import Path
import hashlib
import zipfile

root = Path(__file__).resolve().parent.parent
output = root / "dist" / "MacShot-Simple-0.1.2-source.zip"
output.parent.mkdir(exist_ok=True)
files = ["README.md", "README.en.md", "LICENSE", "NOTICE", "PRIVACY.md", "CONTRIBUTING.md", "SECURITY.md",
         "CHANGELOG.md", "DESIGN.md", "AGENTS.md", "CLAUDE.md", ".gitignore", "RELEASE-READINESS.md"]
folders = ["macshot", "macshotTests", "macshot.xcodeproj", "scripts", ".github"]
excluded_parts = {"xcuserdata", ".DS_Store", "__pycache__", ".git"}
paths = [root / name for name in files]
for folder in folders:
    paths.extend(p for p in (root / folder).rglob("*") if p.is_file()
                 and not excluded_parts.intersection(p.relative_to(root).parts))
for path in paths:
    if not path.is_file():
        raise SystemExit(f"Missing required source: {path.name}")
    if path.suffix.lower() in {".p12", ".pem", ".key", ".mobileprovision", ".pyc"}:
        raise SystemExit(f"Refusing signing material: {path.name}")
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(paths):
        archive.write(path, Path("MacShot-Simple") / path.relative_to(root))
checksum = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_suffix(".zip.sha256").write_text(f"{checksum}  {output.name}\n")
print(f"Source archive: {output.name}, {len(paths)} files, {output.stat().st_size} bytes")

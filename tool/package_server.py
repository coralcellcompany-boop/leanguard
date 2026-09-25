#!/usr/bin/env python3
"""Package only allowlisted, public server/landing sources for VPS deployment."""
from __future__ import annotations

import hashlib
import io
import json
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "leanguard-server.tar.gz"


def public_metadata(info: tarfile.TarInfo) -> tarfile.TarInfo:
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    return info


def main() -> None:
    files: list[Path] = []
    for directory in [
        "backend/src", "backend/scripts", "backend/migrations", "backend/test",
        "backend/deploy", "landing/dist", "docs",
    ]:
        files.extend(path for path in (ROOT / directory).rglob("*") if path.is_file())
    files.extend(ROOT / name for name in [
        "backend/package.json", "backend/package-lock.json", "backend/tsconfig.json",
        "backend/Dockerfile", "backend/.dockerignore", "backend/compose.yml",
        "backend/.env.example", "landing/Dockerfile", "landing/Caddyfile",
        "landing/compose.yaml", "landing/.env.example", "landing/README.md",
        "README.md", "FEATURE_MATRIX.md", "dart_defines.example.json",
    ])
    # Explicitly include deployment overrides, without collecting local .envs.
    files.extend((ROOT / "backend").glob("compose.*.yml"))
    files = sorted(set(files))
    manifest = {}
    for path in files:
        relative = path.relative_to(ROOT)
        if path.is_symlink() or not path.is_file():
            raise RuntimeError(f"Missing or linked source: {relative}")
        if "secrets" in relative.parts or "node_modules" in relative.parts:
            raise RuntimeError(f"Unexpected private/runtime path: {relative}")
        if path.name.startswith(".env") and path.name != ".env.example":
            raise RuntimeError(f"Unexpected environment file: {relative}")
        manifest[str(relative)] = hashlib.sha256(path.read_bytes()).hexdigest()
    OUTPUT.parent.mkdir(exist_ok=True)
    with tarfile.open(OUTPUT, "w:gz") as archive:
        for path in files:
            archive.add(path, arcname=str(path.relative_to(ROOT)), recursive=False,
                        filter=public_metadata)
        content = (json.dumps(manifest, indent=2) + "\n").encode()
        info = tarfile.TarInfo("SOURCE_SHA256.json")
        info.size, info.mode = len(content), 0o644
        archive.addfile(info, io.BytesIO(content))
    # Verify the shipped bytes, not only the source paths.
    with tarfile.open(OUTPUT, "r:gz") as archive:
        for name, digest in manifest.items():
            assert hashlib.sha256(archive.extractfile(name).read()).hexdigest() == digest
    print(f"{OUTPUT}\n{len(files)} public source files; SHA-256 manifest verified.")


if __name__ == "__main__":
    main()

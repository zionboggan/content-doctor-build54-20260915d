#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import glob
import hashlib
import json
import os
import subprocess
from pathlib import Path


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git_value(args: list[str], cwd: Path) -> str:
    try:
        return subprocess.check_output(["git", *args], cwd=cwd, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


def file_digest(repo: Path, rel: str) -> str | None:
    path = repo / rel
    if not path.is_file():
        return None
    return sha256_file(path)


def artifact_entries(repo: Path, patterns: list[str]) -> list[dict[str, object]]:
    seen: set[Path] = set()
    entries: list[dict[str, object]] = []
    for pattern in patterns:
        for raw in glob.glob(str(repo / pattern), recursive=True):
            path = Path(raw)
            if not path.is_file():
                continue
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            rel = path.relative_to(repo).as_posix()
            entries.append(
                {
                    "path": rel,
                    "size_bytes": path.stat().st_size,
                    "sha256": sha256_file(path),
                }
            )
    return sorted(entries, key=lambda item: str(item["path"]))


def main() -> int:
    parser = argparse.ArgumentParser(description="Write an Iris build manifest.")
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--out", required=True)
    parser.add_argument("--artifact-glob", action="append", default=[])
    args = parser.parse_args()

    repo = Path(args.repo_root).resolve()
    out = Path(args.out)
    if not out.is_absolute():
        out = repo / out
    out.parent.mkdir(parents=True, exist_ok=True)

    manifest = {
        "schema": "iris-build-manifest-v1",
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "repository": os.environ.get("GITHUB_REPOSITORY") or git_value(["config", "--get", "remote.origin.url"], repo),
        "commit": os.environ.get("GITHUB_SHA") or git_value(["rev-parse", "HEAD"], repo),
        "ref": os.environ.get("GITHUB_REF") or git_value(["rev-parse", "--abbrev-ref", "HEAD"], repo),
        "run_id": os.environ.get("GITHUB_RUN_ID", ""),
        "toolchain": {
            "flutter_version": os.environ.get("FLUTTER_VERSION", ""),
            "java_version": os.environ.get("JAVA_VERSION", ""),
        },
        "locks": {
            "pubspec_lock_sha256": file_digest(repo, "pubspec.lock"),
        },
        "artifacts": artifact_entries(repo, args.artifact_glob),
    }

    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

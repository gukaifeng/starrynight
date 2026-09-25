#!/usr/bin/env python3
"""Download the pinned Unity package archives; no Unity account is accessed.

The download manifest is a staging record. Unity must still resolve, compile,
and import the project after the user activates an appropriate Editor license.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".local/dependencies/upm"
RECORD = ROOT / "docs/package-downloads.json"


def verify(path: Path, package: dict) -> dict:
    with path.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha1").hexdigest()
    if actual != package["sha1"]:
        raise ValueError(f"Checksum mismatch: {path.name}")
    with tarfile.open(path) as archive:
        metadata = json.load(archive.extractfile("package/package.json"))
    if (metadata["name"], metadata["version"]) != (package["name"], package["version"]):
        raise ValueError(f"Package identity mismatch: {path.name}")
    with path.open("rb") as stream:
        sha256 = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"name": package["name"], "version": package["version"],
            "bytes": path.stat().st_size, "sha256": sha256}


def prepare(package: dict, check_only: bool) -> dict:
    filename = f"{package['name']}-{package['version']}.tgz"
    target = CACHE / filename
    if not target.exists():
        if check_only:
            raise FileNotFoundError(f"Missing archive: {filename}")
        partial = target.with_suffix(".tgz.part")
        subprocess.run(["curl", "-L", "--fail", "--silent", "--show-error",
                        "--retry", "3", "--connect-timeout", "20", "--max-time", "1800",
                        package["url"], "-o", str(partial)], check=True)
        verify(partial, package)
        partial.replace(target)
    result = verify(target, package)
    print(f"Verified {filename} ({result['bytes']} bytes)", flush=True)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Verify existing files without downloading")
    args = parser.parse_args()
    record = json.loads(RECORD.read_text())
    CACHE.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(lambda package: prepare(package, args.check), record["packages"]))
    (CACHE / "verified.json").write_text(json.dumps(results, indent=2) + "\n")
    print("All pinned external package archives are ready. Editor validation is a separate step.")


if __name__ == "__main__":
    main()

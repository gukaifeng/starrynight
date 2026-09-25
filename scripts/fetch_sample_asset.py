#!/usr/bin/env python3
"""Fetch a pinned example model for the V0 prototype. Does not build an app.

Standard library only. Downloads are validated before atomic replacement.
This checks GLB container structure, not full glTF rendering correctness.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import struct
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = "https://raw.githubusercontent.com/mrdoob/three.js/r180/examples/models/gltf/RobotExpressive/"
MODEL_URL = BASE + "RobotExpressive.glb"
README_URL = BASE + "README.md"
MAX_BYTES = 32 * 1024 * 1024


def download(url: str, max_bytes: int = MAX_BYTES) -> bytes:
    error: Exception | None = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "iOS3DPrototype-AssetFetcher/1.0"})
            with urllib.request.urlopen(req, timeout=30) as response:
                blob = response.read(max_bytes + 1)
            if not blob or len(blob) > max_bytes:
                raise ValueError("Empty response or download exceeds size limit")
            return blob
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            error = exc
            if attempt < 2:
                time.sleep(1 + attempt)
    raise RuntimeError(f"Download failed: {url}: {error}")


def validate_glb(blob: bytes) -> dict:
    if len(blob) < 20:
        raise ValueError("Not a GLB: file is too short")
    magic, version, declared_length = struct.unpack_from("<4sII", blob, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(blob):
        raise ValueError("Invalid GLB magic, version, or total length; reject HTML/LFS pointer/truncated files")
    offset, chunks = 12, []
    while offset < len(blob):
        if offset + 8 > len(blob):
            raise ValueError("Truncated GLB chunk header")
        size, chunk_type = struct.unpack_from("<II", blob, offset)
        offset += 8
        if size % 4 != 0 or offset + size > len(blob):
            raise ValueError("Invalid GLB chunk boundary/alignment")
        chunks.append((chunk_type, blob[offset:offset + size]))
        offset += size
    if not chunks or chunks[0][0] != 0x4E4F534A:
        raise ValueError("First chunk is not JSON")
    model = json.loads(chunks[0][1].decode("utf-8").rstrip(" \t\r\n\x00"))
    if model.get("asset", {}).get("version") != "2.0" or not model.get("meshes"):
        raise ValueError("Expected a glTF 2.0 model with meshes")
    for collection in ("buffers", "images"):
        for entry in model.get(collection, []):
            uri = entry.get("uri")
            if uri and not uri.startswith("data:"):
                raise ValueError(f"Unexpected external dependency: {uri}; review before using offline")
    return model


def atomic_write(path: Path, blob: bytes) -> None:
    temp = path.with_name(path.name + ".tmp")
    try:
        temp.write_bytes(blob)
        temp.replace(path)
    finally:
        if temp.exists():
            temp.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("sample_asset"), help="Output directory")
    parser.add_argument("--force", action="store_true", help="Explicitly permit replacement of existing assets")
    args = parser.parse_args()
    destination = args.output.expanduser().resolve()
    destination.mkdir(parents=True, exist_ok=True)
    files = [destination / n for n in ("RobotExpressive.glb", "SOURCE_README.md", "asset-lock.json", "LICENSE_NOTICE.md")]
    if not args.force and any(p.exists() for p in files):
        raise RuntimeError("Output already contains an asset/notice. Review it first, or use --force deliberately.")
    blob = download(MODEL_URL)
    metadata = validate_glb(blob)
    source_readme = download(README_URL, max_bytes=128 * 1024)
    readme_text = source_readme.decode("utf-8")
    if "CC0" not in readme_text or "Laulh" not in readme_text:
        raise ValueError("Source README no longer matches the expected license/credit. Stop and review.")
    lock = {
        "asset_id": "robot_expressive", "repository": "https://github.com/mrdoob/three.js",
        "ref": "r180", "resolved_commit": None,
        "model_url": MODEL_URL, "readme_url": README_URL,
        "sha256": hashlib.sha256(blob).hexdigest(), "bytes": len(blob),
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(),
        "license_declared_by_source": "CC0-1.0",
        "author": "Tomás Laulhé (Quaternius)", "example_modifications": "Don McCurdy",
        "gltf_version": metadata["asset"]["version"],
        "mesh_count": len(metadata.get("meshes", [])),
        "animation_count": len(metadata.get("animations", [])),
        "validation": {"glb_container": "passed", "unity_import": "not_tested", "ios_rendering": "not_tested"},
        "notes": "Upstream tag pinned; content hash recorded after fetching. No animation is enabled by this script."
    }
    notice = "\n".join([
        "# RobotExpressive — provenance notice", "",
        "Creator: Tomás Laulhé (Quaternius).", "Example asset modifications: Don McCurdy.",
        "The pinned upstream README declares CC0 1.0 for this model.",
        "License: https://creativecommons.org/publicdomain/zero/1.0/", "",
        "Source: " + README_URL, "",
        "Local changes: none during download. Record any later model/material modifications.",
        "This notice preserves provenance; it does not imply endorsement by the creators.", ""
    ])
    atomic_write(files[0], blob)
    atomic_write(files[1], source_readme)
    atomic_write(files[2], json.dumps(lock, ensure_ascii=False, indent=2).encode("utf-8"))
    atomic_write(files[3], notice.encode("utf-8"))
    print(f"Saved to: {destination}")
    print(f"Bytes: {len(blob)}; SHA-256: {lock['sha256']}")
    print("Next: import in Unity Editor; verify materials; disable autoplay; test on an actual iPhone.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, ValueError, OSError, UnicodeError, struct.error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)

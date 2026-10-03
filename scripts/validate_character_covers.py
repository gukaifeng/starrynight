#!/usr/bin/env python3
"""Check authored covers against the shipped character and isolated collection catalogs."""
import json
import math
from pathlib import Path
import struct
import hashlib
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "ios/StarryNight/Resources"
ASSETS = ROOT / "ios/StarryNight/Assets.xcassets"


def main():
    catalog = json.loads((RESOURCES / "CharacterCoverCatalog.json").read_text())
    assert catalog["schemaVersion"] == 1, "Unsupported cover catalog version"
    covers = catalog["covers"]
    ids = [row["runtimeID"] for row in covers]
    characters = json.loads((RESOURCES / "CharacterCatalog.json").read_text())["characters"]
    collections = {row["modelID"]: row for row in json.loads((RESOURCES / "CharacterCollections.json").read_text())["collections"]}
    assert len(set(ids)) == len(ids), "Duplicate runtime character cover"
    assert set(ids) == {row["id"] for row in characters}, "Cover catalog must cover the shipped character set"
    report = json.loads((ROOT / "docs/verification/character-covers/render-report.json").read_text())
    rendered = {row["runtimeID"]: row for row in report["covers"] if row["runtimeID"] in ids}
    assert len(rendered) == len(covers) and sum(row["runtimeID"] in ids for row in report["covers"]) == len(covers), "Cover rendering evidence is incomplete"
    size_bytes = 0
    for cover in covers:
        runtime_id = cover["runtimeID"]
        collection = collections[runtime_id]
        assert cover["environmentID"] == collection["defaultEnvironment"], f"{runtime_id}: cover must use the authored default room"
        assert cover["environmentID"] in collection["environments"], f"{runtime_id}: room outside isolated collection"
        for key in ("focusX", "focusY"):
            assert math.isfinite(cover[key]) and 0 <= cover[key] <= 1, f"{runtime_id}: invalid {key}"
        folder = ASSETS / (cover["asset"] + ".imageset")
        entry = json.loads((folder / "Contents.json").read_text())["images"][0]
        data = (folder / entry["filename"]).read_bytes()
        with Image.open(folder / entry['filename']) as artwork:
            width,height=artwork.size;artwork.verify()
        if cover.get('source')=='author-supplied':
            assert min(width,height)>=256 and max(width,height)<=8192, f'{runtime_id}: source cover dimensions'
            assert hashlib.sha256(data).hexdigest()==cover['sourceSHA256'], f'{runtime_id}: source cover changed'
        elif cover.get('source')=='bailian-generated':
            assert (width,height)==(1536,2048), f'{runtime_id}: approved portrait dimensions'
            assert hashlib.sha256(data).hexdigest()==cover['sourceSHA256'], f'{runtime_id}: approved cover changed'
        else:assert (width,height)==(1024,768), f'{runtime_id}: unexpected render resolution'
        evidence = rendered[runtime_id]
        assert evidence["environmentID"] == cover["environmentID"] and evidence["asset"] == cover["asset"], f"{runtime_id}: stale rendering evidence"
        assert (evidence["width"], evidence["height"]) == (width, height)
        size_bytes += len(data)
    print(f"CHARACTER_COVERS_VALID count={len(covers)} bytes={size_bytes} explicit_runtime_bindings=true")


if __name__ == "__main__":
    main()

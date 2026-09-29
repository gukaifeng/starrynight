#!/usr/bin/env python3
"""Review captured Unity camera samples, not display FPS or all visual smoothness."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("logs", nargs="+", type=Path)
args = parser.parse_args()
reviews = []
for path in args.logs:
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    rows = [row for row in rows if row.get("name") == "layoutMotionSample" and row.get("sampleTime", 0) > 3]
    assert rows, f"No post-startup samples: {path}"
    failures = []
    for row in rows:
        viewport = row["renderViewport"]
        if any(abs(viewport[key] - expected) > 0.0001 for key, expected in [("x", 0), ("y", 0), ("width", 1), ("height", 1)]):
            failures.append("Renderer viewport changed")
        if abs(row["cameraFov"] - 35) > 0.001:
            failures.append("FOV changed")
        if row["cameraPosition"]["y"] <= 0:
            failures.append("Camera crossed below ground")
    for before, after in zip(rows, rows[1:]):
        if before["presentationId"] == after["presentationId"] and after["cameraSnapCount"] > before["cameraSnapCount"]:
            failures.append(f"Explicit camera snap at {after['sampleTime']}")
    aspects = [row["cameraAspect"] for row in rows]
    upper = [row for row in rows if not row["framingMotionActive"] and row["cameraAspect"] > 1
             and row["compositionArea"]["height"] < .4 and row["compositionArea"]["width"] < .7]
    if not upper:
        failures.append("No settled upper-stage keyboard samples")
    for row in upper:
        area = row["compositionArea"]
        if not (area["x"]-.025 <= row["headX"] <= area["x"]+area["width"]+.025
                and 1-area["y"]-area["height"]-.025 <= row["headY"] <= 1-area["y"]+.025):
            failures.append("Settled head left the unobscured keyboard stage")
    if not (min(aspects) < 1 < max(aspects)):
        failures.append("Both portrait and landscape were not captured")
    reviews.append(dict(file=path.name, status="FAIL" if failures else "PASS", samples=len(rows),
        scope="Complete final conversation test after engine startup; includes keyboard, editors, profile keyboard and rotations",
        minimumAspect=min(aspects), maximumAspect=max(aspects),
        poses=sorted({row.get("posture", {}).get("id", "") for row in rows}),
        cameraSnapCounts=sorted({row["cameraSnapCount"] for row in rows}), failures=sorted(set(failures))))
    reviews[-1]["minimumCameraHeight"] = min(row["cameraPosition"]["y"] for row in rows)
    reviews[-1]["pitchRange"] = [min(row["pitch"] for row in rows),max(row["pitch"] for row in rows)]
    reviews[-1]["settledUpperStageSamples"] = len(upper)
result = dict(status="PASS" if all(r["status"] == "PASS" for r in reviews) else "FAIL", reviews=reviews,
    limits="Not a device FPS test; explicit snap/FOV/viewport checks alone do not prove every visual frame is smooth")
print(json.dumps(result, ensure_ascii=False, indent=2))
raise SystemExit(0 if result["status"] == "PASS" else 1)

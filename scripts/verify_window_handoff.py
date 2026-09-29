#!/usr/bin/env python3
"""Check display-link evidence recorded by --window-handoff-review UI flows."""
import argparse
import json
from collections import defaultdict
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("events", type=Path)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
groups = defaultdict(list)
for line in args.events.read_text().splitlines():
    event = json.loads(line)
    if event.get("name") == "windowHandoffSample":
        groups[event["transition"]].append(event)
assert groups, "No handoff evidence: launch the flow with --window-handoff-review"

results = []
for transition, samples in groups.items():
    direction = samples[0]["direction"]
    opacity = [sample["coverOpacity"] for sample in samples]
    assert len(samples) >= 5, (transition, "insufficient display-link samples")
    assert all(sample["coverAboveRuntime"] for sample in samples), (transition, "window order changed")
    assert not any(sample["coverHidden"] or sample["runtimeHidden"] for sample in samples), (transition, "window disappeared before fade completed")
    assert all(abs(sample["runtimeOpacity"] - 1) < 0.001 for sample in samples), (transition, "Metal surface was faded")
    changes = [b - a for a, b in zip(opacity, opacity[1:])]
    if direction == "conversation":
        assert all(change <= 0.003 for change in changes), (transition, "cover brightened again")
        assert opacity[-1] <= 0.001, (transition, "conversation still covered")
    else:
        assert all(change >= -0.003 for change in changes), (transition, "shell darkened again")
        assert opacity[-1] >= 0.999, (transition, "runtime removed too early")
    assert sum(0.05 < value < 0.95 for value in opacity) >= 4, (transition, "missing intermediate opacity")
    results.append({"transition": transition, "direction": direction, "samples": len(samples),
                    "firstOpacity": opacity[0], "lastOpacity": opacity[-1],
                    "monotonic": True, "opaqueRuntime": True, "stableWindowOrder": True})

result = {"passed": True, "transitions": results,
          "sampleCount": sum(len(samples) for samples in groups.values()),
          "scope": "Native presentation-layer samples; inspect recorded pixels separately. Not a GPU/display FPS measurement."}
if args.output:
    args.output.write_text(json.dumps(result, indent=2) + "\n")
print(f"PASS: {len(results)} handoffs, {result['sampleCount']} samples; continuous native fades, opaque runtime, fixed stacking.")

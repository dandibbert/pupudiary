#!/usr/bin/env python3
"""Select real, installed iPhone simulators; never relabel a device as a newer model."""
import argparse
import json
import os
from pathlib import Path
import re
import sys


def runtime_version(runtime):
    return tuple(int(x) for x in runtime.split("iOS-")[-1].split("-") if x.isdigit())


def select_devices(data):
    candidates = []
    for runtime, devices in data.get("devices", {}).items():
        if ".iOS-" not in runtime:
            continue
        for device in devices:
            if not device.get("isAvailable", False) or not device["name"].startswith("iPhone"):
                continue
            match = re.search(r"iPhone (\d+)", device["name"])
            candidates.append({
                "name": device["name"], "udid": device["udid"], "runtime": runtime,
                "os": ".".join(map(str, runtime_version(runtime))),
                "generation": int(match[1]) if match else 0,
            })
    if not candidates:
        raise ValueError("No available iPhone simulators. Inspect build/logs/simulators.json.")
    pro = [d for d in candidates if "Pro" in d["name"]]
    primary = max(pro or candidates, key=lambda d: (
        d["generation"], runtime_version(d["runtime"]), "Max" not in d["name"]))
    compact = [d for d in candidates if "SE" in d["name"]]
    if compact:
        small = max(compact, key=lambda d: (runtime_version(d["runtime"]), d["name"]))
        compact_note = "Installed iPhone SE used for compact-layout coverage."
    else:
        compact = [d for d in candidates if "mini" in d["name"]]
        compact = compact or [d for d in candidates if not any(s in d["name"] for s in ("Pro", "Max", "Plus", "Air"))]
        compact = compact or [d for d in candidates if d["udid"] != primary["udid"]]
        small = max(compact or [primary], key=lambda d: (runtime_version(d["runtime"]), d["generation"]))
        compact_note = "No iPhone SE installed. The named fallback is used; no SE coverage is claimed."
    return {"primary": primary, "compact": small, "compact_note": compact_note}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    selection = select_devices(json.loads(args.input.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(selection, indent=2) + "\n")
    print(json.dumps(selection, indent=2))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as output:
            for key in ("primary", "compact"):
                for field in ("udid", "name", "os"):
                    print(f"{key}_{field}={selection[key][field]}", file=output)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError) as error:
        sys.exit(str(error))

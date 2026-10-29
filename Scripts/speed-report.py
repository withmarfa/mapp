#!/usr/bin/env python3
"""Prints `UI|<name>|<median>|<max>|<unit>` lines from a `log stream --style ndjson --signpost` capture of a
`Measure UI` run: for each test's phase (the `begin` and `end` markers `SpeedMeasureTests` logs), the app's signpost
intervals, its launch milestones, and its hangs. A hang is a main-actor interval of 250 ms or more, or an engine
event the engine itself logged as slow."""

import json
import re
import statistics
import sys
from datetime import datetime

HANG_MS = 250
MILESTONE = re.compile(r"(\w+)(?: \([^)]*\))? (\d+) ms")


def seconds(event):
    return datetime.strptime(event["timestamp"], "%Y-%m-%d %H:%M:%S.%f%z").timestamp()


def line(name, values, unit="ms"):
    values = sorted(values)
    return f"UI|{name}|{statistics.median(values):.1f}|{values[-1]:.1f}|{unit}"


def main(path):
    phase = None
    begun = {}
    intervals = {}  # phase -> (category, name) -> [ms]
    milestones = {}  # phase -> milestone -> [ms]
    slow = {}  # phase -> count
    order = []
    with open(path) as handle:
        for text in handle:
            try:
                event = json.loads(text)
            except ValueError:
                continue
            kind, category = event.get("eventType"), event.get("category")
            message = event.get("eventMessage", "")
            if category == "phase" and kind == "logEvent":
                action, _, name = message.partition(" ")
                phase = name if action == "begin" else None
                if action == "begin":
                    order.append(name)
                continue
            if phase is None:
                continue
            if kind == "signpostEvent":
                key = (event.get("processID"), category, event.get("signpostName"), event.get("signpostID"))
                if event.get("signpostType") == "begin":
                    begun[key] = seconds(event)
                elif event.get("signpostType") == "end" and key in begun:
                    ms = (seconds(event) - begun.pop(key)) * 1000
                    intervals.setdefault(phase, {}).setdefault((category, key[2]), []).append(ms)
            elif kind == "logEvent":
                if category == "launch" and message.startswith("launch since process start:"):
                    for name, ms in MILESTONE.findall(message):
                        milestones.setdefault(phase, {}).setdefault(name, []).append(float(ms))
                elif category == "engine" and message.startswith("engine event"):
                    slow[phase] = slow.get(phase, 0) + 1
    for phase in order:
        found = intervals.get(phase, {})
        for (category, name), values in sorted(found.items()):
            print(line(f"{phase}.signpost.{category}.{name}", values))
        for name, values in sorted(milestones.get(phase, {}).items()):
            print(line(f"{phase}.launch.{name}", values))
        main_actor = [ms for (category, name), values in found.items() if category == "navigation" or name.startswith("take.") for ms in values]
        print(f"UI|{phase}.hangs.main|{sum(ms >= HANG_MS for ms in main_actor)}|{len(main_actor)}|hangs of main-actor intervals")
        for (category, name), values in sorted(found.items()):
            over = [ms for ms in values if ms >= HANG_MS and (category == "navigation" or name.startswith("take."))]
            if over:
                print(line(f"{phase}.hang.{category}.{name}", over, "ms, the intervals of 250 ms or more"))
        engine = sum(len(values) for (category, _), values in found.items() if category == "engine")
        print(f"UI|{phase}.hangs.engine|{slow.get(phase, 0)}|{engine}|slow events of engine events")


if __name__ == "__main__":
    main(sys.argv[1])

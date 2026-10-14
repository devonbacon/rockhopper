"""Reads a playtest log (game/metrics.gd) and prints each mission in it:
who played, what happened when, how things stood every 30 s, and what
everyone did.

    python tools/session_summary.py [sessions/<file>.jsonl ...]

With no file, the newest in sessions/ (tools/fetch_sessions.sh puts them
there).
"""

import glob
import json
import os
import sys

QUIET = {"sample", "mission", "end", "flip", "switch", "link", "unlink", "ping", "hole_closed"}


def clock(t):
    return "%2d:%02d" % (t // 60, t % 60)


def missions(path):
    current = None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if entry["kind"] == "mission":
            if current:
                yield current
            current = [entry]
        elif current is not None:
            current.append(entry)
    if current:
        yield current


def describe(e):
    skip = {"t", "at", "kind"}
    parts = []
    for key, value in e.items():
        if key in skip or value is None or value == []:
            continue
        parts.append("%s=%s" % (key, json.dumps(value) if isinstance(value, (list, dict)) else value))
    return " ".join(parts)


def summarise(entries):
    start = entries[0]
    samples = [e for e in entries if e["kind"] == "sample"]
    end = next((e for e in entries if e["kind"] == "end"), None)
    last_t = entries[-1]["t"]
    players = sorted({e["soldier"] for e in entries if e["kind"] == "joined"})
    print("=" * 72)
    print("Mission: build %s, seed %s, %s; players: %s" % (start["build"], start["seed"], clock(last_t), ", ".join(players) or "none"))
    if end:
        print("Result: %s. %s" % (end["result"], end["outcome"]))
    else:
        print("Result: unfinished (server stopped or everyone left at %s)" % clock(last_t))
    print("\nTimeline:")
    for e in entries:
        if e["kind"] in QUIET:
            continue
        print("  %s  %-14s %s" % (clock(e["t"]), e["kind"], describe(e)))
    if samples:
        print("\nEvery %ds:" % 30)
        print("  time   day  ore alloy batt  pod spiders holes built dmg plans  soldiers (hp/warmth, m from pod)")
        for s in samples:
            built = sum(s["built"].values())
            soldiers = ", ".join("%s %d/%d %dm%s" % (name[:10], v["health"], v["warmth"], v["from_pod"], " DOWN" if v["down"] else "") for name, v in s["soldiers"].items())
            print("  %s %4.2f%s %4d %5d %4.0f %4.0f %7d %5d %5d %3d %5d  %s" % (
                clock(s["t"]), s["day"], "n" if s["night"] else " ", s["stock"], s["alloy"], s["battery"], s["pod_health"],
                s["spiders"], s["holes"], built, s["damaged"], s["blueprints"], soldiers))
        last = samples[-1]
        print("  built at last sample: %s; researched: %s" % (last["built"], ", ".join(last["researched"]) or "nothing"))
    tallies = (end or (samples[-1] if samples else {})).get("tallies", {})
    if tallies:
        print("\nTallies:")
        keys = sorted({k for v in tallies.values() for k in v})
        for who, counts in sorted(tallies.items()):
            print("  %-16s %s" % (who, ", ".join("%s %g" % (k, round(counts[k], 1)) for k in keys if k in counts)))
    print()


def main():
    paths = sys.argv[1:]
    if not paths:
        found = sorted(glob.glob(os.path.join("sessions", "*.jsonl")))
        if not found:
            sys.exit("no logs in sessions/; run tools/fetch_sessions.sh")
        paths = [found[-1]]
    for path in paths:
        print(path)
        for mission in missions(path):
            summarise(mission)


main()

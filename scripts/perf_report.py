#!/usr/bin/env python3
"""Turns a performance run into a markdown report with pass/fail marks.

    python scripts/perf_report.py build/perf/2026-11-06-1830-Pixel-6a

The folder may contain any of:
  metrics.csv              the app's recording (Diagnostics → Share recording)
  soak.csv, device.txt     written by scripts/soak.py
  batterystats.txt         written by scripts/soak.py
  scroll_benchmarks.json   copied from build/perf after the benchmark run

Writes report.md into the folder and prints it. Marks are in
docs/PERFORMANCE-REVIEW.md and lib/diagnostics/performance_report.dart
(PerformanceTargets); a test fails if BUDGETS here drifts from the app.
Standard library only.
"""

import csv
import json
import pathlib
import re
import sys

BUDGETS = {
    "smooth_pct": 90.0,  # frames drawn within 16.7 ms
    "memory_growth_mb_per_hour": 10.0,  # after the first 10 minutes
    "drift_s": 1.0,  # timer against the phone clock, over the run
    "warning_late_s": 5.0,  # latest warning after its threshold
    "reconnect_s": 15.0,  # display back after a Wi-Fi drop (soak)
    "scroll_p90_ms": 16.7,  # 90th percentile frame build+raster
}


def read_metrics(path):
    rows, summary = [], []
    if not path.exists():
        return rows, summary
    lines = path.read_text(encoding="utf-8").splitlines()
    try:
        header = next(i for i, l in enumerate(lines) if l.startswith("wall_utc,"))
    except StopIteration:
        return rows, summary
    for l in lines[header + 1 :]:
        if l.startswith("# "):
            summary.append(l[2:])
    data = [l for l in lines[header:] if not l.startswith("#")]
    rows = list(csv.DictReader(data))
    return rows, summary


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def growth_per_hour(points):
    """Least-squares slope of (seconds, MB) after warm-up, in MB per hour."""
    points = [(t, m) for t, m in points if t >= 600 and m is not None]
    if len(points) < 3:
        return None
    n = len(points)
    mt = sum(t for t, _ in points) / n
    mm = sum(m for _, m in points) / n
    var = sum((t - mt) ** 2 for t, _ in points)
    if var == 0:
        return None
    slope = sum((t - mt) * (m - mm) for t, m in points) / var
    return slope * 3600


def mark(ok):
    return "—" if ok is None else ("✅ pass" if ok else "❌ check")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    folder = pathlib.Path(sys.argv[1])
    if not folder.is_dir():
        sys.exit(f"No folder {folder}")
    device = {}
    if (folder / "device.txt").exists():
        for l in (folder / "device.txt").read_text().splitlines():
            if "=" in l:
                k, v = l.split("=", 1)
                device[k] = v

    rows, summary = read_metrics(folder / "metrics.csv")
    results = []  # (measure, value, target, ok)

    if rows:
        samples = [r for r in rows if r["kind"] == "sample"]
        frames = sum(int(num(r["frames"]) or 0) for r in samples)
        slow = sum(int(num(r["slow_frames"]) or 0) for r in samples)
        if frames:
            smooth = 100 * (frames - slow) / frames
            results.append(
                ("Smooth frames (app)", f"{smooth:.1f}%", f"≥ {BUDGETS['smooth_pct']}%",
                 smooth >= BUDGETS["smooth_pct"])
            )
        growth = growth_per_hour(
            [(num(r["elapsed_s"]), num(r["memory_mb"])) for r in samples]
        )
        if growth is not None:
            results.append(
                ("Memory growth after warm-up (app)", f"{growth:+.1f} MB/h",
                 f"≤ {BUDGETS['memory_growth_mb_per_hour']} MB/h",
                 growth <= BUDGETS["memory_growth_mb_per_hour"])
            )
        drift = max((abs(num(r["drift_ms"]) or 0) for r in rows), default=0) / 1000
        results.append(
            ("Timer drift", f"{drift:.1f} s", f"≤ {BUDGETS['drift_s']} s",
             drift <= BUDGETS["drift_s"])
        )
        late = [
            int(m.group(1)) / 1000
            for r in rows
            if r["kind"] == "warning" and (m := re.search(r"late_ms=(\d+)", r["detail"]))
        ]
        if late:
            results.append(
                ("Latest warning", f"{max(late):.1f} s after due ({len(late)} warnings)",
                 f"≤ {BUDGETS['warning_late_s']} s", max(late) <= BUDGETS["warning_late_s"])
            )
        # Reconnect time: from a display drop to the next reconnection.
        dropped, waits = None, []
        for r in rows:
            t = num(r["elapsed_s"])
            if r["kind"] == "display" and "Disconnected" in r["detail"]:
                dropped = t
            elif r["kind"] == "reconnected" and dropped is not None:
                waits.append(t - dropped)
                dropped = None
        if waits:
            results.append(
                ("Slowest reconnect", f"{max(waits):.0f} s ({len(waits)} drops)",
                 f"≤ {BUDGETS['reconnect_s']} s", max(waits) <= BUDGETS["reconnect_s"])
            )
        levels = [num(r["battery_pct"]) for r in rows if num(r["battery_pct"]) is not None]
        hours = (num(rows[-1]["elapsed_s"]) or 0) / 3600
        if len(levels) >= 2 and hours > 0:
            results.append(
                ("Battery use", f"{(levels[0] - levels[-1]) / hours:.1f}%/h "
                 f"({levels[0]:.0f}% → {levels[-1]:.0f}%)", "baseline", None)
            )

    soak = folder / "soak.csv"
    if soak.exists():
        with open(soak, newline="") as f:
            srows = list(csv.DictReader(f))
        growth = growth_per_hour(
            [(60 * (num(r["minute"]) or 0), num(r["memory_mb"])) for r in srows]
        )
        if growth is not None:
            results.append(
                ("Memory growth after warm-up (Android PSS)", f"{growth:+.1f} MB/h",
                 f"≤ {BUDGETS['memory_growth_mb_per_hour']} MB/h",
                 growth <= BUDGETS["memory_growth_mb_per_hour"])
            )

    bench = folder / "scroll_benchmarks.json"
    if bench.exists():
        data = json.loads(bench.read_text())
        for key, value in sorted(data.items()):
            if not isinstance(value, dict):
                continue
            build = num(value.get("90th_percentile_frame_build_time_millis")) or 0
            raster = num(value.get("90th_percentile_frame_rasterizer_time_millis")) or 0
            total = build + raster
            results.append(
                (f"Scroll {key.replace('_scroll', '').replace('_', ' ')} p90",
                 f"{total:.1f} ms (build {build:.1f} + raster {raster:.1f})",
                 f"≤ {BUDGETS['scroll_p90_ms']} ms", total <= BUDGETS["scroll_p90_ms"])
            )

    title = device.get("model", folder.name)
    out = [f"# Performance run · {title}", ""]
    if device:
        out.append(
            f"Android {device.get('android', '?')} · app {device.get('version', '?')}"
            f" · {device.get('minutes', '?')} min"
        )
        out.append("")
    if not results:
        out.append("No measurements found. See the folder contents listed in this script.")
    else:
        out += ["| Measure | Result | Target | |", "|---|---|---|---|"]
        out += [f"| {m} | {v} | {t} | {mark(ok)} |" for m, v, t, ok in results]
    if summary:
        out += ["", "App summary:", ""] + [f"- {l}" for l in summary]
    out += ["", "---", "", "*Created by I-Proton · Church Service Timer*"]
    text = "\n".join(out) + "\n"
    (folder / "report.md").write_text(text, encoding="utf-8")
    print(text)
    failed = [m for m, _, _, ok in results if ok is False]
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

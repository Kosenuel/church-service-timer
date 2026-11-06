# Performance and endurance review

Automated tests prove behaviour; they do not prove that a phone stays smooth, cool and accurate through a full service. This review measures that on real phones, before every release, so slowdowns and leaks are caught while they are new.

## When

| Release | Run | Time |
|---|---|---|
| Every minor release (0.26.0, 0.27.0…) | Full soak on 2–3 phones, plus the scrolling benchmarks | ~2 h each, mostly unattended |
| Patch release (0.26.1…) | Benchmarks; the soak too if the change touches timing, the LED sign or pairing | ~15 min |

Record each run in [Results](#results) below. A release is not tagged while a mark reads ❌ without an agreed explanation.

## Phones

Use real phones, not emulators. Flutter recommends profiling on physical devices, and slower phones show problems first.

1. The slowest supported phone in use (Android 7.0 or later; the app's minimum is API 24).
2. A typical mid-range phone.
3. A tablet, if one is used as a stage screen.

## Targets

| Measure | Target | Source |
|---|---|---|
| Smooth frames during a service | ≥ 90% drawn within 16.7 ms | App recording |
| Scrolling (Programs, Reports, a long program) | 90th percentile frame ≤ 16.7 ms on the mid-range phone; no visible stutter on the slow phone | Benchmarks |
| Memory | Growth ≤ 10 MB per hour after the first 10 minutes | App recording and `dumpsys meminfo` |
| Timer drift | ≤ 1 s against the phone clock over 2 hours | App recording |
| Warnings | Each on the display within 5 s of its threshold, including with the screen off | App recording |
| Reconnect after a Wi-Fi drop | ≤ 15 s | App recording |
| Battery | No more than the previous release's figure on the same phone, within 10% | App recording and batterystats |

The app (`PerformanceTargets` in `lib/diagnostics/performance_report.dart`) and `scripts/perf_report.py` apply these marks; a test fails if the two disagree.

## 1. Scrolling benchmarks

The app runs on generated data in memory (200 programs, 500 past services, a 60-segment program); nothing saved on the phone changes.

```bash
flutter drive --profile --driver=test_driver/perf_driver.dart --target=integration_test/scroll_benchmark_test.dart
```

The summary is saved as `build/perf/scroll_benchmarks.json`.

## 2. Soak run

Needs Python 3.8+ and `adb` (Android platform-tools) on the computer, USB debugging on the phone, and a profile or release build installed.

```bash
python scripts/soak.py
```

When asked, start the test service on the phone: **Settings → About → Diagnostics → Start 2-hour test service**, connected to the display you want to test (LED sign, stage screens or the simulator). Then press Enter on the computer and leave both alone. Over two hours the script:

- reads memory use every minute;
- sends the app to the background and back every 10 minutes;
- turns the screen off for two long stretches;
- turns Wi-Fi off for 30 seconds three times;
- collects battery and frame statistics at the end.

`--minutes 15` runs a short version for checking the setup.

## 3. Report

When the test service ends, the phone writes its own report: **Diagnostics** shows each measure with ✅ or ❌, and **Share recording** sends it as a markdown file (`…-report.md`) together with the minute-by-minute data (`…-metrics.csv`). For a quick check after a real Sunday service, that report is all you need. The phone marks battery use against its own previous recording, so the first one sets the baseline.

For the full pre-release review, which also covers the scrolling benchmarks and Android's own memory figures, save the CSV as `metrics.csv` in the run's folder (the script prints the path), copy `build/perf/scroll_benchmarks.json` there too, then:

```bash
python scripts/perf_report.py build/perf/<run folder>
```

It writes `report.md` with each measure, its target and ✅ or ❌, and exits with an error if anything fails.

## What the app records

Diagnostics is a visible row in **Settings → About**. Recording is off until switched on, covers one service, and switches itself off when that service ends; while it is on, Live shows a **Recording metrics** chip.

It records once a minute and at key moments: memory use, battery level and temperature, frame times, timer drift against the phone clock, how late warnings fire, going to the background, and display or paired-phone connection status. It never records program, segment or church names, notes, messages or device names. The file stays on the phone until **Share recording**.

## Results

| Date | Version | Phone | Smooth | Memory/h | Drift | Warnings | Reconnect | Battery/h | Scroll p90 | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| | | | | | | | | | | |

#!/usr/bin/env python3
"""Endurance (soak) run for the performance review.

Drives a phone over USB with adb while the app runs its 2-hour test service,
and collects Android's own measurements. See docs/performance-review.md.

    python scripts/soak.py                  # 120 minutes, the default
    python scripts/soak.py --minutes 15     # a short check

Needs: Python 3.8+, adb from Android platform-tools on PATH, USB debugging
on, and the app installed (a profile or release build). Only standard
library modules are used, so it runs on Windows, macOS, Linux and WSL.

During the run the script:
  * reads the app's memory use every minute (dumpsys meminfo);
  * sends the app to the background and back every 10 minutes;
  * turns the screen off for two long stretches, to check warnings and the
    lock-screen controls;
  * turns Wi-Fi off for 30 seconds three times, to check reconnecting;
  * collects battery statistics and frame statistics at the end.
"""

import argparse
import csv
import datetime as dt
import pathlib
import re
import shutil
import subprocess
import sys
import time

PACKAGE = "io.github.immanuelokose.churchservicetimer"


def adb(*args, check=False, timeout=60):
    """Runs an adb command and returns its output, or '' if it failed."""
    try:
        result = subprocess.run(
            ["adb", *args], capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        if check:
            sys.exit(f"adb failed: {e}")
        return ""
    if check and result.returncode != 0:
        sys.exit(f"adb {' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout


def shell(*args, **kw):
    return adb("shell", *args, **kw)


def memory_mb():
    """The app's total PSS in MB, or None when it is not running."""
    out = shell("dumpsys", "meminfo", PACKAGE)
    m = re.search(r"TOTAL(?: PSS)?:?\s+(\d+)", out)
    return round(int(m.group(1)) / 1024, 1) if m else None


def battery():
    out = shell("dumpsys", "battery")
    level = re.search(r"level:\s*(\d+)", out)
    temp = re.search(r"temperature:\s*(\d+)", out)
    return (
        int(level.group(1)) if level else None,
        int(temp.group(1)) / 10 if temp else None,
    )


def wifi(on):
    # Android 11+ uses cmd wifi; older versions use svc.
    reply = shell("cmd", "wifi", "set-wifi-enabled", "enabled" if on else "disabled")
    if not reply.strip() == "" or "Unknown" in reply or "Error" in reply:
        shell("svc", "wifi", "enable" if on else "disable")


def screen(on):
    shell("input", "keyevent", "KEYCODE_WAKEUP" if on else "KEYCODE_SLEEP")


def to_background():
    shell("input", "keyevent", "KEYCODE_HOME")


def to_foreground():
    shell("monkey", "-p", PACKAGE, "-c", "android.intent.category.LAUNCHER", "1")


def plan(minutes):
    """Minute → actions. Spread over the run, scaled for short runs."""
    actions = {}

    def at(fraction, action):
        actions.setdefault(max(1, round(minutes * fraction)), []).append(action)

    for m in range(10, minutes, 10):
        actions.setdefault(m, []).append("background")
    for f in (0.25, 0.5, 0.75):
        at(f, "wifi-drop")
    at(0.33, "screen-off")
    at(0.50, "screen-on")
    at(0.83, "screen-off")
    at(0.95, "screen-on")
    return actions


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--minutes", type=int, default=120)
    parser.add_argument("--out", default="build/perf")
    args = parser.parse_args()

    if not shutil.which("adb"):
        sys.exit("adb was not found. Install Android platform-tools and add it to PATH.")
    devices = [l for l in adb("devices", check=True).splitlines()[1:] if "\tdevice" in l]
    if len(devices) != 1:
        sys.exit("Connect exactly one phone with USB debugging allowed.")
    if PACKAGE not in shell("pm", "list", "packages", PACKAGE):
        sys.exit(f"{PACKAGE} is not installed on this phone.")

    model = shell("getprop", "ro.product.model").strip() or "phone"
    android = shell("getprop", "ro.build.version.release").strip()
    stamp = dt.datetime.now().strftime("%Y-%m-%d-%H%M")
    out = pathlib.Path(args.out) / f"{stamp}-{re.sub(r'[^A-Za-z0-9]+', '-', model)}"
    out.mkdir(parents=True, exist_ok=True)
    package = shell("dumpsys", "package", PACKAGE)
    version = re.search(r"versionName=(\S+)", package)
    (out / "device.txt").write_text(
        f"model={model}\nandroid={android}\nminutes={args.minutes}\n"
        f"version={version.group(1) if version else ''}\n"
    )

    print(f"Phone: {model} (Android {android}) · results in {out}")
    print(
        "\nOn the phone: Settings → About → Diagnostics → Start 2-hour test service.\n"
        "Leave the app on Live, then press Enter here to begin."
    )
    input()

    shell("dumpsys", "batterystats", "--reset")
    shell("dumpsys", "gfxinfo", PACKAGE, "reset")
    # Counts battery use as if unplugged, though USB is connected.
    shell("dumpsys", "battery", "unplug")

    actions = plan(args.minutes)
    rows = []
    dark = False  # The screen is off on purpose; leave the app alone.
    start = time.monotonic()
    try:
        for minute in range(args.minutes + 1):
            level, temp = battery()
            mem = memory_mb()
            done = actions.get(minute, [])
            rows.append([minute, mem, level, temp, " ".join(done)])
            print(
                f"{minute:4d} min · memory {mem if mem is not None else '—'} MB"
                f" · battery {level}% · {temp} °C {' · ' + ', '.join(done) if done else ''}",
                flush=True,
            )
            for action in done:
                if action == "background" and dark:
                    continue
                if action == "background":
                    to_background()
                    time.sleep(20)
                    to_foreground()
                elif action == "wifi-drop":
                    wifi(False)
                    time.sleep(30)
                    wifi(True)
                elif action == "screen-off":
                    screen(False)
                    dark = True
                elif action == "screen-on":
                    screen(True)
                    dark = False
                    to_foreground()
            if minute < args.minutes:
                time.sleep(max(0, start + 60 * (minute + 1) - time.monotonic()))
    except KeyboardInterrupt:
        print("\nStopped early; saving what was measured.")
    finally:
        screen(True)
        wifi(True)
        with open(out / "soak.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["minute", "memory_mb", "battery_pct", "battery_temp_c", "actions"])
            w.writerows(rows)
        (out / "batterystats.txt").write_text(
            shell("dumpsys", "batterystats", PACKAGE, timeout=180)
        )
        (out / "gfxinfo.txt").write_text(shell("dumpsys", "gfxinfo", PACKAGE))
        shell("dumpsys", "battery", "reset")

    print(
        f"\nDone. On the phone, end the test service, then Diagnostics → Share recording,"
        f"\nand save the file as {out / 'metrics.csv'}. Then run:\n"
        f"    python scripts/perf_report.py {out}"
    )


if __name__ == "__main__":
    main()

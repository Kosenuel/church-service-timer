# Build the Android prototype

Toolchain: Flutter stable 3.47.7 (Dart 3.13.5), JDK 21, Android SDK platform 36, build tools 36.0.0 and NDK 28.2.13676358. Pin the Flutter version when reproducing results; preserve `pubspec.lock`.

From a normal shell in the repository:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. Install with `adb install -r` after enabling USB debugging and accepting the phone's trust prompt, or transfer the APK and open it on the phone. A physical sign is not needed.

The native bridge supplies Android `SystemClock.elapsedRealtime()` with `BOOT_COUNT`, uses `AtomicFile` in application-private storage, and accesses selected documents through the system picker. The app requires no account or Internet connection. Debug builds may carry Flutter's tooling Internet permission; no application transport is implemented.

Version 0.3 also requests notification permission and, optionally, precise-alarm access. These prompts are initiated by the operator from Live. A private, non-exported receiver posts scheduled warnings. No boot receiver or foreground sign-output service is installed.

## Installation checks (including 0.6)

1. Upgrade without clearing app data. Confirm existing reports/cues survive and the original Matrix appearance is unchanged apart from the chosen LED cell shape.
2. Edit a Live cue (including font/style/speed), Send, switch service and restart. Confirm persistence. Cancel a new cue and confirm nothing is added.
3. Switch square/circular LEDs in Display; check Live and a composer, then restart. Try Sq-Matrix at both heights. Import a licensed Times New Roman Regular TTF and inspect ascenders/descenders, bold/italic and scrolling. Invalid font imports must preserve the previous font.
4. Enable notifications, use Test notification sound, and grant precise alarms if offered. Confirm sound with the device's normal volume and channel settings.
5. Run Quick rehearsal with short future warning thresholds. Keep a manual cue visible: a due stage warning must replace it for eight seconds and then restore it. Compare with operator-only. Confirm countdown thresholds use remaining time.
6. Repeat with the phone locked; check notification timing/sound, then return to Live. Exercise pause/resume, time adjustment, advance and End to confirm obsolete alarms do not fire. Check denied notification/exact-alarm permissions and document any device-specific delay.
7. Cancel and confirm timer actions and report clearing. Export a report first, clear its local record, and confirm the export remains available.

8. Confirm the new Reports list, detail pages and Graph view. Export all records in CSV and JSON while a filter is active; both exports must include the complete saved history. Cancel and confirm cue deletion.
9. Edit one template’s end screen and confirm another template remains unchanged. Change At Zero in Display while a service is at zero and verify it applies immediately unless a cue/warning or output hold has priority. Restart and verify both settings persist.

These runtime checks are not replaced by unit tests or APK compilation. No physical sign is required for them; real controller validation is separate.

For 0.5, also check the arc and allocation after ±2 minutes and Custom removal, warning colours at configured thresholds, and the depleted arc with red overtime. Pause/restart during overtime and verify it survives; adding two minutes at +00:23 should yield 01:37. Next segment must name its destination, and Undo must always confirm the restored state. Disconnect/reconnect the simulator and verify the top banner and preview badge. Use enlarged Android font settings to check the two-row controls and scrollable dialogs. Confirm that At Zero output and the original Matrix font remain unchanged.

For 0.6, compare the arc's horizontal position in Ready, normal, paused, warning, overtime and ended states; it must remain centered in its card. Check the Display preview heading at the left and status badge at the right with normal and enlarged text. Tap compact Templates rows, edit and rename a template, duplicate it, cancel/confirm deletion, and export from the detail page. Confirm the loaded service stays unchanged. Toggle List options → Services & rehearsals, change a template's group in its editor, then restart and check persistence. Check New and Import after deleting all templates.

On this Windows workspace, the reusable Android environment is at `C:\Users\x1\Documents\Codex\android-toolchain\Activate.ps1`. The Flutter SDK installation and build verification details are recorded in the delivered verification report. Machine-specific SDK locations belong in ignored `android/local.properties`, not source control.

The Windows helper `scripts/Build-Prototype.ps1` runs dependency resolution, analysis, tests, APK build and signature verification, then copies both `Cuekeeper-<version>.apk` and `Cuekeeper-prototype.apk` to the repository's parent output directory. It also writes `prototype-build.log` and a result JSON file. Use `-Toolchain` to select a different SDK directory.

Run the helper in a normal PowerShell window when the agent sandbox blocks Flutter child processes. The default run compares screenshot baselines. Only use `-UpdateGoldens` when intentionally changing the UI, then review every changed image in `test/goldens/`. `-BuildOnly` skips analysis and tests and requires separate evidence. `-PushAfterBuild` invokes the existing WSL push helper only after the build and signature checks succeed; commit intended source changes first.

If a fresh checkout lacks the Gradle wrapper binary, run `flutter create --platforms android --org org.kosenuel .` using the pinned Flutter version, then inspect its changes before building. The committed native bridge and app identity must remain intact.

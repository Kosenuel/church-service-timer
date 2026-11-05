# Build the Android prototype

Toolchain: Flutter stable 3.47.7 (Dart 3.13.5), JDK 21, Android SDK platform 36, build tools 36.0.0 and NDK 28.2.13676358. Pin the Flutter version when reproducing results; preserve `pubspec.lock`.

From a normal shell in the repository:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`. From 0.22 the release build is signed with the release key from `android/key.properties` or the `CST_KEYSTORE_*` environment variables (see the README); without them it falls back to the local debug key, which cannot upgrade a release-key install. 0.22 also changes the application ID to `io.github.immanuelokose.churchservicetimer`, so it installs alongside earlier builds; see `history/update-0.22.0.md`. GitHub Actions (`.github/workflows/build.yml`) runs analysis, tests and a signed release build on every push and uploads the APK as a workflow artifact. Install with `adb install -r` after enabling USB debugging and accepting the phone's trust prompt, or transfer the APK and open it on the phone. A physical sign is not needed. The helper defaults to release; use `-BuildMode profile` for VM timeline measurements or `-BuildMode debug` for development.

The native bridge supplies Android `SystemClock.elapsedRealtime()` with `BOOT_COUNT`, uses `AtomicFile` in application-private storage, and accesses selected documents through the system picker. The app requires no account or Internet connection. The W2 adapter uses the local Wi-Fi connection; Internet permission is used for its sockets.

Version 0.3 also requests notification permission and, optionally, precise-alarm access. These prompts are initiated by the operator from Settings → Warnings & alerts. A private, non-exported receiver posts scheduled warnings. There is no boot receiver. Version 0.12 adds a connected-device foreground service for an active authenticated sign session; it is not restarted automatically after process death.

## Installation checks (including 0.10)

1. Upgrade without clearing app data. Confirm existing reports/cues survive and the original Matrix appearance is unchanged apart from the chosen LED cell shape.
2. Edit a Live cue (including font/style/speed), Send, switch service and restart. Confirm persistence. Cancel a new cue and confirm nothing is added.
3. Switch square/circular LEDs in Settings → Display settings; check Live and a composer, then restart. Try Sq-Matrix at both heights. Choose bundled Tinos and inspect ascenders/descenders, Regular/Bold/Italic/Bold Italic, both heights and scrolling. No import is required.
4. Enable notifications, use Test notification sound, and grant precise alarms if offered. Confirm sound with the device's normal volume and channel settings.
5. Run Quick rehearsal with short future warning thresholds. Keep a manual cue visible: a due stage warning must replace it for eight seconds and then restore it. Compare with operator-only. Confirm countdown thresholds use remaining time.
6. Repeat with the phone locked; check notification timing/sound, then return to Live. Exercise pause/resume, time adjustment, advance and End to confirm obsolete alarms do not fire. Check denied notification/exact-alarm permissions and document any device-specific delay.
7. Cancel and confirm timer actions and report clearing. Export a report first, clear its local record, and confirm the export remains available.

8. Confirm the new Reports list, detail pages and Graph view. Export all records in CSV and JSON while a filter is active; both exports must include the complete saved history. Cancel and confirm cue deletion.
9. Edit one template’s end screen and confirm another template remains unchanged. Change At Zero in Settings → Display settings while a service is at zero and verify it applies immediately unless a cue/warning or output hold has priority. Restart and verify both settings persist.

These runtime checks are not replaced by unit tests or APK compilation. No physical sign is required for them; real controller validation is separate.

For 0.5, also check the arc and allocation after ±2 minutes and Custom removal, warning colours at configured thresholds, and the depleted arc with red overtime. Pause/restart during overtime and verify it survives; adding two minutes at +00:23 should yield 01:37. Next segment must name its destination, and Undo must always confirm the restored state. Disconnect/reconnect the simulator and verify the top banner and preview badge. Use enlarged Android font settings to check the two-row controls and scrollable dialogs. Confirm that At Zero output and the original Matrix font remain unchanged.

For 0.6, compare the arc's horizontal position in Ready, normal, paused, warning, overtime and ended states; it must remain centered in its card. Check the Display preview heading at the left and status badge at the right with normal and enlarged text. Tap compact Templates rows, edit and rename a template, duplicate it, cancel/confirm deletion, and export from the detail page. Confirm the loaded service stays unchanged. Toggle List options → Services & rehearsals, change a template's group in its editor, then restart and check persistence. Check New and Import after deleting all templates.

For 0.7, also follow the device checklist in `history/FEATURES-0.7.md`: new launcher/splash identity, optional church name, five theme previews with save/cancel, About author/version, screen awake off/on, report branding, and confirmed setup backup/restore. A native splash precedes the customizable Flutter opening screen. Upgrade using the existing signing key and package ID; do not clear data.

For 0.8, follow the banner, crop, backup and template-warning checks in `history/FEATURES-0.8.md`. Reports and Settings use compact lists. Individual report deletion is in the detail page; Display no longer has an Editing selector. A new schema 2 backup includes the reduced church banner and older schema 1 backups remain importable.

For 0.9, open Settings → Feedback Center, enter a title, message and contact, and open the email app. Check the recipient, subject, line breaks, accented text and version in the draft; return without sending and confirm the form text remains. Try Copy feedback and cancel/confirm Clear draft. Also test on a device with no mail handler and with enlarged text. Opening a composer is not proof of delivery. See `history/FEATURES-0.9.md` for limits and behavior.

On this Windows workspace, the reusable Android environment is at `C:\Users\x1\Documents\Codex\android-toolchain\Activate.ps1`. The Flutter SDK installation and build verification details are recorded in the delivered verification report. Machine-specific SDK locations belong in ignored `android/local.properties`, not source control.

The Windows helper `scripts/Build-Prototype.ps1` runs dependency resolution, analysis, tests, APK build and signature verification, then copies both `Church-Service-Timer-<version>.apk` and `Church-Service-Timer-prototype.apk` to the repository's parent output directory. It also writes `prototype-build.log` and a result JSON file. Use `-Toolchain` to select a different SDK directory.

The helper removes duplicate PATH entries after toolchain activation and restores the caller's PATH on exit. Repeated runs in one console therefore do not add more copies of tool folders. This reduces exposure to [Windows command-line and environment expansion limits](https://learn.microsoft.com/en-US/troubleshoot/windows-client/shell-experience/command-line-string-limitation). The log records only PATH lengths, not its contents. Results explicitly distinguish building, failed and built; older APK files are retained, but a failed result never claims one is current. Run `scripts/Build-EnvironmentChecks.ps1` to check the path handling independently.

Run the helper in a normal PowerShell window when the agent sandbox blocks Flutter child processes. The default run compares screenshot baselines. Only use `-UpdateGoldens` when intentionally changing the UI, then review every changed image in `test/goldens/`. `-BuildOnly` skips analysis and tests and requires separate evidence. `-PushAfterBuild` invokes the existing WSL push helper only after the build and signature checks succeed; commit intended source changes first.

If a fresh checkout lacks the Gradle wrapper binary, run `flutter create --platforms android --org org.kosenuel .` using the pinned Flutter version, then inspect its changes before building. The committed native bridge and app identity must remain intact.

For 0.10, follow `history/FEATURES-0.10.md`: global warning editing (including while paused and after Undo), connection header, compact Display/Appearance, default grouping, cue migration, private notes, readiness, focused mode, blank output and optional feedback diagnostics. Historical version checklists describe those releases; the 0.10 global warning model supersedes per-template warning configuration.

For 0.12, follow `history/FEATURES-0.12.md`: scrolling warnings and return, locked-screen operation, overtime-to-next recovery, focused blank preview/control lock, rundown notes, custom themes, Reports banner and activity timeline. Verify acknowledgement separately from visible output; brief replacement blinking remains expected.

For 0.13, follow `history/FEATURES-0.13.md`: paired-device approval, private-note isolation, handover/reclaim, loss/stale indication, stage cues, upcoming edits and Android print preview. Native administration builder checks are in `scripts/W2AdministrationChecks.kt`; codec tests do not replace an intentional setting-change/reconnection check. Do not reset sign networking during normal timer validation.

## Publishing a release

1. Update the version in `pubspec.yaml` (for example `0.24.0+24`) and `appVersion` in `lib/domain/app_settings.dart` (`0.24.0 (24)`).
2. In `CHANGELOG.md`, rename `## Unreleased` to `## 0.24.0, <date>` and start a new empty `## Unreleased` above it.
3. Merge those changes to `main`, then tag and push:

   ```sh
   git tag v0.24.0
   git push origin v0.24.0
   ```

The [Release workflow](../.github/workflows/release.yml) checks that the tag matches both version strings, runs analysis and tests, builds the APK signed with the release key (it refuses to publish without the `CST_KEYSTORE_*` secrets), and publishes a GitHub Release with the APK, its SHA-256 checksum and that version's changelog section.

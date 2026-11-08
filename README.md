# Church Service Timer

An Android app for keeping a church service on time. It runs a program of timed segments, gives the operator large, confirmed controls, sends discreet cues to the stage, and records a report of how long each part actually took. Output can go to an exact 32 × 16 pixel simulator, to phone or tablet stage screens over local Wi-Fi, or to a Huidu W2 V6.02.232 32 × 16 red LED sign.

Current version: **0.22.0**. See [CHANGELOG.md](CHANGELOG.md) for every release.

## Install

1. Install the APK on Android 7.0 (API 24) or newer. CI builds a signed APK on every push; see [Build and test](#build-and-test).
2. 0.22 uses a new application ID (`io.github.immanuelokose.churchservicetimer`), so it installs **alongside** builds before 0.22. To move your setup, export from **Settings → Backup & restore** in the old app, restore it in the new one, then re-enter sign passwords and pair stage screens again. Backups never contain credentials or pairings.

## Quick start

1. **Rehearse.** On Live, choose **Start service → Quick rehearsal**. While Ready, pick live timing or a **Fast rehearsal** speed, then **Start first segment**.
2. **Run the service.** Pause/Resume and **Next segment** are the main controls. −2 / +2 / Custom adjust time, and Undo reverses the last change. Every action asks for confirmation. Tap the segment title to jump, or the timing line for the full overview.
3. **Cue the stage.** Tap a prepared cue such as WRAP UP. Its button becomes **Show timer** until you return to the countdown. **Show clock**, **Send message** and **Blank screen** sit alongside. Manage cues in **Settings → Stage cues**.
4. **Choose the display.** The chip in the header shows where output goes (Simulator, LED sign, Stage screens or Disconnected). Tap it to switch or see connection details.
5. **Finish.** **End service** shows the end screen and saves a report. Reports have a segment breakdown, graphs, CSV/JSON export and printing.
6. **Plan and personalise.** Build programs in **Programs**, with speakers and private notes. Set warnings in **Settings → Warnings & alerts**, and set your church name, banner and theme in Settings.

**Focused operator view** and **Ready for service** are in the Live ⋮ menu. **Lock controls** (the header padlock) prevents accidental taps; press and hold **Hold to unlock**.

## LED sign and stage screens

- **LED sign:** tap the display chip, then **LED sign**. Join the sign's Wi-Fi, scan, select it and enter its device password. The password can be stored on the phone, encrypted with Android Keystore. A new connection holds output for review. Reconnecting the same sign during a trusted service restores current output automatically.
- **Stage screens:** choose **Phone, tablet or web screens**, then **Share to stage screens**. On the other device, tap **Join as stage screen** and enter the six-digit code (or scan the QR code). The host approves every device and explicitly grants control to an additional operator.

### What is and isn't proven on hardware

- The adapter is gated to the tested W2 V6.02.232 firmware and profile. It never changes scan settings, polarity or firmware.
- Physically confirmed: native countdown, pause/resume, adjustments while paused, cue replacement and return to the current timer. Each program replacement shows one brief blink.
- **Controller accepted** means the sign acknowledged the upload; it is not visual confirmation. The red preview is an estimate.
- Countdowns are limited to **59:59**. The physical clock keeps a steady colon (see [w2-clock-020](docs/w2-clock-020.md)).
- An active service runs a foreground service so warnings and recovery continue while the phone is locked. Force-stop, process death and network loss are not continuous-operation guarantees.
- Not yet established: seamless updates, the 100-cue latency measurement, full-service endurance and power-loss behaviour. See [PROTOTYPE-SCOPE](docs/PROTOTYPE-SCOPE.md) and the [protocol evidence](docs/w2-protocol-evidence.json).

## Data and privacy

Everything is stored on the phone. Backups include programs, cues, reports, preferences and the church banner, but never active clocks, permissions, credentials or pairings. **Settings → Feedback Center** prepares an email draft to immanuelproton@gmail.com. Optional diagnostics are shown for review before sending and exclude church content, notes, credentials and raw error text.

## Build and test

Use Flutter stable 3.47.7 / Dart 3.13.5, JDK 21, Android SDK 36 and build-tools 36.0.0. [docs/BUILD.md](docs/BUILD.md) has reproducible commands and device checklists.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Release builds are signed with the key in `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; git-ignored) or the `CST_KEYSTORE_PATH`, `CST_KEYSTORE_PASSWORD`, `CST_KEY_ALIAS` and `CST_KEY_PASSWORD` environment variables, falling back to the debug key. [GitHub Actions](.github/workflows/build.yml) runs analysis, tests and a signed release build on every push, using the `CST_KEYSTORE_BASE64`, `CST_KEYSTORE_PASSWORD`, `CST_KEY_ALIAS` and `CST_KEY_PASSWORD` repository secrets. Golden screenshots are rendered on Linux, so Windows runs may report small text differences.

## Project layout

`lib/` is organised by feature; `test/` mirrors it.

- `main.dart`: app entry, home screen shell and program editor.
- `app/`: application controller (save-before-publish, retries), suspend-aware clock and storage, phone warning notifications.
- `domain/`: pure service model and timing, programs and library, warnings, reports, planning, stage output, backups and migrations.
- `display/`: bitmap fonts (I-Proton Matrix, Sq-Matrix), exact 512-pixel frames, bundled Tinos rasterization, clock text.
- `hardware/`: W2 output planning and serialization, the guarded LED adapter, connection status, device management and Wi-Fi reconnect views.
- `pairing/`: encrypted local pairing, six-digit PIN, saved devices, pairing and stage-screen views.
- `live/`: Live layout, timer and controls, timing overview, stage output, time recovery, rundown planning and the running-service bar.
- `programs/`: program list, library and filters, import/export, editor insights.
- `reports/`: report list and detail, actions, timing insights and printable PDFs.
- `settings/`: Settings hub, display, appearance, warnings, clock, stage cues and search.
- `feedback/`: Feedback Center form and email composition.
- `shared/`: theme, menus, selection and undo helpers, choice fields, pickers, banner and small utilities.
- Android sources live under `android/app/src/main/kotlin/org/kosenuel/churchservicetimer/` (W2 transport, credential vault, printing, fonts, notifications, foreground service).
- `test/`: deterministic domain, fault-injection, rendering and UI checks, with golden screenshots in `test/goldens/`.
- `scripts/`: standalone smoke and probe scripts; `docs/`: requirements, scope and release guides; `examples/`: portable program examples.

## Import format

CSV uses UTF-8 with the headers `Segment Name,Duration (Minutes)` and an optional `Seconds` column; it carries segments only. JSON is versioned and also keeps cues, styles, end screens, speakers and private notes. New durations must be 00:01–59:59. One invalid item blocks the whole import. Full rules are in [TEMPLATE-FORMAT](docs/TEMPLATE-FORMAT.md).

## Documentation

- [CHANGELOG](CHANGELOG.md): release history, with links to each release guide in [docs/history](docs/history/).
- [BUILD](docs/BUILD.md): toolchain, build helper and device checklists.
- [WEB-SCREENS](docs/WEB-SCREENS.md): following the service from any browser: the three views, codes, easy name and join slide.
- [PERFORMANCE-REVIEW](docs/PERFORMANCE-REVIEW.md): the per-release performance and endurance check, its targets and results.
- [PROTOTYPE-SCOPE](docs/PROTOTYPE-SCOPE.md): implemented behaviour and hardware-dependent work.
- [PRD](docs/PRD.md): the original requirements.
- [TEMPLATE-FORMAT](docs/TEMPLATE-FORMAT.md), [DISPLAY-FONTS](docs/DISPLAY-FONTS.md) and [DEVICE-ADMIN-0.13](docs/DEVICE-ADMIN-0.13.md): formats, fonts and W2 administration.

No original vendor code, APKs, bundled vendor fonts, private keys, passwords or machine-specific settings are included. The code is a fresh implementation informed by the supplied requirements and prior analysis.

# Cuekeeper — Church Service Timer

Offline Android prototype for church production timing and stage cues, with an exact 32 × 16 monochrome pixel simulator. No Huidu controller is contacted. Hardware compatibility and physical latency remain unverified.

## Try it

1. Install the prototype APK on Android 7.0 (API 24) or newer.
2. In **Live**, select **Start service → Quick rehearsal**. Loading enters Ready without starting or changing the simulator.
3. Choose live timing or a **Fast rehearsal** speed while Ready. Select **Start first segment** and accept the untested layouts for this session.
4. Try Pause, Add time, ±2 minutes, Advance and Undo. Timer changes require confirmation. The last segment remains at zero until you act.
5. Tap a Stage cue to edit it, then **Send** to persist its text and all formatting across every service. **New cue → Send** adds another item. Choose unchanged **Cuekeeper Matrix**, new **Cuekeeper Sq-Matrix**, or imported **Times New Roman**. The countdown continues underneath; **Show timer** dismisses the cue without changing pause state.
6. Disconnect the simulator, wait, and reconnect. It receives the current output without replaying missed updates.
7. Follow the **Service timing overview**. The prominent red **End service** button shows the end screen and saves its **Report**, with CSV/JSON export and confirmed clearing of one/all records.
8. Open **Automatic warnings · this service** on Live to edit the loaded rules. Warnings use time remaining and overlay the simulator for eight seconds. Enable phone notifications, allow precise warnings where offered, and test notification sound. Android volume/Do Not Disturb still apply.
9. In Display, select **Square LEDs** or **Circular LEDs** for all simulator previews. The choice survives restart without changing any glyph or output bit.

See the [0.3 feature guide](docs/FEATURES-0.3.md) for behavior and migration, and [Display fonts](docs/DISPLAY-FONTS.md) for font import, rendering and LED shape settings.

The app keeps the screen awake while visible. Locking or closing it can suspend simulator rendering; reopening reconstructs time. Phone warnings use Android alarms independently, subject to permissions and battery restrictions. A 30-minute absence or uncertain reboot timing holds stage output for review. Continuous physical output remains outside this prototype.

## Build and test

Use Flutter stable 3.47.7 / Dart 3.13.5, JDK 21, Android SDK 36 and build-tools 36.0.0. See `docs/BUILD.md` for reproducible commands and local toolchain setup.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK uses a development signing identity. Production signing and distribution are separate release work.

## Project layout

- `lib/domain.dart`: pure service transitions, timing, snapshots, recovery and template schema.
- `lib/controller.dart`: atomic save-before-publication, failure/retry behavior and simulator adapter.
- `lib/service_features.dart`: warning rules, run metrics and reports.
- `lib/pixels.dart`, `matrix_font.dart`, `square_matrix_font.dart`: bitmap fonts, LED appearance and exact 512-bit frames.
- `lib/native_fonts.dart` and Android `TimesFont.kt`: private user font import and native rasterization.
- `lib/warning_notifications.dart` and Android `WarningNotifications.kt`: monotonic phone warning deadlines and notification delivery.
- `lib/main.dart`: responsive dashboard, template editor, import preview and display editor.
- `lib/feature_views.dart`: timing overview, warnings, font/shape settings, rehearsal controls and reports.
- `lib/platform.dart` and Android `MainActivity.kt`: suspend-aware clock, atomic local storage and document picker.
- `test/`: deterministic domain, fault injection, rendering and UI checks.
- `docs/PRD.md`: supplied requirements; historical wording about APK availability is retained as source material.
- `docs/PROTOTYPE-SCOPE.md`: implemented behavior and hardware-dependent work.
- `examples/`: portable template examples.

No original vendor code, APKs, bundled vendor fonts, private keys, passwords or machine-specific settings are included. The code is a fresh implementation informed by the supplied requirements and prior analysis.

## Import format

CSV uses UTF-8 and exact headers `Segment Name,Duration (Minutes)`. Durations are whole minutes from 1 to 99. CSV carries segments only and captures the current defaults in its preview. JSON is versioned and preserves cues/styles/end/zero settings. Hardware fields and physical approvals are rejected. Imports are limited to 1 MiB and 200 segments and remain temporary until accepted; one invalid item blocks the entire import. See `docs/TEMPLATE-FORMAT.md`.

## Physical hardware gate

Before enabling any real adapter, verify controller identity and firmware, preserve panel settings, establish command framing/acknowledgements and transient vs persistent writes, then test countdown, cue replacement, return-to-current-timer, reconnection and ordering. Run the PRD's 100-cue latency measurement and full-service endurance test on each claimed configuration. Simulator timing is not evidence of physical delivery.

# Cuekeeper — Church Service Timer

Offline Android prototype for church production timing and stage cues, with an exact 32 × 16 monochrome pixel simulator. No Huidu controller is contacted. Hardware compatibility and physical latency remain unverified.

## Try it

1. Install the prototype APK on Android 7.0 (API 24) or newer.
2. In **Live**, select **Start service → Quick rehearsal**. Loading enters Ready without starting or changing the simulator.
3. Select **Start first segment** and accept the untested layouts for this session.
4. Try Pause, Add time, ±2 minutes, Advance and Undo. The last segment remains at zero until you act.
5. Preview and send a quick cue, or compose bold/italic text. The countdown continues underneath. **Show timer** dismisses the cue without changing pause state.
6. Disconnect the simulator, wait, and reconnect. It receives the current output without replaying missed updates.
7. End the service to show the configured end screen. Templates and Display settings never mutate the loaded snapshot.

The app keeps the screen awake while visible. Locking or closing it can suspend rendering; reopening reconstructs elapsed time. A 30-minute absence or uncertain reboot timing holds output for explicit review. A foreground service and continuous physical output are intentionally outside this simulator prototype.

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
- `lib/pixels.dart`: original bitmap font, formatting and exact 512-bit frames.
- `lib/main.dart`: responsive dashboard, template editor, import preview and display editor.
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

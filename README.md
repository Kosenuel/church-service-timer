# Church Service Timer

Android church service timer with an exact 32 × 16 pixel simulator and a first hardware milestone for Huidu W2 V6.02.232, 32 × 16 red monochrome displays. Independent hardware tests verified native countdown, pause/resume using static frames, cue replacement and return to the current timer. Each program replacement briefly blinks; seamless updates and production endurance are not established.

For hardware, open **Settings → Display settings → Display connection → Connect a display**. Join the sign's Wi-Fi, scan, select the sign and enter its device password. The app remembers the identity but never saves the password. Connecting does not replace the sign's output. Start a normal-speed service, or use **Restore current output** on Live after reviewing an existing service. The profile is read and validated before any content is sent.

This milestone supports native countdowns up to **59:59**, pause/resume, time adjustments, segment changes and static cues fitting 32 pixels. Static cues retain their chosen font/style; both Matrix fonts remain unchanged. **Controller accepted** requires the final authenticated upload acknowledgement; the red preview estimates accepted content and is not optical confirmation. Keep the app open for controls. On backgrounding, reconnect or uncertain delivery, output is held for operator review. A running countdown continues independently; a cue or paused frame may remain visible until replaced.

Automatic sign warnings, scrolling/flashing sign content, longer countdowns and background control are deferred. Phone warnings retain their configured behaviour. Animated At Zero falls back to 00:00; an animated or oversized end screen clears the sign, as stated in the start/end confirmations. Simulator features are unchanged. See [hardware evidence and remaining checks](docs/w2-protocol-evidence.json).

## Try it

1. Install the prototype APK on Android 7.0 (API 24) or newer.
2. In **Live**, select **Start service → Quick rehearsal**. Loading enters Ready without starting or changing the simulator.
3. Choose live timing or a **Fast rehearsal** speed while Ready. Select **Start first segment** and accept the untested layouts for this session.
4. Use the progress arc, **Remaining / Overtime** clock and **Allocated time** to track the current segment. Try Pause, Custom (add/remove minutes and seconds), ±2 minutes, Next segment and Undo. Every action requires confirmation; adjustments preview their effect while time continues. Stage output retains the shared At Zero setting until you act.
5. Tap a Stage cue to edit it, then **Send** to persist its text and all formatting across every service. **New cue → Send** adds another item; **Delete cue** in an existing cue editor removes it after confirmation. Choose unchanged **Service Matrix**, unchanged **Service Sq-Matrix**, or bundled **Tinos** (Regular, Bold, Italic and Bold Italic). The countdown continues underneath; **Show timer** dismisses the cue without changing pause state.
6. Disconnect the simulator, wait, and reconnect. A banner appears above Live and the display badge changes from **Simulator** to **Disconnected**. The last simulated frame stays marked stale. Reconnection clears the banner and receives current output without replaying missed updates. **Display connected** identifies the authenticated W2 adapter; physical reconnection requires review before replacing output.
7. Follow the **Service timing overview**. The prominent red **End service** button shows the end screen and saves its **Report**, with clickable service records, a detailed segment breakdown, a Graph view, individual/bulk CSV/JSON export and confirmed clearing of one/all records.
8. Open **Settings → Warnings & alerts** to edit the global rules shared by every service and rehearsal. Warnings use time remaining and overlay the simulator for eight seconds. Enable phone notifications, allow precise warnings where offered, and test notification sound. Android volume/Do Not Disturb still apply.
9. In **Settings → Display settings**, open **LED preview shape** and select **Square LEDs** or **Circular LEDs** for all simulator previews. The choice survives restart without changing any glyph or output bit.

10. Open a compact row in **Templates** to see its ordered segments and end screen. Use **Edit template**, **Duplicate**, CSV/JSON exports or confirmed **Delete template** on that detail page. **New** creates a template; **Import CSV / JSON** stays below the list. **Services & Rehearsals** is the default; List options can switch to a single list. Change a template's group in the editor; this does not change timer speed.
11. Set each template’s end screen, speaker names and private operator notes in **Templates → select a template → Edit template**. Settings → Display settings holds clearly labelled defaults for new templates and the **At Zero** setting shared by every service.

See the [0.10 shared settings and Tinos guide](docs/FEATURES-0.10.md), [0.9 Feedback Center guide](docs/FEATURES-0.9.md), [0.8 compact lists and banner guide](docs/FEATURES-0.8.md), [0.7 Settings, themes and backup guide](docs/FEATURES-0.7.md), [0.6 Templates and alignment guide](docs/FEATURES-0.6.md), [0.5 Live controls guide](docs/FEATURES-0.5.md), the [0.4 feature guide](docs/FEATURES-0.4.md) for reports and template settings, and [Display fonts](docs/DISPLAY-FONTS.md) for bundled fonts, rendering and LED shape settings.

**Ready for service** offers an optional checklist and isolated preview test. **Focused operator view** keeps the timer, essential controls and cues visible. **Blank sign** clears simulator output while timing and phone warnings continue; Show timer or sending a cue restores output. The header icon opens connection details and distinguishes local rendering from physical delivery.

The app keeps the screen awake while visible by default; turn this off in Settings to use normal automatic screen sleep. Locking or closing it can suspend simulator rendering; reopening reconstructs time. Phone warnings use Android alarms independently, subject to permissions and battery restrictions. A 30-minute absence or uncertain reboot timing holds simulator output for review; physical output requires review after every background transition. Only the uploaded native countdown is established to continue independently.

## Personalize and back up

Open **Settings → Church profile** to enter your church name and choose a rectangular 3:1 banner (recommended 1200 × 400 px, up to 5 MB), or **Appearance** to preview five themes. Save to keep a theme; Cancel/back discards the preview. **Backup & restore** exports saved templates, cues, reports and preferences, including the reduced banner, and reviews a replacement before restoring. Backups exclude active clocks and phone permissions; all display fonts are bundled with the app. **About** shows creator I-Proton, the installed version, licenses and simulator status. New service reports retain the church name captured when the service was loaded.

**Settings → Feedback Center** collects a title, message and contact, then opens an email draft addressed to **immanuelproton@gmail.com**, including the installed app version. Optional diagnostics show connection/notification status and error categories for review before inclusion; they exclude church content, notes, credentials and raw error text. Review and tap Send in the phone's email app. **Copy feedback** is available if no email app can open. The form retains its text while this page remains open; it is not saved across closing the page or restarting the app. Feedback delivery depends on the email app and its connection.

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

- `lib/app_settings.dart`: church preferences, state migration helpers and portable backup validation.
- `lib/app_theme.dart`: five interface palettes, semantic colors and church/clock brand mark.
- `lib/settings_views.dart`: Settings hub, profile, appearance preview, backup and About pages.
- `lib/feedback_page.dart`, `feedback_message.dart` and Android `FeedbackEmail.kt`: validated feedback form, fixed-recipient email composition and copy fallback.
- `lib/domain.dart`: pure service transitions, timing, snapshots, recovery and template schema.
- `lib/controller.dart`: atomic save-before-publication, failure/retry behavior and simulator adapter.
- `lib/hardware_display.dart`, `hardware_output.dart`, `w2_program.dart`: serialized physical output, stable deadlines, stale-acknowledgement handling and independent W2 serialization.
- `lib/hardware_views.dart`, Android `W2Display.kt`, `w2/Hd7Auth.java`, `w2/W2Discovery.java`: guided connection, Wi-Fi-bound sockets, strict profile validation and authenticated transfer. Credentials and active connections are excluded from backups.
- `lib/service_features.dart`: warning rules, run metrics and reports.
- `lib/pixels.dart`, `matrix_font.dart`, `square_matrix_font.dart`: bitmap fonts, LED appearance and exact 512-bit frames.
- `lib/native_fonts.dart` and Android `BundledFonts.kt`: four bundled Tinos faces and native rasterization.
- `lib/warning_notifications.dart` and Android `WarningNotifications.kt`: monotonic phone warning deadlines and notification delivery.
- `lib/main.dart`: responsive dashboard, template editor, import preview and display editor.
- `lib/feature_views.dart`: timing overview, warnings, font/shape settings, rehearsal controls and shared At Zero settings.
- `lib/live_views.dart`: accessible progress arc, responsive Live controls and live confirmation previews.
- `lib/display_connection.dart`: truthful simulator/physical/disconnected status labels.
- `lib/report_views.dart`: compact report list, detail pages, charts and bulk export.
- `lib/template_views.dart`: compact template rows, detail pages, grouping and template actions.
- `lib/platform.dart` and Android `MainActivity.kt`: suspend-aware clock, atomic local storage and document picker.
- `test/`: deterministic domain, fault injection, rendering and UI checks.
- `docs/PRD.md`: supplied requirements; historical wording about APK availability is retained as source material.
- `docs/PROTOTYPE-SCOPE.md`: implemented behavior and hardware-dependent work.
- `examples/`: portable template examples.

No original vendor code, APKs, bundled vendor fonts, private keys, passwords or machine-specific settings are included. The code is a fresh implementation informed by the supplied requirements and prior analysis.

## Import format

CSV uses UTF-8 and exact headers `Segment Name,Duration (Minutes)`. Durations are whole minutes from 1 to 99. CSV carries segments only and captures the current defaults in its preview. JSON is versioned and preserves cues/styles/end settings; At Zero and warnings use the receiving device’s shared settings. JSON also preserves speaker names/private notes; CSV does not. Hardware fields and physical approvals are rejected. Imports are limited to 1 MiB and 200 segments and remain temporary until accepted; one invalid item blocks the entire import. See `docs/TEMPLATE-FORMAT.md`.

## Physical hardware gate

The first adapter is gated to the tested W2 firmware/profile. It does not change scan settings, polarities, firmware, Wi-Fi settings or passwords. Countdown publication calibrates the controller clock to the phone and sends a fixed target. The PRD's 100-cue latency measurement, full-service endurance and power-loss acceptance remain outstanding. Simulator timing and automated fake-transport tests are not evidence of physical delivery.

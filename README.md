# Church Service Timer

Android church service timer with an exact 32 × 16 pixel simulator and hardware support for Huidu W2 V6.02.232, 32 × 16 red monochrome displays. Independent hardware tests and the installed app have verified native countdown, pause/resume using static frames, time adjustment while paused, cue replacement and return to the current timer. The operator confirmed smooth counting between changes, with one brief blink at each program replacement. Seamless updates and production endurance are not established.

For hardware, open **header display chip → LED sign**. Join the sign's Wi-Fi, scan, select the sign and enter its device password. The app remembers the identity. The default-checked “Remember password on this phone” stores an Android Keystore-encrypted credential, excluded from backups. Initial connection leaves output held for review. Reconnecting the same sign during a trusted service restores its current output automatically, including a deliberate blank or clock. Restarted or uncertain sessions and explicit holds still require **Restore current output** after review. The profile is read and validated before any content is sent.

Version 0.20 supports native countdowns up to **59:59**, pause/resume, time adjustments, segment changes, static/scrolling/flashing cues and automatic stage warnings. Cues retain their chosen font/style; both Matrix fonts remain unchanged. **Controller accepted** requires the final authenticated upload acknowledgement; the red preview estimates accepted content and is not optical confirmation. An active service uses an Android foreground service and persistent notification to run warnings and connection recovery while the phone locks or switches apps. A brief connection loss can recover the latest output using the original deadline; restarting the app, an existing output hold or uncertain timing still requires review. An uploaded countdown continues independently; a cue or paused frame may remain visible until replaced. See the [display workflow guide](docs/FEATURES-0.15.md).

Stage warnings show for a configurable 1–120 seconds or one scrolling cycle, then return to the current countdown (or shared At Zero). The display duration starts after controller acknowledgement. New manual cues, Blank, Next segment and End service supersede the warning. Animated At Zero and end screens use the same frame uploader. See the [0.12 guide and verification](docs/FEATURES-0.12.md) and [earlier physical hardware evidence](docs/w2-protocol-evidence.json).

The 0.12 physical check confirmed a scrolling warning and return to the current countdown while the Android phone was locked. Next segment also restored the physical countdown after overtime. Both were independently observed by the operator; the existing brief blink at each program change remains.

Version 0.15 adds an explicit display chooser, acknowledged mobile-stage previews, rich Quick messages with saved presets, a clean end-service welcome with reliable report-save retry, and historical report printing with the recorded date. See [the update guide](docs/FEATURES-0.15.md).

Version 0.16 keeps disconnected paired screens and operators in **Saved devices**. Reconnect restores the current service without a new code; confirmed **Forget device** revokes approval. Pairing is remembered in a separate encrypted local vault, and operator control still requires an explicit handover. **Stop sharing** is now a prominent button. See [the remembered-device guide](docs/FEATURES-0.16.md).

Version 0.17 adds **Join as stage screen**, **Go to Live**, confirmed Quick messages after End service, recipient counts, themed choice sheets/chips and default password remembering. Print Service omits Planned start. See [the usability guide](docs/FEATURES-0.17.md).

Version 0.18 adds targeted mobile messages with optional **Seen** acknowledgements, per-screen layouts and groups, local draft recovery, deletion Undo, reviewed time recovery and duration insights. Print Service now generates paginated PDFs with fixed footers, preparation timestamps, copy presets and a default-checked church-name watermark. Phone warning notifications clear after 30 seconds by default, separately from the active-service notification. See [the 0.18 guide](docs/FEATURES-0.18.md).

Version 0.19 adds **Show clock** with shared 12/24-hour formatting, post-service messages, **Jump to segment**, wheel time pickers with second precision, bulk program export/import, long-press item menus, focused timing overview and current-output resynchronization. New durations stay within **59:59**; old longer records remain readable. See [the 0.19 guide](docs/FEATURES-0.19.md). The new W2 clock serializer has automated/static checks; its physical firmware behavior still requires the operator's hands-on review.

Version 0.21 adds a running-service navigation bar, searchable/pinned/recent programs, Settings search, clearer cue delivery feedback, a quieter Reports toolbar, flat expandable report details, tablet list/detail layouts, adaptive selection sheets, editable duration fields and optional time-wheel sound/haptics. Programs and Reports support **Select → Export selected** in JSON or CSV, including selections retained across filters. **Reconnect display** can request the saved sign Wi-Fi on Android 10+ before authenticating the remembered controller; Android approval and separate saved Wi-Fi credentials may be needed. See [the 0.21 guide and Wi-Fi limitations](docs/update-0.21.0.md).

Version 0.22 redesigns Live: a labelled display chip in the header, Lock and a ⋮ menu for Focused view and Ready for service, Pause and Next as the primary controls, grouped time adjustments, a one-line timing status, and cue buttons that swap to **Show timer** while their cue is showing. Wide screens get a navigation rail and a two-column Live layout. Programs and Reports are tidier. The application ID changes to `io.github.immanuelokose.churchservicetimer`, so 0.22 installs alongside earlier builds; move your setup with Backup & restore. See [the 0.22 guide](docs/update-0.22.0.md).

## Try it

1. Install the prototype APK on Android 7.0 (API 24) or newer.
2. In **Live**, select **Start service → Quick rehearsal**. Loading enters Ready without starting or changing the simulator.
3. Choose live timing or a **Fast rehearsal** speed while Ready. Select **Start first segment**, review the chosen display and confirm.
4. Use the progress arc, **Remaining / Overtime** clock and **Allocated time** to track the current segment. Try Pause, Custom (add/remove minutes and seconds), ±2 minutes, Next segment and Undo. Every action requires confirmation; adjustments preview their effect while time continues. Stage output retains the shared At Zero setting until you act.
5. Tap a prepared Stage cue to send it immediately. Manage text, formatting, order and deletion in **Settings → Stage cues**. Choose unchanged **I-Proton Matrix**, unchanged **I-Proton Sq-Matrix**, or bundled **Tinos**. The countdown continues underneath; **Show timer** dismisses the cue without changing pause state.
6. Switch destinations with the header display chip. For LED output, disconnect, wait, and reconnect. A banner appears above Live and the display badge changes from **Simulator** to **Disconnected**. The last simulated frame stays marked stale. Reconnection clears the banner and receives current output without replaying missed updates. **Display connected** identifies the authenticated W2 adapter; recovery within the same trusted active session restores current output automatically; app restart or an existing hold still requires review.
7. Follow the **Service timing overview**. The prominent red **End service** button shows the end screen, saves its **Report** and restores the welcome card with **View last service report**, with clickable service records, a detailed segment breakdown, a Graph view, individual/bulk CSV/JSON export and confirmed clearing of one/all records.
8. Open **Settings → Warnings & alerts** to add, edit, disable or remove the global rules shared by every service and rehearsal. Warnings use time remaining and overlay the selected display for the configured duration or one scroll cycle. Enable phone notifications, allow precise warnings where offered, and test notification sound. Android volume/Do Not Disturb still apply.
9. In **Settings → Display settings**, open **LED preview shape** and select **Square LEDs** or **Circular LEDs** for all simulator previews. The choice survives restart without changing any glyph or output bit.

10. Open a compact row in **Programs** to see its ordered segments and end screen. Use **Edit Program**, **Duplicate**, CSV/JSON exports or confirmed **Delete program** on that detail page. **New** creates a program; **Import CSV / JSON** stays below the list. **Services & Rehearsals** is the default; List options can switch to a single list. Change a program's group in the editor; this does not change timer speed.
11. Set each program’s end screen, speaker names and private operator notes in **Programs → select a program → Edit Program**. Settings → Display settings holds clearly labelled defaults for new programs and the **At Zero** setting shared by every service.

12. Use **Edit upcoming** in the Live rundown to change only this service’s future segments. Current/completed segments and saved programs remain unchanged. **Print Service** opens Android printing, including Save as PDF, and remains available after End service. The church banner is included by default; private notes are excluded unless selected.
13. On the host, choose **Phone or tablet** as the display, then **Share to stage screens**. To share controls while keeping the LED destination, use **Share this service** in Paired devices. On the receiving phone, tap **Join as stage screen** on the Live welcome card, select the nearby host and enter its **six-digit code**, or use **Scan QR code instead**. For viewer/operator roles, use **Settings → Paired devices → Join another operator**. Join as viewer, stage display or additional operator. The host approves each device and explicitly grants control to an operator. See the [0.13 pairing and management guide](docs/FEATURES-0.13.md).

See the [0.12 operator and hardware guide](docs/FEATURES-0.12.md), [0.10 shared settings and Tinos guide](docs/FEATURES-0.10.md), [0.9 Feedback Center guide](docs/FEATURES-0.9.md), [0.8 compact lists and banner guide](docs/FEATURES-0.8.md), [0.7 Settings, themes and backup guide](docs/FEATURES-0.7.md), [0.6 Templates and alignment guide](docs/FEATURES-0.6.md), [0.5 Live controls guide](docs/FEATURES-0.5.md), the [0.4 feature guide](docs/FEATURES-0.4.md) for reports and program settings, and [Display fonts](docs/DISPLAY-FONTS.md) for bundled fonts, rendering and LED shape settings.

**Ready for service** offers an optional checklist and isolated preview test. **Focused operator view** keeps the timer, essential controls, compact display preview and cues visible, including while blanked. **Lock controls** prevents accidental commands; hold **Hold to unlock** to resume controls. Tap rundown rows for speaker, timing and private notes; this does not advance the service. **Blank screen** toggles blank output while timing and phone warnings continue; tap **Unblank screen** to restore current output, including after End service. The header icon opens connection details and distinguishes local rendering from physical delivery.

The app keeps the screen awake while visible by default; turn this off in Settings to use normal automatic screen sleep. Locking or closing it can suspend simulator rendering; reopening reconstructs time. Phone warnings use Android alarms independently, subject to permissions and battery restrictions. A 30-minute absence or uncertain reboot timing holds simulator output for review; physical output continues through ordinary screen lock/app switching while the active-service notification is running. Force-stop, process death and network loss are not continuous-operation guarantees; reopen, reconnect and review before restoring output.

## Personalize and back up

Open **Settings → Church profile** to enter your church name and choose a rectangular 3:1 banner (recommended 1200 × 400 px, up to 5 MB), or **Appearance** to preview seven presets, including Morning Sky and Sage Linen, or create a custom accent/background/panel combination with readability checks. Save to keep a theme; Cancel/back discards the preview. **Backup & restore** exports saved programs, cues, reports and preferences, including the reduced banner, and reviews a replacement before restoring. Backups exclude active clocks and phone permissions; all display fonts are bundled with the app. **About** shows creator I-Proton, the installed version, licenses and simulator status. The Reports heading displays the current church banner with a dark gradient; individual reports retain the church name captured when the service was loaded. Reports also include an activity timeline of actions and display send/accept/failure events; JSON exports preserve these events.

**Settings → Feedback Center** collects a title, message and contact, then opens an email draft addressed to **immanuelproton@gmail.com**, including the installed app version. Optional diagnostics show connection/notification status and error categories for review before inclusion; they exclude church content, notes, credentials and raw error text. Review and tap Send in the phone's email app. **Copy feedback** is available if no email app can open. The form retains its text while this page remains open; it is not saved across closing the page or restarting the app. Feedback delivery depends on the email app and its connection.

## Build and test

Use Flutter stable 3.47.7 / Dart 3.13.5, JDK 21, Android SDK 36 and build-tools 36.0.0. See `docs/BUILD.md` for reproducible commands and local toolchain setup.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Release builds are signed with the key in `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; git-ignored) or the `CST_KEYSTORE_PATH`, `CST_KEYSTORE_PASSWORD`, `CST_KEY_ALIAS` and `CST_KEY_PASSWORD` environment variables. Without either, they fall back to the local debug key. GitHub Actions builds and uploads a signed APK on every push using the `CST_KEYSTORE_BASE64`, `CST_KEYSTORE_PASSWORD`, `CST_KEY_ALIAS` and `CST_KEY_PASSWORD` repository secrets. Use `--profile` for performance measurements or `--debug` for development.

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
- Android sources live under `android/app/src/main/kotlin/org/kosenuel/cuekeeper/` (W2 transport, credential vault, printing, fonts, notifications, foreground service).
- `test/`: deterministic domain, fault-injection, rendering and UI checks, with golden screenshots in `test/goldens/`.
- `scripts/`: standalone smoke and probe scripts; `docs/`: requirements, scope and release guides; `examples/`: portable program examples.

No original vendor code, APKs, bundled vendor fonts, private keys, passwords or machine-specific settings are included. The code is a fresh implementation informed by the supplied requirements and prior analysis.

## Import format

CSV uses UTF-8 and exact headers `Segment Name,Duration (Minutes)`. New durations must be 00:01–59:59. The optional `Seconds` column preserves sub-minute precision; old whole-minute files remain readable. CSV carries segments only and captures the current defaults in its preview. JSON is versioned and preserves cues/styles/end settings; At Zero and warnings use the receiving device’s shared settings. JSON also preserves speaker names/private notes; CSV does not. Hardware fields and physical approvals are rejected. Single-program imports are limited to 1 MiB and 200 segments; bulk bundles allow 16 MiB and 200 programs and remain temporary until accepted; one invalid item blocks the entire import. See `docs/TEMPLATE-FORMAT.md`.

## Physical hardware gate

**Clock-colon limitation (0.20):** Blinking is available on the simulator and paired phone/tablet screens. The physical LED clock and its preview retain a steady colon: no supported blink setting was identified in the inspected W2 clock path. The app does not upload a new program every second to imitate blinking. See [the investigation and remaining unknowns](docs/w2-clock-020.md).

The adapter is gated to the tested W2 firmware/profile. It does not change scan settings, polarities or firmware. Version 0.13 adds separately confirmed Wi-Fi/password administration for the observed W2 capability; these setters have code and packet checks but still need controlled physical write/reconnection tests. Countdown publication calibrates the controller clock to the phone and sends a fixed target. The PRD's 100-cue latency measurement, full-service endurance and power-loss acceptance remain outstanding. Simulator timing and automated fake-transport tests are not evidence of physical delivery.

Version 0.16 keeps paired devices saved after Disconnect and app restarts. Reconnect resumes current output without a new code; Forget device requires confirmation and new approval. See the [remembered devices guide](docs/FEATURES-0.16.md).

Version 0.20 adds local layout-density modes (Compact, Comfortable, Spacious and Automatic), high contrast, reduced motion, divider styles, consistent compact menus and clearer action buttons. Clock-colon blinking applies to the simulator and paired screens; the physical LED clock stays steady. See [the 0.20 guide](docs/FEATURES-0.20.md).

Version 0.20.1 extends the selected layout and divider style to Start service and the remaining in-app option menus. See [menu appearance coverage](docs/FEATURES-0.20.1.md).

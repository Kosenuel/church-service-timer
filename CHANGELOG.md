# Changelog

Newest first. Each release links to its full guide in `docs/history/`. Dates are when the release was built.

## Unreleased

## 0.25.0, 5/November/2026
- **Saved passwords in backups (optional).** Export backup can include the LED sign's device password and Wi-Fi reconnect details, encrypted (AES-256-GCM, PBKDF2 key) with a passphrase you choose. It is off by default. Restoring asks for the passphrase; skipping it or a wrong passphrase still restores everything else. Paired-device approvals are never included, and backups without passwords stay readable by earlier versions.
- **Settings PIN.** Optional 4–8 digit PIN (Settings → Settings PIN) that locks Settings, deleting programs and reports, and LED sign administration; Live, Programs and Reports stay open. Setting it shows a one-time recovery code that removes the PIN if forgotten. Five wrong tries wait 30 seconds, and Settings lock again whenever the app leaves the screen. Only a salted hash is stored, and it is never included in backups.
- **Pre-service countdown.** In Ready, set when the service starts. The display (simulator, stage screens or the LED sign's native clock and countdown) shows the clock until the last hour, counts down to the start, then holds "STARTING SOON" at 00:00. It never starts the service by itself; Start first segment clears the schedule.
- **Clicker and foot-pedal support.** On Live during a service, Page Down or → arms Next and a second press within 4 seconds starts the next segment; B or Space pauses and resumes. Keys are ignored while typing, in dialogs and on other tabs. Turn it off in Warnings & alerts → During a service.
- **Wi-Fi rejoin for paired phones.** When joining a host, the phone notes the Wi-Fi it is on (church Wi-Fi, the host's hotspot or the sign's Wi-Fi) and can rejoin that network, and only that network, if the link drops and the phone has moved to another. The password is optional, and storing it (encrypted) is ticked by default; unticked, it is kept only while the app runs. The reconnecting banner shows "Rejoining <network>…".
- **Faster start.** Pinned or recent programs on Live load straight into Ready. Ready shows the display and a readiness verdict inline. When the display is connected and nothing needs attention, Start first segment starts at once, with an 8-second **Undo start**; otherwise a confirmation explains what to check.
- **Live idle:** "Ready when you are" hero with Start, Share and Join; a last-service card with its timing and review note; Stage & display collapses while idle (it stays open while sharing).
- **Quick message** has its own page: preview at the top, recipients, a collapsible Style section and a pinned Send bar with Test 5 s and Save as preset.
- **Reports:** slim header with Select and a menu for Timing insights, Export and Clear; summary tiles for recent services; search with a date filter, type chips and List/Graph tabs; each row shows its total and outcome.
- **Programs:** a floating New program button, Import/Export in a menu, All/Pinned/Recent/Rehearsals chips, and a segment bar and last-used date on each row. **Program details** has Load into Live and Edit up front, actions in a menu, a coloured rundown and an end-screen row.
- **Program editor:** drag handles, tap-to-change duration chips, an end-screen row with a compact preview, and a pinned total and Save bar. Fixes "1 segments".
- **Settings pages reworked:** About (identity card, What's new from this changelog), Ready for service (verdict with one-tap fixes), Warnings & alerts (rule cards with switches, Phone alerts, During a service), LED device management (status card, saved passwords, gated sign settings), Connect a display (three steps; simulator and Wi-Fi details in the menu), Appearance (pinned preview, Theme and Layout & accessibility tabs, pinned Save).
- **Screens & devices** replaces the separate Paired devices and Stage screens pages.
- **Five new themes:** Ocean Deep, Cobalt Night, Graphite, Paper & Ink and Meadow (twelve in total).

## 0.24.0, 5/November/2026

- **Lock-screen controls:** during a service, a notification shows the current segment with a live countdown (counting up when overtime), Pause/Resume and Next segment (Next needs a second tap). On by default in Warnings & alerts; obeys Lock controls.
- **Watch-friendly warnings:** phone warnings use a distinct vibration pattern, which Wear OS watches mirror.
- **Battery check:** Ready for service shows whether Android battery optimisation could pause warnings with the screen off, and Live shows a hint before a service starts; both open the system setting.
- **GitHub Releases:** pushing a tag such as `v0.24.0` publishes a release with the signed APK, its checksum and the changelog section, after checking the tag matches the app version.
- **Reconnecting indicators.** LED sign: the header chip shows a spinner and "Reconnecting…", and Live shows the attempt count with Reconnect display and Stop trying; timer controls and cues stay usable, and the sign receives current output when it returns. Paired phones: stage screens keep the last frame with a "Reconnecting to host…" chip; operator and viewer screens show a banner, dim the controls until the host answers, and suggest Wi-Fi settings after a minute.
- **Review notes** on reports: an after-service reflection kept apart from the recorded timings, editable from the report, optional when exporting (JSON/CSV) or printing, and shown as "Last time" when the same program is loaded into Ready.
- **Delete selected** in Programs and Reports selection mode: shows the count, names items hidden by the current search or filter, confirms in red and offers a 10-second Undo that restores items exactly (order, pins, recent use). Deleting saved programs leaves a running service and past reports unchanged.
- Internal clean-up with no visible change: stricter lint rules (`flutter_lints`), `lib/` and `test/` organised by feature, behaviour-named tests, `AppController` split into focused collaborators, and this changelog.

## 0.22.0, 4 November 2026

- **Live redesign.**
  - The header shows the program and church name, a labelled display chip, a Lock icon and a ⋮ menu.
  - Pause/Resume and Next segment are the primary controls; time adjustments are grouped.
  - A one-line timing status opens the full overview.
  - Tap the segment title to jump.
  - Cue, clock and message buttons swap to **Show timer** while their output is showing, with a guard against double taps.
- Wide screens use a navigation rail and a two-column Live layout.
- Programs: one-row filters. Reports: Export and Clear move to a ⋮ menu.
- **New application ID** `io.github.immanuelokose.churchservicetimer`, so 0.22 installs alongside earlier builds. Move your setup with Backup & restore.
- Release signing and a GitHub Actions build that produces a signed APK.
- Guide: [update-0.22.0](docs/history/update-0.22.0.md).

## 0.21.0, 26 October 2026

- Running-service bar on other tabs.
- Searchable, pinned and recent programs; Settings search.
- Clearer cue delivery feedback.
- Flat expandable report details, and tablet list/detail layouts.
- **Select → Export selected** for programs and reports.
- Editable duration fields and optional picker sound/haptics.
- **Reconnect display** can request the saved sign Wi-Fi on Android 10+.
- Guide: [update-0.21.0](docs/history/update-0.21.0.md).

## 0.20.1, 26 October 2026

- Layout density and divider styles extend to Start service and the remaining option menus.
- Guide: [FEATURES-0.20.1](docs/history/FEATURES-0.20.1.md).

## 0.20.0, 26 October 2026

- Layout density (Compact, Comfortable, Spacious, Automatic), high contrast, reduced motion and divider styles.
- Clock-colon blinking on the simulator and paired screens; the physical LED clock stays steady.
- Guide: [FEATURES-0.20](docs/history/FEATURES-0.20.md).

## 0.19.0, 26 October 2026

- **Show clock** with 12/24-hour formats, post-service messages and **Jump to segment**.
- Second-precision wheel pickers, bulk program export/import and long-press menus.
- Focused timing overview and current-output resynchronisation.
- New durations stay within 59:59.
- Guide: [FEATURES-0.19](docs/history/FEATURES-0.19.md).

## 0.18.0, 20 October 2026

- Targeted stage messages with optional **Seen**, plus per-screen layouts and groups.
- Draft recovery, deletion Undo, reviewed time recovery and duration insights.
- Paginated service PDFs with footers and a watermark.
- Guide: [FEATURES-0.18](docs/history/FEATURES-0.18.md).

## 0.17.0, 19 October 2026

- **Join as stage screen**, **Go to Live** and confirmed post-service messages.
- Recipient counts, themed choice sheets, and remembering the sign password by default.
- Guide: [FEATURES-0.17](docs/history/FEATURES-0.17.md).

## 0.16.0, 19 October 2026

- **Saved devices**: reconnect without a new code, and confirmed **Forget device**.
- Encrypted pairing memory and a prominent **Stop sharing**.
- Guide: [FEATURES-0.16](docs/history/FEATURES-0.16.md).

## 0.15.0, 19 October 2026

- Explicit display chooser and acknowledged mobile stage previews.
- Rich quick messages with presets, plus a clean end-service welcome with report-save retry.
- Historical report printing.
- Guide: [FEATURES-0.15](docs/history/FEATURES-0.15.md).

## 0.14.0, 19 October 2026

- Sign connection recovery: health checks and retries with backoff, without replaying stale uploads.
- Paired control and stage readability polish.
- Guide: [FEATURES-0.14](docs/history/FEATURES-0.14.md).

## 0.13.0, 18 October 2026

- Prepared cues and removable warnings.
- Encrypted sign credentials and explicit reconnection.
- Paired viewers, stage screens and one controlling operator.
- Guarded W2 administration, upcoming-only edits and printing.
- Guides: [FEATURES-0.13](docs/history/FEATURES-0.13.md) and [DEVICE-ADMIN-0.13](docs/DEVICE-ADMIN-0.13.md).

## 0.12.0, 18 October 2026

- Stage warnings returning to the countdown, and Next segment after overtime.
- Active-service foreground service.
- Focused view, control lock, rundown details and the activity timeline.
- Guide: [FEATURES-0.12](docs/history/FEATURES-0.12.md).

## 0.11.0, 18 October 2026

- First physical adapter for the Huidu W2 32 × 16 sign: native countdown, pause/resume, adjustments and cue replacement.
- Evidence: [w2-protocol-evidence.json](docs/w2-protocol-evidence.json).

## 0.10.0, 17 October 2026

- Shared settings, Ready for service, focused operator view and bundled Tinos.
- Guide: [FEATURES-0.10](docs/history/FEATURES-0.10.md).

## 0.9.0, 17 October 2026

- Feedback Center with email composition and a copy fallback.
- Guide: [FEATURES-0.9](docs/history/FEATURES-0.9.md).

## 0.8.0, 17 October 2026

- Compact Reports and Settings lists, and church banners.
- Guide: [FEATURES-0.8](docs/history/FEATURES-0.8.md).

## 0.7.0, 16 October 2026

- Renamed to Church Service Timer.
- Church profile, seven themes, Settings, backup/restore and About.
- Guide: [FEATURES-0.7](docs/history/FEATURES-0.7.md).

## 0.6.0, 16 October 2026

- Compact program rows and consistent Live alignment.
- Guide: [FEATURES-0.6](docs/history/FEATURES-0.6.md).

## 0.5.0, 16 October 2026

- Live controls redesign: progress arc, operator overtime and confirmed adjustments.
- Guide: [FEATURES-0.5](docs/history/FEATURES-0.5.md).

## 0.4.0, 16 October 2026

- Report explorer with bulk exports, and per-program end screens.
- Guide: [FEATURES-0.4](docs/history/FEATURES-0.4.md).

## 0.3.0, 16 October 2026

- Shared live cues, phone warning notifications and display options.
- Guide: [FEATURES-0.3](docs/history/FEATURES-0.3.md).

## 0.2.0, 16 October 2026

- Service reports, warning cues, rehearsal speeds and named display fonts.
- Guide: [FEATURES-0.2](docs/history/FEATURES-0.2.md).

## 0.1.0, 16 October 2026

- First Android timer with an exact 32 × 16 display simulator.

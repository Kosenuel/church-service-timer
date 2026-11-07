# Changelog

Newest first. Each release links to its full guide in `docs/history/`. Dates are when the release was built.

## Unreleased

- **Join slide sizes.** Export join slide asks which screen it is for: 16:9 HD (1920 × 1080), 16:9 4K (3840 × 2160), 16:10 (1920 × 1200), 4:3 for older projectors (1600 × 1200), Portrait 9:16 (1080 × 1920) for a TV on its side or phone stories, or Square (1080 × 1080) for social posts and printing. Each is laid out for its shape rather than stretched: wide slides put the QR code beside the words, square ones put the title on top with the details beside the code, and portrait ones stack everything with a large code. Long names shrink to fit. Dark or light is chosen in the same dialog, the file name includes the size, and the last size is offered first next time.

- **Send to lists only screens that can receive the message.** The list shows "All connected stage screens" with a count, groups only while one of their screens is connected (for example "Choir screens · 2"), and single screens only while connected. If a chosen screen drops off while you write, it stays in the list as "Pulpit tablet · offline" and can't be picked, so the choice never changes without you noticing. With nothing connected, the list says "No stage screens connected".

## 0.26.0, 7/November/2026
- **Web Stage displays now count as stage screens.** When a browser opens Stage display, the host enables the cue buttons and quick messages as it does for a paired stage screen. Web displays appear in the message's **Send to** list, receive only messages sent to them, and Live reports "Sent to 1 web stage display". The host shows a short "Laptop · Chrome joined · Stage display" note, and the device summary counts web screens.
- **Easy name on a hotspot.** The phone now answers `.local` lookups on the hotspot or Wi-Fi network itself, not on mobile data, and also replies directly to the device that asked. If joining the multicast group is refused, it still answers direct questions. Web screens shows how many lookups it has answered, to help tell a blocked network from one that never asks.
- **Web screens, from the first real tests.** A browser shows a red "Connection to the host device lost · reconnecting…" banner and fades the stage countdown within about five seconds of the host device going quiet, even when it leaves the network without a word (requests now time out instead of waiting for minutes), and the page picks up again by itself when the host returns. The role chip now opens on a team Stage display (a tap rebuilt it before it could be pressed). Order of service marks the current item as a solid **NOW** block, with earlier items ticked and faded and **Next** on the following one. The order-of-service code is now the **guest code** (Change guest code, Needs the guest code).
- **Network changes.** While sharing, if the host device moves to another network, for example when the hotspot is turned on, it shares again at the new address by itself. Approved devices, the team code and joined browsers carry over, and a note says so.
- **Stage cues** line up evenly: cue buttons are all one height, a lone last cue fills its row, and Show clock, Send message and Blank screen sit in their own row of three.
- **Styled quick messages on web screens.** A web Stage display shows a quick message in the same colours, alignment, bold or italic and text size as a paired stage screen, shrinking long messages to fit. Web screens have no Seen button, so a Seen request lists them as "On screen (web, no Seen)" and leaves them out of the Seen count.
- **Scrolling and flashing text on web screens.** A web Stage display now scrolls long text right to left and flashes cues, at the same size and speed as a paired stage screen, instead of shrinking the text to fit. The motion carries on smoothly between updates and pauses while the host device is lost.
- **Quick messages after a service.** Test now goes to the screens in **Send to**, as Send does, so a test that works means the real message will too. When Send is unavailable it says why, for example that none of the chosen screens are connected, and a failed send shows the actual reason. A sent message closes the composer and confirms "Message sent to 1 stage screen" on Live, where it shows as On stage.
- **Choose display** is tidier: the middle choice is now **Phone, tablet or web screens**, each choice shows what is connected (for example "1 paired · 2 web connected"), and **Manage screens** is one tap away. The Live stage preview can show a web Stage display, including a message only when that display receives it.
- **Wording:** "host phone" is now "host device" everywhere, including "Reconnecting to the host device…".
- **Web screens.** While sharing, any browser on the same Wi-Fi can follow the service without the app ([docs/WEB-SCREENS.md](docs/WEB-SCREENS.md)). **Order of service** shows the rundown and what is happening now, with no times, using a 4-digit code that stays the same each week (or no code, if you choose). **Stage display** (full-screen countdown and messages) and **Service overview** (time left, ahead or behind, finish time) need the 6-digit team code, which changes each time you share and also unlocks switching between all three. Browsers can't control the service or see private notes. Open them with a short easy name made from the church name (for example `grace-community.local`), the QR code or the address. **Export join slide** makes a 1920 × 1080 image to project.
- **Send a program to a paired phone.** While sharing to screens, Program details → ⋮ → **Send to paired phone** sends the program to the connected operator and viewer phones you tick (stage screens are left out). Private notes are optional. The other phone shows a “Program received” card to review the rundown. If it already has a program with that name, **Update mine** replaces it and keeps its current version in Version history, or **Save as copy** adds it with a numbered name. Received programs wait until reviewed, even after leaving the pairing or closing the app (up to five; sending the same name again replaces the waiting one), and also show at the top of Programs. They are not included in backups.
- **Version history.** Each time you save a change to a program, the version before it is kept, up to the last 10. Program details → ⋮ → Version history lists them with what changed (for example “Added “Offering”, +4 min in total”). Tap one to see its rundown and restore it, with Undo. Restoring keeps the current name, and the version it replaces stays in history. History goes with a deleted program (and comes back with Undo) and is included in backups. A backup with history uses backup format 9; backups without it stay readable by earlier versions.
- **Segment library.** Save segments you use often, such as Offering or Announcements, with their duration, speaker, notes and protection. In the program editor, open a segment and tap **Save to library**. **From library** next to Add segment inserts one into any program, with search. Saving the same name again updates it. Programs → ⋮ → **Segment library** lists them and removes one, with Undo. Up to 50 are kept, and they are included in backups (backup format 9).
- **Import any spreadsheet.** A CSV with its own column names (for example `Item, Time (mins), Who`) now opens **Match spreadsheet columns** instead of an error. It shows the sheet, guesses which column is the name, duration, speaker, notes or program, and reads durations written as `5`, `5.5`, `05:30`, `5 min` or `90s`. A live preview lists every problem by row number. The choice is remembered, so next week's sheet in the same layout needs one tap. The result goes to the usual import review.
- **Share by Bluetooth, messaging or email.** The selection bar on Programs and Reports has **Share**, which opens Android's share sheet with a JSON or CSV file, or one PDF sheet per selected item. Print Service also has **Share PDF**. The private-notes and review-note choices work as they do for Export.
- **Open received files.** A program `.json` or `.csv` opened with, or shared to, the app goes to the usual import review. Reports and backups explain where they belong instead of failing to import.
- **Change program in Ready.** Ready now shows the loaded program with a **Change** button. Pick another program (pinned first, with search) and it replaces the loaded one. The pre-service start time and service mode stay, and the sign's countdown is unchanged. An 8-second Undo switches back. Load into Live from Program details does the same while in Ready. The start chooser marks pinned programs with a pin.
- **Programs list:** a pin icon marks pinned programs (the star toggle and each row's ⋮ menu are gone). Long-press a program to start selecting; the selection bar exports, pins or unpins, and deletes the selected programs. The Android Back key leaves selection mode.
- **Reports list:** each row's ⋮ menu is gone too; long-press a report to start selecting, then export or delete from the selection bar. Single reports still have Export, Print and Delete on their report page.
- **Live:** the Android Back key on a loaded service that has not started cancels the setup and returns to Standing by.
- **Back to exit.** Back on Programs, Reports or Settings returns to Live. On Live, it asks you to press Back again before leaving the app. During a service, it asks for confirmation and explains that the timer keeps running.
- **Program IDs.** Each saved program now has a permanent ID on this phone, so renaming one keeps its pin, recent use, unsaved edits and the review-note link from its past services. Existing programs get IDs automatically on first launch. Shared files, exports and backups leave the ID out, so earlier versions still open them, and a received program always gets its own. This is groundwork for version history and sending programs between phones.
- **Diagnostics.** A new row at the bottom of Settings → About. **Record service metrics** records the next service, then switches itself off. Once a minute and at key moments it notes memory, battery level and temperature, screen smoothness, timer accuracy, how promptly warnings fire, backgrounding and reconnections. When the service ends the phone writes a report with ✅ or ❌ against each target (smoothness, memory growth, timer drift, warnings, reconnects, and battery against this phone’s previous recording), shown on the Diagnostics page. It never records service content or people, and nothing leaves the phone until **Share recording**, which sends the report as a markdown file (footer “Created by I-Proton”) with the minute-by-minute CSV. While recording is on, Live shows a **Recording metrics** chip. **Start 2-hour test service** runs a generated service with recording on and saves no report.
- **Performance review** before each release: scrolling benchmarks, a 2-hour soak script for a USB-connected phone, and a report with pass marks ([docs/PERFORMANCE-REVIEW.md](docs/PERFORMANCE-REVIEW.md)).
- **Updating:** this version upgrades saved data on first launch (program IDs), so the phone cannot go back to 0.25 afterwards; export a backup first if you might. Backups that contain version history or a segment library use backup format 9, which 0.25 cannot open; other backups stay readable by 0.25.

## 0.25.1, 6/November/2026

- **Fewer "Output held" cards:** Undo start no longer holds the display, and cancelling a setup holds it only if the display missed the previous service's output. The card and label now appear only for a running or finished service that was interrupted, and read "Output paused after an interruption".
- **Pre-service countdown fixes:** setting a start time now releases a held LED sign, so the clock and countdown actually reach it. If output is held while the countdown waits, the row says so and offers **Show on display**. Tapping Start first segment before the scheduled time asks "Start now?" first, and the row explains that the service starts only when you tap Start.
- **Default layout density is now Automatic.** Phones use Comfortable (larger touch targets), small tablets Comfortable and large tablets Spacious. Existing installs keep their saved density until it is changed in Settings → Appearance.
- **Appearance:** the pinned preview follows the tab. Theme shows the colour preview; Layout & accessibility shows the selected density ("PREVIEW · COMFORTABLE") with sample rows and dividers, replacing the duplicate sample at the bottom of that tab.
- **Fixes:** the Live idle screen now matches its design, including right after a service ends and on tablets: a Standing by hero, Pinned or Recent programs, a Last service card, and a folded Stage & display row. Undo start and the Undo after deleting now disappear after 8 seconds instead of staying until tapped. An Undo tapped too late no longer leaves an error card that can't be closed; error cards with nothing to retry have a Dismiss button. The battery hint shows only while standing by, is shorter, and can be hidden until the app is next opened.

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

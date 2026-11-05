# Church Service Timer 0.22.0

## New application identity

The Android application ID is now `io.github.immanuelokose.churchservicetimer` (previously `org.kosenuel.cuekeeper`). Android treats 0.22.0 as a different app: it installs **alongside** earlier builds instead of upgrading them, and starts with empty local data.

To move your setup:

1. In the old app, open **Settings → Backup & restore** and export a backup.
2. Install 0.22.0 and restore that backup from the same page.
3. Re-enter LED sign passwords and pair stage screens again. Credentials, pairings and active services are never included in backups.
4. Uninstall the old app when you are satisfied.

Release builds are signed with a new release key. CI reads it from repository secrets; local builds read `android/key.properties` when present and otherwise fall back to the debug key. Future releases signed with the same key upgrade in place.

## Live screen

- The header shows the loaded program and church name, plus a labelled display chip: **Simulator**, **LED sign**, **Stage screens**, **Waiting for screen** or **Disconnected**. Tap it for connection details, as before.
- **Lock controls** is a header icon. **Focused operator view** and **Ready for service** are in the header ⋮ menu. While locked, a banner holds **Hold to unlock**.
- The timer card shows **Segment N of M**. Tap the segment title to **Jump to segment**; the separate Jump button is gone. "Next · name · duration" replaces the uppercase NEXT line.
- On phones, the timing overview is a one-line status (for example "On time · ends 12:41"). On wide screens it is a slim bar above the timer. Tap either for the full overview, including rehearsal notes.
- **Pause/Resume** and **Next segment** are the two large controls. **−2 min / +2 min / Custom** form one grouped control, and **Undo** is an icon button beside it.
- The arc keeps its tick marks. Under the number, "of 15:00 allocated" replaces the two-line Allocated time label.
- Colours each have one meaning: lime for actions, green for on time and connected, amber for warnings or running long, coral for overtime and errors.
- **End service** stays inside the timer card and is visible without scrolling on a typical phone.

## Stage cues: Show timer swap

Sending a prepared cue turns that cue's button into a filled **Show timer** button, labelled with what is showing ("WRAP UP on sign"). Tapping it removes the cue and reveals what was underneath: the countdown, the clock (labelled **Back to clock**) or, after End service, the end screen. Sending a different cue moves the swap to that button. **Show clock** and **Send message** follow the same pattern. **Blank screen / Unblank screen** is unchanged.

To avoid accidental double taps, the swapped button ignores taps for 0.6 seconds after it appears and shows **Sending…** while an LED upload is in progress. Outputs that no button represents (automatic warnings, quick messages) still get a separate **Show timer** button.

The cue card shows one plain status line ("Showing cue: WRAP UP", "Showing countdown") above the existing delivery feedback. The display preview reads "Showing: …" or "Sign accepted: …", plus "Waiting to send: …" only when the two differ.

## Tablet and wide screens

Windows at least 840 logical pixels wide use a navigation rail instead of the bottom bar. Live uses two columns: the timer and controls on the left; the display preview, stage cues, quick messages and rundown on the right.

## Programs and Reports

- Programs: the filter chips (**All**, Favourites, Recent), list options and **Select** share one row; Select is icon-only on narrow phones. Program rows drop the redundant chevron; tapping the row still opens it.
- Reports: **Export report CSV / JSON** and **Clear report** moved to the report's ⋮ menu (the app bar, or the panel header in tablet layouts). Clear report is shown in the destructive colour and still confirms.
- Report figures use neutral text; zero pauses and adjustments are muted. Variance is green when on time or ahead and amber when behind.

## Accessibility and wording

All seven themes already meet WCAG AA for secondary text (at least 5.0:1 against panels), so no colour changes were required. Developer wording such as "Intended / Simulated", "SNAPSHOT" and the Live marketing tagline was replaced with plain status text.

## Build and verification

- GitHub Actions (`.github/workflows/build.yml`) runs `flutter analyze`, `flutter test` and a release APK build on every push and pull request, and uploads the APK as a workflow artifact.
- Golden screenshots are now rendered on Linux (the CI platform). Windows runs can report small text anti-aliasing differences.
- The 59:59 maximum applies to new durations. Validation that accepts up to 99:59 remains only so older records and backups stay readable.

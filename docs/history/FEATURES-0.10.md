# Version 0.10 — shared settings and bundled Tinos

## Operator workspace

- The far-right header icon shows Simulator or Disconnected and opens connection details. The preview retains its readable badge. Display connected is reserved for a future physical adapter.
- Connection details separate adapter state, local frame publication and physical delivery. Hardware delivery is unavailable in this build.
- Optional Ready for service checks the selected timeline, connection and phone warnings. Preview test cue opens an isolated preview; it never changes the current output or clock.
- Focused operator view retains timer controls, next segment, private operator notes, live warning notices and stage cues. Exit focused view returns to the full workspace.
- Show timer, Show cue and confirmed Blank sign make output intent explicit. Blank suppresses stage warnings while phone warnings and timing continue. Blank survives restart, pause, advance and reconnect until an explicit timer/cue action or End service restores output.
- Segment speaker names and private notes are editable in templates and visible to the operator. They are never sent to the display. JSON and full backups include them; CSV remains names/durations only.

## Shared configuration

Warnings & alerts is a dedicated Settings page. The default/shared rule set is authoritative for every service and rehearsal, including the loaded session. Existing per-template overrides are normalized on upgrade; template imports adopt the receiving device's rules. Changing thresholds remaps consumed warnings by time, covers undo/prior snapshots and consumes already-passed thresholds without retroactive replay. Stage warning notices remain dismissible on Live.

Display settings is a compact index: connection, profile, LED preview shape, fonts, At Zero and default end screen. Profile values are explicitly simulator assumptions, and physical properties are Not verified. At Zero is global. Existing end screens remain per-template; the default only seeds new templates.

Appearance uses compact theme rows with palette swatches and a selected indicator. Preview/Save/Cancel behavior is retained. About contains the single Open-source licenses entry.

Services & Rehearsals becomes the default Templates view on upgrade. Subsequent explicit list preferences persist. Upgrade removes Nursery call and duplicate WRAP UP entries once, retaining the last WRAP UP entry and its formatting. Later user-created cues are retained.

## Fonts and feedback

Tinos Regular/Bold/Italic/Bold Italic are bundled under SIL OFL 1.1. Old Times selections migrate to Tinos without manual import. Both Matrix font sources/assets/rendering paths remain unchanged. See [Display fonts](../DISPLAY-FONTS.md).

Feedback now targets **immanuelproton@gmail.com** in the form, copied text and native email URI. Optional diagnostics are off by default. Enabling them takes a visible snapshot of simulator/notification status and current error categories for review; no church names, cue text, private notes, paths, credentials or raw exception messages are included. The operator still reviews and sends through the phone's email app. No automatic sending or backend was added.

## Persistence and verification

Saved-state schema 9, template schema 4 and backup schema 3 retain backward reads of earlier supported versions. Active clocks remain excluded from portable backups. No physical protocol, discovery, controller readback, brightness control or delivery acknowledgement is implemented.

Before the full Flutter build: static analysis, 115 standalone Dart checks, native Kotlin compilation, six email-format checks, font hashes/families/licenses and unchanged Matrix assets were checked. A full-build attempt stopped at flutter --version because its Git child process was denied access in this session.

On 17 October 2026, the normal-terminal build passed Flutter analysis and all **208 Flutter tests**. All **23 changed or new screenshots** were reviewed, including compact settings, connection details, optional diagnostics, focused mode, readiness, shared warnings and nested settings pages at 1.6× text scale. Existing warning persistence and end-screen snapshot tests retain their assertions while exercising the shared-warning model and new navigation. The grouping test checks both list options and persistence.

The debug APK is independently verified as **0.10.0 (code 10)**, package `org.kosenuel.cuekeeper`, label Church Service Timer, minimum API 24 and target API 36. Its v2 signing certificate matches the preceding release. SHA-256: `fc69802787190b78457aa89f794a666e2922b9a9acd902f62494ad7440b9aaae`. All four Tinos font files and both license copies inside the APK match the source assets; no legacy Times font asset is packaged. Both Matrix font sources and JSON assets remain unchanged from 0.9. The build still reports the nonfatal future Kotlin migration advisory.

On Android, check all four Tinos styles at both heights, upgrade a saved Times cue, edit shared warnings while paused and after Next/Undo, reconnect a blank simulator, and inspect focused mode and large text. Check the email destination and opt-in diagnostic content without sending unless intended. Physical-sign checks remain deferred.

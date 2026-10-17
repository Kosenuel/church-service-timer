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

Tinos Regular/Bold/Italic/Bold Italic are bundled under SIL OFL 1.1. Old Times selections migrate to Tinos without manual import. Both Matrix font sources/assets/rendering paths remain unchanged. See [Display fonts](DISPLAY-FONTS.md).

Feedback now targets **immanuelproton@gmail.com** in the form, copied text and native email URI. Optional diagnostics are off by default. Enabling them takes a visible snapshot of simulator/notification status and current error categories for review; no church names, cue text, private notes, paths, credentials or raw exception messages are included. The operator still reviews and sends through the phone's email app. No automatic sending or backend was added.

## Persistence and verification

Saved-state schema 9, template schema 4 and backup schema 3 retain backward reads of earlier supported versions. Active clocks remain excluded from portable backups. No physical protocol, discovery, controller readback, brightness control or delivery acknowledgement is implemented.

Before the full Flutter build: static analysis, 115 standalone Dart checks, native Kotlin compilation, six email-format checks, font hashes/families/licenses and unchanged Matrix assets were checked. A full-build attempt stopped at flutter --version because its Git child process was denied access in this session.

The first normal-terminal run passed analysis and 206 of 208 Flutter tests. Two older tests still used per-template warning configuration and the previous Display settings navigation; both have been updated to exercise the new behavior while retaining their persistence and snapshot assertions. The grouping test now toggles both options instead of tapping the already-selected default. All 23 generated screenshots were visually reviewed; an unsupported arrow in help text was replaced, and the large-text test now applies scaling across nested routes with its debug banner hidden. The refreshed screenshots, full test rerun and APK verification remain pending. Do not treat this source checkpoint as a verified APK release.

On Android, check all four Tinos styles at both heights, upgrade a saved Times cue, edit shared warnings while paused and after Next/Undo, reconnect a blank simulator, and inspect focused mode and large text. Check the email destination and opt-in diagnostic content without sending unless intended. Physical-sign checks remain deferred.

# Prototype scope and evidence boundaries

Version 0.11 adds the first physical adapter to the simulator prototype: Huidu W2 V6.02.232, 32 × 16 red monochrome. Protocol tests verified centered native countdown, static pause, resume, cue replacement and return to the unchanged deadline. The installed app's connection, countdown, pause, adjustment while paused, resume, AMEN cue and return to the current remaining time are also physically confirmed by the operator. Each replacement briefly blinks, including with a shared program identity; counting between changes is smooth. This is a limited hardware milestone, not a production reliability claim. See `w2-protocol-evidence.json` for exact evidence and remaining physical checks.

## Implemented

- Church branding, twelve theme presets and custom colors with cancelable previews, configurable screen awake, grouped Settings, About with author/version, and validated setup backup/restore. Reports snapshot church identity.
- Feedback Center collects title, message and contact, includes the installed version, and opens a draft to immanuelproton@gmail.com in the phone's email app. Copy fallback and confirmed draft clearing are available. The operator reviews and sends from the email app; there is no background delivery or receipt tracking.

- Separate Live, Programs, Settings and Reports views; responsive phone/tablet layouts.
- Independent loaded-service snapshot; program changes/deletion do not change the run. Shared warning settings update every program and the loaded service. Global At Zero edits explicitly update every program and loaded/prior service snapshot.
- Ready with explicit first-segment start, cancellation without prior output replay, manual final-segment ending.
- Suspend-aware Android monotonic clock; elapsed-time calculation instead of callback counting.
- Confirmed pause/resume, custom Add and ±120-second adjustments; clamp at zero; new durations up to 59:59 (older records up to 99:59 remain readable); prominent red End service control.
- Confirmed advance, elapsed-aware one-step undo, 10-second quick-undo window and modification tracking.
- Shared prepared cues: one-tap Live sending; create, format, reorder and delete in Settings → Stage cues. Editing leaves existing stage output unchanged.
- Unchanged I-Proton Matrix and I-Proton Sq-Matrix; bundled Tinos in four styles with native rasterization. No font import is required. Explicit unsupported-character and rendering errors.
- Saved square/circular simulator LED appearance, shared by Live and previews without altering output bits.
- Bold, italic, 7/14-pixel text height, horizontal alignment, scrolling speed and flash preview.
- Cue editing includes a matrix preview; Live prepared cues send immediately. A preview does not confer physical approval.
- Shared global At Zero and per-program end screens editable in the program editor; new programs copy the Display end default.
- Atomic local persistence before logical publication; failure feedback/retry; corrupt state blocks output until explicit reset.
- Running, paused, Ready, ended, alert and undo restoration; conservative 30-minute output hold and uncertainty on reboot.
- Exact 512-pixel simulator; disconnected output freezes while authoritative time continues; reconnect applies current state only.
- Unique service IDs and revisions; stale action confirmations/retries rejected. Simulator delivery is synchronous, so it has no fake wire queue or acknowledgements.
- Android document picker import/export; bounded UTF-8 reads; CSV/JSON validation, preview, conflict checks and atomic acceptance.
- Template reordering by touch and complete JSON/segment-only CSV round trips.
- Service timing overview with elapsed time, projected variance and estimated finish.
- Configurable shared warnings with operator-only or temporary simulator/physical-stage output. Stage warnings return to the current countdown, clearing prior manual cues; a new manual cue takes over immediately. Duration is configurable or one scrolling cycle.
- Android phone notifications with default notification sound, permission/settings controls and monotonic alarm scheduling independent of Flutter frame callbacks.
- After-service reports with segment actuals, pauses, adjustments, compact list/detail pages, filtered comparison charts, individual/bulk CSV/JSON export and confirmed deletion of one/all local records.
- Fast rehearsal at 5×, 10×, 30× or 60×, labelled separately from live timing.

See `history/FEATURES-0.9.md` for Feedback Center, `history/FEATURES-0.8.md` for compact lists and banners, `history/FEATURES-0.7.md` for themes and backup, `history/FEATURES-0.4.md` for reports and migration, and `history/FEATURES-0.3.md` for font/notification behavior. `history/FEATURES-0.2.md` is historical.

## First hardware milestone

- Guided Wi-Fi discovery, strict controller/profile validation, explicit device selection and password entry. Identity is remembered. Optional saved credentials are encrypted with Android Keystore; credentials and connections are excluded from portable backups.
- Authenticated HD7 upload on Wi-Fi-bound sockets. One transfer at a time, bounded identical-packet retries, read-only liveness checks and separate connection/delivery status.
- Native countdown with clock calibration, pause via a static frame, resume, time adjustments, segment changes, static/scrolling/flashing cue replacement and return to current timer. No per-second uploads.
- Cues preserve selected font and formatting. Accelerated rehearsals and remaining times above 59:59 are rejected in hardware mode before changing the run. Animation uploads contain at most 2048 frames, split into 4096-byte chunks.
- Stale successful writes invalidate the accepted-output cache and reconcile the newest intent. Failure, process interruption and reconnect hold output for review; restoring uncertain timing requires verification and retains the report uncertainty marker.
- Animated At Zero and end screens use the frame uploader. The default native countdown can remain at 00:00 without a replacement upload. Next segment clears stale cues/holds and sends its new deadline; deliberate keep-blank is offered.
- Version 0.12 adds the active Android foreground service, compact focused preview and control lock, rundown details, raised chapel branding, glass header, Reports banner and activity timeline. See `history/FEATURES-0.12.md` for evidence and boundaries.

## Version 0.13 additions

Prepared cue management, removable warnings, optional encrypted credentials, explicit physical reconnection, local encrypted device pairing with one controlling operator, viewer and stage screens, guarded W2 administration, upcoming-only live edits, finish proposals and Android printing/PDF are implemented. See `history/FEATURES-0.13.md` for the twelve items and security/recovery boundaries. Pairing coordinates this app’s instances; other controller apps remain outside its ownership model. Administration setters use the exact inspected command path but are not claimed physically validated until an intentional setting change is observed and reconnection succeeds.

## Still deferred

- Countdowns above 59:59 and a replacement method without the observed brief blink.
- Actual Test on Sign, physical-layout fingerprint approval records and profile-change acceptance.
- Broad target-device battery policy validation, process-kill recovery and full-service endurance. A foreground service is not a guarantee against force-stop or process death.
- 250 ms p95 / 500 ms maximum cue measurements, viewing-distance readability and three-hour physical endurance acceptance.

The physical connection page reads the discovered profile. There is no firmware or panel-configuration write path. Final authenticated upload acknowledgement means controller acceptance, not optical verification.

## Prototype limitations

- Simulator frames render while the Flutter UI executes. The application keeps the screen awake while visible by default (configurable in Settings), but no claim is made that rendering continues while backgrounded or terminated. Reopening calculates the current time from native anchors.
- Phone alerts obey Android permission, sound, Do Not Disturb and battery rules. Exact alarm permission does not remove sleep quotas. Reboot/force-stop can clear alarms; reopen to reschedule. Android device runtime checks are still required.
- A disconnected simulator freezes the visible frame, including animation. Real controllers may continue an uploaded animation; that behavior requires observation.
- The 30-minute absence is measured conservatively from the latest saved activity checkpoint. Wall-clock fallback across reboot is marked uncertain.
- The simulator's visual color is lime; the hardware preview is red and estimates the last accepted program. It does not claim that a physical monochrome panel can change color or that the preview is live optical feedback.
- The font covers the explicitly implemented glyph set, not arbitrary Unicode. Names can contain Unicode; LED text cannot silently substitute unsupported glyphs.
- The debug APK has development signing. Production signing, device-matrix validation and release distribution are separate work.

## Next hardware milestone

Validate recovery after network loss, app backgrounding and sign power loss on the physical sign, then run a full-service endurance test. See `history/FEATURES-0.12.md` for the current animation/background test status. Longer countdowns and midnight transitions remain unverified.

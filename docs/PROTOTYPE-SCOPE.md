# Prototype scope and evidence boundaries

This build implements a simulator-first subset of the supplied PRD. It is suitable for rehearsing application behavior before acquiring the sign. It is not a claim of Huidu compatibility, production reliability, or physical readability.

## Implemented

- Separate Live, Templates, Display and Reports views; responsive phone/tablet layouts.
- Independent loaded-service snapshot; template changes/deletion do not change the run. Live warning edits explicitly update current rules and the matching saved template. Global At Zero edits explicitly update every template and loaded/prior service snapshot.
- Ready with explicit first-segment start, cancellation without prior output replay, manual final-segment ending.
- Suspend-aware Android monotonic clock; elapsed-time calculation instead of callback counting.
- Confirmed pause/resume, custom Add and ±120-second adjustments; clamp at zero, 99:59 maximum; prominent red End service control.
- Confirmed advance, elapsed-aware one-step undo, 10-second quick-undo window and modification tracking.
- Shared Live cues: editing and Send replaces the item persistently across services; New cue and Send appends. All formatting persists; old customized cues migrate.
- Unchanged Cuekeeper Matrix plus new Cuekeeper Sq-Matrix; genuine Times New Roman Regular TTF import and native rendering. Explicit unsupported-character and missing-font errors.
- Saved square/circular simulator LED appearance, shared by Live and previews without altering output bits.
- Bold, italic, 7/14-pixel text height, horizontal alignment, scrolling speed and flash preview.
- New/untested cues require preview and confirmation on each send. No preview confers physical approval.
- Shared global At Zero and per-template end screens editable in the template editor; new templates copy the Display end default.
- Atomic local persistence before logical publication; failure feedback/retry; corrupt state blocks output until explicit reset.
- Running, paused, Ready, ended, alert and undo restoration; conservative 30-minute output hold and uncertainty on reboot.
- Exact 512-pixel simulator; disconnected output freezes while authoritative time continues; reconnect applies current state only.
- Unique service IDs and revisions; stale action confirmations/retries rejected. Simulator delivery is synchronous, so it has no fake wire queue or acknowledgements.
- Android document picker import/export; bounded UTF-8 reads; CSV/JSON validation, preview, conflict checks and atomic acceptance.
- Template reordering by touch and complete JSON/segment-only CSV round trips.
- Service timing overview with elapsed time, projected variance and estimated finish.
- Configurable warnings with operator-only or temporary simulated-stage output. Due stage warnings briefly overlay manual cues, then restore them; a new manual cue takes over immediately.
- Android phone notifications with default notification sound, permission/settings controls and monotonic alarm scheduling independent of Flutter frame callbacks.
- After-service reports with segment actuals, pauses, adjustments, compact list/detail pages, filtered comparison charts, individual/bulk CSV/JSON export and confirmed deletion of one/all local records.
- Fast rehearsal at 5×, 10×, 30× or 60×, labelled separately from live timing.

See `FEATURES-0.4.md` for current changes and migration, and `FEATURES-0.3.md` for font/notification behavior. `FEATURES-0.2.md` is historical.

## Explicitly deferred until hardware is available

- Controller discovery, address/port selection, packet framing, checksum, handshake, acknowledgements and status probes.
- Real reconnection/backoff and in-flight controller ordering/cancellation. Simulator toggles are immediate and are not network tests.
- Native countdown versus temporary frame updates versus persistent program uploads.
- Actual Test on Sign, physical-layout fingerprint approval records and profile-change acceptance.
- Native foreground service for continuous screen-locked physical output, target-device battery policy validation and hardware liveness.
- 250 ms p95 / 500 ms maximum cue measurements, viewing-distance readability and three-hour physical endurance acceptance.

There is no real controller settings page in the prototype, no speculative addresses, and no firmware or panel-configuration write path. Adding the adapter must not reuse simulator success as proof of delivery.

## Prototype limitations

- Simulator frames render while the Flutter UI executes. The application keeps the screen awake while visible, but no claim is made that rendering continues while backgrounded or terminated. Reopening calculates the current time from native anchors.
- Phone alerts obey Android permission, sound, Do Not Disturb and battery rules. Exact alarm permission does not remove sleep quotas. Reboot/force-stop can clear alarms; reopen to reschedule. Android device runtime checks are still required.
- A disconnected simulator freezes the visible frame, including animation. Real controllers may continue an uploaded animation; that behavior requires observation.
- The 30-minute absence is measured conservatively from the latest saved activity checkpoint. Wall-clock fallback across reboot is marked uncertain.
- The simulator's visual color is lime; it does not claim that a physical monochrome panel can change color.
- The font covers the explicitly implemented glyph set, not arbitrary Unicode. Names can contain Unicode; LED text cannot silently substitute unsupported glyphs.
- The debug APK has development signing. Production signing, device-matrix validation and release distribution are separate work.

## Next hardware milestone

Record the exact controller and firmware. Preserve its working panel configuration. Capture a small set of original-app exchanges and correlate them with static APK findings. Implement one minimal verified adapter and demonstrate countdown → cue → current countdown, disconnect recovery and stale-output ordering before expanding capabilities.

# Cuekeeper 0.3

## Live cues save when sent

Tap an existing Stage cue on Live, change text or formatting, then **Send**. That same item is updated for every service and survives restart. **New cue → Send** adds a reusable item to the same section. Cancel leaves everything unchanged. There is no separate Saved cue library button or extra Save step.

Font, bold, italic, height, alignment, effect and speed save together. Persistence must succeed before simulator publication. A failed write leaves the prior item/output intact and offers Retry. Customized template cues and the former named library migrate into this shared list; exact duplicate layouts combine.

## Warnings on the simulator and phone

Open **Live → Automatic warnings · this service** to edit the loaded service's rules. These edits also update its saved template, when still present. Display defaults/template editors otherwise affect future loads only.

Thresholds mean **time remaining**, not elapsed: for a three-minute segment, a 2:00 warning occurs one minute after starting. Suggested warnings are 2:00, 0:30 and 0:00, now targeting operator and simulated stage. Upgrading the old suggested operator-only set enables stage output; custom operator-only rules remain operator-only.

A stage warning overlays even a manual cue for eight real seconds, then restores that cue or the current timer. Sending another manual cue or selecting Show timer dismisses the overlay. The countdown keeps running. Pausing defers unconsumed warnings until resumed. Each threshold fires once per segment; adding time does not rearm it. If several thresholds cross together, only the most urgent is shown. Warnings above a segment's starting time are skipped unless added time makes them relevant. A disconnected/held simulator does not replay missed overlays when restored.

Editing running rules does not replay thresholds already passed. Test a future threshold or load a new service. Fast rehearsal accelerates deadlines but keeps overlays eight real seconds.

Select **Enable phone notifications**, accept Android's prompt if shown, and use **Test notification sound**. **Notification settings** opens Android's controls. **Allow precise warnings** opens alarm permission on supported versions. Both operator-only and operator-plus-stage rules produce phone notifications when enabled. The high-importance channel uses the default notification sound and opens Cuekeeper when tapped.

Android alarms schedule future phone warnings independently of Flutter rendering. Pause, time adjustments, advance, undo, changed rules and End service update/cancel future alarms. Foreground and alarm delivery share identifiers to avoid duplicates. Scheduling/permission failures appear separately and do not undo saved timer actions.

Sound obeys channel settings, device volume and Do Not Disturb. Exact alarm access improves deadlines, but Android sleep quotas and manufacturer battery restrictions can delay closely spaced alerts, particularly fast rehearsal with the phone locked. Reboot or force-stop can clear alarms; reopen Cuekeeper to recover and reschedule. There is no hard real-time background guarantee. Simulator rendering still requires the app to run; notifications are not a physical sign adapter.

## Controls and reports

Pause/Resume and ±2-minute buttons open confirmation dialogs. Add time's duration dialog requires **Confirm add time**. Adjustments use the remaining time when confirmed. Stale confirmations are rejected. **End service** is a full-width red button and still requires confirmation.

Reports have **Clear report** and **Clear all reports**, each with confirmation. Clearing removes selected local records only; exported files and an active service are unaffected. A failed save keeps records intact. Clear all captures the records listed at confirmation so a later record cannot be silently included.

## Fonts and shape

Cuekeeper Matrix is unchanged. Cuekeeper Sq-Matrix is a separate condensed bitmap face for square cells. Display lets the operator choose square or circular LEDs, saved for this device and used throughout previews. Times New Roman supports licensed Regular TTF import with native Android rendering. Service Serif and Clear Sans are removed. See [Display fonts](DISPLAY-FONTS.md).

## Upgrade and test boundaries

Local state is version 3; versions 1 and 2 migrate on load. Reports and service timing are retained. Template interchange remains schema version 2; the shared cue list and LED shape are not part of that format. See [Template format](TEMPLATE-FORMAT.md).

Tests cover transitions, warning thresholds/priority, notification plans, save failures, migrations, cue persistence, report deletion, confirmations, font bitmap logic and simulator views. Native compilation verifies API wiring. Permission prompts, audible alerts, locked-phone delivery and real imported Times rendering require installation checks in [Build](BUILD.md). Physical sign communication/readability remain unverified.

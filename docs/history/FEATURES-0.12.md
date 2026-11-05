# Version 0.12 — first agreed update

## Operator and display behaviour

- **Next segment after overtime** clears previous manual/automatic cues and restores the new segment countdown in both adapters. If output was deliberately blanked, the confirmation offers **Keep the display blank**; the default restores the timer. The hardware's native countdown remains at 00:00 while the operator clock records red overtime.
- **Focused operator view** always retains a compact Display preview, including a blanked state. **Lock controls** disables timer, cue and navigation actions; hold **Hold to unlock** to resume. This prevents accidental taps; it is not authentication or multi-operator ownership.
- **Warnings & alerts** remains shared across all services. Stage warnings support static, scroll and flash, a duration of 1–120 seconds, or one scrolling cycle. A too-short string remains static. The preview plays on request. Warning completion restores the current countdown, adjusted paused time, or At Zero rather than a stale prior cue. New manual cues, Blank, Next segment and End service supersede pending warnings. Crossed thresholds are consumed once; adding time does not replay them.
- For hardware, warning duration starts at the successful controller acknowledgement, so upload time does not shorten the warning. Scrolling uses a controller-resident sequence of monochrome frames; it does not upload every frame while playing. A later urgent warning can replace an earlier one. The controller can retain the last cue if communication or the app stops before restoration.
- **At Zero** now explains its shared behaviour, overtime, manual advancement, cue/blank precedence and the separate end screen. The overtime label and digits are both red. Pause and Resume use accessible icon-only controls with tooltips, while confirmation dialogs remain. Focused view and readiness links are underlined.
- Tap **Service rundown · snapshot** rows for planned/allocated/remaining or recorded timing, speaker and private note. The current row has a stronger background, accent edge and bold title. Opening details never advances the service; private notes are not sent to the sign.

## Background operation

An active service with an authenticated, released W2 connection starts an Android `connectedDevice` foreground service. Its persistent notification opens the app; a bounded, renewed partial wake lock and native callbacks keep the existing Flutter engine and authenticated transport active while the screen locks or another app opens. The Activity can be recreated without replacing that engine. The service stops at service end, display disconnection/hold or removal of the app task.

If the foreground service cannot start, the app says to keep it open. It does not silently promise background delivery. No automatic restart follows process death, force-stop, reboot or task removal. Reopen, reconnect and review before restoring output. Device battery restrictions and prolonged physical endurance still need installation testing. A running native countdown itself remains independent of phone callbacks.

## Appearance and reports

- Enlarged **raised chapel** church-only brand mark, tinted by the selected in-app theme. Launcher artwork uses the chapel, with an Android monochrome variant for launchers that support system themed icons. Android launcher colours follow the launcher's/system palette, not arbitrary in-app theme colours.
- **Morning Sky** and **Sage Linen** join the five existing themes. **Create custom theme** accepts accent, background and panel colours via swatches/hex values, with a preview, Reset and Cancel. Text/accent contrast is adjusted and incompatible background/panel combinations are rejected. The outer **Save appearance** commits the choice; cancel/back discards it. Custom colours are included in setup backup.
- Rounded translucent header with a clipped backdrop blur over scrolling content. Large text and phone/tablet layouts remain supported.
- Reports uses the current church banner with a dark gradient and readable title. Individual reports retain the church name captured at service load; later profile changes do not rewrite it. Historical reports do not duplicate banner image data.
- Each new report includes the latest 1,000 **Activity timeline** events: timer actions, warning requests, connection/hold events and send/accepted/failure outcomes. Acknowledgement is controller acceptance, not optical confirmation. JSON exports/backups preserve events; the existing CSV format remains a segment-duration table. Older records show an empty timeline rather than fabricated history. Events are checkpointed locally; abrupt process termination can lose the last unpersisted acknowledgement.

## Compatibility and limits

- Package ID, signing identity, existing templates/cues/reports and both Matrix fonts are preserved. New fields have migration defaults; no reset or font import is required.
- Physical support remains limited to the observed **HD_W2 V6.02.232, 32 × 16 red monochrome** profile, normal speed and at most **59:59** remaining. Frame sequences are capped at 2,048 and uploaded in 4,096-byte chunks with authenticated acknowledgements.
- Existing brief blinking at whole-program replacement is expected; seamless transitions are not promised. Controller configuration, Wi-Fi names/passwords, scan settings and firmware are untouched.
- The second update remains separate: shared operator/viewer pairing and handover, Android stage display, device administration, live rundown editing, target finish/catch-up assistance and printable service sheets.

## Verification

Automated checks cover warning timing after delayed upload, late acknowledgements, preemption, scrolling duration, return to the current deadline, pause/adjustment during a warning, overtime-to-next, explicit keep-blank, background service continuity/failure, report event persistence, custom-theme backup/contrast, focus/control locking and rundown details. UI screenshots include the two light themes, custom theme editor, focused blank/locked view, rundown details and report activity.

Physical checks on 18 October 2026 used the connected Samsung Android 16 phone and GloryArenaTimer W2 V6.02.232:

- The connected-device foreground service and partial wake lock were observed while the phone was locked. The controller accepted the scrolling **1 MIN, 30 SEC LEFT** warning and subsequent current countdown. The user independently confirmed correct scrolling and restoration, with only the existing brief blink at each program replacement.
- After deliberately reducing a segment to zero and entering overtime, **Next segment** started **Message** at 02:00. The simulator and physical sign resumed counting; the user independently confirmed the physical result.
- Ending the test saved its activity report and received an end-screen acknowledgement. The foreground service stopped. The end-screen appearance was not separately confirmed by the user.
- The final build adds header sizing/scrolling polish and chronological activity ordering to that tested implementation. Hardware transport, warning scheduling and the native foreground service are unchanged from the physically tested build.

Build hashes and verification scope are recorded in `verification-0.12.json`. Earlier countdown/pause/cue evidence remains in `w2-protocol-evidence.json`. Physical flash, scroll-once duration, process-kill/reboot, connection-loss recovery and long-duration/battery endurance are not established by this short physical test.

# Church Service Timer 0.19.0

## Stage output and clock

Use **Stage cues → Show clock** during or after a service. The underlying service countdown continues; **Return to countdown** reveals its current time. **Settings → Display settings → Clock format** selects 24-hour (default) or 12-hour with AM/PM. This preference applies across services, the simulator, paired stage screens and the LED clock. Countdown formatting stays minutes:seconds.

Prepared cues and automatic warnings can temporarily replace the clock. Clear a manual cue/message to return to the underlying clock or countdown. The output label distinguishes Countdown, Clock, Cue, Message, Blank and End screen from connection status. Blank/unblank preserves the underlying mode. **Show end screen** restores a completed service's configured ending.

**Send message** opens a formatted short-message editor and a duration selector. Choose 00:00 / **Until cleared**, or a duration up to 59:59. Sending after service end requires confirmation. Prepared cues after service end also require confirmation. Output changes do not restart the service, remove the welcome card or rewrite the completed report. Mobile-only rich Quick messages remain available with their existing recipient and Seen controls.

W2 clock output uses an autonomous controller clock widget rather than repeated frame uploads. The existing Matrix font files and countdown glyphs are unchanged. The 12-hour clock uses compact clock-only digits to fit AM/PM in 32×16 pixels. Static protocol evidence and automated payload validation are recorded in [the native-clock investigation](w2-clock-019.md). Physical clock behavior, particularly noon/midnight, remains for the operator to test. The known brief blink at program replacement may still occur.

## Timing and rundown

**Jump to segment** lists upcoming segments. Confirming finishes the current segment, marks bypassed segments Skipped, and starts the chosen segment with its full duration. Paused timing stays paused. The existing short Undo window restores the previous position and metrics. Reports distinguish Skipped from unfinished segments and retain jump and adjustment events.

The themed time picker has scrolling wheels, tap-to-type numbers and useful presets. Durations use minutes:seconds; clock targets use hours:minutes. Segment duration, custom adjustments, warnings, message duration and recovery settings preserve seconds. Each new segment/current remaining countdown is capped at 59:59, while the whole service can last longer. Existing longer programs/reports remain readable; shorten those programs before starting or saving them.

Focused view keeps a compact **Service timing overview**. Expand it for planned time, elapsed time, projected finish and timing variance.

## Connection and pairing

When a new valid device joins from an open QR dialog, the QR dialog closes and the host sees **Approve / Decline**. Approval remains explicit; operator control still requires a separate handover.

Reconnecting the same LED sign during a trusted service sends the current desired output to the physical sign and updates the app preview. It preserves deliberate blanking, clock mode and current cues, expires old timed messages, and keeps the countdown's original deadline. The preview retains the last acknowledged frame while connecting and distinguishes it from current delivery. No per-second program upload is introduced.

An explicit output hold, restarted app, changed boot/time uncertainty or extended interruption still requires operator review. Selecting a different display does not silently overwrite that sign. Firmware acceptance is separate from optical confirmation.

## Programs and reports

**Programs → Export all programs** offers JSON or CSV. JSON preserves program formatting; select **Include private operator notes** when those should travel too. CSV is a spreadsheet rundown with second precision. Import shows a preview and applies all programs together; duplicate names get a numbered suffix, and existing programs stay unchanged.

Long-press a program/report or use its three-dot menu for **Export** and **Delete**. Export is first; deletion remains confirmed. Report export offers JSON, CSV and PDF through Print Service. Deleting a saved program does not alter an already running service's snapshot.

See [program formats](TEMPLATE-FORMAT.md) for schemas, legacy compatibility and size limits. Automated validation and build results are recorded in the release verification record. Installation is followed by the operator's own hands-on testing.

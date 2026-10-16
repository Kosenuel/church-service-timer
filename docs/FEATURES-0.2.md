# Cuekeeper 0.2: timing, warnings, reports and fonts

## Rehearse a service

Load a template in Live. While it is Ready, choose Live timing (1×) or Fast rehearsal (5×, 10×, 30× or 60×), then start the first segment. The speed is fixed for that run. Segment advances and ending the service remain manual.

Rehearsal accelerates the countdown and recorded durations, including pauses. The scrolling animation, eight-second automatic stage cue and ten-second quick-undo window use real time. Rehearsals are labelled throughout the app and in exports.

## Service timing overview

Scroll below the timer and simulator to see planned total, elapsed time, current-segment duration, projected timing variance and estimated finish. Elapsed time includes pauses and time spent at zero; the countdown itself stops at zero. The projection assumes the rest of the current countdown and all later segments use their remaining planned durations. While paused, its finish estimate assumes you resume now.

In rehearsal, durations are simulated time while the estimated finish is a real local clock time. A service restored from the previous app version cannot reconstruct historical segment durations; start a new run for complete reporting. Recovery uncertainty is shown explicitly.

## Automatic warning cues

In Display, select the defaults or template you want to edit, then configure Automatic warnings. New defaults include 2 minutes left, 30 seconds left and time up, initially shown on the operator screen. Existing templates imported or saved without warnings keep their prior behavior; use the suggested warnings button to add them.

Each rule has a threshold, enabled switch, destination and fully formatted text. Up to six unique thresholds from 0 to 5,999 seconds are supported. Choose Operator + simulated stage for an eight-second overlay on the display. The start confirmation shows configured stage warnings. Changes to a template or defaults apply when loading a new service, not to an already loaded snapshot.

A warning fires once per segment, when the running countdown reaches its threshold. Pauses do not trigger warnings. Short segments skip thresholds above their starting duration. If one update crosses several thresholds, only the most urgent message appears and the crossed warnings are consumed. Adding time does not repeat warnings that have already fired.

Manual cues take priority. If a manual cue is active, output is held, the simulator is disconnected, or the app is recovering, a due warning is recorded on the operator screen without queuing a delayed stage message. Stage warnings return to the current timer after eight real seconds. Show timer can dismiss them sooner. The operator notice remains until dismissed or replaced. Undo restores the previous segment's warning state.

## After-service reports

End service saves a report atomically with the ended session. Reports shows planned and actual totals, segment durations, pauses, net time adjustments and timing variance. Export CSV or JSON through the Android document picker. These are report files, separate from portable service templates.

Actual duration measures time spent in a segment, including pauses and time at zero. Ending early records the current segment and leaves unvisited segments as not recorded. An older run without timing history is labelled incomplete rather than filled with estimates. Rehearsal durations are simulated and carry the speed label. Reports stay local until you export them.

## Saved formatted cues

Use Save to cue library in the text composer, or Create saved cue in Display. A named cue retains text, font, bold, italic, 7/14-pixel height, alignment, scrolling/flashing/static effect and speed. The library is available across services and survives restart. Select Saved cue library in Live to preview and send one.

The template's four to six quick cues also retain all these fields. Editing a library cue does not change a cue already on display or replace a template's quick cues. The shared library is local app data; template exports include that template's quick cues, not the entire library.

## Display fonts

The original display font is now named **Cuekeeper Matrix**, with its original glyphs preserved as a reusable asset. **Service Serif** is a Times-style alternative; **Clear Sans** provides a simpler alternative. Both have regular, bold, italic and bold italic variants at 7 and 14 pixels. Fine serif details are clearer at 14 pixels. Countdown digits continue to use Cuekeeper Matrix.

See [Display fonts](DISPLAY-FONTS.md) for source assets, licenses and regeneration. The simulator is still 32 × 16 monochrome pixels. Physical readability and controller compatibility await the sign.

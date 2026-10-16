# Cuekeeper 0.5 — Live service controls

The reviewed Live design is implemented with a 270-degree progress arc, tick marks, a 14 px stroke, a large operator clock and the adjusted **Allocated time**. Service name, phase, current segment and next segment remain visible. The original Cuekeeper Matrix font and both LED shapes are unchanged.

## Timing and confirmations

- The arc drains against the adjusted allocation. Enabled warning thresholds for the current segment turn the arc amber. Thresholds above a short segment's starting duration do not create an immediate warning colour.
- At zero the arc remains depleted; the clock turns red. The operator clock then counts **Overtime**, such as **+00:23**. It uses the same suspend-aware clock and rehearsal multiplier as the countdown. Pausing freezes both remaining time and overtime.
- Stage output still follows the shared **At Zero** configuration, including any active cue or automatic warning that has priority. Operator overtime does not override that setting or change the countdown font.
- **Custom** supports adding or removing minutes and seconds. Fixed ±2 minute controls and Custom show the allocation change and before/after remaining or overtime values, refreshed while the dialog is open. Removal stops at zero; addition first covers existing overtime. For example, adding 2 minutes at +00:23 produces 01:37 remaining. The maximum remaining duration is still 99:59.
- Pause/Resume, both fixed adjustments, Custom, Next segment, Undo and End service require confirmation. Opening or cancelling a dialog has no timer effect. If another action or warning changes the service revision, the stale confirmation is disabled and must be reviewed again.
- **Next segment** names the destination and planned duration. **Undo** always asks for confirmation, explains the previous segment/allocation/pause state, and accounts for elapsed time since the advance. It discards timing changes made to the accidental next segment; the active manual cue remains.
- **End service** remains a full-width red button and describes the saved report and template-specific end screen.

Controls use four columns where they fit, two columns on narrower screens, and stacked navigation actions with enlarged text. On very large text settings, gauge labels move outside the arc to preserve readability. The clock remains sized to fit its available space.

## Display connection

The display preview uses **Simulator**, **Display connected**, or **Disconnected**. The implemented adapter is a simulator, so it never reports a physical display as connected. The physical label mapping is ready for a future verified adapter; no hardware transport has been added.

A disconnected active/ended session also shows a banner above the Live card. Reconnection clears it automatically. Held output has a separate review message. A disconnected simulator retains its last frame; the current intended output is listed separately and reconnecting publishes the current state.

## Saved data

Saved-state version 5 supports a signed timing anchor so overtime survives pause, checkpoint, restart, end and Undo. Versions 1–4 still load. Existing template, report, cue, font and LED preferences are retained. Timing that was already lost by an older version cannot be reconstructed. Uncertain reboot/long-absence recovery still holds output for review.

## Verification

The new regression cases cover overtime/recovery/Undo, adjusted allocation, warning eligibility, connection labels, changing/stale confirmations, Custom cancellation and removal, and narrow layouts with enlarged text. Run `flutter test --update-goldens` and review the changed Live screenshots and new `phone-overtime.png` before distribution. Android runtime and physical-display verification remain separate.

The compact Templates listing discussed alongside this change is a design preview awaiting approval; it is not included in 0.5.

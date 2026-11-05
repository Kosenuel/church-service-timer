# Church Service Timer 0.20.0

## Appearance and layout

Settings → Appearance now offers Compact (default), Comfortable, Spacious and Automatic layout density. Automatic uses Compact on windows with a short side below 600 logical pixels, Comfortable on medium windows, and Spacious when at least 1000 × 700 logical pixels are available. Manual choices remain unchanged across orientation changes. All modes retain at least 48-pixel touch targets and respect the phone's text-size settings.

Subtle (default), Strong and Hidden divider styles apply to list rows and selection menus. Hidden retains the separator before destructive actions. High contrast strengthens text, outlines and selected items. Reduced motion suppresses navigation, dialog, sheet and connection-success transitions and interface ripples; intentional stage cue effects and the clock colon retain their own controls. System high-contrast and reduced-animation preferences also apply.

The live preview contains a sample program, active rundown item and action menu. Changes are previewed immediately but persisted only by Save appearance; Cancel/back restores the saved selection. Density, divider style, high contrast and reduced motion belong to this device. They are excluded from paired-service snapshots and portable backups; restoring a backup keeps the receiving device's preferences.

## Buttons and menus

Jump to segment is outlined, with names and allocated durations separated by subtle rules in its destination menu. Its disabled state explains why it is unavailable. The Live rundown has dividers and a bold active item marked Now. Program import/export use outlined buttons with icons; file-format choices are shown after tapping.

Program/report long-press and three-dot actions open the same compact menu. Export precedes Delete; Delete remains confirmed. Shared list, panel, control and menu styling follows density and contrast selections.

The Live welcome card places Share service beside Join as stage screen. Share service opens the existing phone/tablet host setup, including confirmation before leaving a connected LED sign. When already hosting, Manage sharing opens the paired-device controls without restarting the host or replacing its pairing code. The buttons sit side by side when space permits and stack on narrow screens or with large text.

Stop sharing now has the same confirmed behavior on Live, Stage screens and Paired devices: it closes the host and disconnects all paired screens and operators. It clears temporary messages, preserves saved device approvals, and leaves the local service and LED output running. Blank screen remains the temporary output-only control.

The welcome card's report shortcut is now labelled View last service report.

## Clock colon

Display settings → Clock format → Blink clock colon defaults to on. The simulator and paired stage clocks show one blink per second (half a second visible, half a second hidden). Only the colon changes visibility; text stays aligned and screen-reader text remains complete. Stale/offline stage clocks keep the separator visible rather than implying a live update. Countdown punctuation and timing are unchanged.

No confirmed native colon-blink setting was found in the retained LedArt clock path. The physical LED clock and its preview therefore remain steady. No per-second uploads or unverified protocol flags were introduced. See [the clock investigation](../w2-clock-020.md).

Saved-state version is 13; portable backup schema is 7 (adds clockBlink). Earlier state and supported backups remain readable. Matrix fonts and native clock/countdown payloads are unchanged.

Hands-on phone and sign testing remains with the operator.

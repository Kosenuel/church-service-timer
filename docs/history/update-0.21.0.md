# Church Service Timer 0.21.0

## Operator workflow

- A running-service strip appears while browsing Programs, Reports and Settings (including detail pages). It shows the current segment and remaining time, pause, warning or overtime. Return to Live changes navigation only.
- Programs and the Start service chooser support search, pinned favourites and recent programs. Search includes program names, segment names and speakers. Loading a program successfully records its recent use; a failed save does not.
- Programs and Reports use two-pane list/detail layouts on windows at least 1000 logical pixels wide, with the familiar single-page navigation on phones and at larger text sizes.
- Stage cues retain their selected highlight and add Sending / Controller accepted / Not sent feedback. Timed messages show their remaining return interval. Controller acceptance is a protocol acknowledgement, not visual confirmation of the physical sign.
- Reports offer search, an inclusive local-date filter and List/Graph switching. Clear all records lives in the overflow menu and still asks for confirmation.
- Individual reports use one flat segment breakdown with expandable speaker/private-note, pause and adjustment details. The duration chart and activity log can be expanded separately. Missing timing remains distinct from zero and skipped segments.
- Select in Programs or Reports enables checkboxes, a selected count, Select all shown, Clear selection and Export selected. Filtering keeps selections and displays the hidden selected count. JSON/CSV export contains only the selected saved items; cancelling the format dialog writes nothing. Program private notes remain opt-in. Existing individual and export-all actions remain available.
- Settings search opens the relevant setting directly. Examples: clock, password, font, warning, picker or banner.
- Longer selections use expandable phone bottom sheets or contained dialogs on larger windows. Export/Delete action menus stay anchored to the row/button. Confirmations use dialogs. Density and divider preferences continue to apply.
- Unavailable operator actions offer an explanation on tap/focus rather than executing a disabled action. Examples include missing stage screens, operator locking, a current save, controller administration and segment timing limits.
- Segment duration is an outlined editable min:sec field with an edit icon. The existing wheel and direct entry remain available, with the 59:59 per-segment controller limit preserved.
- Appearance → Picker feedback offers Off, Haptics only (default), Sound only and Sound + haptics. Only user wheel movement produces feedback; automatic timer ticks and restoring values do not. Native feedback is throttled and respects Android sound/touch-feedback controls. The short tick WAV is an original generated asset.

## Reconnect to the sign

Reconnect first searches for the remembered controller on the available Wi-Fi. If it cannot find it, the manual reconnect flow can request the saved sign Wi-Fi network, then rediscover and authenticate that exact controller using its saved device password.

Set the network name, security and Wi-Fi password in Connect a display → Wi-Fi reconnect details. The Wi-Fi password and controller connection password are separate. Passwords are encrypted locally through the existing Android Keystore-backed vault; they are not included in exports or logs. A password known only to Android cannot be read back by this app. If no controller password is available, the manual connection page opens.

Android 10 or newer is required for the app-driven local Wi-Fi request. Android can ask for network approval the first time, and nearby Wi-Fi permission (location on older versions). The app cannot silently turn Wi-Fi on. Open Wi-Fi settings and manual connection remain available after refusal, a timeout, unsupported Android or an unavailable sign.

The Wi-Fi request is app-scoped and local-only. W2 sockets use the selected network; the app does not bind all process traffic to it. Phone hardware and Android determine whether the request replaces the primary Wi-Fi connection. Switching networks may disconnect paired phones; an active sharing session gets a confirmation before this switch.

Cancel, explicit Disconnect, forgetting the sign, or choosing Simulator/mobile output stops LED reconnect intent and releases its network request. Android can recover a temporary loss while an approved request remains active; routine controller reconnect uses the existing bounded retry schedule. It never opens Android permission/approval prompts in the background.

After recovery, the existing output-safety rules still apply: current timer/output can be restored for the same known controller/session; uncertain timing or a new connection remains held for review. Intentional blanking is preserved. Expired cues are not replayed. Controller changes can still cause the previously observed brief blanking.

## Compatibility and validation

Local program shortcuts and picker feedback are optional additions to stored data. Older app data loads with an empty shortcut library and haptic feedback. Local shortcuts and appearance preferences stay out of portable backups. Matrix font bitmaps and W2 display encoding are unchanged.

Automated checks cover state persistence, search/filter/selection exports, navigation, layout, feedback and reconnect races. Android network approval, Wi-Fi recovery and picker sound/haptic feel require hands-on checking on the user's phone. Version 0.21.0 is installed on the Samsung after 446 passing automated tests and review of 48 screenshots. Physical testing is left to the user. See [the verification record](verification-0.21.json).

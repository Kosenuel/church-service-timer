# 0.15 — Programs and stage screens

## End a service

End service saves one completed report and returns Live to **Standing by**, with **Start service** and **View last report**. Live scrolls back to the welcome card and exits focused view. The rundown and timing overview disappear. The selected display remains connected and shows the program's configured end screen. Blank/Unblank remains available.

If saving fails, the completed information stays visible with **Retry saving report**. Retrying keeps the original finish time and produces one report; success automatically restores the welcome card. A pending save blocks service mutations.

## Choose a display

The header icon and **Change display** open **Choose display**: LED sign, Phone or tablet, or Simulator. Switching preserves the running timer and cancels LED reconnect attempts when another output is chosen. The choice survives restart. Leaving a connected LED sign offers **Blank previous sign** (waits for acknowledgement) or **Leave output**.

Phone/tablet output uses **Stage screens** to start sharing, approve devices, show the existing six-digit/QR pairing, test the intended screen, and stop sharing. Both phones need peer-reachable Wi-Fi; the W2 hotspot tested here isolates clients. Stopping stage sharing leaves paired operators and the service running. LED output and mobile stage output are exclusive destinations; operator/viewer access is a separate role.

Pairing needs a local network, not internet access. A normal router or third device's hotspot can provide that network if it permits local communication. Hosting the service on the same phone that provides the hotspot is not verified in this release: address detection currently expects an active Wi-Fi client interface. The QR code does not bypass network isolation or missing reachability.

The Live preview uses the same landscape renderer as the receiving screen and displays its most recently acknowledged snapshot. **Synced** means the app received the snapshot, not an optical confirmation or a guarantee that the screen is unobstructed. Stale output is marked disconnected. A blanked output is labelled **Screen intentionally blanked** on the operator phone.

## Quick messages

For Phone/tablet output, the Live **Quick message** card has an optional headline and body (160 characters combined, headline at most 48; up to six body lines). Choose bold/italic, alignment, four contrast-tested colour combinations, text size and 5/10/15/30 seconds or Until cleared. The preview and stage use the same uniformly scaled 16:9 composition; longer messages fit without scrolling or distortion.

Four editable presets are included. **Save as preset** and Settings → Quick message presets preserve formatting. Unsent drafts remain available when the link drops; sending requires an approved, recently acknowledging stage screen and an active service. A manual message takes precedence over automatic stage warnings while phone warnings continue. Return to timer restores the current remaining time. Blank, manual cues, segment changes, End service and disconnect discard the sent message so it cannot replay on reconnection. A test message lasts five seconds and is available before starting a service.

## Programs, reports and printing

The navigation order is **Live · Programs · Reports · Settings**. Saved plans are Programs; the editor has Program name with **Youth sunday** as its hint. Program details puts **Edit Program** near the top and confirmed **Delete program** at the bottom. Start service and End service still describe a run. Private operator notes have underlined View/Hide actions. Global warning and At Zero notices have been removed from the program editor; their settings remain shared.

Report details includes **Print Service**, with Service report and Service rundown choices. Printing uses the recorded service date; printing an unstarted program offers a date picker. Church banner is selected by default and private notes are excluded by default. New reports retain an immutable program snapshot, so later program edits cannot alter historical speakers or notes. Older records clearly indicate missing historical speaker/notes rather than copying current program data.

Settings → **LED device management** explicitly manages the LED sign's Wi-Fi and credentials. **Connect LED display** / **Reconnect LED display** opens the direct LED connection workflow. No controller configuration changes are made by installing this update.

## Compatibility

Saved-state schema 10 and backup schema 4 add output selection, rich presets and report program snapshots while preserving older supported data. Output credentials and destination selection are excluded from portable backups. Programs keep their existing schema and internal storage keys. Both Matrix font implementations are unchanged. Existing W2 countdown/transition behaviour, including the brief blink on program replacement, is unchanged.

See verification-0.15.json for automated and physical evidence and remaining limits.

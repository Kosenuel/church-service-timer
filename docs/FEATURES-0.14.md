# Version 0.14 — connection recovery and operator polish

## Display recovery

One or two missed controller health replies put the connection into a brief checking state instead of immediately disconnecting. Three misses close the old connection. The app retries the remembered controller, with a delay rising from two to thirty seconds, using the current session's credential or the optional Android Keystore-encrypted saved password. It never tries another sign or replays a queue of stale uploads.

Recovery within the same active, trusted session restores the latest output against the original countdown deadline. Starting the app again, an uncertain clock, an existing output hold or a long absence still requires review. Explicit Disconnect, Forget display or Use simulator stops automatic retries. Missing or rejected credentials require password entry. Android Wi-Fi availability, force-stop and power loss remain outside the app's recovery guarantee.

Live Reconnect display uses the saved credential first and opens connection setup when necessary. A confirmation animation follows successful manual authentication. Connection diagnostics contain event categories, not credentials or church content.

## Paired operators

Approved devices reconnect to the current host using an in-memory, encrypted resume credential. Fresh key exchange and message sequence validation still apply. Lost control returns to the host; reconnecting does not silently grant control again. Leaving, host removal or stopping sharing revokes the relevant approval. Six-digit and optional QR pairing remain unchanged.

Cue commands bind to the current service, segment and exact prepared cue. A harmless elapsed-time revision no longer rejects a valid cue, while stale segment/cue selections are rejected. Applying a cue to the service and mobile stage display does not require the separate LED sign to be online; the result tells the operator if LED output is unavailable or held.

Controls and cues use aligned grids. Leave is an accessible top-right close control. Stage mode uses landscape, immersive full screen, with tap-to-show overview/exit tools; leaving restores ordinary orientation and system bars. Stale stage output stays visibly marked. Static stage content stops its animation ticker.

Fullscreen countdowns and static cues now expand to the available screen with proportional fitting and clear margins. Scrolling cues use most of the display height and scale their travel speed with the text size. Long static messages stay on one line without clipping or distortion. Neither Matrix font's glyphs are changed.

## Live and Settings

- Manage cues is underlined at the Stage cues heading; cues send on one tap. Show cue and Plan finish are removed from Live.
- Blank screen toggles to Unblank screen and works after End service. Print Service also remains available after ending.
- The duplicate automatic-warning notice/dismiss card is removed; scheduled phone and stage warnings continue normally.
- Disconnected status is concise. Warnings and Stage cues settings have item dividers.
- Starting a segment uses a short confirmation naming its destination, without the hardware specification and warning-setting checklist.
- Controller administration explains its requirements and offers aligned Open Wi-Fi and Connect/Reconnect display shortcuts. Settings remain gated to the authenticated supported W2, available Wi-Fi, an ended service and stopped sharing.
- Current Wi-Fi name can be refreshed with Android permission. Saved passwords can be revealed and are hidden again when the app backgrounds. Only locally saved secrets are shown; the sign does not reveal its existing passwords. Saving a known Wi-Fi password does not modify the sign. Forget display is a smaller, confirmed action.

## Printing and responsiveness

Print Service includes the church banner by default, cropped without distortion and overlaid with a dark gradient for readable headings. Private notes remain opt-in; either checkbox can be changed before Android printing/Save as PDF.

Clock and LED animation notifications are separated from full-app rebuilds. Unchanged pixel frames skip repainting, and the glass header uses a less expensive blur. Distributed APKs now use Flutter release optimization with the existing local prototype signing key, preserving upgrades. This key is not a production distribution identity. Profile builds remain available through `-BuildMode profile` for measurements.

See `verification-0.14.json` for measured and on-device evidence. Administration setting changes still need intentional new values and a controlled acknowledgement/reconnection check; ordinary timer validation never changes sign passwords, Wi-Fi names, scan settings or firmware.

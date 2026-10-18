# Version 0.13.0 — prepared cues, paired devices and service planning

## The twelve update items

1. Connect a display is a short, focused workflow: Wi-Fi, scan/select, credential and result. The W2 capability limit is retained; obsolete milestone prose is removed.
2. Warnings & alerts describes the active-service notification and recovery in one place.
3. Use simulator instead is an outlined button with confirmation.
4. Shared warnings can be edited, disabled or deleted. An already accepted stage warning completes its duration, then returns to the current countdown. Deletion does not replay passed thresholds.
5. Live prepared cues send on one tap. Settings → Stage cues owns create/edit/delete/reorder and formatting. Editing a prepared cue does not change output already on stage. Offline physical cues are rejected, not queued.
6. Live offers Reconnect display. Scanning preselects only the remembered identity. A password is saved only with the operator’s opt-in, encrypted by Android Keystore; forgetting it does not change the controller. Authentication and Restore current output remain separate deliberate actions.
7. Labels are I-Proton Matrix and I-Proton Sq-Matrix. Persisted IDs, bitmap glyphs, rendering and controller countdown data are unchanged.
8. Paired viewers/operators use encrypted local links and explicit host approval. One phone hosts the clock, persistence and sign connection. At most one approved operator receives control; the host can reclaim it. Disconnect returns control to the host. Handover/reclaim events enter the active report.
9. A paired Android phone/tablet can be a stage display with large countdown/cue text, scrolling/flashing, blank state and stale indication. Viewer/stage modes exclude private notes and prepared-cue lists. Stage mode keeps the screen awake and freezes animation on a stale link. It is a large text presentation, not an optical copy of the physical LED sign.
10. Device management shows remembered hardware and optionally saved credentials; supports forgetting the display. Exact W2 V6.02.232 administration controls have independent SSID, Wi-Fi-password and device-password setters. Changing settings requires no active service or paired sharing and a review/confirmation. No alternative password protection is automatically cleared. See [administration evidence and limits](DEVICE-ADMIN-0.13.md).
11. Edit upcoming changes only future rows in the active service. Existing metrics/current clock and saved template are preserved. Plan finish shows proposed whole-minute reductions (minimum one minute per future segment), and rechecks the proposal on confirmation. Manual advances and pauses can change the actual finish.
12. Print service sheet works from template details and the live rundown. Android’s print screen offers print or Save as PDF. Private notes require an unchecked-by-default opt-in. Names, speakers and notes are HTML-escaped; the renderer cannot load network/file resources.

## Pair two Android devices

1. Install this version on both devices. Join the same local Wi-Fi. Some sign hotspots/router settings isolate clients; if devices cannot reach each other, pairing needs a LAN that permits peer traffic. Internet access is unnecessary.
2. Keep the main phone as the host/sign connection. Settings → Paired devices → Share this service shows a six-digit code and an optional QR code. New code replaces both invitations without disconnecting approved devices.
3. On the second device, open Settings → Paired devices → Join another operator. Choose a device name and role, select the nearby host and enter its six digits (including leading zeros). Alternatively, choose Scan QR code instead and scan the host's QR code; camera access is needed only for scanning. Both methods work without internet. Nearby discovery advertises the host name and port, never its pairing secrets. If discovery is unavailable, QR pairing can connect directly; neither method bypasses Wi-Fi client isolation.
4. Approve the joining device on the host. An operator initially only views the service; give it control explicitly or approve its request. Granting control makes private rundown notes available to that operator. Viewers and stage displays never receive them.
5. The host remains responsible for the timer and sign, including after handover. Keep it powered and connected. Active sharing uses the foreground service; force-stop/process death/network loss can interrupt delivery. A stale receiver freezes its last state and disables control. Rejoin with a fresh code after disconnection.
6. The host banner always offers Manage devices and control. Take back control restores its controls. End service can be issued by the current operator, with confirmation.

## Security and privacy boundaries

Both invitations expire after 10 minutes and are not persisted. The six-digit code is uniformly generated with a secure random source. PIN entry uses PointyCastle's SRP-6a password-authenticated exchange with the fixed RFC 5054 3072-bit group and SHA-256, mutual proof verification, and a challenge-bound HKDF-SHA256 session key. The PIN is never sent across the network or used directly as an encryption key. Each invitation permits five PIN handshakes, including successful attempts; New code resets this limit. The optional QR invitation carries a separate random 256-bit secret and uses the existing X25519/HKDF exchange. QR pairing remains available if PIN entry is locked. Expired/replaced invitations cannot complete an in-flight handshake.

AES-256-GCM encrypts messages. A connection challenge and strictly increasing sequence numbers reject cross-session reuse and replay. Each operator command includes a lease epoch and service revision. The host alone validates and commits commands; no service ownership is migrated to a peer. Pending connections have message/time/connection-count limits and require host approval. The short-code protocol is covered by integration tests, not an independent security audit.

This system coordinates Church Service Timer instances. It cannot prevent a separate app, such as LedArt, from using the sign’s controller password. Keep controller credentials with trusted operators and use a protected Wi-Fi network. Saved credentials are excluded from portable backups and feedback diagnostics. The saved-password display hides again when the app backgrounds. No API claims to recover the controller’s existing plaintext password.

## Administration outcome and recovery

The actual sign’s read-only discovery returned W2 V6.02.232, HD7=1, password complexity=1. The setter schemas are supported by inspected LedArt code; there have been no physical administration writes during development. The transport sends one authenticated request without automatic retry and closes its session after an attempt. An ACK means the controller accepted a request, not that reconnection using the new setting was proven. A missing ACK is explicitly an uncertain result; reconnect and verify before retrying. Password setters never offer a blank password/disable-lock option.

## Verification

- Full Flutter analysis/tests and APK build: recorded in `outputs/prototype-build-result.json` and the final version delivery notes.
- 36 native administration builder checks passed, including exact expected bytes and validation bounds.
- Pairing integration tests use real loopback sockets: encrypted framing, corruption/replay rejection, pending approval heartbeat, one operator, stale revision rejection, privacy and disconnect/reclaim.
- Widget previews cover cues, paired-device setup, device management, upcoming editor, printing and stage display. Existing Live, Settings, fonts, warning and connection previews are refreshed.
- Physical two-device and print checks are recorded separately after installation. No production endurance or independent cryptographic security audit is claimed.

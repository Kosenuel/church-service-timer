# 0.16 — Remembered paired devices

Disconnect now pauses a device's service session and keeps it in **Saved devices**. It receives no service snapshots and cannot request or exercise control while disconnected. **Reconnect** on the host resumes the current service output without a new pairing code. Expired messages are not replayed. Other connected screens keep running.

**Forget device** is separate and requires confirmation. It revokes the saved approval; the device must pair again and receive host approval. Reject still rejects a pending, unapproved device. Leaving from a receiver retains its saved host but disables automatic joining until the user chooses **Reconnect saved host**.

Paired devices and Stage screens use the same list. It shows the device name, role, connection state and last-seen time. Saved devices remain visible when sharing stops and after restarting the app. Selecting Reconnect while hosting is stopped starts hosting first. If the receiver is unavailable, open Church Service Timer on it and connect it to the same reachable Wi-Fi network. An operator always needs a fresh explicit control handover after disconnection, even when its approved role is remembered.

The host stores approvals and the receiver stores its last approved host in a separate Android Keystore-encrypted vault. These credentials are excluded from portable app backups, printed documents and diagnostics. No private notes, timer snapshots or message contents are stored in this vault. Existing programs, reports and LED credentials are retained.

A disconnected receiver keeps only an encrypted availability channel while its app is open, allowing the host's Reconnect button to work without user interaction on the receiver. After network loss, that channel may recover, but the paused service session remains paused until the host reconnects it. The receiver clears its previous service display and operator controls. A normal accidental connection loss on an active session continues to recover automatically.

The host retains its listening port where possible. If its address or port changes, a remembered receiver can locate its host through local discovery and must still authenticate with the saved pairing secret. An explicitly stopped receiver does not automatically rejoin after restarting. Starting hosting is still an explicit host action; it does not automatically resume on host app launch.

This remains a local-network feature. Devices must be reachable on the same network. The tested W2 hotspot isolates clients; host-provided Android hotspot address detection remains outside this update. The app supports one host and multiple stage receivers; the available socket limit is eight simultaneous connections, including pending pairing connections. All stage screens share the same service output.

Both Matrix fonts and the LED-controller protocol are unchanged. Older receiver builds do not implement remembered pause/reconnect; update both sides before using this workflow.

**Stop sharing** is now a prominent, theme-aware button with a stop-sharing icon, bold text and a contrasting background, both on the Paired devices page and in the mobile-stage controls. Its confirmation remains in place.

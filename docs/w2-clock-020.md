# Clock-colon blinking investigation — 0.20

Date: 2026-10-26. Scope: retained LedArt-Lite 2.3.14 Android clock model, serializer and preview path. No phone, sign or network operations were performed.

## Decision

No supported controller-side colon-blink setting was identified. The existing native clock payload and intended LED preview stay unchanged. No invented flags, unverified time-style values or per-second program uploads are used.

`W2Program.clock(format12Hour:, programId:)` and `W2Program.clockPixels(wall, format12Hour:)` remain unchanged. Blinking is applied separately to simulator and mobile/tablet clocks. The physical preview does not imply unsupported blinking.

## Evidence

These are ordinary retained JADX Java/smali observations, not REA MCP Evidence records; REA MCP tools were unavailable. Artifact identity and source hashes are recorded in [the 0.19 investigation](w2-clock-019.md). Sources below are relative to the workspace root.

| Source | Observation |
| --- | --- |
| `work/ledart/code/cn/huidu/singlecolor/model/widget/Clock.java` | Fields cover numeric/analog type, styles, colors, timezone, spacing, positions and date/week/AM-PM visibility. No blink or separator-visibility property exists in this retained class. |
| `work/ledart/code/cn/huidu/singlecolor/model/Widget.java` and `Node.java` | Widget adds no fields; Node contains children, name, tag and UUID. No inherited blink option was found. |
| `work/ledart/code/F0/f.java:3398`, complete `i(Clock,...)` method | Writes the 94-byte native clock header and glyph tables. No blink flag, second-parity option or separator animation timing was identified. |
| `work/ledart/hardware-format/F0/f.smali:10040` onward | Corroborates the 0x32 header writes. Numeric clocks zero analog-hand fields; these are not evidence of reserved blink flags. |
| `work/ledart/code/G0/f.java:716`, time-style selection | Styles 0, 1, 6 and 7 concatenate a literal colon. Seconds determine seconds text or analog-hand position, not colon visibility. |
| `work/ledart/code/cn/huidu/singlecolor/model/effect/Effects.java` and `F0/f.java` | Animation timing belongs to the separate 0x30 image/frame path and does not establish a digital-clock separator control. |

A bounded search across retained Java/smali and available native string inventories found no clock-linked blink field. An isolated `drawBlink` string in `libapp.so.strings.txt` has no established relationship to this clock path.

## Limits

This does not prove every W2 firmware lacks blinking, or that firmware cannot blink by default. Controller firmware and vendor protocol documentation were unavailable; optical cadence remains for user observation.

An animated colon area over a native clock with a blank colon would require unverified area overlap/compositing and animation phase behavior. It is not a known native setting and was not implemented. A vendor-documented flag, or a genuine LedArt setting with before/after payloads, would provide a basis for further work.

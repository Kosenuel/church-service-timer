# W2 autonomous clock — 0.19 investigation

Date: 2026-10-26. Scope: the existing W2 V6.02.232, 32×16 red-monochrome profile. No phone, sign, or network actions were performed for this investigation. Native clock output is implemented from static evidence, **not yet physically verified**. The prior countdown and upload tests do not establish clock support on this firmware.

## Evidence and confidence

The REA workflow was applied to retained LedArt-Lite decompilation. These are ordinary local JADX Java/smali observations, not new REA MCP Evidence records. REA tools were unavailable in the current session. The original APK path is no longer present, so its identity comes from the earlier `w2-protocol-evidence.json` record: LedArt-Lite 2.3.14 (157), base APK SHA-256 `4f36553aac8a221726e4d9e20a232133f4547d9fb53c87658677e6c3ac95f6ae`.

Retained workspace sources, relative to the workspace root:

| Source | Observation |
| --- | --- |
| `work/ledart/code/cn/huidu/singlecolor/model/widget/Clock.java` | Numeric clock type 0, analog type 1; styles 1=`HH:mm`, 6=`08:59 AM`, 7=`AM 08:59`; separate time-zone, AM/PM and layout fields. |
| `work/ledart/code/F0/f.java:3070`, especially 3398–3491 | Clock serializer `i(Clock,...)` emits widget 0x32, 94-byte header, big-endian dimensions and area-relative bitmap offsets. Numeric glyph order is `0123456789/:,-.`; suffix table contains AM then PM. |
| `work/ledart/hardware-format/F0/f.smali:10040` | Raw bytecode independently confirms the 0x32 discriminator and clock-header field writes, avoiding reliance on the larger method's decompiler control-flow warnings. |
| `work/ledart/hardware-format/p000a/b.java` | `c` writes 16-bit, `e` writes 32-bit, `f` writes 8-bit values; multibyte fields are big-endian. |
| `work/ledart/code/F0/a.java` | Glyph bitmaps are row-major monochrome, each row padded to 8-bit width. |
| `work/ledart/code/G0/f.java:716` | Android clock preview selects Calendar.HOUR for styles 6/7 and HOUR_OF_DAY otherwise. It does **not** prove controller-side hour conversion; noon/midnight remains a physical check. |

Retained-source SHA-256:

- `F0/f.java`: `8c1b69a4f74a80cc1df5657d229017a610b47244fb479171ec2be2c85fd20807`
- `F0/f.smali`: `956944e569cc4ef290cafd76ba45da6bf2abbb96dd7fed06e268abb1cb42c1f1`
- `Clock.java`: `7ce53cacf45475e0ec006f9eba4e733ce187a193856ea58361603dd504480108`

High confidence: native clock widget schema and style values in the shipped Android library. Inference: the selected W2 firmware can execute this widget autonomously, as intended by that library. Unknown: actual firmware acceptance, optical layout/centering, RTC drift, 12-hour rollover at noon/midnight and behavior across power loss. No firmware-specific clock capability reply has been observed.

## Implemented API and layout

```dart
final payload = W2Program.clock(
  format12Hour: clockFormatIs12Hour,
  programId: existingProgramIdentity,
);
final previewPixels = W2Program.clockPixels(
  DateTime.now(),
  format12Hour: clockFormatIs12Hour,
);
```

`clockPixels` returns 512 row-major booleans and converts its argument to the phone's local timezone. It models the intended output, not a sign framebuffer readback.

- 24-hour: five 6px cells, 30px total centered horizontally; original Matrix digits, 14px high by vertical doubling.
- 12-hour: dedicated 3px-wide digit recipes in 4px cells plus a 12px suffix containing the original Matrix A/P/M shapes. Total 32×14px. These compact clock-only cells do not replace or modify either named Matrix font or the existing countdown serializer. Preview uses conventional 12:xx at noon/midnight; the native style's rollover must be checked by the user.
- Program length 444 bytes (24-hour) or 500 bytes (12-hour); clock widget begins 140, glyph data begins 234, area begins 99.
- Date/week/analog background disabled. Clock timezone difference is zero because the RTC is calibrated to phone local wall time.
- No current timestamp or deadline is stored in the program; the controller is expected to advance its clock locally without repeated program uploads.

## Integration and RTC

Send through the existing `sendDisplay` path with `deadline`/`targetWall` **null**. `W2Display.send` recognises 0x32 internally, validates the complete 94-byte clock header and allowed container geometry, calibrates RTC using command 20, then uploads through commands 2/3/4. The caller must not pass a countdown deadline for a clock payload.

Calibration is the existing 14-byte command 20 body: length 14, local epoch seconds u32BE, zero byte, two zero u32 values. Local seconds are `(System.currentTimeMillis() + TimeZone.getDefault().getOffset(now)) / 1000`. The clock widget adds no further timezone offset. Do not put UTC seconds into this existing controller convention or add the timezone twice. This change also extracts the countdown's existing RTC write into the same helper; countdown target logic is otherwise unchanged.

Clock output deduplication should use mode, format, connection generation and timezone identity/offset, **not current seconds/minutes**. Redraw the in-app preview as time changes without uploading. Re-upload/recalibrate after reconnect, explicit clock selection, format change, wall-clock correction or timezone/DST change. A controller offline during a timezone change cannot infer the phone's new timezone. Keep acknowledged delivery separate from intended preview.

## Checks and remaining physical review

Five standalone Dart cases passed: header/pointer layout, unchanged original Matrix digits and countdown bytes, all 1,440 times of day in each format against an independent bitmap-table reader, explicit AM/PM glyph differences, stable time-independent payloads and rejected program identities. The same cases are included in Flutter via `test/w2_clock_test.dart`. Native Kotlin compilation passed with the existing `allNetworks` deprecation warning. A reflection-only validator check accepted both encoded fixtures and rejected 54 malformed headers/geometries (56 cases total); it did not construct an Android context or access any device/network.

The user should check 24-hour output, 12-hour legibility, noon/midnight, a minute transition, continuation when phone Wi-Fi is disabled, and return from a cue/blank/end screen. Firmware rejection should be reported as a failed clock send, never silently substituted with a frozen screenshot. Full program replacement may produce the already-observed brief blink. No claims of physical verification are made here.

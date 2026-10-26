import 'dart:math';
import 'dart:typed_data';

import 'matrix_font.dart';

/// Minimal 32x16 red-monochrome W2 program. No hardware configuration fields.
/// Program integers are big-endian; this is separate from HD7 packet framing.
class W2Program {
  /// Autonomous digital clock, based on LedArt-Lite's native 0x32 widget.
  /// The sender must align the controller RTC with the phone's local time.
  /// Hardware layout and noon/midnight transitions await physical validation.
  static Uint8List clock({bool format12Hour = false, List<int>? programId}) {
    const headerLength = 94;
    const height = 14;
    final digitWidth = format12Hour ? 4 : 6;
    final suffix = format12Hour
        ? [..._clockSuffix(false), ..._clockSuffix(true)]
        : <int>[];
    final numbers = BytesBuilder(copy: false);
    // Native clock glyph indices, recovered from F0.f.i(Clock,...).
    for (final char in '0123456789/:,-.'.split('')) {
      numbers.add(_clockCell(char, compact: format12Hour));
    }
    final numberBytes = numbers.takeBytes();
    final bytes = _container(
      headerLength + suffix.length + numberBytes.length,
      programId,
    );
    final b = ByteData.sublistView(bytes);
    const widget = 140;
    const area = 99;
    const dataOffset = widget + headerLength - area;
    b.setUint16(widget, headerLength);
    bytes[widget + 2] = 0x32;
    // Numeric clock, zero timezone difference, no date/week, one line.
    bytes[widget + 6] = 0xff;
    bytes[widget + 7] = 0xff;
    bytes[widget + 8] = format12Hour ? 6 : 1;
    b.setUint16(widget + 29, height);
    b.setUint16(widget + 31, digitWidth);
    b.setUint32(widget + 35, dataOffset); // No month names.
    b.setUint32(widget + 41, dataOffset); // No weekday names.
    b.setUint16(widget + 47, format12Hour ? 12 : 0);
    b.setUint32(widget + 49, dataOffset); // AM, then PM bitmap.
    b.setUint32(widget + 53, 1); // Red on a monochrome sign.
    b.setUint32(widget + 65, dataOffset + suffix.length);
    b.setUint32(widget + 69, bytes.length - area); // No Chinese glyphs.
    b.setUint32(widget + 73, bytes.length - area); // No analog background.
    // showAmPm at +85 belongs to the analog clock; numeric style 6 includes it.
    b.setUint32(widget + 86, 1);
    bytes.setRange(
      widget + headerLength,
      widget + headerLength + suffix.length,
      suffix,
    );
    bytes.setRange(
      widget + headerLength + suffix.length,
      bytes.length,
      numberBytes,
    );
    return bytes;
  }

  /// Intended 32x16 clock preview, sharing the exact uploaded glyph cells.
  /// This does not read the sign's framebuffer or establish physical delivery.
  static List<bool> clockPixels(DateTime wall, {bool format12Hour = false}) {
    final local = wall.toLocal();
    final hour = format12Hour
        ? (local.hour % 12 == 0 ? 12 : local.hour % 12)
        : local.hour;
    final text =
        '${hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final pixels = List.filled(512, false);
    final width = format12Hour ? 4 : 6;
    var left = format12Hour ? 0 : 1;
    void draw(List<int> packed, int cellWidth) {
      final stride = (cellWidth + 7) ~/ 8;
      for (var y = 0; y < 14; y++) {
        for (var x = 0; x < cellWidth; x++) {
          pixels[(y + 1) * 32 + left + x] =
              packed[y * stride + x ~/ 8] & (1 << (7 - x % 8)) != 0;
        }
      }
      left += cellWidth;
    }

    for (final char in text.split('')) {
      draw(_clockCell(char, compact: format12Hour), width);
    }
    if (format12Hour) draw(_clockSuffix(local.hour >= 12), 12);
    return pixels;
  }

  // Dedicated compact clock cells make HH:mm + AM/PM fit a 32px row.
  // Neither named Matrix font nor the countdown glyph recipes are changed.
  static const _compactClock = <String, String>{
    '0': '111/101/101/101/101/101/111',
    '1': '010/110/010/010/010/010/111',
    '2': '111/001/001/111/100/100/111',
    '3': '111/001/001/111/001/001/111',
    '4': '101/101/101/111/001/001/001',
    '5': '111/100/100/111/001/001/111',
    '6': '111/100/100/111/101/101/111',
    '7': '111/001/001/010/010/010/010',
    '8': '111/101/101/111/101/101/111',
    '9': '111/101/101/111/001/001/111',
    '/': '001/001/010/010/010/100/100',
  };

  static List<int> _clockCell(String char, {required bool compact}) {
    final pattern = (compact ? _compactClock[char] : null) ?? glyphs[char]!;
    final width = compact ? 4 : 6;
    final rows = pattern.split('/');
    final left = (width - rows.first.length) ~/ 2;
    final packed = <int>[];
    for (final row in rows) {
      var value = 0;
      for (var x = 0; x < row.length; x++) {
        if (row[x] == '1') value |= 1 << (7 - left - x);
      }
      packed.addAll([value, value]);
    }
    return packed;
  }

  static List<int> _clockSuffix(bool pm) {
    final first = glyphs[pm ? 'P' : 'A']!.split('/');
    final second = glyphs['M']!.split('/');
    final packed = <int>[];
    for (var y = 0; y < 7; y++) {
      final row = '0${first[y]}0${second[y]}';
      var value = 0;
      for (var x = 0; x < 12; x++) {
        if (row[x] == '1') value |= 1 << (15 - x);
      }
      packed.addAll([value >> 8, value & 255, value >> 8, value & 255]);
    }
    return packed;
  }

  static Uint8List countdown(int localEpochSeconds, {List<int>? programId}) {
    if (localEpochSeconds < 0 || localEpochSeconds > 0xffffffff) {
      throw ArgumentError('Target time is outside the controller range.');
    }
    // Original Matrix bits, doubled vertically, with a blank spacing column.
    // Font definitions and the simulator renderer are deliberately unchanged.
    final bitmap = BytesBuilder(copy: false);
    for (final char in '0123456789:::'.split('')) {
      for (final row in glyphs[char]!.split('/')) {
        var packed = 0;
        for (var x = 0; x < row.length; x++) {
          if (row[x] == '1') packed |= 1 << (7 - x);
        }
        bitmap.add([packed, packed]);
      }
    }
    bitmap.add(Uint8List(14)); // Positive-width, blank seconds suffix.
    final pixels = bitmap.takeBytes();
    final bytes = _container(57 + pixels.length, programId);
    final b = ByteData.sublistView(bytes);
    void u16(int at, int value) => b.setUint16(at, value);
    void u32(int at, int value) => b.setUint32(at, value);
    const t = 140;
    u16(t, 57);
    bytes[t + 2] = 0x34;
    bytes[t + 3] = 3; // Minutes and seconds only.
    u32(t + 4, localEpochSeconds);
    u16(t + 8, 3);
    u16(t + 10, 1);
    bytes[t + 12] = 13; // Colon style.
    u16(t + 15, 6); // Five-column Matrix digit plus spacing column.
    u16(t + 17, 14);
    u16(t + 19, 2);
    u16(t + 21, 2);
    u16(t + 23, 2);
    u16(t + 25, 2);
    // Empty title; both bitmap offsets are area-relative.
    u32(t + 29, 98);
    u32(t + 33, 98);
    u32(t + 37, 1);
    u32(t + 41, 1);
    u32(t + 45, 1);
    bytes.setRange(197, bytes.length, pixels);
    return bytes;
  }

  /// Prepared frames play on the controller, without per-frame network sends.
  /// The initial animation cadence remains subject to physical verification.
  static Uint8List frames(
    List<List<bool>> frames, {
    int frameIntervalMs = 100,
    List<int>? programId,
  }) {
    if (frames.isEmpty ||
        frames.length > 2048 ||
        frames.any((f) => f.length != 512) ||
        frameIntervalMs < 20 ||
        frameIntervalMs > 2000) {
      throw ArgumentError('Invalid 32x16 frame sequence.');
    }
    final count = frames.length;
    final bitmapOffset = 27 + count * 2;
    final bytes = _container(bitmapOffset + count * 64, programId);
    final b = ByteData.sublistView(bytes);
    const t = 140;
    b.setUint16(t, 22);
    bytes[t + 2] = 0x30;
    b.setUint16(t + 3, count);
    b.setUint16(t + 5, 1);
    bytes[t + 8] = 1;
    b.setUint16(t + 9, 0xffff);
    b.setUint32(t + 11, count * 64);
    b.setUint32(t + 15, bitmapOffset);
    bytes[t + 23] = 0xc9;
    b.setUint16(t + 24, count == 1 ? 10 : frameIntervalMs ~/ 2);
    bytes[t + 26] = count == 1 ? 3 : 0;
    var rightmost = 0;
    for (var f = 0; f < count; f++) {
      for (var pixel = 0; pixel < 512; pixel++) {
        if (frames[f][pixel]) {
          rightmost = max(rightmost, pixel % 32);
          bytes[t + bitmapOffset + f * 64 + pixel ~/ 8] |= 1 << (7 - pixel % 8);
        }
      }
    }
    b.setUint16(t + 20, rightmost);
    return bytes;
  }

  static Uint8List _container(int widgetBytes, List<int>? programId) {
    final random = Random.secure();
    final id = programId ?? List.generate(16, (_) => random.nextInt(256));
    if (id.length != 16 || id.any((v) => v < 0 || v > 255)) {
      throw ArgumentError('Program identity must be 16 bytes.');
    }
    final bytes = Uint8List(140 + widgetBytes);
    final b = ByteData.sublistView(bytes);
    void u16(int at, int value) => b.setUint16(at, value);
    void u32(int at, int value) => b.setUint32(at, value);
    bytes.setRange(0, 2, [72, 67]); // HC: one program, no read-back ZIP.
    bytes[2] = 27;
    u16(3, 1);
    u32(5, 0xffffffff);
    u16(9, 3);
    u32(27, 31);
    const p = 31;
    bytes.setRange(p, p + 2, [72, 80]); // HP: always eligible to play.
    u16(p + 2, 59);
    bytes[p + 4] = 1;
    bytes.setRange(p + 9, p + 12, [1, 0x51, 0x7f]); // 86399, u24.
    bytes[p + 16] = 0x7f;
    bytes.setRange(p + 34, p + 50, id);
    bytes[p + 50] = 0xff;
    u32(p + 60, 68); // Border disabled; one area pointer and sentinel.
    u32(p + 64, 0xffffffff);
    const a = 99;
    bytes.setRange(a, a + 2, [72, 65]); // HA: full sign, one widget.
    u16(a + 2, 37);
    u16(a + 8, 32);
    u16(a + 10, 16);
    u16(a + 12, 1);
    u32(a + 37, 41);
    return bytes;
  }
}

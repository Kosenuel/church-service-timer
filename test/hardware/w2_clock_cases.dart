import 'dart:typed_data';

import 'package:church_service_timer/display/matrix_font.dart';
import 'package:church_service_timer/hardware/w2_program.dart';

void _expect(Object? actual, Object? expected) {
  if (actual != expected)
    throw StateError('Expected $expected; received $actual');
}

// Independent small reader of the native glyph tables, not the preview helper.
List<bool> _render(Uint8List bytes, int hour, int minute) {
  final b = ByteData.sublistView(bytes);
  final program = b.getUint32(27);
  final area = program + b.getUint32(program + 60);
  final widget = area + b.getUint32(area + 37);
  final twelve = bytes[widget + 8] == 6;
  final displayHour = twelve ? (hour % 12 == 0 ? 12 : hour % 12) : hour;
  final chars =
      '${displayHour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';
  final height = b.getUint16(widget + 29);
  final width = b.getUint16(widget + 31);
  final ampmWidth = b.getUint16(widget + 47);
  final frame = List.filled(512, false);
  var left = (32 - width * chars.length - (twelve ? ampmWidth : 0)) ~/ 2;
  final top = (16 - height) ~/ 2;
  void blit(int offset, int w) {
    final stride = (w + 7) ~/ 8;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < w; x++) {
        frame[(top + y) * 32 + left + x] =
            bytes[offset + y * stride + x ~/ 8] & (0x80 >> (x % 8)) != 0;
      }
    }
    left += w;
  }

  for (final char in chars.split('')) {
    final index = '0123456789/:,-.'.indexOf(char);
    blit(area + b.getUint32(widget + 65) + index * height, width);
  }
  if (twelve) {
    blit(area + b.getUint32(widget + 49) + (hour < 12 ? 0 : 28), ampmWidth);
  }
  return frame;
}

final w2ClockCases = <String, void Function()>{
  'Native clocks retain one safe display area and explicit format/glyph pointers':
      () {
        for (final twelve in [false, true]) {
          final bytes = W2Program.clock(
            format12Hour: twelve,
            programId: List.filled(16, 3),
          );
          final b = ByteData.sublistView(bytes);
          _expect(bytes.length, twelve ? 500 : 444);
          _expect(String.fromCharCodes(bytes.take(2)), 'HC');
          _expect(b.getUint32(19), 0); // No hardware configuration.
          _expect(b.getUint16(107), 32);
          _expect(b.getUint16(109), 16);
          _expect(b.getUint16(111), 1);
          _expect(b.getUint16(140), 94);
          _expect(bytes[142], 0x32);
          _expect(bytes[143], 0); // Digital, not analog.
          _expect(b.getUint16(144), 0); // Same timezone as calibrated RTC.
          _expect(bytes[146], 255);
          _expect(bytes[147], 255);
          _expect(bytes[148], twelve ? 6 : 1);
          _expect(bytes[149], 0);
          _expect(b.getUint16(169), 14);
          _expect(b.getUint16(171), twelve ? 4 : 6);
          _expect(b.getUint32(175) + 99, 234);
          _expect(b.getUint32(181) + 99, 234);
          _expect(b.getUint16(187), twelve ? 12 : 0);
          _expect(b.getUint32(189) + 99, 234);
          _expect(b.getUint32(205) + 99, twelve ? 290 : 234);
          _expect(b.getUint32(209) + 99, bytes.length);
          _expect(b.getUint32(213) + 99, bytes.length);
          _expect(bytes[225], 0); // Separate analog AM/PM field stays off.
          _expect(b.getUint32(193), 1);
        }
      },
  '24-hour hardware clock uses exact original Matrix digits without mutation':
      () {
        final original = Map<String, String>.from(glyphs);
        final bytes = W2Program.clock();
        for (var digit = 0; digit < 10; digit++) {
          final rows = glyphs['$digit']!.split('/');
          for (var y = 0; y < 7; y++) {
            final expected = int.parse(rows[y], radix: 2) << 3;
            _expect(bytes[234 + digit * 14 + y * 2], expected);
            _expect(bytes[235 + digit * 14 + y * 2], expected);
          }
        }
        W2Program.clock(format12Hour: true);
        _expect(glyphs.toString(), original.toString());
        _expect(
          W2Program.countdown(1).sublist(197, 211).join(','),
          '112,112,136,136,152,152,168,168,200,200,136,136,112,112',
        );
      },
  'Clock preview agrees with uploaded cells across all minutes of the day': () {
    for (final twelve in [false, true]) {
      final bytes = W2Program.clock(format12Hour: twelve);
      for (var minute = 0; minute < 24 * 60; minute++) {
        final wall = DateTime(2026, 10, 26, minute ~/ 60, minute % 60);
        final preview = W2Program.clockPixels(wall, format12Hour: twelve);
        final encoded = _render(bytes, wall.hour, wall.minute);
        _expect(preview.length, 512);
        for (var pixel = 0; pixel < 512; pixel++) {
          _expect(preview[pixel], encoded[pixel]);
        }
        _expect(preview.take(32).any((p) => p), false);
        _expect(preview.skip(480).any((p) => p), false);
      }
    }
  },
  '12-hour suffix has distinct original AM and PM letters at fixed width': () {
    final am = W2Program.clockPixels(
      DateTime(2026, 10, 26, 0),
      format12Hour: true,
    );
    final pm = W2Program.clockPixels(
      DateTime(2026, 10, 26, 12),
      format12Hour: true,
    );
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 20; x++) {
        _expect(am[y * 32 + x], pm[y * 32 + x]); // 12:00 both times.
      }
    }
    _expect(am.join() == pm.join(), false);
    // First visible row: AM = leading blank, A 01110, gap, M 10001.
    _expect(
      am.sublist(32 + 20, 32 + 32).map((p) => p ? 1 : 0).join(),
      '001110010001',
    );
    _expect(
      pm.sublist(32 + 20, 32 + 32).map((p) => p ? 1 : 0).join(),
      '011110010001',
    );
  },
  'Clock payload is time-independent and validates program identity': () {
    final identity = List.filled(16, 11);
    _expect(
      W2Program.clock(programId: identity).join(','),
      W2Program.clock(programId: identity).join(','),
    );
    for (final id in [<int>[], List.filled(16, -1), List.filled(16, 256)]) {
      var rejected = false;
      try {
        W2Program.clock(programId: id);
      } on ArgumentError {
        rejected = true;
      }
      _expect(rejected, true);
    }
  },
};

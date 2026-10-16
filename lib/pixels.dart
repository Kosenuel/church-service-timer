import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';

/// Original, fixed pixel glyphs. Preview and future transport share these bits.
/// No system font substitution or antialiasing enters the display payload.
const glyphs = <String, String>{
  ' ': '000/000/000/000/000/000/000',
  '0': '01110/10001/10011/10101/11001/10001/01110',
  '1': '00100/01100/00100/00100/00100/00100/01110',
  '2': '01110/10001/00001/00010/00100/01000/11111',
  '3': '11110/00001/00001/01110/00001/00001/11110',
  '4': '00010/00110/01010/10010/11111/00010/00010',
  '5': '11111/10000/10000/11110/00001/00001/11110',
  '6': '01110/10000/10000/11110/10001/10001/01110',
  '7': '11111/00001/00010/00100/01000/01000/01000',
  '8': '01110/10001/10001/01110/10001/10001/01110',
  '9': '01110/10001/10001/01111/00001/00001/01110',
  'A': '01110/10001/10001/11111/10001/10001/10001',
  'B': '11110/10001/10001/11110/10001/10001/11110',
  'C': '01111/10000/10000/10000/10000/10000/01111',
  'D': '11110/10001/10001/10001/10001/10001/11110',
  'E': '11111/10000/10000/11110/10000/10000/11111',
  'F': '11111/10000/10000/11110/10000/10000/10000',
  'G': '01111/10000/10000/10111/10001/10001/01111',
  'H': '10001/10001/10001/11111/10001/10001/10001',
  'I': '111/010/010/010/010/010/111',
  'J': '00111/00010/00010/00010/10010/10010/01100',
  'K': '10001/10010/10100/11000/10100/10010/10001',
  'L': '10000/10000/10000/10000/10000/10000/11111',
  'M': '10001/11011/10101/10101/10001/10001/10001',
  'N': '10001/11001/10101/10011/10001/10001/10001',
  'O': '01110/10001/10001/10001/10001/10001/01110',
  'P': '11110/10001/10001/11110/10000/10000/10000',
  'Q': '01110/10001/10001/10001/10101/10010/01101',
  'R': '11110/10001/10001/11110/10100/10010/10001',
  'S': '01111/10000/10000/01110/00001/00001/11110',
  'T': '11111/00100/00100/00100/00100/00100/00100',
  'U': '10001/10001/10001/10001/10001/10001/01110',
  'V': '10001/10001/10001/10001/10001/01010/00100',
  'W': '10001/10001/10001/10101/10101/10101/01010',
  'X': '10001/10001/01010/00100/01010/10001/10001',
  'Y': '10001/10001/01010/00100/00100/00100/00100',
  'Z': '11111/00001/00010/00100/01000/10000/11111',
  'a': '00000/00000/01110/00001/01111/10001/01111',
  'b': '10000/10000/11110/10001/10001/10001/11110',
  'c': '00000/00000/01111/10000/10000/10000/01111',
  'd': '00001/00001/01111/10001/10001/10001/01111',
  'e': '00000/00000/01110/10001/11111/10000/01111',
  'f': '00110/01001/01000/11100/01000/01000/01000',
  'g': '00000/01111/10001/10001/01111/00001/01110',
  'h': '10000/10000/11110/10001/10001/10001/10001',
  'i': '010/000/110/010/010/010/111',
  'j': '001/000/011/001/001/101/010',
  'k': '10000/10000/10010/10100/11000/10100/10010',
  'l': '110/010/010/010/010/010/111',
  'm': '00000/00000/11010/10101/10101/10101/10101',
  'n': '00000/00000/11110/10001/10001/10001/10001',
  'o': '00000/00000/01110/10001/10001/10001/01110',
  'p': '00000/11110/10001/10001/11110/10000/10000',
  'q': '00000/01111/10001/10001/01111/00001/00001',
  'r': '00000/00000/10110/11001/10000/10000/10000',
  's': '00000/00000/01111/10000/01110/00001/11110',
  't': '01000/01000/11100/01000/01000/01001/00110',
  'u': '00000/00000/10001/10001/10001/10001/01111',
  'v': '00000/00000/10001/10001/10001/01010/00100',
  'w': '00000/00000/10001/10001/10101/10101/01010',
  'x': '00000/00000/10001/01010/00100/01010/10001',
  'y': '00000/10001/10001/10001/01111/00001/01110',
  'z': '00000/00000/11111/00010/00100/01000/11111',
  ':': '0/1/1/0/1/1/0',
  '.': '0/0/0/0/0/1/1',
  ',': '00/00/00/00/00/01/10',
  "'": '1/1/0/0/0/0/0',
  '!': '1/1/1/1/1/0/1',
  '?': '01110/10001/00001/00010/00100/00000/00100',
  '-': '000/000/000/111/000/000/000',
  '+': '000/010/010/111/010/010/000',
  '/': '00001/00010/00010/00100/01000/01000/10000',
  '(': '01/10/10/10/10/10/01',
  ')': '10/01/01/01/01/01/10',
  '&': '01100/10010/10100/01000/10101/10010/01101',
  '=': '000/000/111/000/111/000/000',
  '_': '00000/00000/00000/00000/00000/00000/11111',
  '"': '101/101/000/000/000/000/000',
  '#': '01010/11111/01010/01010/11111/01010/00000',
  '%': '11001/11010/00010/00100/01000/01011/10011',
};

int textWidth(TextLayout l) =>
    l.text
        .split('')
        .fold<int>(
          -1,
          (w, c) =>
              w +
              (glyphs[c]?.split('/').first.length ?? 5) +
              1 +
              (l.bold ? 1 : 0),
        ) +
    (l.italic ? 2 : 0);

void validateLayout(TextLayout layout) {
  layout.validate();
  final unknown = layout.text.runes
      .where((r) => !glyphs.containsKey(String.fromCharCode(r)))
      .toSet();
  require(
    unknown.isEmpty,
    'This pixel font does not support: ${unknown.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(', ')}. Use basic Latin letters, numbers and supported punctuation.',
  );
  require(
    layout.effect == 'scroll' || textWidth(layout) <= 32,
    'This text is ${textWidth(layout)} pixels wide. Choose scrolling or shorten it to fit 32 pixels.',
  );
}

void validateTimelinePixels(Timeline timeline) {
  for (final l in [
    ...timeline.display.cues,
    timeline.display.end,
    if (timeline.display.zero != null) timeline.display.zero!,
  ]) {
    validateLayout(l);
  }
}

List<bool> renderPixels(TextLayout? layout, int elapsedMs) {
  final pixels = List<bool>.filled(512, false);
  if (layout == null) return pixels;
  if (layout.effect == 'flash' && (elapsedMs ~/ 500).isOdd) return pixels;
  final width = textWidth(layout);
  int start;
  if (layout.effect == 'scroll' && width > 32) {
    // Begin visibly at x=0, then scroll through a 6-pixel inter-message gap.
    start = -((elapsedMs * layout.speed ~/ 1000) % (width + 6));
  } else {
    start = layout.align == 'left'
        ? 0
        : layout.align == 'right'
        ? 32 - width
        : (32 - width) ~/ 2;
  }
  final top = (16 - 7 * layout.height) ~/ 2;
  void drawAt(int origin) {
    var x = origin;
    for (final char in layout.text.split('')) {
      final rows = glyphs[char]!.split('/');
      for (var y = 0; y < 7; y++) {
        final skew = layout.italic ? (6 - y) ~/ 3 : 0;
        for (var col = 0; col < rows[y].length; col++) {
          if (rows[y][col] != '1') continue;
          for (var bold = 0; bold <= (layout.bold ? 1 : 0); bold++) {
            for (var sy = 0; sy < layout.height; sy++) {
              final px = x + col + skew + bold,
                  py = top + y * layout.height + sy;
              if (px >= 0 && px < 32 && py >= 0 && py < 16)
                pixels[py * 32 + px] = true;
            }
          }
        }
      }
      x += rows.first.length + 1 + (layout.bold ? 1 : 0);
    }
  }

  drawAt(start);
  if (layout.effect == 'scroll' && width > 32) drawAt(start + width + 6);
  return pixels;
}

class LedMatrix extends StatelessWidget {
  final List<bool> pixels;
  final bool stale;
  const LedMatrix({super.key, required this.pixels, this.stale = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '32 by 16 monochrome LED simulator${stale ? ', output held' : ''}',
    child: AspectRatio(
      aspectRatio: 2,
      child: CustomPaint(painter: _MatrixPainter(pixels, stale)),
    ),
  );
}

class _MatrixPainter extends CustomPainter {
  final List<bool> pixels;
  final bool stale;
  _MatrixPainter(this.pixels, this.stale);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = const Color(0xff070d0d),
    );
    final pitch = math.min(size.width / 32, size.height / 16);
    final off = Paint()..color = const Color(0xff14201d);
    final on = Paint()
      ..color = stale ? const Color(0xffb79558) : const Color(0xffc9f96c);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 32; x++) {
        canvas.drawCircle(
          Offset((x + .5) * pitch, (y + .5) * pitch),
          pitch * .32,
          pixels[y * 32 + x] ? on : off,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixPainter old) => true;
}

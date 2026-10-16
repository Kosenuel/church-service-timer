import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'matrix_font.dart';
import 'font_atlas.dart';
export 'matrix_font.dart' show glyphs;

Map<String, String> layoutGlyphs(TextLayout l) => l.font == 'cuekeeper_matrix'
    ? glyphs
    : fontAtlas['${l.font}_${l.height}_${(l.bold ? 1 : 0) + (l.italic ? 2 : 0)}']!;

int textWidth(TextLayout l) {
  final table = layoutGlyphs(l);
  final matrix = l.font == 'cuekeeper_matrix';
  return l.text
          .split('')
          .fold<int>(
            -1,
            (w, c) =>
                w +
                (table[c]?.split('/').first.length ?? 5) +
                1 +
                (matrix && l.bold ? 1 : 0),
          ) +
      (matrix && l.italic ? 2 : 0);
}

void validateLayout(TextLayout layout) {
  layout.validate();
  final unknown = layout.text.runes
      .where((r) => !layoutGlyphs(layout).containsKey(String.fromCharCode(r)))
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
    ...timeline.display.warnings.map((w) => w.cue),
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
  final matrix = layout.font == 'cuekeeper_matrix';
  final table = layoutGlyphs(layout);
  final rowScale = matrix ? layout.height : 1;
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
      final rows = table[char]!.split('/');
      for (var y = 0; y < rows.length; y++) {
        final skew = matrix && layout.italic ? (6 - y) ~/ 3 : 0;
        for (var col = 0; col < rows[y].length; col++) {
          if (rows[y][col] != '1') continue;
          for (var bold = 0; bold <= (matrix && layout.bold ? 1 : 0); bold++) {
            for (var sy = 0; sy < rowScale; sy++) {
              final px = x + col + skew + bold, py = top + y * rowScale + sy;
              if (px >= 0 && px < 32 && py >= 0 && py < 16)
                pixels[py * 32 + px] = true;
            }
          }
        }
      }
      x += rows.first.length + 1 + (matrix && layout.bold ? 1 : 0);
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

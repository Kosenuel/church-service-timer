import 'package:church_service_timer/shared/device_words.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/matrix_font.dart';
import 'package:church_service_timer/display/square_matrix_font.dart';
import 'package:church_service_timer/display/native_fonts.dart';
export 'package:church_service_timer/display/matrix_font.dart' show glyphs;

Map<String, String> layoutGlyphs(TextLayout l) =>
    l.font == 'i-proton_sq_matrix' ? squareGlyphs : glyphs;

int warningDurationMs(WarningRule rule) {
  if (rule.scrollOnce &&
      rule.cue.effect == 'scroll' &&
      textWidth(rule.cue) > 32) {
    return ((textWidth(rule.cue) + 6) * 2 * (500 / rule.cue.speed).round())
        .clamp(1000, 120000);
  }
  return rule.durationSeconds * 1000;
}

int textWidth(TextLayout l) {
  if (l.font == 'tinos') {
    final raster = NativeDisplayFonts.cached(l);
    require(
      raster != null,
      NativeDisplayFonts.available
          ? 'Preparing Tinos preview…'
          : desktopWording
          ? 'Bundled Tinos could not be loaded. Reinstall the app to restore its fonts.'
          : 'Bundled Tinos could not be loaded. Android is required for native text rendering.',
    );
    return raster!.width;
  }
  final table = layoutGlyphs(l);
  final scaleX = l.font == 'i-proton_sq_matrix' ? l.height : 1;
  return l.text
          .split('')
          .fold<int>(
            -1,
            (w, c) =>
                w +
                (table[c]?.split('/').first.length ?? 5) * scaleX +
                1 +
                (l.bold ? 1 : 0),
          ) +
      (l.italic ? 2 : 0);
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
    // Every effect but scrolling says "(must fit)" in the editor's list.
    'This text is ${textWidth(layout)} pixels wide and must fit the LED sign’s 32 pixels. Choose Scroll long text, or make it shorter.',
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
  // Three flashes, then steady, as the controller's loop plays it.
  if (layout.effect == 'flashHold') {
    final cycle = elapsedMs % flashHoldCycleMs;
    if (cycle < flashHoldMs && (cycle ~/ 500).isOdd) return pixels;
  }
  final width = textWidth(layout);
  if (layout.font == 'tinos') {
    final raster = NativeDisplayFonts.cached(layout)!;
    final scrolling = layout.effect == 'scroll' && width > 32;
    final start = scrolling
        ? -((elapsedMs * layout.speed ~/ 1000) % (width + 6))
        : layout.align == 'left'
        ? 0
        : layout.align == 'right'
        ? 32 - width
        : (32 - width) ~/ 2;
    final top = (16 - raster.height) ~/ 2;
    void draw(int left) {
      for (var y = 0; y < raster.height; y++) {
        for (var x = 0; x < width; x++) {
          final px = left + x;
          if (px >= 0 && px < 32 && raster.rows[y][x] == '1')
            pixels[(top + y) * 32 + px] = true;
        }
      }
    }

    draw(start);
    if (scrolling) draw(start + width + 6);
    return pixels;
  }
  final scaleX = layout.font == 'i-proton_sq_matrix' ? layout.height : 1;
  final table = layoutGlyphs(layout);
  final rowScale = layout.height;
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
        final skew = layout.italic ? (6 - y) ~/ 3 : 0;
        for (var col = 0; col < rows[y].length; col++) {
          if (rows[y][col] != '1') continue;
          for (var bold = 0; bold <= (layout.bold ? 1 : 0); bold++) {
            for (var sy = 0; sy < rowScale; sy++) {
              for (var sx = 0; sx < scaleX; sx++) {
                final px = x + col * scaleX + sx + skew + bold,
                    py = top + y * rowScale + sy;
                if (px >= 0 && px < 32 && py >= 0 && py < 16)
                  pixels[py * 32 + px] = true;
              }
            }
          }
        }
      }
      x += rows.first.length * scaleX + 1 + (layout.bold ? 1 : 0);
    }
  }

  drawAt(start);
  if (layout.effect == 'scroll' && width > 32) drawAt(start + width + 6);
  return pixels;
}

/// Above the Navigator, so dialogs and the Live view use the same preference.
class LedAppearance extends InheritedWidget {
  final String shape;
  const LedAppearance({super.key, required this.shape, required super.child});
  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LedAppearance>()?.shape ??
      'square';
  @override
  bool updateShouldNotify(LedAppearance old) => shape != old.shape;
}

class LedMatrix extends StatelessWidget {
  final List<bool> pixels;
  final bool stale;
  final bool hardware;
  const LedMatrix({
    super.key,
    required this.pixels,
    this.stale = false,
    this.hardware = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '32 by 16 monochrome LED ${hardware ? 'accepted-program preview' : 'simulator'}${stale ? ', output held' : ''}',
    child: AspectRatio(
      aspectRatio: 2,
      child: CustomPaint(
        painter: _MatrixPainter(
          pixels,
          stale,
          LedAppearance.of(context),
          hardware,
        ),
      ),
    ),
  );
}

class _MatrixPainter extends CustomPainter {
  final List<bool> pixels;
  final bool stale;
  final String shape;
  final bool hardware;
  _MatrixPainter(this.pixels, this.stale, this.shape, this.hardware);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = const Color(0xff070d0d),
    );
    final pitch = math.min(size.width / 32, size.height / 16);
    final off = Paint()..color = const Color(0xff14201d);
    final on = Paint()
      ..color = stale
          ? const Color(0xffb79558)
          : hardware
          ? const Color(0xffff4545)
          : const Color(0xffc9f96c);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 32; x++) {
        final paint = pixels[y * 32 + x] ? on : off;
        if (shape == 'circular') {
          canvas.drawCircle(
            Offset((x + .5) * pitch, (y + .5) * pitch),
            pitch * .32,
            paint,
          );
        } else {
          canvas.drawRect(
            Rect.fromLTWH(
              (x + .18) * pitch,
              (y + .18) * pitch,
              pitch * .64,
              pitch * .64,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MatrixPainter old) =>
      stale != old.stale ||
      shape != old.shape ||
      hardware != old.hardware ||
      !listEquals(pixels, old.pixels);
}

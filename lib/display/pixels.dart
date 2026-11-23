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

/// Whether the LED sign scrolls [layout] across it: text too wide for the
/// sign with Scroll long text, or with an effect only screens show (see
/// [signScrollEffects]). False while a Tinos cue is still being drawn.
bool scrollsOnSign(TextLayout layout) {
  if (layout.effect != 'scroll' && !signScrollEffects.contains(layout.effect)) {
    return false;
  }
  try {
    return textWidth(layout) > 32;
  } catch (_) {
    return false;
  }
}

int warningDurationMs(WarningRule rule) {
  if (rule.scrollOnce && scrollsOnSign(rule.cue)) {
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

/// [l] with only [text], drawn steady: one group of its words.
TextLayout _part(TextLayout l, String text) => TextLayout(
  text,
  bold: l.bold,
  italic: l.italic,
  effect: 'static',
  align: l.align,
  speed: l.speed,
  height: l.height,
  font: l.font,
);

/// The texts the LED sign measures to split [l] into groups of words:
/// each word, and each run of words that might share a group. A Tinos
/// cue has each drawn ahead (see `NativeDisplayFonts.prepare`).
Iterable<TextLayout> wordGroupCandidates(TextLayout l) sync* {
  final words = l.text.trim().split(RegExp(r'\s+'));
  for (var i = 0; i < words.length; i++) {
    for (var j = i; j < words.length; j++) {
      final part = _part(l, words.sublist(i, j + 1).join(' '));
      yield part;
      // Longer runs only get wider; a run is no use once past the sign.
      try {
        if (textWidth(part) > 32) break;
      } catch (_) {
        break;
      }
    }
  }
}

/// The groups of words a Flash or Pulse cue too wide for the LED sign is
/// shown in, one after another (see [groupWords]); null when it is shown
/// as it is: another effect, it fits, it is longer than
/// [wordGroupMaxLength] characters, or one of its words is too wide.
List<String>? signWordGroups(TextLayout l) {
  if (!wordGroupEffects.contains(l.effect) || textWidth(l) <= 32) return null;
  if (l.text.trim().runes.length > wordGroupMaxLength) return null;
  return groupWords(l.text, (text) => textWidth(_part(l, text)) <= 32);
}

/// [signWordGroups] for a stage snapshot: null, never an error, while a
/// Tinos cue is still being drawn or the text cannot be shown.
List<String>? stageWordGroupsOf(TextLayout? l) {
  if (l == null) return null;
  try {
    return signWordGroups(l);
  } catch (_) {
    return null;
  }
}

/// Whether [layout] can be saved and shown. With [signFit] (the default),
/// text must also fit the LED sign as its effect requires. Pass false when
/// no sign is the display in use: stage screens show any width, and the
/// check is made again when something is sent to a sign.
void validateLayout(TextLayout layout, {bool signFit = true}) {
  layout.validate();
  final unknown = layout.text.runes
      .where((r) => !layoutGlyphs(layout).containsKey(String.fromCharCode(r)))
      .toSet();
  require(
    unknown.isEmpty,
    'This pixel font does not support: ${unknown.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(', ')}. Use basic Latin letters, numbers and supported punctuation.',
  );
  if (!signFit) return;
  final width = textWidth(layout);
  // Scroll long text, and the effects only screens show, scroll across
  // the sign when they are too wide for it.
  if (layout.effect == 'scroll' ||
      signScrollEffects.contains(layout.effect) ||
      width <= 32) {
    return;
  }
  // Flash and Pulse show text too wide for the sign a few words at a time.
  if (wordGroupEffects.contains(layout.effect)) {
    final length = layout.text.trim().runes.length;
    require(
      length <= wordGroupMaxLength,
      'This text has $length characters. Flash and Pulse show long text a few words at a time, up to $wordGroupMaxLength characters. Choose Scroll long text, or make it shorter.',
    );
    if (signWordGroups(layout) != null) return;
  }
  // Static and Flash then hold say "(must fit)" in the editor's list; a
  // single word too wide for the sign does not fit either.
  require(
    false,
    layout.effect == 'flashHold'
        ? 'This text is $width pixels wide and must fit the LED sign’s 32 pixels to flash then hold. Choose Flash, which shows long text a few words at a time, or make it shorter.'
        : 'This text is $width pixels wide and must fit the LED sign’s 32 pixels. Choose Scroll long text, or make it shorter.',
  );
}

void validateTimelinePixels(Timeline timeline, {bool signFit = true}) {
  for (final l in [
    ...timeline.display.cues,
    ...timeline.display.warnings.map((w) => w.cue),
    ?timeline.display.end,
    if (timeline.display.zero != null) timeline.display.zero!,
  ]) {
    validateLayout(l, signFit: signFit);
  }
}

List<bool> renderPixels(TextLayout? layout, int elapsedMs) {
  final pixels = List<bool>.filled(512, false);
  if (layout == null) return pixels;
  // Too wide for the sign: a few words at a time, a frame at a time, as
  // the controller's loop plays it (see [wordGroupAt]).
  final groups = signWordGroups(layout);
  if (groups != null) {
    final at = wordGroupAt(
      layout.effect,
      groups.length,
      elapsedMs ~/ wordGroupFrameMs * wordGroupFrameMs,
    );
    final lit = layout.effect == 'flash'
        ? at.opacity > .5
        : at.opacity >= wordGroupSignPulseLevel;
    return lit ? renderPixels(_part(layout, groups[at.index]), 0) : pixels;
  }
  if (layout.effect == 'flash' && (elapsedMs ~/ 500).isOdd) return pixels;
  // Three flashes, then steady, as the controller's loop plays it.
  if (layout.effect == 'flashHold') {
    final cycle = elapsedMs % flashHoldCycleMs;
    if (cycle < flashHoldMs && (cycle ~/ 500).isOdd) return pixels;
  }
  final width = textWidth(layout);
  final scrolling = scrollsOnSign(layout);
  if (layout.font == 'tinos') {
    final raster = NativeDisplayFonts.cached(layout)!;
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
  if (scrolling) {
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
  if (scrolling) drawAt(start + width + 6);
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

/// Above the Navigator like [LedAppearance]: whether text must fit the LED
/// sign to be sent or saved, because a sign is the display in use. True
/// when nothing says otherwise.
class SignFit extends InheritedWidget {
  final bool required;
  const SignFit({super.key, required this.required, required super.child});
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SignFit>()?.required ?? true;
  @override
  bool updateShouldNotify(SignFit old) => required != old.required;
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

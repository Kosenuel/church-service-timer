import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_backgrounds.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The face slides are drawn in, as every stage screen.
const lyricFontFamily = 'Roboto';

/// The `lyrics` field of a stage picture, when the screen should show a
/// slide: present, readable, and no quick message to the stage on top
/// (a speaker always sees one). Null otherwise, and the screen shows what
/// it would without lyrics.
Json? stageLyrics(Json data) {
  final l = data['lyrics'];
  if (l is! Map || data['quickMessage'] is Map) return null;
  return Map<String, dynamic>.from(l);
}

/// The colours of a slide's words: light on the dark backgrounds, dark on
/// Linen.
class LyricInk {
  final Color text, accent, detail;
  final List<Shadow> shadows;
  const LyricInk(this.text, this.accent, this.detail, this.shadows);

  static LyricInk of(String background, double width) =>
      lyricDarkInkBackgrounds.contains(background)
      ? const LyricInk(
          Color(0xff1b2420),
          Color(0xff7a4e0c),
          Color(0xff4a524c),
          [],
        )
      : LyricInk(
          Colors.white,
          const Color(0xfff5d88c),
          const Color(0xe6ffffff),
          [
            Shadow(
              color: const Color(0xa6000000),
              offset: Offset(0, width * .002),
              blurRadius: width * .012,
            ),
          ],
        );
}

/// One run of words on a slide and how large it is beside the others.
class LyricBlock {
  final String text;
  final double scale;
  final FontWeight weight;
  final Color Function(LyricInk ink) color;

  /// The space after it, in the slide's font size.
  final double gap;
  const LyricBlock(
    this.text, {
    this.scale = 1,
    this.weight = FontWeight.w500,
    required this.color,
    this.gap = 0,
  });
}

/// The blocks a slide's picture field makes.
List<LyricBlock> lyricBlocks(Json slide) {
  final kind = slide['kind'], text = '${slide['text'] ?? ''}';
  final title = '${slide['title'] ?? ''}', detail = '${slide['detail'] ?? ''}';
  final reference = '${slide['reference'] ?? ''}';
  Color main(LyricInk i) => i.text;
  if (kind == 'announcement') {
    return [
      if (title.isNotEmpty)
        LyricBlock(
          title,
          scale: 1.35,
          weight: FontWeight.w700,
          color: (i) => i.accent,
          gap: text.isEmpty && detail.isEmpty ? 0 : .55,
        ),
      if (text.isNotEmpty)
        LyricBlock(text, color: main, gap: detail.isEmpty ? 0 : .6),
      if (detail.isNotEmpty)
        LyricBlock(
          detail,
          scale: .62,
          color: (i) => i.accent,
          weight: FontWeight.w500,
        ),
    ];
  }
  return [
    if (text.isNotEmpty)
      LyricBlock(text, color: main, gap: reference.isEmpty ? 0 : .7),
    if (reference.isNotEmpty)
      LyricBlock(
        reference,
        scale: .55,
        color: (i) => i.accent,
        weight: FontWeight.w500,
      ),
  ];
}

final _raised = RegExp('[⁰¹²³⁴⁵⁶⁷⁸⁹]+');
const _plainDigits = {
  '⁰': '0',
  '¹': '1',
  '²': '2',
  '³': '3',
  '⁴': '4',
  '⁵': '5',
  '⁶': '6',
  '⁷': '7',
  '⁸': '8',
  '⁹': '9',
};

/// A line of words as spans: verse numbers, sent as raised digits, are
/// drawn as small digits in [number] (Roboto has no raised 4 to 9).
TextSpan lyricLine(String line, TextStyle style, {Color? number}) {
  if (!_raised.hasMatch(line)) return TextSpan(text: line, style: style);
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _raised.allMatches(line)) {
    if (m.start > at) spans.add(TextSpan(text: line.substring(at, m.start)));
    spans.add(
      TextSpan(
        text: m[0]!.split('').map((c) => _plainDigits[c]).join(),
        style: TextStyle(
          fontSize: (style.fontSize ?? 14) * .55,
          fontWeight: FontWeight.w700,
          color: number,
        ),
      ),
    );
    at = m.end;
  }
  if (at < line.length) spans.add(TextSpan(text: line.substring(at)));
  return TextSpan(style: style, children: spans);
}

/// How a slide's words are laid out: the font size, and for each typed
/// line the width it is wrapped to, so a line that must wrap is wrapped
/// into lines of nearly the same length.
class LyricFit {
  final double size;
  final List<List<double>> widths;
  const LyricFit(this.size, this.widths);
}

final _fits = <String, LyricFit>{};

/// The largest size, up to [most], at which [blocks] fit [room]: every
/// line fits across without a word broken, and all fit the height.
LyricFit fitLyricBlocks(
  List<LyricBlock> blocks,
  Size room, {
  required double most,
  required double lineHeight,
  TextAlign align = TextAlign.center,
}) {
  final key =
      '${blocks.map((b) => '${b.text}|${b.scale}|${b.weight.value}|${b.gap}').join('§')}#${room.width.round()}x${room.height.round()}#${most.round()}#$lineHeight';
  final known = _fits.remove(key);
  if (known != null) return _fits[key] = known;

  TextPainter painter(String line, double size, FontWeight weight) =>
      TextPainter(
        text: lyricLine(
          line,
          lyricTextStyle(size, weight, Colors.white, const [], lineHeight),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
        textScaler: TextScaler.noScaling,
      );

  // The height the blocks take at [size], or null if a word is too wide.
  // The height the blocks take at [size], or null if a word is too wide
  // (or, with [whole], if any typed line would have to wrap).
  double? height(double size, {bool whole = false}) {
    var total = 0.0;
    for (final b in blocks) {
      final s = size * b.scale;
      for (final line in b.text.split('\n')) {
        final p = painter(line.isEmpty ? ' ' : line, s, b.weight)
          ..layout(maxWidth: room.width);
        final wide =
            (whole ? p.maxIntrinsicWidth : p.minIntrinsicWidth) >
            room.width + .5;
        total += p.height;
        p.dispose();
        if (wide) return null;
      }
      total += b.gap * size;
    }
    return total;
  }

  double largest({bool whole = false}) {
    bool fits(double size) {
      final h = height(size, whole: whole);
      return h != null && h <= room.height;
    }

    var lo = 2.0, hi = math.max(lo, most);
    if (fits(hi)) return hi;
    for (var i = 0; i < 16; i++) {
      final mid = (lo + hi) / 2;
      if (fits(mid)) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  // Each typed line on a line of its own reads best, as the words were
  // written; it is kept when it costs no more than a fifth of the size.
  // Otherwise lines wrap, evenly.
  final any = largest(), whole = largest(whole: true);
  final size = whole >= any * .8 ? whole : any;
  // Each line that wraps, at the narrowest width that keeps its number
  // of lines: the lines come out even.
  final widths = <List<double>>[];
  for (final b in blocks) {
    final s = size * b.scale;
    final row = <double>[];
    for (final line in b.text.split('\n')) {
      final p = painter(line.isEmpty ? ' ' : line, s, b.weight)
        ..layout(maxWidth: room.width);
      final lines = p.computeLineMetrics().length;
      var width = room.width;
      if (lines > 1) {
        var a = math.max(p.minIntrinsicWidth, room.width / lines),
            z = room.width;
        for (var i = 0; i < 12; i++) {
          final mid = (a + z) / 2;
          p.layout(maxWidth: mid);
          if (p.computeLineMetrics().length <= lines) {
            z = mid;
          } else {
            a = mid;
          }
        }
        width = math.min(room.width, z + 1);
      }
      p.dispose();
      row.add(width);
    }
    widths.add(row);
  }
  final fit = LyricFit(size, widths);
  _fits[key] = fit;
  while (_fits.length > 64) {
    _fits.remove(_fits.keys.first);
  }
  return fit;
}

TextStyle lyricTextStyle(
  double size,
  FontWeight weight,
  Color color,
  List<Shadow> shadows,
  double lineHeight,
) => TextStyle(
  // Not the app's text style: its letter spacing would make the words
  // wider than they were measured.
  inherit: false,
  fontFamily: lyricFontFamily,
  fontSize: size,
  height: lineHeight,
  fontWeight: weight,
  letterSpacing: 0,
  wordSpacing: 0,
  color: color,
  shadows: shadows,
);

/// A lyric slide as every screen draws it: the background, the Dim layer,
/// the words as large as fit, and the countdown chip. [data] is the
/// picture's `lyrics` field.
class LyricStage extends StatelessWidget {
  final Json data;
  final bool stale;
  const LyricStage({super.key, required this.data, this.stale = false});

  @override
  Widget build(BuildContext context) {
    if (data['black'] == true) {
      return const ColoredBox(
        key: ValueKey('lyric-black'),
        color: Colors.black,
        child: SizedBox.expand(),
      );
    }
    final bg = '${data['bg'] ?? 'black'}';
    final dark = lyricDarkInkBackgrounds.contains(bg);
    final dim = dark
        ? 0
        : ((data['dim'] as num?)?.toDouble() ?? 70).clamp(0, 90) / 100;
    final moving = data['motion'] != false && !reduceAppMotion(context);
    final chip = data['chip'] is String ? data['chip'] as String : null;
    return LayoutBuilder(
      builder: (context, space) {
        final size = space.biggest;
        final ink = LyricInk.of(bg, size.width);
        return Stack(
          key: const ValueKey('lyric-stage'),
          fit: StackFit.expand,
          children: [
            LyricBackground(
              id: bg,
              moving: moving,
              picture: data['picture'] is String
                  ? data['picture'] as String
                  : null,
            ),
            if (dim > 0)
              ColoredBox(color: Colors.black.withValues(alpha: dim.toDouble())),
            AnimatedSwitcher(
              duration: reduceAppMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              child: KeyedSubtree(
                key: ValueKey(
                  '${data['key']}|${data['text']}|${data['title']}',
                ),
                child: Opacity(
                  opacity: stale ? .4 : 1,
                  child: _words(size, ink),
                ),
              ),
            ),
            if (chip != null)
              Positioned(
                right: size.width * .024,
                top: size.width * .024,
                child: _chip(chip, data['chipOver'] == true, size.width),
              ),
          ],
        );
      },
    );
  }

  Widget _chip(String text, bool over, double width) => DecoratedBox(
    key: const ValueKey('lyric-chip'),
    decoration: BoxDecoration(
      // In overtime the chip turns the stage's red with dark ink, as the
      // countdown's own screen does, so it is plain to see over any slide.
      color: over ? StageColors.overtimeRed : const Color(0x8c000000),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: width * .02,
        vertical: width * .007,
      ),
      child: Text(
        text,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          inherit: false,
          letterSpacing: 0,
          fontFamily: lyricFontFamily,
          color: over ? StageColors.overtimeInk : Colors.white,
          fontSize: math.max(10, width * .03),
          fontWeight: over ? FontWeight.w700 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1.2,
        ),
      ),
    ),
  );

  Widget _words(Size size, LyricInk ink) {
    final blocks = lyricBlocks(data);
    if (blocks.isEmpty) return const SizedBox.expand();
    // Clear of the edges and of the chip; on a tall screen the words are
    // sized as if it were 16:9, so they never tower over a narrow width.
    final padX = size.width * .07,
        padY = math.min(size.width * .06, size.height * .1);
    final room = Size(
      math.max(1, size.width - padX * 2),
      math.max(1, size.height - padY * 2),
    );
    final basis = math.min(size.width, size.height * 16 / 9);
    final most =
        basis *
        switch (data['size']) {
          's' => .045,
          'l' => .064,
          _ => .054,
        };
    final left = data['align'] == 'left';
    final align = left ? TextAlign.left : TextAlign.center;
    const lineHeight = 1.22;
    final fit = fitLyricBlocks(
      blocks,
      room,
      most: most,
      lineHeight: lineHeight,
      align: align,
    );
    final cross = left ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: padX, vertical: padY),
      child: FittedBox(
        // Never needed when the fit is right; a last guard against any
        // overflow at all.
        fit: BoxFit.scaleDown,
        alignment: left ? Alignment.centerLeft : Alignment.center,
        child: SizedBox(
          width: room.width,
          child: Column(
            key: const ValueKey('lyric-words'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: cross,
            children: [
              for (var b = 0; b < blocks.length; b++) ...[
                for (var l = 0; l < fit.widths[b].length; l++)
                  SizedBox(
                    width: fit.widths[b][l],
                    child: Text.rich(
                      // The words' own style only, as they were measured:
                      // never the app's letter spacing.
                      style: const TextStyle(letterSpacing: 0, wordSpacing: 0),
                      lyricLine(
                        blocks[b].text.split('\n')[l],
                        lyricTextStyle(
                          fit.size * blocks[b].scale,
                          blocks[b].weight,
                          blocks[b].color(ink),
                          ink.shadows,
                          lineHeight,
                        ),
                        number: ink.accent,
                      ),
                      textAlign: align,
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                if (blocks[b].gap > 0)
                  SizedBox(height: blocks[b].gap * fit.size),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

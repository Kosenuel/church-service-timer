import 'dart:math' as math;

import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/lyrics/lyric_stage.dart';
import 'package:church_service_timer/pairing/paired_screen.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// The `confidence` field of a stage picture, when the screen should show
/// the confidence monitor: present, readable, and no quick message to the
/// stage on top. Null otherwise, and the screen shows the countdown in its
/// group's layout.
Json? stageConfidence(Json data) {
  final c = data['confidence'];
  if (c is! Map || data['quickMessage'] is Map) return null;
  return Map<String, dynamic>.from(c);
}

/// Slides and timer, for a worship leader or speaker facing the room: the
/// words of the slide on the screens large on one side, and on the other
/// the countdown and what the next slide starts with. On the stage
/// theme's own background (never a picture), so the words are as clear as
/// the screen can make them. Upright (a phone on a stand) the words are
/// on top and the time below.
///
/// The time follows the moment as the countdown does: amber in the
/// warning period, dimmed when paused, and in overtime red with the time
/// over. Gentle draws red digits and a red frame round the time; Strong
/// makes the time's panel red; Strongest also pulses it. Only the panel
/// changes, so the words stay readable.
class ConfidenceMonitor extends StatefulWidget {
  final Json data;
  final bool stale;
  const ConfidenceMonitor({super.key, required this.data, required this.stale});

  @override
  State<ConfidenceMonitor> createState() => _ConfidenceMonitorState();
}

class _ConfidenceMonitorState extends State<ConfidenceMonitor>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  bool pulsing = false;

  void syncPulse(bool want) {
    if (want == pulsing) return;
    pulsing = want;
    if (want) {
      pulse.repeat(reverse: true);
    } else {
      pulse.stop();
      pulse.value = 0;
    }
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final slide = stageConfidence(data) ?? const {};
    final colors = StageColors.of(data);
    final active = data['phase'] == 'active';
    final moment = active ? stageMoment(data) : 'normal';
    final over = moment == 'overtime';
    final alert = overtimeAlertValue(data['overtimeAlert']);
    final solid = over && alert != 'gentle';
    final wantsPulse =
        solid &&
        alert == 'strongest' &&
        !reduceAppMotion(context) &&
        !widget.stale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) syncPulse(wantsPulse);
    });
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 1280.0;
        final h = box.maxHeight.isFinite ? box.maxHeight : w * 9 / 16;
        final upright = h > w * 1.1;
        final words = Padding(
          key: const ValueKey('confidence-words'),
          padding: upright
              ? EdgeInsets.fromLTRB(w * .07, w * .08, w * .07, w * .05)
              : EdgeInsets.fromLTRB(w * .045, h * .08, w * .035, h * .08),
          child: _Words(slide: slide, colors: colors),
        );
        final side = AnimatedBuilder(
          animation: pulse,
          builder: (context, _) => _Side(
            slide: slide,
            data: data,
            colors: colors,
            active: active,
            moment: moment,
            alert: alert,
            pulse: pulsing ? Curves.easeInOut.transform(pulse.value) : 0,
            upright: upright,
            stale: widget.stale,
          ),
        );
        return ColoredBox(
          key: const ValueKey('confidence-monitor'),
          color: colors.background,
          child: upright
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 58, child: words),
                    Expanded(flex: 42, child: side),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 62, child: words),
                    Expanded(flex: 38, child: side),
                  ],
                ),
        );
      },
    );
  }
}

/// The slide's words, as large as fits the box without a word being
/// broken: the slide's name above them, small, in the accent colour.
class _Words extends StatelessWidget {
  final Json slide;
  final StageColors colors;
  const _Words({required this.slide, required this.colors});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final label = '${slide['label'] ?? ''}'.trim();
      final title = '${slide['title'] ?? ''}'.trim();
      final text = '${slide['text'] ?? ''}'.trim();
      final reference = '${slide['reference'] ?? ''}'.trim();
      final detail = '${slide['detail'] ?? ''}'.trim();
      final eyebrow = (box.maxHeight * .055).clamp(10.0, 40.0).toDouble();
      final room = Size(
        box.maxWidth,
        math.max(0, box.maxHeight - eyebrow * 2.2),
      );
      // Blocks in the order they are drawn, each with its share of the
      // main size, as the slides themselves set them.
      final blocks = <(String, double, Color, FontWeight)>[
        if (title.isNotEmpty) (title, 1.2, colors.accent, FontWeight.w700),
        if (text.isNotEmpty) (text, 1, colors.text, FontWeight.w500),
        if (reference.isNotEmpty)
          (reference, .55, colors.muted, FontWeight.w500),
        if (detail.isNotEmpty) (detail, .6, colors.muted, FontWeight.w500),
      ];
      final size = _fit(context, blocks, room);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: eyebrow * 2.2,
            child: label.isEmpty
                ? null
                : Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      label.toUpperCase(),
                      key: const ValueKey('confidence-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontFamily: lyricFontFamily,
                        color: colors.accent,
                        fontSize: eyebrow,
                        fontWeight: FontWeight.w700,
                        letterSpacing: eyebrow * .16,
                        height: 1.1,
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, b) in blocks.indexed) ...[
                    if (i > 0) SizedBox(height: size * .35),
                    Text.rich(
                      _span(b, size),
                      key: ValueKey('confidence-block-$i'),
                      textScaler: TextScaler.noScaling,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  static TextSpan _span((String, double, Color, FontWeight) b, double size) {
    final style = TextStyle(
      fontFamily: lyricFontFamily,
      color: b.$3,
      fontSize: size * b.$2,
      fontWeight: b.$4,
      height: 1.18,
      // Set, so the screen's default style (a letter spacing in Material's
      // body text) cannot make the words wider than they were measured.
      letterSpacing: 0,
      wordSpacing: 0,
    );
    final lines = b.$1.split('\n');
    return TextSpan(
      style: style,
      children: [
        for (final (i, line) in lines.indexed) ...[
          if (i > 0) const TextSpan(text: '\n'),
          lyricLine(line, style, number: b.$3.withValues(alpha: .7)),
        ],
      ],
    );
  }

  /// The largest main size, up to a fifth of the height, at which every
  /// block fits [room] with no word broken across lines.
  static double _fit(
    BuildContext context,
    List<(String, double, Color, FontWeight)> blocks,
    Size room,
  ) {
    if (blocks.isEmpty || room.width <= 0 || room.height <= 0) return 12;
    bool fits(double size) {
      var height = 0.0;
      for (final (i, b) in blocks.indexed) {
        final painter = TextPainter(
          text: _span(b, size),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: room.width);
        height += painter.height + (i > 0 ? size * .35 : 0);
        // A word wider than the box would be broken: too big.
        final words = b.$1.split(RegExp(r'\s+'));
        final style = TextStyle(
          fontFamily: lyricFontFamily,
          fontSize: size * b.$2,
          fontWeight: b.$4,
        );
        var broken = false;
        for (final word in words) {
          final p = TextPainter(
            text: TextSpan(text: word, style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.noScaling,
          )..layout();
          broken = p.width > room.width;
          p.dispose();
          if (broken) break;
        }
        painter.dispose();
        if (broken || height > room.height) return false;
      }
      return true;
    }

    // Each typed line kept to one line: the words as they were typed.
    bool fitsWhole(double size) {
      var height = 0.0;
      for (final (i, b) in blocks.indexed) {
        final painter = TextPainter(
          text: _span(b, size),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout();
        height += painter.height + (i > 0 ? size * .35 : 0);
        final wide = painter.width > room.width;
        painter.dispose();
        if (wide || height > room.height) return false;
      }
      return true;
    }

    double largest(bool Function(double) ok) {
      var lo = 8.0, hi = math.max(8.0, room.height / 4);
      if (ok(hi)) return hi;
      for (var i = 0; i < 14; i++) {
        final mid = (lo + hi) / 2;
        if (ok(mid)) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    // As on the slides: typed lines stay whole when that costs at most a
    // fifth of the size; otherwise long lines wrap.
    final wrapped = largest(fits), whole = largest(fitsWhole);
    return whole >= wrapped * .8 ? whole : wrapped;
  }
}

/// The time and what is next, in a panel of the theme's surface colour
/// that turns red in Strong and Strongest overtime.
class _Side extends StatelessWidget {
  final Json slide, data;
  final StageColors colors;
  final bool active, upright, stale;
  final String moment, alert;
  final double pulse;
  const _Side({
    required this.slide,
    required this.data,
    required this.colors,
    required this.active,
    required this.moment,
    required this.alert,
    required this.pulse,
    required this.upright,
    required this.stale,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final over = moment == 'overtime';
      final solid = over && alert != 'gentle';
      final ground = solid
          ? Color.lerp(
              StageColors.overtimeRed,
              StageColors.overtimeBright,
              pulse,
            )!
          : colors.surface;
      final ink = solid
          ? StageColors.overtimeInk
          : over
          ? colors.over
          : moment == 'warning'
          ? colors.warn
          : colors.text;
      final soft = solid ? StageColors.overtimeInk : colors.muted;
      final accent = solid ? StageColors.overtimeInk : colors.accent;
      final frame = over && alert == 'gentle'
          ? (math.min(w, h) * .03).clamp(4.0, 28.0).toDouble()
          : 0.0;
      final unit = upright ? math.min(w * .75, h) : math.min(w, h * .9);
      final eyebrow = (unit * .055).clamp(10.0, 36.0).toDouble();
      final time = active
          ? '${data['remaining'] ?? ''}'
          : '${slide['clock'] ?? ''}';
      final heading = !active
          ? 'TIME'
          : over
          ? 'OVER TIME'
          : data['paused'] == true
          ? 'PAUSED'
          : 'TIME LEFT';
      // A cue for the person on stage sits over the time's side; the
      // slide's words stay as they are.
      final cue = stageCueOverSlide(data);
      final next = slide['next'];
      final nextLabel = next is Map ? '${next['label'] ?? ''}'.trim() : '';
      final nextLine = next is Map ? '${next['line'] ?? ''}'.trim() : '';
      Text small(String text, Color color, {Key? key}) => Text(
        text,
        key: key,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: lyricFontFamily,
          color: color,
          fontSize: eyebrow,
          fontWeight: FontWeight.w700,
          letterSpacing: eyebrow * .16,
          height: 1.1,
        ),
      );
      final digits = Opacity(
        opacity: active && data['paused'] == true ? .45 : 1,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ClockText(
            key: const ValueKey('confidence-time'),
            text: time,
            blink: active && data['paused'] != true,
            stale: stale,
            style: TextStyle(
              fontFamily: lyricFontFamily,
              color: ink,
              fontSize: unit * .3,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ),
      );
      final nextPart = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          small('NEXT', accent, key: const ValueKey('confidence-next-eyebrow')),
          SizedBox(height: eyebrow * .6),
          Text.rich(
            TextSpan(
              children: [
                if (nextLabel.isNotEmpty)
                  TextSpan(
                    text: nextLine.isEmpty ? nextLabel : '$nextLabel · ',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                TextSpan(
                  text: nextLabel.isEmpty && nextLine.isEmpty
                      ? 'Last slide'
                      : nextLine,
                ),
              ],
            ),
            key: const ValueKey('confidence-next'),
            maxLines: upright ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: lyricFontFamily,
              color: solid ? StageColors.overtimeInk : colors.text,
              fontSize: eyebrow * 1.55,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      );
      final pad = EdgeInsets.all(math.max(frame, 0) + unit * .07);
      return DecoratedBox(
        key: const ValueKey('confidence-side'),
        decoration: BoxDecoration(
          color: ground,
          border: frame > 0
              ? Border.all(color: colors.over, width: frame)
              : null,
        ),
        child: Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              small(
                // With a cue in the time's place, the time stays in view
                // beside its heading.
                cue && time.isNotEmpty ? '$heading  $time' : heading,
                over ? ink : soft,
                key: const ValueKey('confidence-heading'),
              ),
              SizedBox(height: eyebrow * .5),
              Expanded(
                flex: 5,
                child: cue
                    ? _CueCard(data: data, stale: stale)
                    : Align(alignment: Alignment.centerLeft, child: digits),
              ),
              Divider(
                height: eyebrow * 1.6,
                thickness: math.max(1, unit * .004),
                color: (solid ? StageColors.overtimeInk : colors.muted)
                    .withValues(alpha: .35),
              ),
              Expanded(
                flex: 4,
                child: Align(alignment: Alignment.topLeft, child: nextPart),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A cue in the confidence monitor's time panel: its words in its colour
/// on a dark tint of it, with a rule along the edge, as a banner cue looks.
class _CueCard extends StatelessWidget {
  final Json data;
  final bool stale;
  const _CueCard({required this.data, required this.stale});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final color = stageCueColor(data);
      return StageScreenFlash(
        key: const ValueKey('confidence-cue'),
        data: data,
        base: Color.alphaBlend(color.withValues(alpha: .16), Colors.black),
        border: Border(
          left: BorderSide(
            color: color,
            width: (box.maxWidth * .025).clamp(3.0, 10.0),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(box.maxHeight * .08),
          child: StageMessage(
            data: stageSlideCueText(data),
            stale: stale,
            fullscreen: true,
            wrapLines: 3,
          ),
        ),
      );
    },
  );
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';

const _flipFace = 'Roboto';

/// How the flip clock is laid out in a box, as multiples of the height of
/// one card ([card]). Every size follows from the card, so the clock keeps
/// its proportions on any screen.
class FlipClockLayout {
  /// The height of a card.
  final double card;

  /// Whether the AM and PM tiles sit in a row below the time (an upright
  /// screen) rather than stacked beside it.
  final bool upright;
  const FlipClockLayout(this.card, this.upright);

  // The widths, in cards. A digit is .72 as wide as it is tall.
  static const digitWidth = .72, digitGap = .05, colonWidth = .2, pairGap = .06;
  static const tileWidth = .62, tileGap = .14;
  static const dateGap = .2, weekdaySize = .13, dateSize = .115;
  static const tilesGap = .22, tilesHeight = .27;

  static double pairWidth(int digits) =>
      digits * digitWidth + (digits - 1) * digitGap;

  /// The height of the whole clock for a card of one unit, and its width
  /// for [hourDigits] digits in the hours; the card is then as large as
  /// both fit. A 12 hour clock is sized for two hour digits, so it does
  /// not change size as 9:59 becomes 10:00.
  static double heightOf(bool upright, bool twelve) =>
      1 +
      (upright && twelve ? tilesGap + tilesHeight : 0) +
      dateGap +
      weekdaySize * 1.25 +
      .05 +
      dateSize * 1.25;
  static double widthOf(bool upright, bool twelve, int hourDigits) =>
      pairWidth(hourDigits) +
      pairGap * 2 +
      colonWidth +
      pairWidth(2) +
      (!upright && twelve ? tileGap + tileWidth : 0);

  /// The layout for a box: the largest card that fits, and not so large
  /// that it uses the whole of an enormous screen.
  factory FlipClockLayout.fit(Size box, {required bool twelve}) {
    final upright = box.height > box.width;
    // A margin of 4% of the shorter side, all round.
    final margin = math.min(box.width, box.height) * .04;
    final width = math.max(1.0, box.width - 2 * margin);
    final height = math.max(1.0, box.height - 2 * margin);
    final card = math.min(
      width / widthOf(upright, twelve, 2),
      height / heightOf(upright, twelve),
    );
    return FlipClockLayout(card, upright);
  }
}

/// A flip clock: the hours and minutes on cards that fold over when a
/// digit changes, the day and date under them, and on a 12 hour clock AM
/// and PM tiles with the current one lit. It takes its size from the box
/// it is given and its colours from [colors].
class FlipClock extends StatelessWidget {
  final StageClockFace face;
  final StageColors colors;

  /// Whether a digit folds over when it changes: false with reduced
  /// motion, and then it changes at once.
  final bool animate;
  const FlipClock({
    super.key,
    required this.face,
    required this.colors,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${face.time}, ${face.weekday} ${face.date}',
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(
            box.maxWidth.isFinite ? box.maxWidth : 1280,
            box.maxHeight.isFinite ? box.maxHeight : 720,
          );
          final fit = FlipClockLayout.fit(size, twelve: face.twelveHour);
          final h = fit.card;
          Widget digits(String text, String place) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, char) in text.split('').indexed) ...[
                if (i > 0) SizedBox(width: h * FlipClockLayout.digitGap),
                FlipDigit(
                  key: ValueKey('flip-$place-$i'),
                  char: char,
                  height: h,
                  colors: colors,
                  animate: animate,
                ),
              ],
            ],
          );
          final time = Row(
            key: const ValueKey('flip-time'),
            mainAxisSize: MainAxisSize.min,
            children: [
              digits(face.hours, 'h'),
              SizedBox(width: h * FlipClockLayout.pairGap),
              _Colon(height: h, colors: colors),
              SizedBox(width: h * FlipClockLayout.pairGap),
              digits(face.minutes, 'm'),
              if (face.twelveHour && !fit.upright) ...[
                SizedBox(width: h * FlipClockLayout.tileGap),
                SizedBox(
                  height: h,
                  width: h * FlipClockLayout.tileWidth,
                  child: _Tiles(
                    pm: face.pm!,
                    height: h,
                    colors: colors,
                    stacked: true,
                  ),
                ),
              ],
            ],
          );
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  time,
                  if (face.twelveHour && fit.upright) ...[
                    SizedBox(height: h * FlipClockLayout.tilesGap),
                    SizedBox(
                      height: h * FlipClockLayout.tilesHeight,
                      child: _Tiles(
                        pm: face.pm!,
                        height: h,
                        colors: colors,
                        stacked: false,
                      ),
                    ),
                  ],
                  SizedBox(height: h * FlipClockLayout.dateGap),
                  Text(
                    face.weekday.toUpperCase(),
                    key: const ValueKey('flip-weekday'),
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: _flipFace,
                      color: colors.accent,
                      fontSize: h * FlipClockLayout.weekdaySize,
                      letterSpacing: h * FlipClockLayout.weekdaySize * .32,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: h * .05),
                  Text(
                    face.date,
                    key: const ValueKey('flip-date'),
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontFamily: _flipFace,
                      color: colors.muted,
                      fontSize: h * FlipClockLayout.dateSize,
                      letterSpacing: h * FlipClockLayout.dateSize * .04,
                      fontWeight: FontWeight.w300,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _Colon extends StatelessWidget {
  final double height;
  final StageColors colors;
  const _Colon({required this.height, required this.colors});
  @override
  Widget build(BuildContext context) {
    final dot = height * .075;
    return SizedBox(
      key: const ValueKey('flip-colon'),
      width: height * FlipClockLayout.colonWidth,
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 2; i++) ...[
              if (i > 0) SizedBox(height: height * .2),
              Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Tiles extends StatelessWidget {
  final bool pm, stacked;
  final double height;
  final StageColors colors;
  const _Tiles({
    required this.pm,
    required this.height,
    required this.colors,
    required this.stacked,
  });
  @override
  Widget build(BuildContext context) {
    Widget tile(String text, bool lit) => Container(
      key: ValueKey('flip-${text.toLowerCase()}${lit ? '-lit' : ''}'),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: height * .1),
      decoration: BoxDecoration(
        color: lit ? colors.accent : colors.tileOff,
        border: Border.all(color: lit ? colors.accent : colors.tileLine),
        borderRadius: BorderRadius.circular(height * .05),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontFamily: _flipFace,
          fontWeight: FontWeight.w700,
          fontSize: height * .17,
          letterSpacing: height * .17 * .06,
          color: lit ? colors.onAccent : colors.muted,
          height: 1,
        ),
      ),
    );
    final am = tile('AM', !pm), pmTile = tile('PM', pm);
    if (stacked) {
      return Column(
        children: [
          Expanded(child: SizedBox.expand(child: am)),
          SizedBox(height: height * .06),
          Expanded(child: SizedBox.expand(child: pmTile)),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: height * .5, child: am),
        SizedBox(width: height * .1),
        SizedBox(width: height * .5, child: pmTile),
      ],
    );
  }
}

/// One digit on a card. When [char] changes the top half folds down,
/// showing the new digit's top half behind it, and then the new digit's
/// bottom half folds down over the old one's.
class FlipDigit extends StatefulWidget {
  final String char;
  final double height;
  final StageColors colors;
  final bool animate;
  const FlipDigit({
    super.key,
    required this.char,
    required this.height,
    required this.colors,
    this.animate = true,
  });
  static const duration = Duration(milliseconds: 640);
  @override
  State<FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<FlipDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController flip = AnimationController(
    vsync: this,
    duration: FlipDigit.duration,
  );
  late String before = widget.char;

  @override
  void didUpdateWidget(FlipDigit old) {
    super.didUpdateWidget(old);
    if (old.char == widget.char) return;
    if (widget.animate) {
      before = old.char;
      flip.forward(from: 0);
    } else {
      flip.value = 0;
    }
  }

  @override
  void dispose() {
    flip.dispose();
    super.dispose();
  }

  Widget face(String char, {required bool top}) {
    final h = widget.height, w = h * FlipClockLayout.digitWidth;
    final colors = widget.colors;
    final r = Radius.circular(h * .07);
    final mid = Color.lerp(colors.cardTop, colors.cardBottom, .5)!;
    return SizedBox(
      width: w,
      height: h / 2,
      child: ClipRect(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: top
                ? BorderRadius.only(topLeft: r, topRight: r)
                : BorderRadius.only(bottomLeft: r, bottomRight: r),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: top ? [colors.cardTop, mid] : [mid, colors.cardBottom],
            ),
          ),
          child: OverflowBox(
            alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
            minHeight: h,
            maxHeight: h,
            minWidth: w,
            maxWidth: w,
            child: SizedBox(
              width: w,
              height: h,
              child: Center(
                child: Text(
                  char,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: _flipFace,
                    fontWeight: FontWeight.w500,
                    fontSize: h * .86,
                    height: 1,
                    color: colors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height, w = h * FlipClockLayout.digitWidth;
    return AnimatedBuilder(
      animation: flip,
      builder: (context, _) {
        final t = flip.value;
        final flipping = flip.isAnimating;
        final now = widget.char;
        // The first half of the turn folds the old top down; the second
        // unfolds the new bottom.
        final first = t < .5;
        final bottomChar = flipping ? before : now;
        Widget turn({
          required double angle,
          required Alignment origin,
          required Widget child,
        }) => Transform(
          alignment: origin,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 1 / (h * 4))
            ..rotateX(angle),
          child: child,
        );
        return SizedBox(
          key: ValueKey('flip-digit-${widget.char}'),
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The soft shadow the card throws.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(h * .07),
                    boxShadow: [
                      // On a light theme a black shadow reads as a hard
                      // grey foot under each card, so it is the theme's own
                      // ink, much fainter and spread wider.
                      BoxShadow(
                        color: widget.colors.light
                            ? widget.colors.text.withValues(alpha: .07)
                            : Colors.black.withValues(alpha: .35),
                        blurRadius: h * (widget.colors.light ? .22 : .12),
                        offset: Offset(
                          0,
                          h * (widget.colors.light ? .02 : .03),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(top: 0, child: face(now, top: true)),
              Positioned(bottom: 0, child: face(bottomChar, top: false)),
              if (flipping && first)
                Positioned(
                  top: 0,
                  child: turn(
                    angle:
                        Curves.easeIn.transform(t * 2) * (math.pi / 2) * .999,
                    origin: Alignment.bottomCenter,
                    child: face(before, top: true),
                  ),
                ),
              if (flipping && !first)
                Positioned(
                  bottom: 0,
                  child: turn(
                    angle:
                        -(1 - Curves.easeOut.transform((t - .5) * 2)) *
                        (math.pi / 2) *
                        .999,
                    origin: Alignment.topCenter,
                    child: face(now, top: false),
                  ),
                ),
              // The hinge between the halves.
              Positioned(
                left: 0,
                right: 0,
                top: h / 2 - math.max(1.0, h * .004),
                height: math.max(2.0, h * .008),
                child: ColoredBox(
                  key: const ValueKey('flip-hinge'),
                  color: widget.colors.hinge,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

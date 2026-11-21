import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A time whose colons blink once a second: fully lit as each second starts
/// and dimmed to 20% for its second half, with a short fade. The blink is
/// restarted whenever the time changes, so it follows the host's seconds and
/// several screens blink together. Only the colons' colour changes, so the
/// digits never move. Each digit stands centred in a place as wide as the
/// widest digit, so the time keeps its width and every digit its place as
/// it counts, even in a font whose digits differ in width. Semantics always
/// exposes the complete time, without announcing every blink.
class ClockText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool blink, stale;
  const ClockText({
    super.key,
    required this.text,
    required this.style,
    this.blink = true,
    this.stale = false,
  });
  static const dimmed = .2;

  /// Characters that share one width of place.
  static const places = ['0123456789', 'AP'];
  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText>
    with SingleTickerProviderStateMixin {
  // 1 = lit, 0 = dimmed.
  late final AnimationController lit = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 100),
  )..addListener(() => setState(() {}));
  Timer? half, second;
  bool get active => widget.blink && !widget.stale;

  void restart() {
    half?.cancel();
    second?.cancel();
    half = second = null;
    lit.value = 1;
    if (!active) return;
    // Dim halfway through this second, and start the next one in 1 s unless
    // the time changes first.
    half = Timer(const Duration(milliseconds: 500), () {
      if (mounted) lit.reverse();
    });
    second = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        lit.forward();
        restart();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    restart();
  }

  @override
  void didUpdateWidget(ClockText old) {
    super.didUpdateWidget(old);
    final wasActive = old.blink && !old.stale;
    if (old.text != widget.text || wasActive != active) restart();
  }

  @override
  void dispose() {
    half?.cancel();
    second?.cancel();
    lit.dispose();
    super.dispose();
  }

  // The width of each character's place in the style last drawn. A digit's
  // place is as wide as the widest digit, and A and P share one too, so
  // the time never moves or changes size as it changes, whatever the
  // font's own digits do.
  TextStyle? measured;
  final widths = <String, double>{};

  double placeOf(String char, TextStyle style) {
    final shared = ClockText.places.firstWhere(
      (group) => group.contains(char),
      orElse: () => char,
    );
    return widths[shared] ??= [
      for (final c in shared.split('')) widthOf(c, style),
    ].reduce(math.max);
  }

  double widthOf(String char, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: char, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    // Roboto, which the app carries, on every device.
    final style = widget.style.copyWith(fontFamily: 'Roboto');
    if (style != measured) {
      measured = style;
      widths.clear();
    }
    final base = style.color ?? DefaultTextStyle.of(context).style.color;
    final alpha = ClockText.dimmed + (1 - ClockText.dimmed) * lit.value;
    final dim = alpha < 1 && base != null
        ? style.copyWith(color: base.withValues(alpha: base.a * alpha))
        : style;
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: Row(
          key: const ValueKey('clock-text'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, char) in widget.text.split('').indexed)
              SizedBox(
                key: ValueKey('clock-char-$i'),
                width: placeOf(char, style),
                child: RichText(
                  textScaler: TextScaler.noScaling,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  textAlign: TextAlign.center,
                  text: TextSpan(text: char, style: char == ':' ? dim : style),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

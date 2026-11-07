import 'dart:async';
import 'package:flutter/material.dart';

/// A time whose colons blink once a second: fully lit as each second starts
/// and dimmed to 20% for its second half, with a short fade. The blink is
/// restarted whenever the time changes, so it follows the host's seconds and
/// several screens blink together. Only the colons' colour changes, so the
/// digits never move. Semantics always exposes the complete time, without
/// announcing every blink.
class ClockText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool blink, stale;
  final TextAlign textAlign;
  const ClockText({
    super.key,
    required this.text,
    required this.style,
    this.blink = true,
    this.stale = false,
    this.textAlign = TextAlign.center,
  });
  static const dimmed = .2;
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

  @override
  Widget build(BuildContext context) {
    final base = widget.style.color ?? DefaultTextStyle.of(context).style.color;
    final alpha = ClockText.dimmed + (1 - ClockText.dimmed) * lit.value;
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: RichText(
          key: const ValueKey('clock-text'),
          textScaler: TextScaler.noScaling,
          softWrap: false,
          textAlign: widget.textAlign,
          text: TextSpan(
            style: widget.style.copyWith(fontFamily: 'Roboto'),
            children: [
              for (final char in widget.text.split(''))
                TextSpan(
                  text: char,
                  style: char == ':' && alpha < 1 && base != null
                      ? TextStyle(color: base.withValues(alpha: base.a * alpha))
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

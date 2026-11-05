import 'dart:async';
import 'package:flutter/material.dart';

/// One on/off cycle per second; hiding only the separator preserves geometry.
/// Semantics always exposes the complete time, without announcing every blink.
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
  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  Timer? timer;
  bool visible = true;
  void sync() {
    final active = widget.blink && !widget.stale;
    if (!active) {
      timer?.cancel();
      timer = null;
      visible = true;
    }
    if (active && timer == null) {
      timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() => visible = !visible);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    sync();
  }

  @override
  void didUpdateWidget(ClockText old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    child: ExcludeSemantics(
      child: RichText(
        key: const ValueKey('clock-text'),
        textScaler: TextScaler.noScaling,
        softWrap: false,
        textAlign: TextAlign.center,
        text: TextSpan(
          style: widget.style.copyWith(fontFamily: 'Roboto'),
          children: [
            for (final char in widget.text.split(''))
              TextSpan(
                text: char,
                style: char == ':' && !visible
                    ? const TextStyle(color: Colors.transparent)
                    : null,
              ),
          ],
        ),
      ),
    ),
  );
}

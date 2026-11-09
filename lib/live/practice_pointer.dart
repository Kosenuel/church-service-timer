import 'package:church_service_timer/shared/app_theme.dart';
import 'package:flutter/material.dart';

/// Points at the control a practice step needs: a pulsing accent ring with
/// a small "Tap" badge that bobs above it for a few seconds, then holds
/// steady. With reduced motion the ring is steady from the start. When it appears, the control is scrolled
/// into view.
class PracticePointer extends StatefulWidget {
  final bool active;
  final Widget child;
  final double radius;

  /// The badge text, e.g. "Tap" or "Tap −2 min" when the ring circles a
  /// group of buttons.
  final String label;
  const PracticePointer({
    super.key,
    required this.active,
    required this.child,
    this.radius = 16,
    this.label = 'Tap',
  });

  @override
  State<PracticePointer> createState() => _PracticePointerState();
}

class _PracticePointerState extends State<PracticePointer>
    with SingleTickerProviderStateMixin {
  late final pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _appear();
  }

  @override
  void didUpdateWidget(PracticePointer old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _appear();
    if (!widget.active && old.active) pulse.stop();
  }

  void _appear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active) return;
      final still = reduceAppMotion(context);
      // Pulse for a few seconds to draw the eye, then hold a steady ring.
      if (!still) {
        pulse.repeat(reverse: true, count: 8).whenComplete(() {
          if (mounted) pulse.value = 1;
        });
      } else {
        pulse.value = 1;
      }
      // Scroll only as far as needed, so the coach card above stays in
      // view whenever it can.
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: still ? Duration.zero : const Duration(milliseconds: 300),
      );
    });
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final accent = appColors(context).accent;
    return AnimatedBuilder(
      animation: pulse,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(pulse.value);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            // The ring sits just outside the control and never takes taps.
            // 7 px out, so a strip of background separates the ring from a
            // filled button of the same colour.
            Positioned.fill(
              left: -7,
              top: -7,
              right: -7,
              bottom: -7,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const ValueKey('practice-pointer'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius + 7),
                    // A ring only: a glow would paint over the control and
                    // make it look disabled.
                    border: Border.all(
                      color: accent.withValues(alpha: .45 + .55 * t),
                      width: 2 + 2 * t,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -30 - 6 * t,
              right: 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          size: 14,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Turns a horizontal swipe across [child] into a move to the next or
/// previous tab: [onSwipe] gets +1 for a swipe to the left (the next tab)
/// and -1 for a swipe to the right.
///
/// A sideways scroller, slider or swipeable row inside [child] wins the
/// gesture, because it sits deeper in the hit test. Swipes that start in
/// the system's edge-gesture zones are left alone, so they stay Android
/// Back.
class TabSwipeDetector extends StatefulWidget {
  final Widget child;

  /// Whether a swipe can move to the tab in [direction] (+1 or -1).
  final bool Function(int direction) canSwipe;
  final void Function(int direction) onSwipe;

  /// On a computer, only a finger or pen on a touch screen swipes between
  /// tabs: dragging with a mouse there selects text and moves sliders, and
  /// must not also change the page.
  final bool touchOnly;
  const TabSwipeDetector({
    super.key,
    required this.child,
    required this.canSwipe,
    required this.onSwipe,
    this.touchOnly = false,
  });

  /// The share of the width a slow swipe has to cover.
  static const distanceFraction = .25;

  /// A flick faster than this (logical pixels a second) is enough on its
  /// own.
  static const flingVelocity = 600.0;

  @override
  State<TabSwipeDetector> createState() => _TabSwipeDetectorState();
}

class _TabSwipeDetectorState extends State<TabSwipeDetector> {
  double? _start;
  double _dx = 0;

  bool _fromEdge(double x) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final insets = media.systemGestureInsets;
    final left = math.max(insets.left, 20.0);
    final right = math.max(insets.right, 20.0);
    return x < left || x > width - right;
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    gestures: {
      HorizontalDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(
              debugOwner: this,
              supportedDevices: widget.touchOnly
                  ? const {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.invertedStylus,
                    }
                  : null,
            ),
            (r) => r
              ..onStart = (d) {
                _start = _fromEdge(d.globalPosition.dx)
                    ? null
                    : d.globalPosition.dx;
                _dx = 0;
              }
              ..onUpdate = (d) {
                _dx += d.primaryDelta ?? 0;
              }
              ..onEnd = (d) {
                if (_start == null) return;
                _start = null;
                final velocity = d.primaryVelocity ?? 0;
                final width = MediaQuery.sizeOf(context).width;
                final far =
                    _dx.abs() >= width * TabSwipeDetector.distanceFraction;
                final fast = velocity.abs() >= TabSwipeDetector.flingVelocity;
                if (!far && !fast) return;
                // Use the travel when it is clear, otherwise the flick.
                final sign = far ? _dx.sign : velocity.sign;
                // Fingers moving left reveal the tab on the right.
                final direction = sign < 0 ? 1 : -1;
                if (widget.canSwipe(direction)) widget.onSwipe(direction);
              }
              ..onCancel = () {
                _start = null;
              },
          ),
    },
    child: widget.child,
  );
}

/// Slides a newly shown tab in from the side it was swiped from.
/// [direction] is +1 when it comes in from the right and -1 from the left;
/// 0 (or reduced motion) shows it at once.
class TabSlideIn extends StatelessWidget {
  final int direction;
  final bool reduceMotion;
  final Widget child;
  const TabSlideIn({
    super.key,
    required this.direction,
    required this.reduceMotion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (direction == 0 || reduceMotion) return child;
    final width = MediaQuery.sizeOf(context).width;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: 1 - t * .6,
        child: Transform.translate(
          offset: Offset(direction * width * .18 * t, 0),
          child: child,
        ),
      ),
    );
  }
}

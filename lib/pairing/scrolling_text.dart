import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// One line of text moving right to left across its box, over and over:
/// a scrolling cue on a stage screen.
///
/// It moves on every frame by the time since the last one, at [speed]
/// logical pixels a second, so its pace does not depend on how often new
/// pictures arrive from the host or on the frame rate. Only the text's
/// position changes from frame to frame: the text is painted once and
/// moved, and nothing around it is built or painted again.
///
/// The same [text] keeps its place when the widget is rebuilt, also with
/// a new speed, style or size; different text starts again from the
/// right-hand edge. While [paused] it holds still where it is.
class ScrollingText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Logical pixels a second.
  final double speed;

  /// The height of the box; when null, the line's height and 24 more.
  final double? height;
  final bool paused;

  const ScrollingText({
    super.key,
    required this.text,
    required this.style,
    required this.speed,
    this.height,
    this.paused = false,
  });

  @override
  State<ScrollingText> createState() => ScrollingTextState();
}

class ScrollingTextState extends State<ScrollingText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = _Frame();
  Duration _last = Duration.zero;

  /// How far the text has moved since it came in at the right-hand edge,
  /// in logical pixels, over and over.
  double travelled = 0;

  /// The width of the box plus the text's: one way across.
  double _travel = 0, _width = 0;

  /// Where the text's left edge is in its box just now.
  double get offset => _travel <= 0 ? _width : _width - travelled % _travel;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(ScrollingText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different cue starts again; the same one carries on.
    if (oldWidget.text != widget.text) travelled = 0;
    _sync();
  }

  void _sync() {
    if (!widget.paused && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (widget.paused && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    final step = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (step <= 0) return;
    travelled += step * widget.speed;
    // Kept small, so it never loses precision over a long service.
    if (_travel > 0 && travelled >= _travel) travelled %= _travel;
    _frame.tick();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, space) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: widget.style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      final width = space.maxWidth, travel = width + painter.width;
      // After a new size the text stays where it was in its box.
      if (_travel > 0 && (travel != _travel || width != _width)) {
        final x = _width > 0 ? offset * width / _width : width;
        travelled = (width - x) % travel;
      }
      _travel = travel;
      _width = width;
      final height = widget.height ?? painter.height + 24;
      final top = (height - painter.height) / 2;
      painter.dispose();
      return SizedBox(
        height: height,
        width: space.maxWidth,
        // Each frame only moves the text, painted once, to its new place:
        // nothing is built or laid out again.
        child: Flow(
          delegate: _Lane(this, top),
          children: [
            RepaintBoundary(
              child: Text(
                widget.text,
                style: widget.style,
                softWrap: false,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Frame extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Paints the text at its place for this frame, and again on each frame.
class _Lane extends FlowDelegate {
  final ScrollingTextState state;
  final double top;
  _Lane(this.state, this.top) : super(repaint: state._frame);

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints(maxHeight: constraints.maxHeight);

  @override
  void paintChildren(FlowPaintingContext context) => context.paintChild(
    0,
    transform: Matrix4.translationValues(state.offset, top, 0),
  );

  @override
  bool shouldRepaint(_Lane old) => old.state != state || old.top != top;
}

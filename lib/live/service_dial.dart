import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/live_timer_views.dart';
import 'package:church_service_timer/live/mission_control_live.dart'
    show timelinePieces, TimelinePiece;
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/format_labels.dart';

/// The Dial layout's countdown: the app's mark at full size. The outer
/// ring is the whole service, a piece per segment, running clockwise from
/// three o'clock to end at the cross; the inner ring is the time left in
/// the running segment, with the figures in the middle.
class ServiceDial extends StatelessWidget {
  final Session session;
  final Stamp now;
  final double size;

  /// Called with a segment's index when its piece of the ring is clicked.
  final ValueChanged<int>? onSegment;
  const ServiceDial({
    super.key,
    required this.session,
    required this.now,
    required this.size,
    this.onSegment,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final s = session, run = s.run;
    final balance = s.balance(now);
    final warning = s.nearWarning(now);
    final expired = balance < 0 || (s.active && balance == 0);
    // Royal Navy's gold accent would read as the amber warning colour, so
    // its rings use the theme's on-time green, as the phone's dial does.
    final ring = colors.id == 'royal_navy' ? colors.success : colors.accent;
    final lit = expired
        ? colors.error
        : warning
        ? colors.warning
        : ring;
    final pieces = timelinePieces(s, now);
    final total = math.max(
      1,
      pieces.fold<int>(0, (n, p) => math.max(n, p.startMs + p.lengthMs)),
    );
    final notice = !s.active
        ? ''
        : balance < 0
        ? 'Allocated time exceeded'
        : balance == 0
        ? 'Time complete'
        : warning
        ? 'Warning · ${formatTime(balance)} left'
        : '';
    final geometry = DialGeometry(size);
    final cross = geometry.cross;
    return Semantics(
      label:
          '${operatorTimeDescription(balance)}, ${formatTime(s.allocatedMs)} allocated',
      child: SizedBox.square(
        key: const ValueKey('service-dial'),
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: ServiceDialPainter(
                    pieces: pieces,
                    total: total,
                    index: s.index,
                    started: s.phase != 'ready',
                    active: s.active,
                    elapsed: s.active && run != null ? s.totalElapsed(now) : 0,
                    left: (s.remaining(now) / math.max(1, s.allocatedMs)).clamp(
                      0.0,
                      1.0,
                    ),
                    ring: ring,
                    lit: lit,
                    over: colors.warning,
                    track: colors.track,
                    mark: colors.accent,
                    text: colors.text,
                    muted: colors.muted,
                    surface: colors.surface,
                    border: colors.border,
                    label:
                        Theme.of(context).textTheme.bodySmall ??
                        const TextStyle(),
                  ),
                ),
              ),
            ),
            if (onSegment != null)
              Positioned.fill(
                child: _RingTaps(
                  size: size,
                  pieces: pieces,
                  total: total,
                  onSegment: onSegment!,
                ),
              ),
            // When the service is now set to end, beside the cross.
            if (s.active && run != null)
              Positioned(
                left: cross.dx + size * .045,
                top: cross.dy - 16,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ends',
                        style: TextStyle(fontSize: 11, color: colors.muted),
                      ),
                      Text(
                        clockLabel(
                          now.wall +
                              ((s.projectedTotal(now) - s.totalElapsed(now)) /
                                      s.rate)
                                  .round(),
                        ),
                        key: const ValueKey('dial-ends'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Center(
              child: SizedBox(
                width: geometry.inner * 1.5,
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        balance < 0 ? 'OVERTIME' : 'REMAINING',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.1,
                          color: balance < 0 ? colors.error : colors.muted,
                        ),
                      ),
                      SizedBox(
                        height: size * .2,
                        child: FittedBox(
                          child: Text(
                            operatorTime(balance),
                            key: const ValueKey('operator-clock'),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w300,
                              height: 1.15,
                              letterSpacing: -2,
                              color: expired || warning ? lit : colors.text,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'of ${formatTime(s.allocatedMs)} allocated',
                        key: const ValueKey('allocated-time'),
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (notice.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            notice,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: lit, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Where the dial's rings and cross sit for a given size.
class DialGeometry {
  final double size;
  const DialGeometry(this.size);
  Offset get centre => Offset(size / 2, size / 2);

  /// Width of the service ring and radius of its centre line; the margin
  /// outside it holds the segment numbers.
  double get stroke => size * .038;
  double get outer => size / 2 - 26 - stroke / 2;
  double get inner => outer - stroke / 2 - size * .034;

  /// The cross stands in the gap, up and to the right, as on the mark.
  Offset get cross =>
      centre + Offset(math.cos(-math.pi / 4), math.sin(-math.pi / 4)) * outer;

  /// Service time as an angle: three quarters of a turn, clockwise from
  /// three o'clock.
  static double angle(int ms, int total) => ms / total * math.pi * 1.5;

  /// The arc for a piece of the service on a ring of [radius]: where it
  /// starts and how far it sweeps, with a hair of space between pieces
  /// kept small enough that a short piece still shows.
  (double, double) arc(int startMs, int lengthMs, int total, {double? radius}) {
    final gap = 2.4 / (radius ?? outer);
    final from = angle(startMs, total);
    final to = angle(startMs + lengthMs, total);
    return (from + gap / 2, math.max(.004, to - from - gap));
  }

  static Paint line(Color color, double width, {bool round = false}) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = round ? StrokeCap.round : StrokeCap.butt;

  /// A segment's number outside the service ring at angle [at], on a
  /// filled disc when [disc] is given.
  void paintNumber(
    Canvas canvas,
    double at,
    String text,
    TextStyle style, {
    Color? disc,
  }) {
    final where =
        centre + Offset(math.cos(at), math.sin(at)) * (outer + stroke / 2 + 13);
    if (disc != null) canvas.drawCircle(where, 9, Paint()..color = disc);
    final number = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    number.paint(canvas, where - Offset(number.width / 2, number.height / 2));
  }

  /// The cross the ring ends at.
  void paintCross(Canvas canvas, Color color) {
    final arm = size * .036;
    final paint = line(color, math.max(4, size * .011), round: true);
    canvas
      ..drawLine(
        cross - Offset(0, arm * 1.25),
        cross + Offset(0, arm * 1.25),
        paint,
      )
      ..drawLine(
        cross + Offset(-arm * .8, -arm * .45),
        cross + Offset(arm * .8, -arm * .45),
        paint,
      );
  }
}

/// The segment whose piece of the service ring is at [position], in a dial
/// [size] across; null in the middle, outside the ring, and in the gap
/// where the cross stands. The margin just outside the ring, where the
/// segment numbers are, counts as the ring.
int? dialSegmentAt(
  Offset position,
  double size,
  List<TimelinePiece> pieces,
  int total,
) {
  final g = DialGeometry(size);
  final offset = position - g.centre;
  final radius = offset.distance;
  if (radius < g.outer - g.stroke / 2 - 4 ||
      radius > g.outer + g.stroke / 2 + 24) {
    return null;
  }
  var angle = math.atan2(offset.dy, offset.dx);
  if (angle < 0) angle += math.pi * 2;
  for (final p in pieces) {
    if (angle >= DialGeometry.angle(p.startMs, total) &&
        angle < DialGeometry.angle(p.startMs + p.lengthMs, total)) {
      return p.index;
    }
  }
  return null;
}

/// Clicks on the service ring, and the hand cursor over it. Everything
/// else on the dial is left alone.
class _RingTaps extends StatefulWidget {
  final double size;
  final List<TimelinePiece> pieces;
  final int total;
  final ValueChanged<int> onSegment;
  const _RingTaps({
    required this.size,
    required this.pieces,
    required this.total,
    required this.onSegment,
  });
  @override
  State<_RingTaps> createState() => _RingTapsState();
}

class _RingTapsState extends State<_RingTaps> {
  bool over = false;
  int? at(Offset position) =>
      dialSegmentAt(position, widget.size, widget.pieces, widget.total);
  void hover(bool value) {
    if (value != over) setState(() => over = value);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    key: const ValueKey('dial-ring'),
    opaque: false,
    cursor: over ? SystemMouseCursors.click : MouseCursor.defer,
    onHover: (event) => hover(at(event.localPosition) != null),
    onExit: (_) => hover(false),
    child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final index = at(details.localPosition);
        if (index != null) widget.onSegment(index);
      },
    ),
  );
}

class ServiceDialPainter extends CustomPainter {
  final List<TimelinePiece> pieces;
  final int total, index, elapsed;
  final bool started, active;

  /// The share of the running segment still to go.
  final double left;
  final Color ring, lit, over, track, mark, text, muted, surface, border;

  /// The app's text style, for the segment numbers.
  final TextStyle label;
  const ServiceDialPainter({
    required this.pieces,
    required this.total,
    required this.index,
    required this.started,
    required this.active,
    required this.elapsed,
    required this.left,
    required this.ring,
    required this.lit,
    required this.over,
    required this.track,
    required this.mark,
    required this.text,
    required this.muted,
    required this.surface,
    required this.border,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = DialGeometry(size.width);
    final c = g.centre;
    final outer = Rect.fromCircle(center: c, radius: g.outer);
    const stroke = DialGeometry.line;
    for (final p in pieces) {
      final (a0, sweep) = g.arc(p.startMs, p.lengthMs, total);
      final done = started && p.index < index;
      final current = active && p.index == index;
      canvas.drawArc(
        outer,
        a0,
        sweep,
        false,
        stroke(done ? ring.withValues(alpha: .5) : track, g.stroke),
      );
      if (current) {
        final reached = DialGeometry.angle(elapsed, total);
        if (reached > a0)
          canvas.drawArc(
            outer,
            a0,
            math.min(sweep, reached - a0),
            false,
            stroke(ring, g.stroke),
          );
      }
      // The part of a finished segment past its planned time.
      if (done && p.lengthMs > p.plannedMs) {
        final plan = DialGeometry.angle(p.startMs + p.plannedMs, total);
        if (a0 + sweep > plan)
          canvas.drawArc(
            outer,
            plan,
            a0 + sweep - plan,
            false,
            stroke(over, g.stroke),
          );
      }
      // The segment's number, outside the ring, where there is room.
      if (sweep * g.outer >= 15) {
        g.paintNumber(
          canvas,
          a0 + sweep / 2,
          '${p.index + 1}',
          label.copyWith(
            fontSize: 11,
            fontWeight: current ? FontWeight.w700 : FontWeight.w500,
            color: current ? surface : muted,
          ),
          disc: current ? ring : null,
        );
      }
    }
    // Where the service is now.
    if (active) {
      final now = DialGeometry.angle(elapsed, total);
      final dir = Offset(math.cos(now), math.sin(now));
      canvas.drawLine(
        c + dir * (g.outer - g.stroke / 2 - 4),
        c + dir * (g.outer + g.stroke / 2 + 4),
        stroke(text, 2.5, round: true),
      );
    }
    g.paintCross(canvas, mark);
    // The running segment: what is left of it leads up to the cross.
    final inner = Rect.fromCircle(center: c, radius: g.inner);
    final width = math.max(5.0, size.width * .014);
    canvas.drawArc(
      inner,
      0,
      math.pi * 1.5,
      false,
      stroke(border, width, round: true),
    );
    if (active && left > 0)
      canvas.drawArc(
        inner,
        math.pi * 1.5 * (1 - left),
        math.pi * 1.5 * left,
        false,
        stroke(lit, width, round: true),
      );
  }

  @override
  bool shouldRepaint(ServiceDialPainter old) =>
      old.total != total ||
      old.index != index ||
      old.elapsed != elapsed ||
      old.left != left ||
      old.started != started ||
      old.active != active ||
      old.pieces.length != pieces.length ||
      old.ring != ring ||
      old.lit != lit ||
      old.track != track ||
      old.text != text;
}

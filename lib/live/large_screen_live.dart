import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/service_dial.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// How the middle pane of Three panes and The dial is arranged.
enum LargePane {
  /// The window is not tall enough: the usual arrangement.
  off,

  /// The ring takes the spare height, with the controls under it.
  grow,

  /// The ring at the left of a wide pane, the controls in a column at its
  /// right.
  beside,
}

/// The middle pane height from which the ring grows. A 1366 × 768 window
/// is below it; a 1920 × 1080 one and a tall laptop window are above.
const largePaneFromHeight = 800.0;

/// The middle pane width from which the controls sit beside the ring.
const largePaneBesideFromWidth = 1240.0;

/// The middle pane of Three panes and The dial in a window with room to
/// spare.
extension LargeScreenPanes on HomeState {
  /// Which arrangement a middle pane [width] by [height] gets.
  LargePane largePaneMode(double width, double height) {
    if (height < largePaneFromHeight) return LargePane.off;
    // Beside needs room for the ring and a column of controls; a narrower
    // pane grows the ring over the controls instead.
    return width >= largePaneBesideFromWidth
        ? LargePane.beside
        : LargePane.grow;
  }

  /// The running segment in a large middle pane.
  Widget largeTimerPane({
    required LargePane mode,
    required List<Widget> notices,
    required Widget header,
    required Widget endService,
    required bool enabled,
    required bool canJump,
    required double width,
    required double height,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final segment = t.segments[s.index];
    final next = s.index + 1 < t.segments.length
        ? t.segments[s.index + 1]
        : null;
    final dial = desktopLayout == 'dial';
    final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
    const padding = EdgeInsets.fromLTRB(28, 10, 28, 16);
    final innerWidth = width - padding.horizontal;
    final innerHeight = height - padding.vertical;
    final hasNote = segment.notes.isNotEmpty;

    // The gauge is a little wider than tall, with a line under it for the
    // warning; the dial is square.
    double gaugeWidthFor(double room) => room * 300 / 250;
    Widget ring(double size) => dial
        ? ServiceDial(
            session: s,
            now: c.now,
            size: size,
            onSegment: showSegmentDetails,
          )
        : SizedBox(
            width: size,
            child: SegmentGauge(
              session: s,
              now: c.now,
              maxWidth: size,
              noticeInside: true,
            ),
          );
    final speakerLine = segment.speaker.isEmpty
        ? null
        : 'Speaker: ${segment.speaker}';
    final nextLine = s.quickTimer
        ? null
        : next == null
        ? 'Final segment'
        : 'Next · ${next.name} · ${next.durationText}';
    Widget note() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const AppDivider(indent: 0, endIndent: 0),
        const SizedBox(height: 12),
        Text(
          'Private note',
          style: TextStyle(
            color: colors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(segment.notes, key: const ValueKey('desktop-private-note')),
      ],
    );

    final List<Widget> children;
    if (mode == LargePane.beside) {
      // The gauge has a margin of its own around the arc.
      const column = 500.0;
      final gap = dial ? 64.0 : 16.0;
      final size = math
          .min(
            innerWidth - column - gap,
            dial ? innerHeight - 32 : gaugeWidthFor(innerHeight),
          )
          .clamp(
            280.0,
            // The size chosen for a 2560 × 1440 window, and in proportion
            // on a taller one.
            dial
                ? math.max(900.0, innerHeight * .66)
                : math.max(820.0, innerHeight * .6),
          )
          .toDouble();
      children = [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: notices,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ring(size),
            SizedBox(width: gap),
            SizedBox(
              width: column,
              child: Column(
                key: const ValueKey('timer-card-content'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Transform.translate(
                      // The title's own padding, so its text lines up
                      // with the lines under it.
                      offset: const Offset(-8, 0),
                      child: segmentTitle(canJump, size: 40, centred: false),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final line in [?speakerLine, ?nextLine])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(line, style: TextStyle(color: colors.muted)),
                    ),
                  const SizedBox(height: 28),
                  liveControls(enabled),
                  if (hasNote) note(),
                  // Set apart from the time adjustments, so a slip does
                  // not land on End service.
                  const SizedBox(height: 28),
                  Align(alignment: Alignment.centerRight, child: endService),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(),
      ];
    } else {
      // The title above and the controls below keep their room; the ring
      // has the rest, up to a size the figures still look right at.
      // A long title wraps; the ring gives up the height of its extra
      // lines, so End service stays in view.
      final title = TextPainter(
        text: TextSpan(
          text: segment.name,
          style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
              .copyWith(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: math.max(120, innerWidth - 48));
      final extraTitle = title.height - title.preferredLineHeight;
      title.dispose();
      final room =
          innerHeight - (hasNote ? 440 : 372) * scale - math.max(0, extraTitle);
      final size = math
          .min(innerWidth - 40, dial ? room : gaugeWidthFor(room))
          .clamp(dial ? 280.0 : 270.0, dial ? 880.0 : 800.0);
      final controls = (size * .8).clamp(560.0, 640.0);
      children = [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...notices,
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: header,
              ),
            ),
            const SizedBox(height: 6),
            Center(child: segmentTitle(canJump, size: size > 560 ? 40 : 34)),
            if (speakerLine != null || nextLine != null) ...[
              const SizedBox(height: 6),
              Text(
                [?speakerLine, ?nextLine].join('   ·   '),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ],
          ],
        ),
        // The ring with its controls straight under it, in the middle of
        // the height that is left.
        Column(
          children: [
            Padding(
              padding: EdgeInsets.only(top: 8, bottom: dial ? 16 : 8),
              child: ring(size),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: controls),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  liveControls(enabled),
                  if (hasNote) note(),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: endService),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(),
      ];
    }
    return SingleChildScrollView(
      key: const ValueKey('live-timer-pane'),
      // Page Down is Next segment here, not a scroll key.
      primary: false,
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(0, innerHeight),
          minWidth: innerWidth,
        ),
        child: Column(
          key: mode == LargePane.beside
              ? null
              : const ValueKey('timer-card-content'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: children,
        ),
      ),
    );
  }
}

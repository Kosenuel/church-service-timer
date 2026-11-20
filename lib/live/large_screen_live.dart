import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/large_screen_variants.dart';
import 'package:church_service_timer/live/service_dial.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// PROTOTYPE: the middle pane of Three panes and The dial in a window with
/// room to spare. See [LargeScreenLive].
extension LargeScreenPanes on HomeState {
  /// Which arrangement a middle pane [width] by [height] gets: 'off' for
  /// today's, 'grow' or 'beside'.
  String largePaneMode(double width, double height) {
    final variant = LargeScreenLive.panes;
    if (variant == 'off' || height < LargeScreenLive.panesFromHeight) {
      return 'off';
    }
    // Beside needs room for the ring and a column of controls; a narrower
    // pane grows the ring over the controls instead.
    if (variant == 'beside' && width >= 1240) return 'beside';
    return 'grow';
  }

  /// The running segment in a large middle pane.
  Widget largeTimerPane({
    required String mode,
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
    double gaugeWidthFor(double room) => (room - 32) * 300 / 260;
    Widget ring(double size) => dial
        ? ServiceDial(
            session: s,
            now: c.now,
            size: size,
            onSegment: showSegmentDetails,
          )
        : SizedBox(
            width: size,
            child: SegmentGauge(session: s, now: c.now, maxWidth: size),
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
    if (mode == 'beside') {
      // The gauge has a margin of its own around the arc.
      const column = 500.0;
      final gap = dial ? 64.0 : 16.0;
      final size = math
          .min(
            innerWidth - column - gap,
            dial ? innerHeight - 32 : gaugeWidthFor(innerHeight - 32),
          )
          .clamp(280.0, dial ? 900.0 : 820.0);
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
      final room = innerHeight - (hasNote ? 400 : 330) * scale;
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
            const SizedBox(height: 6),
            Text(
              [?speakerLine, ?nextLine].join('   ·   '),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
          key: mode == 'beside' ? null : const ValueKey('timer-card-content'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: children,
        ),
      ),
    );
  }
}

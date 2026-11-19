import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/stage_request_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';

/// The Mission control desktop layout: a status strip, the timer, stage
/// and cues side by side, and the whole rundown as a timeline along the
/// bottom. Nothing scrolls during a normal service.
extension MissionControlLive on HomeState {
  Widget missionControlLive({
    required List<Widget> notices,
    required Widget header,
    required Widget? timer,
    required Widget endService,
    required Widget display,
    required Widget cues,
    required bool enabled,
    required bool canJump,
  }) {
    final colors = appColors(context);
    final s = c.liveSession;
    final line = VerticalDivider(width: 1, thickness: 1, color: colors.border);
    final rule = Divider(height: 1, thickness: 1, color: colors.border);
    return Column(
      key: const ValueKey('mission-control-live'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.active) ...[missionStatus(endService), rule],
        Expanded(
          child: LayoutBuilder(
            builder: (context, space) {
              final timerWidth = (space.maxWidth * .37).clamp(440.0, 640.0);
              final stageWidth = (space.maxWidth * .3).clamp(340.0, 520.0);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: timerWidth,
                    child: SingleChildScrollView(
                      key: const ValueKey('live-timer-pane'),
                      // Page Down is Next segment here, not a scroll key.
                      primary: false,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...notices,
                          timer ??
                              missionTimer(
                                header: header,
                                enabled: enabled,
                                canJump: canJump,
                                width: timerWidth - 40,
                                height: space.maxHeight - 16,
                              ),
                        ],
                      ),
                    ),
                  ),
                  line,
                  SizedBox(
                    width: stageWidth,
                    child: SingleChildScrollView(
                      key: const ValueKey('live-stage-pane'),
                      primary: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: FlatPanels(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (c.stageRequests.open.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                child: stageRequestCards(),
                              ),
                            display,
                            if (c.destination == 'mobile') ...[
                              const AppDivider(),
                              quickMessagePanel(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  line,
                  Expanded(
                    child: SingleChildScrollView(
                      key: const ValueKey('live-cue-pane'),
                      primary: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: FlatPanels(child: cues),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        rule,
        ColoredBox(color: colors.surface, child: timelineStrip(enabled)),
        if (showKeyHints && s.active) ...[rule, const KeyLegend()],
      ],
    );
  }

  /// How the service is running, in one line across the top.
  Widget missionStatus(Widget endService) {
    final colors = appColors(context);
    final s = c.liveSession, run = s.run;
    final projected = s.projectedTotal(c.now);
    final variance = projected - s.plannedMs;
    Widget figure(String label, String value, {Color? color, Key? key}) =>
        Padding(
          padding: const EdgeInsets.only(right: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: colors.muted)),
              Text(
                value,
                key: key,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        );
    return Padding(
      key: const ValueKey('mission-status'),
      padding: const EdgeInsets.fromLTRB(20, 7, 16, 7),
      child: Row(
        children: [
          if (run != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Text(
                varianceLabel(variance),
                key: const ValueKey('rundown-variance'),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: variance > 999 ? colors.warning : colors.success,
                ),
              ),
            ),
            figure('Now', clockLabel(c.now.wall)),
            figure('Elapsed', durationLabel(s.totalElapsed(c.now))),
            figure(
              'Planned finish',
              clockLabel(run.startedWall + (s.plannedMs / s.rate).round()),
            ),
            figure(
              s.paused ? 'Ending, if resumed now' : 'Now ending',
              clockLabel(
                c.now.wall +
                    ((projected - s.totalElapsed(c.now)) / s.rate).round(),
              ),
              color: variance > 999 ? colors.warning : null,
              key: const ValueKey('rundown-finish'),
            ),
            if (s.targetFinishWall != null)
              figure('Target finish', clockLabel(s.targetFinishWall!)),
          ],
          const Spacer(),
          endService,
        ],
      ),
    );
  }

  /// The running segment: name, the dial beside its figures, the controls.
  Widget missionTimer({
    required Widget header,
    required bool enabled,
    required bool canJump,
    required double width,
    required double height,
  }) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final segment = t.segments[s.index];
    Segment? later(int steps) => s.index + steps < t.segments.length
        ? t.segments[s.index + steps]
        : null;
    final next = later(1), then = later(2);
    // The dial takes the height the title and controls leave.
    final gauge = math.min(width - 196, height - 250).clamp(232.0, 400.0);
    // In a short window the private note sits beside the dial.
    final noteBelow = height - (gauge * 260 / 300) > 360;
    final muted = TextStyle(color: colors.muted, fontSize: 13);
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 68, child: Text(label, style: muted)),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    Widget note({int? lines}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Private note', style: muted.copyWith(fontSize: 12)),
        const SizedBox(height: 2),
        Tooltip(
          message: segment.notes,
          child: Text(
            segment.notes,
            key: const ValueKey('desktop-private-note'),
            maxLines: lines,
            overflow: lines == null ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
    return Column(
      key: const ValueKey('timer-card-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Align(
          alignment: Alignment.centerLeft,
          child: segmentTitle(canJump, size: 30, centred: false),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: gauge,
              child: SegmentGauge(session: s, now: c.now, maxWidth: gauge),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  fact('Allocated', formatTime(s.allocatedMs)),
                  fact(
                    'Used',
                    formatTime(math.max(0, s.allocatedMs - s.balance(c.now))),
                  ),
                  if (segment.speaker.isNotEmpty)
                    fact('Speaker', segment.speaker),
                  if (!s.quickTimer)
                    fact(
                      'Next',
                      next == null
                          ? 'Final segment'
                          : '${next.name} · ${next.durationText}',
                    ),
                  if (then != null)
                    fact('Then', '${then.name} · ${then.durationText}'),
                  if (segment.notes.isNotEmpty && !noteBelow) ...[
                    const SizedBox(height: 2),
                    note(lines: 3),
                  ],
                ],
              ),
            ),
          ],
        ),
        liveControls(enabled),
        if (segment.notes.isNotEmpty && noteBelow) ...[
          const SizedBox(height: 16),
          const AppDivider(indent: 0, endIndent: 0),
          const SizedBox(height: 12),
          note(),
        ],
      ],
    );
  }

  /// The rundown as a timeline, with the planning actions above it.
  Widget timelineStrip(bool enabled) {
    final colors = appColors(context);
    final s = c.liveSession, t = s.timeline!;
    final small = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
    );
    return Padding(
      key: const ValueKey('timeline-strip'),
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Rundown',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 16),
              if (s.active) ...[
                _swatch(colors.warning.withValues(alpha: .45)),
                Text(
                  '  Ran over',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
              const Spacer(),
              if (s.active) ...[
                OutlinedButton.icon(
                  style: small,
                  onPressed: enabled ? editUpcoming : null,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 17),
                  label: const Text('Edit upcoming'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: small,
                  onPressed: enabled ? recoverTime : null,
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                  label: const Text('Recover time'),
                ),
              ],
              IconButton(
                key: const ValueKey('print-rundown'),
                tooltip: 'Print order of service',
                visualDensity: VisualDensity.compact,
                onPressed: controlsLocked ? null : () => printServiceSheet(t),
                icon: const Icon(Icons.print_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RundownTimeline(
            session: s,
            now: c.now,
            onSegment: showSegmentDetails,
          ),
        ],
      ),
    );
  }

  Widget _swatch(Color color) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}

/// One piece of the timeline: where a segment starts and how long it is,
/// in service time.
class TimelinePiece {
  final int index, startMs, lengthMs;

  /// Planned length, to mark how much of a finished segment ran over.
  final int plannedMs;
  const TimelinePiece(this.index, this.startMs, this.lengthMs, this.plannedMs);
}

/// Lays the service out end to end: finished segments at the time they
/// really took, the running one at its allocation (or longer, in overtime)
/// and the rest as planned. Skipped segments take no room.
List<TimelinePiece> timelinePieces(Session s, Stamp now) {
  final t = s.timeline!, run = s.run;
  final pieces = <TimelinePiece>[];
  var at = 0;
  for (var i = 0; i < t.segments.length; i++) {
    final planned = t.segments[i].durationMs;
    int length;
    if (run != null && run.skipped.contains(i)) {
      continue;
    } else if (i < s.index && s.phase != 'ready') {
      length = run != null && i < run.actualMs.length
          ? run.actualMs[i] ?? planned
          : planned;
    } else if (i == s.index && s.active) {
      length = math.max(s.allocatedMs, s.currentElapsed(now));
    } else {
      length = planned;
    }
    pieces.add(TimelinePiece(i, at, length, planned));
    at += length;
  }
  return pieces;
}

/// The whole service as a row of blocks sized by time, with a marker at
/// now and clock times underneath.
class RundownTimeline extends StatelessWidget {
  final Session session;
  final Stamp now;
  final ValueChanged<int> onSegment;
  const RundownTimeline({
    super.key,
    required this.session,
    required this.now,
    required this.onSegment,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final s = session, t = s.timeline!, run = s.run;
    final pieces = timelinePieces(s, now);
    final total = math.max(
      1,
      pieces.fold<int>(0, (n, p) => math.max(n, p.startMs + p.lengthMs)),
    );
    final running = s.active && run != null;
    final elapsed = running ? s.totalElapsed(now) : 0;
    final small = TextStyle(
      fontSize: 11,
      color: colors.muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, space) {
        final w = space.maxWidth;
        double x(int ms) => ms / total * w;
        // Clock times every 5, 10, 15, 30 or 60 minutes, whichever keeps
        // them about 110 px apart.
        final minutes = total / s.rate / 60000;
        final step = const [
          5,
          10,
          15,
          30,
          60,
        ].firstWhere((m) => minutes / m * 110 <= w, orElse: () => 120);
        final plannedEnd = x(s.plannedMs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 50,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final p in pieces)
                    Positioned(
                      left: x(p.startMs),
                      width: math.max(4, x(p.lengthMs) - 3),
                      top: 0,
                      bottom: 0,
                      child: _block(context, p),
                    ),
                  if (running)
                    Positioned(
                      key: const ValueKey('timeline-now'),
                      left: (x(elapsed) - 1).clamp(0, w - 2),
                      top: -4,
                      bottom: -4,
                      width: 2,
                      child: ColoredBox(color: colors.text),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: run == null || s.phase == 'ready'
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${t.segments.length} segments · ${durationLabel(s.plannedMs)} planned',
                        style: small,
                      ),
                    )
                  : Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (
                          var m = 0;
                          x(m * 60000 * s.rate) < w - 150;
                          m += step
                        )
                          Positioned(
                            left: x(m * 60000 * s.rate),
                            child: Container(
                              padding: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: colors.border),
                                ),
                              ),
                              child: Text(
                                clockLabel(run.startedWall + m * 60000),
                                style: small,
                              ),
                            ),
                          ),
                        Positioned(
                          right: 0,
                          child: Text(
                            'plan ${clockLabel(run.startedWall + (s.plannedMs / s.rate).round())}${plannedEnd < w - 1 ? ' · ends ${clockLabel(run.startedWall + (total / s.rate).round())}' : ''}',
                            key: const ValueKey('timeline-ends'),
                            style: small,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _block(BuildContext context, TimelinePiece p) {
    final colors = appColors(context);
    final s = session, segment = s.timeline!.segments[p.index];
    final current = p.index == s.index && s.active;
    final done = p.index < s.index && s.phase != 'ready';
    final over = done ? p.lengthMs - p.plannedMs : 0;
    final doneFill = Color.alphaBlend(
      colors.accent.withValues(alpha: .16),
      colors.surface,
    );
    final String detail;
    if (current) {
      final balance = s.balance(now);
      detail =
          '${operatorTime(balance)} ${balance < 0 ? 'over' : 'left'} of ${formatTime(s.allocatedMs)}';
    } else if (done) {
      detail = '${formatTime(p.lengthMs)} · ${signedTime(over)}';
    } else {
      detail = segment.durationText;
    }
    return Semantics(
      button: true,
      label: '${segment.name}, $detail',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('timeline-${p.index}'),
          borderRadius: BorderRadius.circular(4),
          onTap: () => onSegment(p.index),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: done ? doneFill : null,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: current
                    ? colors.accent
                    : done
                    ? Colors.transparent
                    : colors.border,
                width: current ? 1.5 : 1,
              ),
            ),
            child: Stack(
              children: [
                // How far the running segment has got.
                if (current)
                  FractionallySizedBox(
                    widthFactor:
                        (s.currentElapsed(now) / math.max(1, p.lengthMs)).clamp(
                          0.0,
                          1.0,
                        ),
                    heightFactor: 1,
                    child: ColoredBox(
                      color: colors.accent.withValues(alpha: .22),
                    ),
                  ),
                // The part of a finished segment past its planned time.
                if (over > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: (over / math.max(1, p.lengthMs)).clamp(
                        0.0,
                        1.0,
                      ),
                      heightFactor: 1,
                      child: ColoredBox(
                        color: colors.warning.withValues(alpha: .45),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        segment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: current
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The keys that work on Live, along the bottom of the window.
class KeyLegend extends StatelessWidget {
  const KeyLegend({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final style = TextStyle(fontSize: 12, color: colors.muted);
    Widget item(String keys, String action) => Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: keys,
              style: TextStyle(
                color: colors.text,
                fontWeight: FontWeight.w600,
                letterSpacing: .3,
              ),
            ),
            TextSpan(text: '  $action'),
          ],
        ),
        style: style,
      ),
    );
    return Container(
      key: const ValueKey('key-legend'),
      color: colors.surface,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          item('Space', 'Pause'),
          item('PgDn PgDn', 'Next segment'),
          item('+ −', 'Adjust time'),
          item('Ctrl Z', 'Undo'),
          const Spacer(),
          Text('Every action asks to confirm', style: style),
        ],
      ),
    );
  }
}

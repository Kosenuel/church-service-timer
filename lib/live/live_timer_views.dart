import 'dart:async';
import 'dart:math' as math;
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/hardware/display_connection.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/practice_views.dart';

class OperatorNotes extends StatefulWidget {
  final String notes;
  const OperatorNotes({super.key, required this.notes});
  @override
  State<OperatorNotes> createState() => _OperatorNotesState();
}

class _OperatorNotesState extends State<OperatorNotes> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    onExpansionChanged: (value) => setState(() => expanded = value),
    leading: const Icon(Icons.lock_outline, size: 18),
    title: Text(
      expanded ? 'Hide operator notes' : 'View operator notes',
      style: const TextStyle(decoration: TextDecoration.underline),
    ),
    children: [
      Align(alignment: Alignment.centerLeft, child: Text(widget.notes)),
    ],
  );
}

String operatorTime(int balance) => balance < 0
    ? '+${formatTime((-balance ~/ 1000) * 1000)}'
    : formatTime(balance);
String operatorTimeDescription(int balance) =>
    '${operatorTime(balance)} ${balance < 0 ? 'overtime' : 'remaining'}';

class SegmentGauge extends StatelessWidget {
  final Session session;
  final Stamp now;

  /// The widest the dial is drawn; the desktop layouts make it larger.
  final double maxWidth;

  /// Puts the warning line in the opening at the foot of the ring, not in
  /// a band under it, so a large ring sits close to what follows.
  final bool noticeInside;
  const SegmentGauge({
    super.key,
    required this.session,
    required this.now,
    this.maxWidth = 306,
    this.noticeInside = false,
  });
  @override
  Widget build(BuildContext context) {
    final balance = session.balance(now);
    final warning = session.nearWarning(now);
    final expired = balance < 0 || (session.active && balance == 0);
    final color = expired
        ? appColors(context).error
        : warning
        ? appColors(context).warning
        // Royal Navy's gold accent would read as the amber warning colour,
        // so its dial uses the theme's on-time green instead.
        : appColors(context).id == 'royal_navy'
        ? appColors(context).success
        : appColors(context).accent;
    final progress = (session.remaining(now) / math.max(1, session.allocatedMs))
        .clamp(0.0, 1.0);
    final labelText = balance < 0 ? 'Overtime' : 'Remaining';
    final notice = !session.active
        ? ''
        : balance < 0
        ? 'Allocated time exceeded'
        : balance == 0
        ? 'Time complete'
        : warning
        ? 'Warning · ${formatTime(balance)} left'
        : '';
    Widget label(String value, [double grow = 1]) => Text(
      value.toUpperCase(),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11 * grow,
        letterSpacing: 1.1 * grow,
        color: value == 'Overtime'
            ? appColors(context).error
            : appColors(context).muted,
      ),
    );
    final number = Text(
      operatorTime(balance),
      key: const ValueKey('operator-clock'),
      maxLines: 1,
      style: TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w300,
        height: 1.15,
        letterSpacing: -2,
        color: expired
            ? color
            : warning
            ? appColors(context).warning
            : appColors(context).text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(maxWidth, constraints.maxWidth);
        // Past the largest dial the layouts drew before, the lettering
        // and the ring's stroke grow with it.
        final grow = (width / 460).clamp(1.0, 2.6);
        final outsideLabels =
            MediaQuery.textScalerOf(context).scale(14) > 21 || width < 230;
        final noticeLine = notice.isEmpty
            ? const SizedBox()
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 17 * grow,
                    color: color,
                  ),
                  SizedBox(width: 6 * grow),
                  Flexible(
                    child: Text(
                      notice,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: color, fontSize: 12 * grow),
                    ),
                  ),
                ],
              );
        return SizedBox(
          width: constraints.maxWidth,
          child: Semantics(
            label:
                '${operatorTimeDescription(balance)}, ${formatTime(session.allocatedMs)} allocated',
            child: Column(
              children: [
                if (outsideLabels) label(labelText),
                SizedBox(
                  width: width,
                  height: width * (noticeInside ? 250 : 260) / 300,
                  child: Stack(
                    children: [
                      if (noticeInside)
                        Positioned(
                          left: width * .2,
                          right: width * .2,
                          // Under the ends of the ring.
                          top: width * 224 / 300,
                          bottom: 0,
                          child: Center(child: noticeLine),
                        ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: TimerArcPainter(
                            progress: progress,
                            color: color,
                            stroke: 14 * grow,
                            track: appColors(context).track,
                            ticks: appColors(context).muted,
                          ),
                        ),
                      ),
                      Positioned(
                        top: width * (outsideLabels ? .34 : .22),
                        left: width * .17,
                        right: width * .17,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!outsideLabels) ...[
                              label(labelText, grow),
                              SizedBox(height: 4 * grow),
                            ],
                            // In a desktop layout the figures grow or
                            // shrink with the dial.
                            Container(
                              height: maxWidth != 306 ? 74 * width / 306 : null,
                              // A long overtime figure in a large ring
                              // stays inside the tick marks.
                              padding: EdgeInsets.symmetric(
                                horizontal: noticeInside ? width * .06 : 0,
                              ),
                              child: FittedBox(
                                fit: maxWidth != 306
                                    ? BoxFit.contain
                                    : BoxFit.scaleDown,
                                child: number,
                              ),
                            ),
                            if (!outsideLabels) ...[
                              SizedBox(height: 6 * grow),
                              Text(
                                'of ${formatTime(session.allocatedMs)} allocated',
                                key: const ValueKey('allocated-time'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14 * grow,
                                  color: appColors(context).muted,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (outsideLabels)
                  Text(
                    'of ${formatTime(session.allocatedMs)} allocated',
                    key: const ValueKey('allocated-time'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 14,
                    ),
                  ),
                if (!noticeInside)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: noticeLine,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TimerArcPainter extends CustomPainter {
  final double progress;
  final Color color, track, ticks;

  /// Width of the ring.
  final double stroke;
  const TimerArcPainter({
    required this.progress,
    required this.color,
    this.stroke = 14,
    this.track = const Color(0xff2b3a30),
    this.ticks = const Color(0xff829080),
  });
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 300;
    final center = Offset(150 * scale, 142 * scale);
    final bounds = Rect.fromCircle(center: center, radius: 112 * scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      bounds,
      math.pi * .75,
      math.pi * 1.5,
      false,
      paint..color = track,
    );
    if (progress > 0)
      canvas.drawArc(
        bounds,
        math.pi * .75,
        math.pi * 1.5 * progress,
        false,
        paint..color = color,
      );
    for (var i = 0; i <= 30; i++) {
      final angle = (135 + i * 9) * math.pi / 180;
      final major = i % 5 == 0;
      Offset point(double r) =>
          center + Offset(math.cos(angle), math.sin(angle)) * r * scale;
      canvas.drawLine(
        point(major ? 88 : 92),
        point(98),
        Paint()
          ..color = major ? ticks : ticks.withValues(alpha: .65)
          ..strokeWidth = (major ? 1.6 : 1.3) * stroke / 14,
      );
    }
  }

  @override
  bool shouldRepaint(TimerArcPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      stroke != oldDelegate.stroke ||
      track != oldDelegate.track ||
      ticks != oldDelegate.ticks;
}

class DisplayPreviewHeader extends StatelessWidget {
  final DisplayConnection connection;
  const DisplayPreviewHeader({super.key, required this.connection});
  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('display-preview-header'),
    children: [
      // Both stay on one line ("Stage screen · Connected" used to wrap);
      // the badge gets the larger share and shortens with "…" only on the
      // narrowest screens.
      Expanded(
        flex: 2,
        child: Text(
          'DISPLAY PREVIEW',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: appColors(context).muted,
            letterSpacing: 1.6,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 3,
        child: Align(
          alignment: Alignment.centerRight,
          child: DisplayConnectionBadge(connection: connection),
        ),
      ),
    ],
  );
}

class DisplayConnectionBadge extends StatelessWidget {
  final DisplayConnection connection;
  const DisplayConnectionBadge({super.key, required this.connection});
  @override
  Widget build(BuildContext context) {
    final color =
        connection == DisplayConnection.disconnected ||
            connection == DisplayConnection.stageDisconnected
        ? appColors(context).error
        : connection == DisplayConnection.connected ||
              connection == DisplayConnection.stageConnected
        ? appColors(context).accent
        : appColors(context).muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(connectionIcon(connection), size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              connection.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class TimeAdjustmentDialog extends StatefulWidget {
  final AppController controller;
  final int revision;
  final int? fixedSeconds;
  const TimeAdjustmentDialog({
    super.key,
    required this.controller,
    required this.revision,
    this.fixedSeconds,
  });
  @override
  State<TimeAdjustmentDialog> createState() => _TimeAdjustmentDialogState();
}

class _TimeAdjustmentDialogState extends State<TimeAdjustmentDialog> {
  final minutes = TextEditingController(text: '0');
  final seconds = TextEditingController(text: '30');
  bool remove = false;
  @override
  void dispose() {
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      widget.controller,
      widget.controller.liveClock,
    ]),
    builder: (context, _) {
      final c = widget.controller, s = c.state.session;
      final custom = widget.fixedSeconds == null;
      final m = int.tryParse(minutes.text), sec = int.tryParse(seconds.text);
      final validInput =
          m != null &&
          sec != null &&
          m >= 0 &&
          m <= 59 &&
          sec >= 0 &&
          sec <= 59 &&
          m * 60 + sec > 0;
      final requested =
          widget.fixedSeconds ??
          (validInput ? (m * 60 + sec) * (remove ? -1 : 1) : 0);
      final before = s.balance(c.now);
      final applied = requested < 0
          ? math.max(-s.remaining(c.now), requested * 1000)
          : requested * 1000;
      final after = before + applied;
      final stale = s.revision != widget.revision || !s.active;
      final error = stale
          ? 'The service changed. Cancel and review this action again.'
          : custom && !validInput
          ? 'Enter 00:01–59:59; seconds must be 0–59.'
          : requested < 0 && before <= 0
          ? 'There is no remaining time to remove.'
          : after > supportedCountdownMs
          ? 'The maximum remaining time is 59:59.'
          : null;
      final name = s.timeline?.segments[s.index].name ?? 'this segment';
      final adding = requested >= 0;
      Widget value(String title, int ms, {bool result = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            operatorTime(ms),
            style: TextStyle(
              fontSize: 24,
              color: result
                  ? appColors(context).accent
                  : appColors(context).text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '${ms < 0 ? 'Overtime' : 'Remaining'} $title',
            style: TextStyle(color: appColors(context).muted, fontSize: 12),
          ),
        ],
      );
      return AlertDialog(
        title: Text(
          custom
              ? 'Custom time'
              : '${adding ? 'Add' : 'Remove'} 2 minutes ${adding ? 'to' : 'from'} $name?',
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (custom) ...[
                  Text(name, style: TextStyle(color: appColors(context).muted)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Add time'),
                        selected: !remove,
                        onSelected: (_) => setState(() => remove = false),
                      ),
                      ChoiceChip(
                        label: const Text('Remove time'),
                        selected: remove,
                        onSelected: (_) => setState(() => remove = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TimeWheels(
                    value:
                        (int.tryParse(minutes.text) ?? 0) * 60 +
                        (int.tryParse(seconds.text) ?? 0),
                    onChanged: (v) => setState(() {
                      minutes.text = '${v ~/ 60}';
                      seconds.text = '${v % 60}';
                    }),
                  ),
                  const SizedBox(height: 16),
                ],
                if (error == null) ...[
                  Text(
                    'Allocated time: ${formatTime(s.allocatedMs)} to ${formatTime(s.allocatedMs + applied)}',
                    style: TextStyle(color: appColors(context).muted),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 230 ||
                          MediaQuery.textScalerOf(context).scale(14) > 21)
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            value('now', before),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Icon(Icons.arrow_downward, size: 20),
                            ),
                            value('after', after, result: true),
                          ],
                        );
                      return Row(
                        children: [
                          Expanded(child: value('now', before)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.arrow_forward, size: 20),
                          ),
                          Expanded(child: value('after', after, result: true)),
                        ],
                      );
                    },
                  ),
                  if (requested < 0 && applied != requested * 1000)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('Removal stops at zero.'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    s.paused
                        ? 'The timer remains paused.'
                        : 'The timer keeps running. Values refresh until you confirm.',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (error != null)
                  Text(
                    error,
                    style: TextStyle(color: appColors(context).error),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: error != null || c.busy
                ? null
                : () => Navigator.pop(context, requested),
            child: Text(
              custom
                  ? (adding ? 'Confirm add time' : 'Confirm remove time')
                  : (adding ? 'Confirm +2 min' : 'Confirm −2 min'),
            ),
          ),
        ],
      );
    },
  );
}

extension LiveViewActions on HomeState {
  Future<bool> confirmTimer({
    required int revision,
    required String title,
    required String action,
    required Widget Function() content,
    bool destructive = false,
  }) async {
    // The same question, in a form that fits the mini timer window, and
    // sits over the stage in full screen.
    if (compactQuestions) {
      return miniConfirm(
        revision: revision,
        title: title,
        action: action,
        content: content,
        destructive: destructive,
      );
    }
    return await showDialog<bool>(
          context: context,
          animationStyle: reduceAppMotion(context)
              ? AnimationStyle.noAnimation
              : null,
          builder: (ctx) => AnimatedBuilder(
            animation: Listenable.merge([c, c.liveClock]),
            builder: (ctx, _) {
              final stale = c.state.session.revision != revision;
              return AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(
                  child: stale ? const Text(staleActionText) : content(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    // On a computer the key that asked can also answer:
                    // Space or Enter confirms. Never for End service and
                    // the other destructive questions.
                    autofocus: c.port.isDesktop && !destructive,
                    onPressed: stale || c.busy
                        ? null
                        : () => Navigator.pop(ctx, true),
                    style: destructive ? destructiveFilled() : null,
                    child: Text(action),
                  ),
                ],
              );
            },
          ),
        ) ??
        false;
  }

  Future<void> adjustTime({int? fixedSeconds}) async {
    // Adjust time has more on it than the mini timer window can hold.
    if (miniTimer) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            key: ValueKey('mini-adjust-hint'),
            content: Text('Expand the window to adjust the time.'),
          ),
        );
      return;
    }
    final revision = c.state.session.revision;
    final delta = await showDialog<int>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => TimeAdjustmentDialog(
        controller: c,
        revision: revision,
        fixedSeconds: fixedSeconds,
      ),
    );
    if (delta != null) await c.act('adjust', value: delta, revision: revision);
  }

  Widget liveControls(bool enabled) {
    final s = c.state.session;
    final canAdvance = enabled && s.index + 1 < s.timeline!.segments.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(14) > 18;
        final colors = appColors(context);
        final primaryHeight = math.max(
          64.0,
          MediaQuery.textScalerOf(context).scale(18) * 2.6,
        );
        final primaryText = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        );
        final pause = practiceSpot(
          'pause',
          Tooltip(
            message: s.paused ? 'Resume' : 'Pause',
            child: UnavailableAction(
              reason: enabled ? null : unavailableReason('Pause'),
              child: FilledButton.icon(
                key: const ValueKey('pause-resume'),
                onPressed: enabled ? confirmPause : null,
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, primaryHeight),
                  textStyle: primaryText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: Icon(
                  s.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 26,
                ),
                label: keyLabel(s.paused ? 'Resume' : 'Pause', 'Space'),
              ),
            ),
          ),
        );
        // On a phone "Next segment" wraps onto two lines beside Pause; the
        // line above the timer already names the next segment.
        final nextLabel =
            constraints.maxWidth < (showKeyHints ? 480 : 400) && !large
            ? 'Next'
            : 'Next segment';
        final next = practiceSpot(
          'next',
          UnavailableAction(
            reason: canAdvance ? null : unavailableReason('Next segment'),
            child: Tooltip(
              message: 'Next segment',
              child: OutlinedButton.icon(
                key: const ValueKey('next-segment'),
                onPressed: canAdvance ? advance : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, primaryHeight),
                  textStyle: primaryText,
                  foregroundColor: colors.accent,
                  side: BorderSide(
                    color: canAdvance ? colors.accent : colors.border,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.skip_next_rounded, size: 26),
                label: keyLabel(nextLabel, 'PgDn', textAlign: TextAlign.center),
              ),
            ),
          ),
        );
        Widget segment(
          String text,
          VoidCallback? callback, {
          bool last = false,
          String? keys,
        }) => UnavailableAction(
          reason: callback == null ? unavailableReason(text) : null,
          child: TextButton(
            onPressed: callback,
            style: TextButton.styleFrom(
              minimumSize: Size(0, appLayout(context).controlHeight),
              foregroundColor: colors.text,
              shape: const RoundedRectangleBorder(),
              textStyle: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontSize: 14),
            ),
            child: keys == null
                ? Text(text, textAlign: TextAlign.center)
                : keyLabel(text, keys, textAlign: TextAlign.center),
          ),
        );
        final adjust = [
          segment(
            '−2 min',
            enabled && s.remaining(c.now) > 0
                ? () => adjustTime(fixedSeconds: -120)
                : null,
          ),
          segment(
            '+2 min',
            enabled && s.balance(c.now) + 120000 <= supportedCountdownMs
                ? () => adjustTime(fixedSeconds: 120)
                : null,
          ),
          segment('Custom', enabled ? adjustTime : null, keys: '+ −'),
        ];
        final adjustGroup = Semantics(
          container: true,
          label: 'Adjust time',
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < adjust.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: colors.border),
                          adjust[i],
                        ],
                      ],
                    )
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < adjust.length; i++) ...[
                            if (i > 0)
                              VerticalDivider(width: 1, color: colors.border),
                            Expanded(child: adjust[i]),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        );
        final undoButton = practiceSpot(
          'undo',
          UnavailableAction(
            reason: enabled && s.undo != null
                ? null
                : unavailableReason('Undo'),
            child: Tooltip(
              message: showKeyHints ? 'Undo · Ctrl+Z' : 'Undo',
              child: OutlinedButton(
                key: const ValueKey('undo'),
                onPressed: enabled && s.undo != null ? undo : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.square(appLayout(context).controlHeight),
                  padding: EdgeInsets.zero,
                  // Dimmed like the controls beside it when unavailable,
                  // for example while the controls are locked.
                  foregroundColor: colors.text,
                  disabledForegroundColor: colors.muted.withValues(alpha: .5),
                  side: BorderSide(color: colors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.undo, size: 20),
                    Text('Undo', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
          radius: 12,
        );
        // A quick timer is one countdown: no Next, nothing to jump to.
        final quick = s.quickTimer;
        final hint = quick
            ? ''
            : s.index + 1 >= s.timeline!.segments.length
            ? 'No upcoming segments'
            : !enabled
            ? (controlsLocked
                  ? 'Unlock controls to jump'
                  : !c.pairing.localControl
                  ? 'Request control to jump'
                  : 'Finish the current action to jump')
            : '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (quick)
              pause
            else if (large || constraints.maxWidth < 300) ...[
              pause,
              const SizedBox(height: 10),
              next,
            ] else
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pause),
                    const SizedBox(width: 10),
                    Expanded(child: next),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // One ring around −2/+2/Custom; the badge says which.
                Expanded(
                  child: practiceSpot(
                    c.practice.pointer == 'minus' ? 'minus' : 'plus',
                    adjustGroup,
                    radius: 12,
                    label: c.practice.pointer == 'minus'
                        ? deviceText('Tap −2 min')
                        : deviceText('Tap +2 min'),
                  ),
                ),
                const SizedBox(width: 10),
                undoButton,
              ],
            ),
            if (hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  hint,
                  style: TextStyle(fontSize: 12, color: colors.muted),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        );
      },
    );
  }
}

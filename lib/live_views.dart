part of 'main.dart';

String operatorTime(int balance) => balance < 0
    ? '+${formatTime((-balance ~/ 1000) * 1000)}'
    : formatTime(balance);
String operatorTimeDescription(int balance) =>
    '${operatorTime(balance)} ${balance < 0 ? 'overtime' : 'remaining'}';

class SegmentGauge extends StatelessWidget {
  final Session session;
  final Stamp now;
  const SegmentGauge({super.key, required this.session, required this.now});
  @override
  Widget build(BuildContext context) {
    final balance = session.balance(now);
    final warning = session.nearWarning(now);
    final expired = session.active && balance <= 0;
    final color = expired
        ? const Color(0xffffb4ab)
        : warning
        ? const Color(0xfff3ba61)
        : accent;
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
    Widget label(String value) => Text(
      value.toUpperCase(),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 11, letterSpacing: 1.1, color: muted),
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
            ? const Color(0xffffdca2)
            : Colors.white,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(306.0, constraints.maxWidth);
        final outsideLabels =
            MediaQuery.textScalerOf(context).scale(14) > 21 || width < 230;
        return Semantics(
          label:
              '${operatorTimeDescription(balance)}, ${formatTime(session.allocatedMs)} allocated',
          child: Column(
            children: [
              if (outsideLabels) label(labelText),
              SizedBox(
                width: width,
                height: width * 260 / 300,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: TimerArcPainter(
                          progress: progress,
                          color: color,
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
                            label(labelText),
                            const SizedBox(height: 4),
                          ],
                          FittedBox(fit: BoxFit.scaleDown, child: number),
                          if (!outsideLabels) ...[
                            const SizedBox(height: 10),
                            label('Allocated time'),
                            const SizedBox(height: 3),
                            Text(
                              formatTime(session.allocatedMs),
                              key: const ValueKey('allocated-time'),
                              style: const TextStyle(
                                fontSize: 19,
                                fontFeatures: [FontFeature.tabularFigures()],
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
                  'Allocated time · ${formatTime(session.allocatedMs)}',
                  key: const ValueKey('allocated-time'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: notice.isEmpty
                      ? const SizedBox()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 17,
                              color: color,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                notice,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: color, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TimerArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  const TimerArcPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 300;
    final center = Offset(150 * scale, 142 * scale);
    final bounds = Rect.fromCircle(center: center, radius: 112 * scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 14;
    canvas.drawArc(
      bounds,
      math.pi * .75,
      math.pi * 1.5,
      false,
      paint..color = const Color(0xff2b3a30),
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
          ..color = major ? const Color(0xff829080) : const Color(0xff5b6f5e)
          ..strokeWidth = major ? 1.6 : 1.3,
      );
    }
  }

  @override
  bool shouldRepaint(TimerArcPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}

class DisplayConnectionBadge extends StatelessWidget {
  final DisplayConnection connection;
  const DisplayConnectionBadge({super.key, required this.connection});
  @override
  Widget build(BuildContext context) {
    final color = connection == DisplayConnection.disconnected
        ? const Color(0xffffb4ab)
        : connection == DisplayConnection.connected
        ? accent
        : const Color(0xffb9c8d4);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connection == DisplayConnection.simulator
                ? Icons.monitor
                : connection == DisplayConnection.connected
                ? Icons.wifi
                : Icons.wifi_off,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              connection.label,
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
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, s = c.state.session;
      final custom = widget.fixedSeconds == null;
      final m = int.tryParse(minutes.text), sec = int.tryParse(seconds.text);
      final validInput =
          m != null &&
          sec != null &&
          m >= 0 &&
          m <= 99 &&
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
          ? 'Enter 00:01–99:59; seconds must be 0–59.'
          : requested < 0 && before <= 0
          ? 'There is no remaining time to remove.'
          : after > maxRemainingMs
          ? 'The maximum remaining time is 99:59.'
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
              color: result ? accent : Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            '${ms < 0 ? 'Overtime' : 'Remaining'} $title',
            style: const TextStyle(color: muted, fontSize: 12),
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
                  Text(name, style: const TextStyle(color: muted)),
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minutes,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Minutes',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: seconds,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Seconds (0–59)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (error == null) ...[
                  Text(
                    'Allocated time: ${formatTime(s.allocatedMs)} → ${formatTime(s.allocatedMs + applied)}',
                    style: const TextStyle(color: muted),
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
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
                if (error != null)
                  Text(error, style: const TextStyle(color: Color(0xffffb4ab))),
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

extension LiveViewActions on _HomeState {
  Future<bool> confirmTimer({
    required int revision,
    required String title,
    required String action,
    required Widget Function() content,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AnimatedBuilder(
          animation: c,
          builder: (ctx, _) {
            final stale = c.state.session.revision != revision;
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: stale
                    ? const Text(
                        'The service changed. Cancel and review this action again.',
                      )
                    : content(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: stale || c.busy
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: Text(action),
                ),
              ],
            );
          },
        ),
      ) ??
      false;

  Future<void> adjustTime({int? fixedSeconds}) async {
    final revision = c.state.session.revision;
    final delta = await showDialog<int>(
      context: context,
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
    Widget control(
      String text,
      VoidCallback? callback, {
      IconData? icon,
      bool filled = false,
    }) {
      final style = ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(48, 50)),
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13),
        ),
      );
      final label = Text(text, textAlign: TextAlign.center);
      if (filled)
        return FilledButton.icon(
          onPressed: callback,
          style: style,
          icon: Icon(icon, size: 18),
          label: label,
        );
      if (icon != null)
        return OutlinedButton.icon(
          onPressed: callback,
          style: style,
          icon: Icon(icon, size: 18),
          label: label,
        );
      return OutlinedButton(onPressed: callback, style: style, child: label);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final large = MediaQuery.textScalerOf(context).scale(14) > 18;
        final columns = constraints.maxWidth >= 330 && !large ? 4 : 2;
        final controls = [
          control(
            '−2 min',
            enabled && s.remaining(c.now) > 0
                ? () => adjustTime(fixedSeconds: -120)
                : null,
          ),
          control(
            s.paused ? 'Resume' : 'Pause',
            enabled ? confirmPause : null,
            icon: s.paused ? Icons.play_arrow : Icons.pause,
            filled: true,
          ),
          control(
            '+2 min',
            enabled && s.balance(c.now) + 120000 <= maxRemainingMs
                ? () => adjustTime(fixedSeconds: 120)
                : null,
          ),
          control('Custom', enabled ? adjustTime : null),
        ];
        Widget row(List<Widget> children) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        );
        final navigation = [
          control(
            'Next segment',
            enabled && s.index + 1 < s.timeline!.segments.length
                ? advance
                : null,
            icon: Icons.skip_next,
          ),
          control(
            'Undo',
            enabled && s.undo != null ? undo : null,
            icon: Icons.undo,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < controls.length; i += columns) ...[
              if (i > 0) const SizedBox(height: 8),
              row(controls.sublist(i, i + columns)),
            ],
            const SizedBox(height: 12),
            if (large || constraints.maxWidth < 260) ...[
              navigation.first,
              const SizedBox(height: 8),
              navigation.last,
            ] else
              row(navigation),
          ],
        );
      },
    );
  }
}

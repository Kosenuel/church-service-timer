import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';

/// Minutes/seconds for durations; hours/minutes only for a time of day.
class TimeWheels extends StatefulWidget {
  final int value;
  final bool clock;
  final int maximum;
  final ValueChanged<int> onChanged;
  const TimeWheels({
    super.key,
    required this.value,
    required this.onChanged,
    this.clock = false,
    this.maximum = 3599,
  });
  @override
  State<TimeWheels> createState() => _TimeWheelsState();
}

class _TimeWheelsState extends State<TimeWheels> {
  late final List<FixedExtentScrollController> controllers;
  bool syncing = false, userScrolling = false;
  final feedbackClock = Stopwatch()..start();
  int lastFeedback = -100;
  void feedback() {
    final mode = appLayout(context).preferences.pickerFeedback;
    if (!userScrolling ||
        mode == 'off' ||
        feedbackClock.elapsedMilliseconds - lastFeedback < 70)
      return;
    lastFeedback = feedbackClock.elapsedMilliseconds;
    unawaited(
      const MethodChannel(
        'church.timer/device',
      ).invokeMethod<void>('pickerTick', mode).catchError((Object _) {}),
    );
  }

  List<int> get values => [widget.value ~/ 60, widget.value % 60];
  int get maximum => widget.clock ? 1439 : widget.maximum;
  List<int> get limits => [
    maximum ~/ 60,
    values[0] == maximum ~/ 60 ? maximum % 60 : 59,
  ];
  List<String> get labels =>
      widget.clock ? ['Hours', 'Minutes'] : ['Minutes', 'Seconds'];
  @override
  void initState() {
    super.initState();
    controllers = [
      for (final v in values) FixedExtentScrollController(initialItem: v),
    ];
  }

  @override
  void didUpdateWidget(covariant TimeWheels old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      syncing = true;
      try {
        for (var i = 0; i < 2; i++) {
          if (controllers[i].hasClients &&
              controllers[i].selectedItem != values[i])
            controllers[i].jumpToItem(values[i]);
        }
      } finally {
        syncing = false;
      }
    });
  }

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> type(int unit) async {
    final text = TextEditingController(text: '${values[unit]}');
    String? error;
    final result = await showDialog<int>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: Text('Set ${labels[unit].toLowerCase()}'),
          content: TextField(
            controller: text,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: labels[unit],
              helperText: '0–${limits[unit]}',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final n = int.tryParse(text.text);
                if (n == null || n < 0 || n > limits[unit]) {
                  refresh(() => error = 'Enter 0–${limits[unit]}.');
                  return;
                }
                Navigator.pop(ctx, n);
              },
              child: const Text('Use value'),
            ),
          ],
        ),
      ),
    );
    // The route animates out after its result resolves.
    Future<void>.delayed(const Duration(seconds: 1), text.dispose);
    if (result != null && mounted) {
      final v = values;
      v[unit] = result;
      widget.onChanged((v[0] * 60 + v[1]).clamp(0, maximum));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    Widget wheel(int i) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labels[i].toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: colors.muted,
            ),
          ),
          SizedBox(
            height: 220,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null)
                  userScrolling = true;
                if (n is ScrollEndNotification) userScrolling = false;
                return false;
              },
              child: CupertinoPicker(
                scrollController: controllers[i],
                itemExtent: 44,
                diameterRatio: 1.5,
                selectionOverlay: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onSelectedItemChanged: (n) {
                  if (syncing) return;
                  if (n != values[i]) feedback();
                  final v = values;
                  v[i] = n;
                  widget.onChanged((v[0] * 60 + v[1]).clamp(0, maximum));
                },
                children: [
                  for (var n = 0; n <= limits[i]; n++)
                    Center(
                      child: Semantics(
                        label: '${labels[i]} $n',
                        button: true,
                        child: GestureDetector(
                          onTap: () => type(i),
                          child: Text(
                            n.toString().padLeft(2, '0'),
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              color: n == values[i]
                                  ? colors.accent
                                  : colors.muted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            wheel(0),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text(
                ':',
                style: TextStyle(fontSize: 28, color: colors.accent),
              ),
            ),
            wheel(1),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (final n
                in widget.clock
                    ? [540, 600, 660, 1080]
                    : [10, 30, 60, 120, 300, 600, 1800].where(
                        (n) => n <= maximum && (maximum <= 120 || n >= 60),
                      ))
              ActionChip(
                label: Text(
                  widget.clock
                      ? '${(n ~/ 60).toString().padLeft(2, '0')}:00'
                      : durationLabel(n * 1000),
                ),
                onPressed: () => widget.onChanged(n),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.clock
              ? 'Scroll the wheels or tap a number to type.'
              : 'Scroll or tap a number to type · ${maximum ~/ 60}:${(maximum % 60).toString().padLeft(2, '0')} maximum.',
          style: TextStyle(fontSize: 12, color: colors.muted),
        ),
      ],
    );
  }
}

Future<int?> showWheelTimePicker(
  BuildContext context, {
  required String title,
  required int initial,
  bool clock = false,
  bool allowZero = false,
  int maximum = 3599,
}) => showDialog<int>(
  context: context,
  animationStyle: reduceAppMotion(context) ? AnimationStyle.noAnimation : null,
  builder: (ctx) => _TimePickerDialog(
    title: title,
    initial: initial,
    clock: clock,
    allowZero: allowZero,
    maximum: maximum,
  ),
);

class _TimePickerDialog extends StatefulWidget {
  final String title;
  final int initial;
  final int maximum;
  final bool clock, allowZero;
  const _TimePickerDialog({
    required this.title,
    required this.initial,
    required this.clock,
    required this.allowZero,
    required this.maximum,
  });
  @override
  State<_TimePickerDialog> createState() => _TimePickerDialogState();
}

class _TimePickerDialogState extends State<_TimePickerDialog> {
  late int selected = widget.initial.clamp(
    0,
    widget.clock ? 1439 : widget.maximum,
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    scrollable: true,
    content: SizedBox(
      width: 340,
      child: TimeWheels(
        value: selected,
        clock: widget.clock,
        maximum: widget.maximum,
        onChanged: (v) => setState(() => selected = v),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: selected == 0 && !widget.clock && !widget.allowZero
            ? null
            : () => Navigator.pop(context, selected),
        child: Text(
          'Use ${(selected ~/ 60).toString().padLeft(2, '0')}:${(selected % 60).toString().padLeft(2, '0')}',
        ),
      ),
    ],
  );
}

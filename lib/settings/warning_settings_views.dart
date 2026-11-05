import 'dart:async';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/shared/time_picker.dart';
import 'package:flutter/material.dart';

class WarningSettingsPanel extends StatelessWidget {
  final DisplaySettings settings;
  final Future<void> Function(DisplaySettings) onSave;
  final bool busy;
  final String title;
  final String? scope;
  const WarningSettingsPanel({
    super.key,
    required this.settings,
    required this.onSave,
    this.busy = false,
    this.title = 'Automatic warning cues',
    this.scope,
  });
  @override
  Widget build(BuildContext context) {
    final d = settings;
    Future<void> edit({int? index}) async {
      final initial = index == null
          ? const WarningRule(
              60,
              TextLayout('1 MIN LEFT'),
              destination: 'stage',
            )
          : d.warnings[index];
      final next = await showDialog<WarningRule>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (_) => WarningEditor(
          initial: initial,
          usedThresholds: d.warnings
              .asMap()
              .entries
              .where((e) => e.key != index)
              .map((e) => e.value.seconds)
              .toSet(),
        ),
      );
      if (next != null && context.mounted) {
        final rules = [...d.warnings];
        if (index == null) {
          rules.add(next);
        } else {
          rules[index] = next;
        }
        await onSave(d.withWarnings(rules));
      }
    }

    final colors = appColors(context);
    Future<void> save(List<WarningRule> rules) => onSave(d.withWarnings(rules));
    Future<void> toggle(int index, bool on) {
      final rules = [...d.warnings];
      rules[index] = WarningRule.fromJson({
        ...rules[index].toJson(),
        'enabled': on,
      });
      return save(rules);
    }

    Future<void> delete(int index) async {
      final yes = await showDialog<bool>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete warning for all services?'),
          content: Text(
            'Remove “${d.warnings[index].cue.text}”? A warning already on stage will finish normally.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete warning'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      await save([...d.warnings]..removeAt(index));
    }

    Widget card(int index) {
      final w = d.warnings[index];
      final timeColor = !w.enabled
          ? colors.muted
          : w.seconds == 0
          ? colors.error
          : w.seconds < 60
          ? colors.warning
          : colors.text;
      final where = [
        w.destination == 'stage' ? 'Operator and stage' : 'Operator only',
        if (w.destination == 'stage')
          w.scrollOnce ? 'scrolls once' : '${w.durationSeconds} seconds',
        displayFontNames[w.cue.font] ?? w.cue.font,
      ].join(' · ');
      return Material(
        key: ValueKey('warning-rule-$index'),
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: busy ? null : () => edit(index: index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                SizedBox(
                  width: 68,
                  child: Text(
                    formatTime(w.seconds * 1000),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                      color: timeColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        w.cue.text,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: w.enabled ? null : colors.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        where,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: w.enabled,
                  onChanged: busy ? null : (on) => toggle(index, on),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Warning actions',
                  enabled: !busy,
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await edit(index: index);
                    } else if (action == 'delete') {
                      await delete(index);
                    } else {
                      await toggle(index, !w.enabled);
                    }
                  },
                  itemBuilder: (ctx) => appMenuEntries(ctx, [
                    const AppMenuAction('edit', 'Edit warning'),
                    AppMenuAction(
                      'toggle',
                      w.enabled ? 'Disable warning' : 'Enable warning',
                    ),
                    const AppMenuAction(
                      'delete',
                      'Delete warning',
                      destructive: true,
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: colors.muted,
                    letterSpacing: 1.2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (d.warnings.length < 6)
              TextButton.icon(
                onPressed: busy ? null : () => edit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
          ],
        ),
        if (scope != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              scope!,
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
        for (var i = 0; i < d.warnings.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          card(i),
        ],
        if (d.warnings.isEmpty)
          OutlinedButton.icon(
            onPressed: busy ? null : () => save(defaultWarnings),
            icon: const Icon(Icons.auto_awesome_outlined, size: 20),
            label: const Text('Use suggested warnings'),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Each warning fires once per segment at the time remaining. Stage cues return to the timer afterwards; Blank sign suppresses them.',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class WarningEditor extends StatefulWidget {
  final WarningRule initial;
  final Set<int> usedThresholds;
  const WarningEditor({
    super.key,
    required this.initial,
    required this.usedThresholds,
  });
  @override
  State<WarningEditor> createState() => _WarningEditorState();
}

class _WarningEditorState extends State<WarningEditor> {
  late int threshold;
  late bool enabled;
  late String destination;
  late bool scrollOnce;
  late int duration;
  late TextLayout cue;
  String? error;
  @override
  void initState() {
    super.initState();
    threshold = widget.initial.seconds;
    enabled = widget.initial.enabled;
    destination = widget.initial.destination;
    cue = widget.initial.cue;
    scrollOnce = widget.initial.scrollOnce;
    duration = widget.initial.durationSeconds;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Automatic warning'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: enabled,
              onChanged: (v) => setState(() => enabled = v),
            ),
            const Text('Trigger when this much time remains:'),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Remaining time'),
              subtitle: Text(formatTime(threshold * 1000)),
              trailing: const Icon(Icons.expand_more),
              onTap: () async {
                final value = await showWheelTimePicker(
                  context,
                  title: 'Warning threshold',
                  initial: threshold,
                  allowZero: true,
                );
                if (value != null && mounted) setState(() => threshold = value);
              },
            ),
            const SizedBox(height: 12),
            ChoiceField<String>(
              value: destination,
              decoration: const InputDecoration(labelText: 'Where to show'),
              options: const [
                ChoiceOption(
                  value: 'operator',
                  label: 'Operator + phone notification',
                ),
                ChoiceOption(value: 'stage', label: 'Operator + stage display'),
              ],
              onChanged: (v) => setState(() => destination = v!),
            ),
            const SizedBox(height: 12),
            Text(styleSummary(cue)),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final next = await showDialog<TextLayout>(
                  context: context,
                  animationStyle: reduceAppMotion(context)
                      ? AnimationStyle.noAnimation
                      : null,
                  builder: (_) => TextComposer(
                    initial: cue,
                    title: 'Warning text and formatting',
                    button: 'Use warning text',
                  ),
                );
                if (next != null && mounted) setState(() => cue = next);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit warning text'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Scroll once, then return'),
              subtitle: const Text(
                'For scrolling text wider than the display.',
              ),
              value: scrollOnce,
              onChanged: (v) => setState(() => scrollOnce = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show for'),
              subtitle: Text(formatTime(duration * 1000)),
              trailing: const Icon(Icons.expand_more),
              onTap: () async {
                final value = await showWheelTimePicker(
                  context,
                  title: 'Warning duration',
                  initial: duration,
                  maximum: 120,
                );
                if (value != null && mounted) setState(() => duration = value);
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Preview duration: ${(warningDurationMs(WarningRule(0, cue, scrollOnce: scrollOnce, durationSeconds: duration)) / 1000).toStringAsFixed(1)} real seconds. Timing continues underneath.',
            ),
            const SizedBox(height: 8),
            WarningAnimationPreview(layout: cue),
            if (error != null)
              Text(error!, style: TextStyle(color: appColors(context).warning)),
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
        onPressed: () {
          try {
            require(
              threshold >= 0 && threshold <= 3599,
              'Choose a threshold up to 59:59.',
            );
            require(
              !widget.usedThresholds.contains(threshold),
              'A warning already uses this threshold.',
            );
            validateLayout(cue);
            final secondsToShow = duration;
            require(
              secondsToShow >= 1 && secondsToShow <= 120,
              'Enter a duration from 1 to 120 seconds.',
            );
            Navigator.pop(
              context,
              WarningRule(
                threshold,
                cue,
                enabled: enabled,
                destination: destination,
                durationSeconds: secondsToShow,
                scrollOnce: scrollOnce,
              ),
            );
          } catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('Save warning'),
      ),
    ],
  );
}

class WarningAnimationPreview extends StatefulWidget {
  final TextLayout layout;
  const WarningAnimationPreview({super.key, required this.layout});
  @override
  State<WarningAnimationPreview> createState() =>
      _WarningAnimationPreviewState();
}

class _WarningAnimationPreviewState extends State<WarningAnimationPreview> {
  Timer? timer;
  final watch = Stopwatch();
  void toggle() {
    if (watch.isRunning) {
      watch.stop();
      timer?.cancel();
    } else {
      watch.start();
      timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(WarningAnimationPreview old) {
    super.didUpdateWidget(old);
    if (old.layout != widget.layout) watch.reset();
  }

  @override
  void dispose() {
    timer?.cancel();
    watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      LedMatrix(pixels: renderPixels(widget.layout, watch.elapsedMilliseconds)),
      TextButton.icon(
        onPressed: toggle,
        icon: Icon(watch.isRunning ? Icons.pause : Icons.play_arrow),
        label: Text(watch.isRunning ? 'Pause preview' : 'Play preview'),
      ),
    ],
  );
}

extension WarningSettingsViews on HomeState {
  Widget sharedZeroSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('At zero · all services'),
        const SizedBox(height: 8),
        Text(
          c.state.defaults.zero?.text ?? '00:00',
          style: const TextStyle(fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose what the stage display shows when a segment reaches 00:00. The operator’s timer continues into overtime, and the next segment starts only when you select Next segment. This setting applies to every service. Blank output and active cues take priority; an end screen applies when you end the whole service.',
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            button(
              'Use 00:00',
              Icons.timer_outlined,
              c.busy ? null : () => c.setSharedZero(null),
            ),
            button(
              'Custom text',
              Icons.edit_outlined,
              c.busy
                  ? null
                  : () async {
                      final next = await compose(
                        c.state.defaults.zero ?? const TextLayout("TIME'S UP"),
                        'Zero-time screen · all services',
                        'Save zero screen',
                      );
                      if (next != null) await c.setSharedZero(next);
                    },
            ),
          ],
        ),
      ],
    ),
  );

  Widget ledShapeSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Simulator LED shape'),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'square',
              label: Text('Square LEDs'),
              icon: Icon(Icons.square),
            ),
            ButtonSegment(
              value: 'circular',
              label: Text('Circular LEDs'),
              icon: Icon(Icons.circle),
            ),
          ],
          selected: {c.state.pixelShape},
          onSelectionChanged: c.busy || c.corrupt
              ? null
              : (values) async {
                  await c.commit((draft, _) {
                    draft.pixelShape = values.single;
                  });
                },
        ),
        const SizedBox(height: 10),
        Text(
          'Saved for this device. Applies to Live and all cue previews; fonts and the 32 × 16 pixel data stay the same.',
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 12),
        LedMatrix(
          pixels: renderPixels(
            const TextLayout('Aa 12', font: 'cuekeeper_sq_matrix'),
            0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'I-Proton Sq-Matrix · compact preview',
          style: TextStyle(color: appColors(context).muted),
        ),
      ],
    ),
  );

  Widget warningsSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WarningSettingsPanel(
        settings: c.state.defaults,
        title: 'Automatic warnings',
        scope:
            'All services and rehearsals. Changes apply to future warnings; earlier thresholds are not replayed.',
        busy: c.busy,
        onSave: saveWarningsWithUndo,
      ),
      const SizedBox(height: 24),
      phoneWarningSettings(),
      settingsGroup('During a service', [
        SwitchListTile(
          key: const ValueKey('lock-screen-controls'),
          contentPadding: appLayout(context).tileInsets,
          title: const Text(
            'Lock-screen controls',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Countdown, Pause and Next in a notification. Next needs a second tap.',
            style: TextStyle(fontSize: 13, color: appColors(context).muted),
          ),
          value: c.state.lockScreenControls,
          onChanged: c.busy
              ? null
              : (v) async {
                  await c.commit((draft, _) => draft.lockScreenControls = v);
                  await c.syncActiveService();
                },
        ),
        settingsRow(
          c.backgroundActive ? Icons.sync : Icons.info_outline,
          c.backgroundActive
              ? 'Background operation active'
              : 'Background operation',
          'Starts with the LED sign or sharing and keeps warnings running while locked. If unavailable, keep the app open; after an interruption, reconnect and review the output.',
          null,
        ),
      ]),
    ],
  );

  Widget phoneWarningSettings() {
    final colors = appColors(context);
    final on = c.notificationState['enabled'] == true;
    final exact = c.notificationState['exact'] == true;
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (mounted) await showError('$e');
      }
    }

    return settingsGroup('Phone alerts', [
      ListTile(
        key: const ValueKey('phone-alerts-status'),
        contentPadding: appLayout(context).tileInsets,
        leading: Icon(
          on
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          color: on ? colors.accent : colors.warning,
        ),
        title: Text(
          on
              ? (c.notificationState['sound'] == true
                    ? 'Notifications and sound on'
                    : 'Notifications on · channel sound off')
              : 'Notifications are off',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          c.notificationError ??
              (on
                  ? 'Warnings also reach this phone'
                  : 'Warnings show on the stage only'),
          style: TextStyle(
            fontSize: 13,
            color: c.notificationError == null ? colors.muted : colors.warning,
          ),
        ),
        trailing: on
            ? null
            : FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: c.busy ? null : c.enablePhoneWarnings,
                child: const Text('Turn on'),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: ChoiceField<int>(
          value: c.state.notificationClearSeconds,
          decoration: const InputDecoration(
            labelText: 'Clear phone warnings after',
          ),
          options: const [
            ChoiceOption(value: 15, label: '15 seconds'),
            ChoiceOption(value: 30, label: '30 seconds'),
            ChoiceOption(value: 60, label: '60 seconds'),
            ChoiceOption(value: 0, label: 'Until dismissed'),
          ],
          onChanged: c.busy
              ? null
              : (value) async {
                  if (!await c.commit(
                        (draft, _) => draft.notificationClearSeconds = value!,
                      ) &&
                      mounted) {
                    await showError(
                      c.error ?? 'Could not save notification preference.',
                    );
                  }
                },
        ),
      ),
      ListTile(
        contentPadding: appLayout(context).tileInsets,
        leading: Icon(Icons.volume_up_outlined, color: colors.muted),
        title: const Text('Sound and vibration'),
        subtitle: Text(
          'Follows phone volume and Do Not Disturb · watches mirror the vibration',
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
        trailing: TextButton(
          onPressed: () => run(c.port.testNotification),
          child: const Text('Test'),
        ),
      ),
      if (!exact)
        ListTile(
          contentPadding: appLayout(context).tileInsets,
          leading: Icon(Icons.alarm, color: colors.warning),
          title: const Text('Precise timing'),
          subtitle: Text(
            'Without precise alarm access, Android may delay warnings while the phone sleeps.',
            style: TextStyle(fontSize: 13, color: colors.muted),
          ),
          trailing: TextButton(
            onPressed: () => run(c.port.requestExactWarnings),
            child: const Text('Allow'),
          ),
        ),
      settingsRow(
        Icons.settings_outlined,
        'Notification settings',
        'Android channel, sound and lock-screen visibility',
        () => run(c.port.openNotificationSettings),
      ),
    ]);
  }
}

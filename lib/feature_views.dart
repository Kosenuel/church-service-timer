import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_menu.dart';
import 'time_picker.dart';
import 'choice_field.dart';
import 'domain.dart';
import 'pixels.dart';
import 'main.dart';

String clockLabel(int wall) {
  final date = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

extension FeatureViews on HomeState {
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
        title: 'Automatic warnings · all services',
        scope:
            'All services and rehearsals. Changes affect future warnings; earlier thresholds are not replayed.',
        busy: c.busy,
        onSave: saveWarningsWithUndo,
      ),
      const SizedBox(height: 16),
      panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.backgroundActive
                  ? 'Background operation active'
                  : 'Background operation starts with a connected service',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Keep the active-service notification running for stage warnings while the phone is locked. If unavailable, keep the app open. After interruption, reconnect and restore output.',
            ),
            const SizedBox(height: 16),
            phoneWarningSettings(),
          ],
        ),
      ),
    ],
  );

  Widget phoneWarningSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ChoiceField<int>(
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
                    mounted)
                  await showError(
                    c.error ?? 'Could not save notification preference.',
                  );
              },
      ),
      const SizedBox(height: 8),
      const Text(
        'Clears phone warnings only. Stage cue duration and the silent active-service notification are unchanged.',
      ),
      const SizedBox(height: 16),
      Text(
        c.notificationState['enabled'] == true
            ? (c.notificationState['sound'] == true
                  ? 'Phone notifications and sound enabled'
                  : 'Phone notifications enabled · channel sound is off')
            : 'Phone notifications are off',
        style: TextStyle(color: appColors(context).muted),
      ),
      if (c.notificationError != null)
        Text(
          c.notificationError!,
          style: TextStyle(color: appColors(context).warning),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (c.notificationState['enabled'] != true)
            button(
              'Enable phone notifications',
              Icons.notifications_active_outlined,
              c.enablePhoneWarnings,
            ),
          button('Notification settings', Icons.settings_outlined, () async {
            try {
              await c.port.openNotificationSettings();
            } catch (e) {
              if (mounted) await showError('$e');
            }
          }),
          button('Test notification sound', Icons.volume_up_outlined, () async {
            try {
              await c.port.testNotification();
            } catch (e) {
              if (mounted) await showError('$e');
            }
          }),
          if (c.notificationState['exact'] != true)
            button('Allow precise warnings', Icons.alarm, () async {
              try {
                await c.port.requestExactWarnings();
              } catch (e) {
                if (mounted) await showError('$e');
              }
            }),
        ],
      ),
      if (c.notificationState['exact'] != true)
        Text(
          'Without precise alarm access, Android may delay warnings while the phone sleeps.',
          style: TextStyle(color: appColors(context).muted, fontSize: 12),
        ),
    ],
  );

  Future<void> confirmPause() async {
    final s = c.state.session;
    final paused = s.paused, revision = s.revision;
    if (await confirmTimer(
      revision: revision,
      title:
          '${paused ? 'Resume' : 'Pause'} ${s.timeline!.segments[s.index].name}?',
      action: paused ? 'Confirm resume' : 'Confirm pause',
      content: () => Text(
        '${paused ? 'Continue from' : 'Hold the timer at'} ${operatorTimeDescription(c.state.session.balance(c.now))}.${paused ? '' : ' It stays paused until you resume.'}\n\nAny stage cue stays visible. Service elapsed time includes pauses.',
      ),
    ))
      await c.act('pause', revision: revision);
  }

  Future<bool> confirmClearReports({ServiceReport? record}) async {
    final ids = record == null
        ? c.state.reports.map((r) => r.id).toSet()
        : {record.id};
    if (ids.isEmpty) return false;
    if (await confirm(
      record == null ? 'Clear all reports?' : 'Clear this report?',
      record == null
          ? 'Delete all ${ids.length} currently saved report records from this device? Exported files and the current service are unaffected. This cannot be undone.'
          : 'Delete the report for “${record.name}” (${DateTime.fromMillisecondsSinceEpoch(record.endedWall).toLocal()})? Exported files and the current service are unaffected. This cannot be undone.',
      record == null ? 'Clear all reports' : 'Clear report',
    )) {
      final ok = await c.clearReports(ids);
      if (!ok && mounted)
        await showError(c.error ?? 'The report could not be cleared.');
      return ok;
    }
    return false;
  }

  Widget timingOverview() {
    final s = c.state.session;
    final projected = s.projectedTotal(c.now);
    final eta =
        c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round();
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(
            s.rehearsal
                ? 'Rehearsal timing · ${s.rate}×'
                : 'Service timing overview',
          ),
          const SizedBox(height: 10),
          if (s.run == null)
            const Text(
              'This service started before timing reports were available. Start a new service to track its full duration.',
            )
          else ...[
            Text(
              varianceLabel(projected - s.plannedMs),
              style: TextStyle(
                fontSize: 24,
                color: projected > s.plannedMs + 999
                    ? appColors(context).warning
                    : appColors(context).accent,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                Text('Planned ${durationLabel(s.plannedMs)}'),
                Text('Elapsed ${durationLabel(s.totalElapsed(c.now))}'),
                Text('This segment ${durationLabel(s.currentElapsed(c.now))}'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              s.phase == 'ended'
                  ? 'Final duration recorded in Reports.'
                  : 'Estimated finish ${clockLabel(eta)}${s.paused ? ' · if resumed now' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              s.rehearsal
                  ? 'Durations are simulated at ${s.rate}×; finish time is real clock time. Advances remain manual.'
                  : 'Includes pauses and time spent at zero. Assumes remaining segments use their planned duration.',
              style: TextStyle(color: appColors(context).muted, fontSize: 12),
            ),
            if (s.uncertain)
              Text(
                'Timing is uncertain after recovery.',
                style: TextStyle(color: appColors(context).warning),
              ),
          ],
          if (s.phase == 'ended')
            TextButton.icon(
              onPressed: () => navigatePage(2),
              icon: const Icon(Icons.assessment_outlined),
              label: const Text('Open reports'),
            ),
        ],
      ),
    );
  }

  Future<void> exportReport(ServiceReport r, String type) async {
    try {
      await c.port.exportFile(
        'Church-Service-Timer-report-${r.endedWall}.$type',
        type == 'csv' ? exportReportCsv(r) : exportReportJson(r),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
  }
}

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
    Widget button(String text, IconData icon, VoidCallback? action) =>
        OutlinedButton.icon(
          onPressed: action,
          icon: Icon(icon, size: 20),
          label: Text(text),
        );
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

    return Material(
      color: appColors(context).surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: appColors(context).border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                color: appColors(context).muted,
                letterSpacing: 1.6,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (scope != null) ...[
              const SizedBox(height: 8),
              Text(scope!, style: TextStyle(color: appColors(context).muted)),
            ],
            const SizedBox(height: 8),
            Text(
              'Triggers once per segment at the selected time remaining. A stage cue returns to the timer after its duration. Blank sign suppresses stage cues; phone alerts follow Android sound and Do Not Disturb settings.',
              style: TextStyle(color: appColors(context).muted),
            ),
            for (final e in d.warnings.asMap().entries) ...[
              if (e.key > 0) const AppDivider(indent: 0, endIndent: 0),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${e.value.enabled ? '' : 'Off · '}${formatTime(e.value.seconds * 1000)} · ${e.value.cue.text}',
                ),
                subtitle: Text(
                  '${e.value.destination == 'stage' ? 'Operator + stage' : 'Operator only'} · ${displayFontNames[e.value.cue.font]}',
                ),
                onTap: busy ? null : () => edit(index: e.key),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Warning actions',
                  enabled: !busy,
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await edit(index: e.key);
                      return;
                    }
                    if (action == 'delete') {
                      final yes = await showDialog<bool>(
                        context: context,
                        animationStyle: reduceAppMotion(context)
                            ? AnimationStyle.noAnimation
                            : null,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete warning for all services?'),
                          content: Text(
                            'Remove “${e.value.cue.text}”? A warning already on stage will finish normally.',
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
                    }
                    final rules = [...d.warnings];
                    if (action == 'delete') {
                      rules.removeAt(e.key);
                    } else {
                      rules[e.key] = WarningRule.fromJson({
                        ...e.value.toJson(),
                        'enabled': !e.value.enabled,
                      });
                    }
                    await onSave(d.withWarnings(rules));
                  },
                  itemBuilder: (ctx) => appMenuEntries(ctx, [
                    const AppMenuAction('edit', 'Edit warning'),
                    AppMenuAction(
                      'toggle',
                      e.value.enabled ? 'Disable warning' : 'Enable warning',
                    ),
                    const AppMenuAction(
                      'delete',
                      'Delete warning',
                      destructive: true,
                    ),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (d.warnings.isEmpty)
              button(
                'Use suggested warnings',
                Icons.auto_awesome_outlined,
                busy ? null : () => onSave(d.withWarnings(defaultWarnings)),
              ),
            if (d.warnings.length < 6)
              button(
                'Add warning',
                Icons.notification_add_outlined,
                busy ? null : () => edit(),
              ),
          ],
        ),
      ),
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

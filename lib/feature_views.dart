part of 'main.dart';

String clockLabel(int wall) {
  final date = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

extension FeatureViews on _HomeState {
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
          'Shared across every service, including the one currently loaded. A manual cue or automatic warning keeps priority.',
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
          'Service Sq-Matrix · compact preview',
          style: TextStyle(color: appColors(context).muted),
        ),
      ],
    ),
  );

  Widget liveWarnings() {
    final d = c.state.session.timeline!.display;
    final count = d.warnings
        .where((w) => w.enabled && w.destination == 'stage')
        .length;
    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Automatic warnings · this service'),
            subtitle: Text(
              '$count stage warnings · thresholds use time remaining',
            ),
            children: [
              warningSettings(d, (next) async {
                await c.setLiveWarnings(next.warnings);
              }),
            ],
          ),
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
              button(
                'Notification settings',
                Icons.settings_outlined,
                () async {
                  try {
                    await c.port.openNotificationSettings();
                  } catch (e) {
                    if (mounted) await showError('$e');
                  }
                },
              ),
              button(
                'Test notification sound',
                Icons.volume_up_outlined,
                () async {
                  try {
                    await c.port.testNotification();
                  } catch (e) {
                    if (mounted) await showError('$e');
                  }
                },
              ),
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
      ),
    );
  }

  Widget timesFontSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Times New Roman'),
        const SizedBox(height: 8),
        Text(
          NativeDisplayFonts.available
              ? 'Times New Roman is installed on this device.'
              : 'Import a Times New Roman Regular .ttf licensed for use on this device. The app does not bundle or substitute this font.',
        ),
        const SizedBox(height: 12),
        button(
          NativeDisplayFonts.available
              ? 'Replace Times New Roman font'
              : 'Import Times New Roman font',
          Icons.font_download_outlined,
          c.busy || c.state.session.active
              ? null
              : () async {
                  try {
                    if (await c.port.importTimesFont()) {
                      await c.reloadFonts();
                    }
                  } catch (e) {
                    if (mounted) await showError('Font import failed: $e');
                  }
                },
        ),
        if (c.state.session.active)
          Text(
            'End the current service before changing the installed font.',
            style: TextStyle(color: appColors(context).muted),
          ),
        const SizedBox(height: 8),
        Text(
          'Service Matrix is built in and unchanged. Retired Service Serif and Clear Sans selections use Service Matrix.',
          style: TextStyle(color: appColors(context).muted),
        ),
      ],
    ),
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
              onPressed: () => navigatePage(3),
              icon: const Icon(Icons.assessment_outlined),
              label: const Text('Open reports'),
            ),
        ],
      ),
    );
  }

  Widget warningSettings(
    DisplaySettings d,
    Future<void> Function(DisplaySettings) save,
  ) => WarningSettingsPanel(settings: d, onSave: save, busy: c.busy);

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
              'Triggers at the selected time remaining, once per segment. Stage warnings overlay the display for 8 seconds, then restore the cue or timer. Phone notifications follow Android sound and Do Not Disturb settings.',
              style: TextStyle(color: appColors(context).muted),
            ),
            ...d.warnings.asMap().entries.map(
              (e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${e.value.enabled ? '' : 'Off · '}${formatTime(e.value.seconds * 1000)} · ${e.value.cue.text}',
                ),
                subtitle: Text(
                  '${e.value.destination == 'stage' ? 'Operator + stage' : 'Operator only'} · ${displayFontNames[e.value.cue.font]}',
                ),
                onTap: busy ? null : () => edit(index: e.key),
                trailing: IconButton(
                  tooltip: 'Edit warning',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy ? null : () => edit(index: e.key),
                ),
              ),
            ),
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
  late TextEditingController minutes, seconds;
  late bool enabled;
  late String destination;
  late TextLayout cue;
  String? error;
  @override
  void initState() {
    super.initState();
    minutes = TextEditingController(text: '${widget.initial.seconds ~/ 60}');
    seconds = TextEditingController(text: '${widget.initial.seconds % 60}');
    enabled = widget.initial.enabled;
    destination = widget.initial.destination;
    cue = widget.initial.cue;
  }

  @override
  void dispose() {
    minutes.dispose();
    seconds.dispose();
    super.dispose();
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: seconds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Seconds'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: destination,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Where to show'),
              items: const [
                DropdownMenuItem(
                  value: 'operator',
                  child: Text('Operator + phone notification'),
                ),
                DropdownMenuItem(
                  value: 'stage',
                  child: Text('Operator + simulated stage'),
                ),
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
            Text(
              'Stage cues last 8 real seconds, including in fast rehearsal. Long scrolling messages may need shorter text or a faster speed.',
              style: TextStyle(color: appColors(context).muted),
            ),
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
            final m = int.tryParse(minutes.text),
                sec = int.tryParse(seconds.text);
            require(
              m != null &&
                  sec != null &&
                  m >= 0 &&
                  m <= 99 &&
                  sec >= 0 &&
                  sec < 60,
              'Enter 0–99 minutes and 0–59 seconds.',
            );
            final threshold = m! * 60 + sec!;
            require(
              !widget.usedThresholds.contains(threshold),
              'A warning already uses this threshold.',
            );
            validateLayout(cue);
            Navigator.pop(
              context,
              WarningRule(
                threshold,
                cue,
                enabled: enabled,
                destination: destination,
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

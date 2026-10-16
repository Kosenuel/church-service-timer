part of 'main.dart';

String clockLabel(int wall) {
  final date = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

extension FeatureViews on _HomeState {
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
                    ? Colors.orangeAccent
                    : accent,
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
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            if (s.uncertain)
              const Text(
                'Timing is uncertain after recovery.',
                style: TextStyle(color: Colors.orangeAccent),
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

  Future<bool> saveCueToLibrary(TextLayout layout) async {
    final name = TextEditingController(text: layout.text);
    String? error;
    bool saving = false;
    final route = DialogRoute<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Save formatted cue'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Cue name'),
                ),
                const SizedBox(height: 12),
                Text(styleSummary(layout)),
                const SizedBox(height: 8),
                const Text(
                  'Saves text, font, size, bold, italic, alignment, effect and speed. Available in every service.',
                ),
                if (error != null)
                  Text(
                    error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      try {
                        final n = nameValue(name.text, 'Cue name');
                        require(
                          !c.state.savedCues.any(
                            (e) => e.name.toLowerCase() == n.toLowerCase(),
                          ),
                          'That cue name already exists. Use another name or edit it in Display.',
                        );
                        validateLayout(layout);
                        update(() {
                          saving = true;
                          error = null;
                        });
                        final success = await c.commit((draft, _) {
                          require(
                            !draft.savedCues.any(
                              (e) => e.name.toLowerCase() == n.toLowerCase(),
                            ),
                            'Cue name already exists.',
                          );
                          draft.savedCues.add(
                            SavedCue(n, TextLayout.fromJson(layout.toJson())),
                          );
                        });
                        if (!ctx.mounted) return;
                        if (success) {
                          Navigator.pop(ctx, true);
                        } else {
                          update(() {
                            saving = false;
                            error = c.error;
                          });
                        }
                      } catch (e) {
                        update(() {
                          error = '$e';
                          saving = false;
                        });
                      }
                    },
              child: const Text('Save formatted cue'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    // The text field remains mounted during the dialog's exit animation.
    await route.completed;
    name.dispose();
    return result ?? false;
  }

  Future<void> chooseSavedCue() async {
    final picked = await showDialog<SavedCue>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Saved cue library'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.state.savedCues.isEmpty)
                  const Text(
                    'Compose text, choose its formatting, then use Save to cue library.',
                  ),
                ...c.state.savedCues.map(
                  (cue) => ListTile(
                    title: Text(cue.name),
                    subtitle: Text(styleSummary(cue.layout)),
                    onTap: () => Navigator.pop(ctx, cue),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (picked != null && mounted) await sendCue(picked.layout);
  }

  Widget cueLibrary() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label('Saved cue library · all services'),
        const SizedBox(height: 8),
        const Text(
          'Each cue keeps its full formatting. Editing the library does not change a cue already on display.',
          style: TextStyle(color: muted),
        ),
        ...c.state.savedCues.map(
          (cue) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(cue.name),
            subtitle: Text(styleSummary(cue.layout)),
            onTap: c.busy
                ? null
                : () async {
                    final next = await compose(
                      cue.layout,
                      'Edit saved cue',
                      'Save changes',
                    );
                    if (next != null)
                      await c.commit((draft, _) {
                        final index = draft.savedCues.indexWhere(
                          (e) => e.name == cue.name,
                        );
                        require(index >= 0, 'This cue was removed.');
                        draft.savedCues[index] = SavedCue(cue.name, next);
                      });
                  },
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete saved cue',
              onPressed: c.busy
                  ? null
                  : () async {
                      if (await confirm(
                        'Delete saved cue?',
                        'Remove “${cue.name}” from the library?',
                        'Delete',
                      )) {
                        await c.commit(
                          (draft, _) => draft.savedCues.removeWhere(
                            (e) => e.name == cue.name,
                          ),
                        );
                      }
                    },
            ),
          ),
        ),
        const SizedBox(height: 10),
        button(
          'Create saved cue',
          Icons.bookmark_add_outlined,
          c.busy
              ? null
              : () async {
                  final next = await compose(
                    const TextLayout(''),
                    'Create saved cue',
                    'Name and save',
                  );
                  if (next != null && mounted) await saveCueToLibrary(next);
                },
        ),
      ],
    ),
  );

  Widget warningSettings(
    DisplaySettings d,
    Future<void> Function(DisplaySettings) save,
  ) {
    Future<void> edit({int? index}) async {
      final initial = index == null
          ? const WarningRule(60, TextLayout('1 MIN LEFT'))
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
      if (next != null) {
        final rules = [...d.warnings];
        if (index == null) {
          rules.add(next);
        } else {
          rules[index] = next;
        }
        await save(d.withWarnings(rules));
      }
    }

    return panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label('Automatic warning cues'),
          const SizedBox(height: 8),
          const Text(
            'Once per threshold per segment. Stage warnings appear for 8 seconds; manual cues take priority. Missed warnings are never queued.',
            style: TextStyle(color: muted),
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
              onTap: c.busy ? null : () => edit(index: e.key),
              trailing: IconButton(
                tooltip: 'Edit warning',
                icon: const Icon(Icons.edit_outlined),
                onPressed: c.busy ? null : () => edit(index: e.key),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (d.warnings.isEmpty)
            button(
              'Use suggested warnings',
              Icons.auto_awesome_outlined,
              c.busy ? null : () => save(d.withWarnings(defaultWarnings)),
            ),
          if (d.warnings.length < 6)
            button(
              'Add warning',
              Icons.notification_add_outlined,
              c.busy ? null : () => edit(),
            ),
        ],
      ),
    );
  }

  Widget reports() {
    final history = c.state.reports.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'After the service.',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Planned and actual durations, including pauses and time at zero. Reports are saved locally when you end a service.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        if (history.isEmpty)
          panel(
            child: const Text(
              'No completed services yet. End a live service or fast rehearsal to create a report.',
            ),
          ),
        ...history.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.name,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Chip(
                        label: Text(
                          r.rehearsal ? 'Rehearsal ${r.rate}×' : 'Live',
                        ),
                      ),
                    ],
                  ),
                  Text(
                    DateTime.fromMillisecondsSinceEpoch(
                      r.endedWall,
                    ).toLocal().toString().split('.').first,
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Planned ${durationLabel(r.plannedMs)} · Actual ${r.totalMs == null ? 'not recorded' : durationLabel(r.totalMs!)}',
                  ),
                  if (r.totalMs != null)
                    Text(
                      varianceLabel(r.totalMs! - r.plannedMs),
                      style: const TextStyle(color: accent),
                    ),
                  if (r.uncertain)
                    const Text(
                      'Incomplete or uncertain timing; review before using these figures.',
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                  const SizedBox(height: 12),
                  ...r.rows.map(
                    (row) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Plan ${durationLabel(row.plannedMs)} · Actual ${row.actualMs == null ? 'not recorded' : durationLabel(row.actualMs!)}',
                            style: const TextStyle(color: muted),
                          ),
                          if (row.actualMs != null)
                            Text(
                              '${varianceLabel(row.actualMs! - row.plannedMs)} · paused ${durationLabel(row.pausedMs)}${row.adjustmentMs == 0 ? '' : ' · adjusted ${row.adjustmentMs > 0 ? '+' : '−'}${durationLabel(row.adjustmentMs)}'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (r.rehearsal)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Rehearsal durations are simulated time.',
                        style: TextStyle(color: muted),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      button(
                        'Export report CSV',
                        Icons.download_outlined,
                        () => exportReport(r, 'csv'),
                      ),
                      button(
                        'Export report JSON',
                        Icons.code,
                        () => exportReport(r, 'json'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> exportReport(ServiceReport r, String type) async {
    try {
      await c.port.exportFile(
        'Cuekeeper-report-${r.endedWall}.$type',
        type == 'csv' ? exportReportCsv(r) : exportReportJson(r),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
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
            const Text('Trigger when the countdown reaches:'),
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
                  child: Text('Operator screen only'),
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
            const Text(
              'Stage cues last 8 real seconds, including in fast rehearsal. Long scrolling messages may need shorter text or a faster speed.',
              style: TextStyle(color: muted),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
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

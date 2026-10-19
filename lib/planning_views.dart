part of 'main.dart';

extension PlanningViews on _HomeState {
  Future<void> editUpcoming() async {
    final s = c.state.session, revision = c.state.session.revision;
    final result = await Navigator.of(context).push<Timeline>(
      MaterialPageRoute(
        builder: (_) => TemplateEditor(
          initial: Timeline(
            s.timeline!.name,
            s.timeline!.segments.skip(s.index + 1).toList(),
            s.timeline!.display,
          ),
          defaultEnd: s.timeline!.display.end,
          existingNames: const {},
          upcomingOnly: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!await confirm(
      'Update upcoming segments?',
      'Keep the current and completed segments unchanged. Apply ${result.segments.length} upcoming segments to this running service only. The saved program is unchanged.',
      'Update rundown',
    ))
      return;
    if (!await c.commit(
          (draft, at) => replaceUpcoming(draft.session, result.segments, at),
          revision: revision,
        ) &&
        mounted)
      await showError(c.error ?? 'Could not update rundown.');
  }

  Future<void> finishPlanning() async {
    final s = c.state.session;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        DateTime.fromMillisecondsSinceEpoch(
          c.now.wall + s.remaining(c.now) ~/ s.rate,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final date = DateTime.fromMillisecondsSinceEpoch(c.now.wall);
    var target = DateTime(
      date.year,
      date.month,
      date.day,
      selected.hour,
      selected.minute,
    );
    if (target.millisecondsSinceEpoch <= c.now.wall)
      target = target.add(const Duration(days: 1));
    final revision = c.state.session.revision;
    try {
      final proposed = catchUpPlan(
        c.state.session,
        c.now,
        target.millisecondsSinceEpoch,
      );
      final before = c.state.session.timeline!.segments
          .skip(c.state.session.index + 1)
          .toList();
      final changes = [
        for (var i = 0; i < proposed.length; i++)
          '${proposed[i].name}: ${before[i].minutes} → ${proposed[i].minutes} min',
      ].join('\n');
      if (!await confirm(
        'Finish by ${clockLabel(target.millisecondsSinceEpoch)}?',
        '$changes\n\nOnly upcoming durations change. The current timer stays unchanged. Pauses and manual advances can move the actual finish.',
        'Apply plan',
      ))
        return;
      if (!await c.commit((draft, at) {
            final fresh = catchUpPlan(
              draft.session,
              at,
              target.millisecondsSinceEpoch,
            );
            require(
              fresh.map((e) => e.minutes).join(',') ==
                  proposed.map((e) => e.minutes).join(','),
              'Timing changed while this plan was open. Review the finish plan again.',
            );
            replaceUpcoming(draft.session, proposed, at);
            draft.session.targetFinishWall = target.millisecondsSinceEpoch;
          }, revision: revision) &&
          mounted)
        await showError(c.error ?? 'Could not apply plan.');
    } catch (e) {
      if (mounted) await showError('$e');
    }
  }

  Future<void> printServiceSheet(
    Timeline? timeline, {
    ServiceReport? report,
  }) async {
    var includeNotes = false, includeBanner = true;
    var fullReport = report != null;
    final session = c.state.session;
    final actualDate =
        report?.startedWall ??
        (report == null && identical(timeline, session.timeline)
            ? session.run?.startedWall
            : null) ??
        report?.endedWall;
    var selectedDate = DateTime.fromMillisecondsSinceEpoch(
      actualDate ?? c.now.wall,
    );
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Print Service'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Print or choose Save as PDF in Android’s print screen.',
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Service date'),
                  subtitle: Text(
                    serviceDateLabel(selectedDate.millisecondsSinceEpoch),
                  ),
                  trailing: actualDate == null
                      ? const Icon(Icons.edit_calendar_outlined)
                      : null,
                  onTap: actualDate != null
                      ? null
                      : () async {
                          final date = await showDatePicker(
                            context: ctx,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (date != null && ctx.mounted)
                            update(() => selectedDate = date);
                        },
                ),
                if (report != null)
                  DropdownButtonFormField<bool>(
                    initialValue: fullReport,
                    decoration: const InputDecoration(labelText: 'Document'),
                    items: const [
                      DropdownMenuItem(
                        value: true,
                        child: Text('Service report'),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text('Service rundown'),
                      ),
                    ],
                    onChanged: (value) => update(() => fullReport = value!),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include church banner'),
                  value: includeBanner,
                  onChanged: (v) => update(() => includeBanner = v!),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include private operator notes'),
                  subtitle: report != null && report.program == null
                      ? const Text('Not recorded in this older report')
                      : null,
                  value: includeNotes,
                  onChanged: report != null && report.program == null
                      ? null
                      : (v) => update(() => includeNotes = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (yes != true) return;
    try {
      final html = report != null
          ? reportServiceHtml(
              report,
              fullReport: fullReport,
              privateNotes: includeNotes,
              banner: c.state.churchBanner,
              includeBanner: includeBanner,
            )
          : serviceSheetHtml(
              timeline!,
              c.state.churchName,
              privateNotes: includeNotes,
              banner: c.state.churchBanner,
              includeBanner: includeBanner,
              serviceDate: selectedDate.millisecondsSinceEpoch,
            );
      await c.port.printServiceSheet(report?.name ?? timeline!.name, html);
    } catch (e) {
      if (mounted) await showError('Printing failed: $e');
    }
  }
}

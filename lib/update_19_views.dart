part of 'main.dart';

extension Update19Views on _HomeState {
  bool get outputControlsEnabled =>
      !c.busy &&
      !c.corrupt &&
      !controlsLocked &&
      c.pairing.localControl &&
      !c.reportSavePending &&
      c.destinationConnected &&
      (c.state.session.active || c.state.session.phase == 'ended');

  Future<void> jumpToSegment() async {
    final s = c.state.session, revision = c.state.session.revision;
    final target = await showAppSelection<int>(
      context,
      title: 'Jump to segment',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = s.index + 1; i < s.timeline!.segments.length; i++) ...[
            if (i > s.index + 1) const AppDivider(),
            ListTile(
              onTap: () => Navigator.pop(ctx, i),
              leading: Text('${i + 1}'.padLeft(2, '0')),
              title: Text(s.timeline!.segments[i].name),
              subtitle: Text(s.timeline!.segments[i].durationText),
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
        ],
      ),
    );
    if (target == null || !mounted) return;
    final skipped = s.timeline!.segments
        .sublist(s.index + 1, target)
        .map((e) => e.name)
        .join(', ');
    if (await confirmTimer(
      revision: revision,
      title: 'Jump to ${s.timeline!.segments[target].name}?',
      action: 'Jump to segment',
      content: () => Text(
        'Finish ${s.timeline!.segments[s.index].name}. ${skipped.isEmpty ? 'No segments are bypassed.' : 'Mark as skipped: $skipped.'}\n\nStart with ${s.timeline!.segments[target].durationText}. ${s.paused ? 'The timer stays paused.' : 'The timer starts counting.'}',
      ),
    ))
      await c.act('jump', value: target, revision: revision);
  }

  Widget focusedTimingOverview() {
    final s = c.state.session,
        projected = c.state.session.projectedTotal(c.now);
    final eta =
        c.now.wall + ((projected - s.totalElapsed(c.now)) / s.rate).round();
    return panel(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        key: const ValueKey('focused-timing-overview'),
        title: const Text(
          'Service timing overview',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${varianceLabel(projected - s.plannedMs)}\nElapsed ${durationLabel(s.totalElapsed(c.now))} · Finish ${clockLabel(eta)}${s.paused ? ' if resumed now' : ''}',
        ),
        children: [
          Padding(padding: const EdgeInsets.all(16), child: timingOverview()),
        ],
      ),
    );
  }

  Widget clockFormatSettings() => panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Clock format',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (final format in ['24h', '12h'])
          RadioListTile<String>(
            value: format,
            groupValue: c.state.clockFormat,
            title: Text(format == '24h' ? '24-hour' : '12-hour'),
            subtitle: Text(stageClockText(c.now.wall, format)),
            onChanged: c.busy
                ? null
                : (v) => c.commit((draft, _) => draft.clockFormat = v!),
          ),
        const AppDivider(),
        SwitchListTile(
          key: const ValueKey('clock-blink'),
          title: const Text('Blink clock colon'),
          subtitle: Text(
            c.state.clockBlink ? 'Blinking · once per second' : 'Steady',
          ),
          value: c.state.clockBlink,
          onChanged: c.busy
              ? null
              : (v) => c.commit((draft, _) => draft.clockBlink = v),
        ),
        const Text(
          'Blinking applies to the simulator and paired screens. The LED sign and its preview keep a steady colon.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Shared across services and stage screens. Uses this phone’s current time and timezone. Countdown timers stay in minutes and seconds.',
        ),
      ],
    ),
  );

  Future<void> sendStageMessage() async {
    final revision = c.state.session.revision;
    final layout = await compose(
      c.state.session.alert ?? const TextLayout('Thank you'),
      'Stage message',
      'Continue',
    );
    if (layout == null || !mounted) return;
    var duration = 0;
    final send = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            c.state.session.phase == 'ended'
                ? 'Send after service ended?'
                : 'Send stage message?',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(layout.text),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show for'),
                subtitle: Text(
                  duration == 0 ? 'Until cleared' : formatTime(duration * 1000),
                ),
                trailing: const Icon(Icons.expand_more),
                onTap: () async {
                  final v = await showWheelTimePicker(
                    ctx,
                    title: 'Message duration · 00:00 means Until cleared',
                    initial: duration,
                    allowZero: true,
                  );
                  if (v != null && ctx.mounted) update(() => duration = v);
                },
              ),
              if (duration != 0)
                TextButton(
                  onPressed: () => update(() => duration = 0),
                  child: const Text('Until cleared'),
                ),
              Text(
                c.state.session.phase == 'ended'
                    ? 'This replaces the end screen or clock. The completed report stays unchanged.'
                    : 'Timing continues while the message is displayed.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send message'),
            ),
          ],
        ),
      ),
    );
    if (send == true &&
        !await c.act(
          'message',
          value: StageOutputMessage(layout, seconds: duration),
          revision: revision,
        ) &&
        mounted)
      await showError(c.error ?? 'The message could not be sent.');
  }

  Future<String?> itemExportFormat({bool report = false}) => showDialog<String>(
    context: context,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (ctx) => SimpleDialog(
      title: Text(report ? 'Export report' : 'Export program'),
      contentPadding: EdgeInsets.symmetric(vertical: appLayout(ctx).gap),
      children: [
        if (report) ...[
          ListTile(
            onTap: () => Navigator.pop(ctx, 'pdf'),
            leading: const Icon(Icons.print_outlined),
            title: const Text('PDF · Print Service'),
          ),
          const AppDivider(),
        ],
        ListTile(
          onTap: () => Navigator.pop(ctx, 'json'),
          leading: const Icon(Icons.data_object),
          title: const Text('JSON'),
        ),
        const AppDivider(),
        ListTile(
          onTap: () => Navigator.pop(ctx, 'csv'),
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('CSV'),
        ),
      ],
    ),
  );

  Future<void> programItemAction(Timeline program, String action) async {
    if (c.busy || c.corrupt) return;
    if (action == 'export') {
      final format = await itemExportFormat();
      if (format != null) await export(program, format);
    }
    if (action == 'delete' &&
        await confirm(
          'Delete program?',
          'Delete “${program.name}”? A service already running from this program stays unchanged.',
          'Delete program',
        )) {
      if (!await c.commit((draft, _) => draft.deleteTemplate(program)) &&
          mounted)
        await showError(c.error ?? 'Could not delete program.');
    }
  }

  Future<void> reportItemAction(ServiceReport report, String action) async {
    if (c.busy || c.corrupt) return;
    if (action == 'delete') {
      await confirmClearReports(record: report);
      return;
    }
    final format = await itemExportFormat(report: true);
    if (format == 'pdf') {
      await printServiceSheet(report.program, report: report);
    } else if (format != null) {
      await exportReport(report, format);
    }
  }

  Future<void> showItemActions(
    String kind,
    Future<void> Function(String) action,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final point = overlay.globalToLocal(
      menuAnchor ?? Offset(overlay.size.width / 2, overlay.size.height / 2),
    );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(point.dx, point.dy, 1, 1),
        overlay.size,
      ),
      semanticLabel: '$kind actions',
      items: appMenuEntries(context, [
        AppMenuAction('export', 'Export ${kind.toLowerCase()}'),
        AppMenuAction(
          'delete',
          'Delete ${kind.toLowerCase()}',
          destructive: true,
        ),
      ]),
    );
    if (choice != null) await action(choice);
  }

  Widget itemMenu(String kind, void Function(String) action) =>
      PopupMenuButton<String>(
        tooltip: '$kind actions',
        enabled: !c.busy && !c.corrupt,
        onSelected: action,
        itemBuilder: (ctx) => appMenuEntries(ctx, [
          AppMenuAction('export', 'Export ${kind.toLowerCase()}'),
          AppMenuAction(
            'delete',
            'Delete ${kind.toLowerCase()}',
            destructive: true,
          ),
        ]),
      );

  Future<void> exportAllPrograms({List<Timeline>? selected}) async {
    final programs = List<Timeline>.of(selected ?? c.state.templates);
    if (programs.isEmpty) return;
    var notes = false;
    final format = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            selected == null
                ? 'Export all programs'
                : 'Export selected programs',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${programs.length} ${selected == null ? 'saved' : 'selected'} programs. JSON preserves formatting; CSV contains the rundown for spreadsheets.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include private operator notes'),
                value: notes,
                onChanged: (v) => update(() => notes = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            for (final f in ['json', 'csv'])
              FilledButton(
                onPressed: () => Navigator.pop(ctx, f),
                child: Text(f.toUpperCase()),
              ),
          ],
        ),
      ),
    );
    if (format == null) return;
    try {
      await c.port.exportFile(
        'Church-Service-Timer-${selected == null ? 'all' : 'selected'}-programs.$format',
        format == 'json'
            ? exportProgramsJson(programs, privateNotes: notes)
            : exportProgramsCsv(programs, privateNotes: notes),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
  }

  Future<void> importProgramBundle(List<Timeline> candidates) async {
    final names = c.state.templates.map((p) => p.name.toLowerCase()).toSet();
    final incoming = <Timeline>[];
    for (final candidate in candidates) {
      var name = candidate.name, index = 2;
      while (names.contains(name.toLowerCase())) {
        name =
            '${candidate.name.substring(0, math.min(65, candidate.name.length))} ($index)';
        index++;
      }
      names.add(name.toLowerCase());
      incoming.add(candidate.renamed(name));
      await NativeDisplayFonts.prepareState(
        AppState(
          [candidate],
          c.state.defaults,
          Session(id: 'import-preview', anchor: c.now),
        ),
      );
      validateTimelinePixels(candidate);
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Preview program import'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All programs are added together. Existing programs stay unchanged; duplicate names receive a numbered suffix.',
                ),
                SizedBox(height: appLayout(ctx).gap),
                AppMenuList(
                  children: [
                    for (final p in incoming)
                      ListTile(
                        title: Text(p.name),
                        subtitle: Text(templateSummary(p)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Import ${incoming.length} programs'),
          ),
        ],
      ),
    );
    if (accepted == true &&
        !await c.commit((draft, _) {
          for (final p in incoming) {
            draft.saveTemplate(p);
          }
        }) &&
        mounted)
      await showError(c.error ?? 'Nothing was imported.');
  }
}

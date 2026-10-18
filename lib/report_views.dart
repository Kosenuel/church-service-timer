part of 'main.dart';

String reportDate(int wall) {
  final d = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year} · ${clockLabel(wall)}';
}

String reportMode(ServiceReport r) =>
    r.rehearsal ? 'Rehearsal ${r.rate}×' : 'Live';

Widget reportSurface(BuildContext context, {required Widget child}) => Material(
  color: appColors(context).surface,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: BorderSide(color: appColors(context).border),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

Widget reportMetric(
  BuildContext context,
  String label,
  String value, {
  Color? color,
}) => SizedBox(
  width: 160,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: appColors(context).muted, fontSize: 12),
      ),
      const SizedBox(height: 6),
      Text(
        value,
        style: TextStyle(
          color: color ?? appColors(context).accent,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
);

extension ReportViews on _HomeState {
  Future<void> exportAllReports() async {
    final records = List<ServiceReport>.unmodifiable(c.state.reports);
    if (records.isEmpty) return;
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export all records'),
        content: Text(
          'Export all ${records.length} saved services, including live services and rehearsals. Includes every segment, duration, pause and time adjustment, regardless of the current filter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, 'json'),
            child: const Text('JSON'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'csv'),
            child: const Text('CSV'),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    try {
      await c.port.exportFile(
        'Church-Service-Timer-all-reports-${c.now.wall}.$format',
        format == 'csv'
            ? exportReportsCsv(records)
            : exportReportsJson(records),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
  }

  Future<void> openReport(ServiceReport r) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReportDetailPage(
          report: r,
          onExport: (format) => exportReport(r, format),
          onDelete: () => confirmClearReports(record: r),
        ),
      ),
    );
  }

  Widget reports() {
    final history =
        c.state.reports
            .where(
              (r) =>
                  reportFilter == 'all' ||
                  (reportFilter == 'rehearsal' ? r.rehearsal : !r.rehearsal),
            )
            .toList()
          ..sort((a, b) => b.endedWall.compareTo(a.endedWall));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            ChurchProfileBanner(image: c.state.churchBanner),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x22000000), Color(0xcc000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reports',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (c.state.churchName.isNotEmpty)
                    Text(
                      c.state.churchName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Your service history. Tap a record for its full timing breakdown.',
          style: TextStyle(color: appColors(context).muted),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('export-all-reports'),
              onPressed: c.state.reports.isEmpty || c.busy
                  ? null
                  : exportAllReports,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Export all records'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('clear-all-reports'),
              onPressed: c.state.reports.isEmpty || c.busy
                  ? null
                  : () => confirmClearReports(),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear all reports'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in {
              'all': 'All services',
              'live': 'Live only',
              'rehearsal': 'Rehearsals',
            }.entries)
              ChoiceChip(
                label: Text(option.value),
                selected: reportFilter == option.key,
                onSelected: (_) => selectReportFilter(option.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Text(
              '${history.length} ${history.length == 1 ? 'record' : 'records'}',
              style: TextStyle(color: appColors(context).muted),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'list',
                  icon: Icon(Icons.view_list_outlined),
                  label: Text('List'),
                ),
                ButtonSegment(
                  value: 'graph',
                  icon: Icon(Icons.bar_chart),
                  label: Text('Graph'),
                ),
              ],
              selected: {reportView},
              onSelectionChanged: (v) => selectReportView(v.single),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (history.isEmpty)
          panel(
            child: Text(
              c.state.reports.isEmpty
                  ? 'No completed services yet. End a live service or fast rehearsal to create a report.'
                  : 'No records match this filter.',
            ),
          )
        else if (reportView == 'graph')
          reportGraphs(history)
        else
          reportSurface(
            context,
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ReportListRow(
                    report: history[i],
                    onTap: () => openReport(history[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget reportGraphs(List<ServiceReport> records) {
    final summary = ReportSummary(records);
    final chronological = [...records]
      ..sort((a, b) => a.endedWall.compareTo(b.endedWall));
    final comparable = summary.comparable.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Timing at a glance'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 20,
                runSpacing: 18,
                children: [
                  reportMetric(context, 'SERVICES', '${records.length}'),
                  reportMetric(
                    context,
                    'RECORDED TIME',
                    summary.timedCount == 0
                        ? '—'
                        : durationLabel(summary.recordedMs),
                  ),
                  reportMetric(
                    context,
                    'AVERAGE VARIANCE',
                    summary.averageVarianceMs == null
                        ? '—'
                        : varianceLabel(summary.averageVarianceMs!),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '$comparable complete, reliable ${comparable == 1 ? 'record' : 'records'} used for variance and outcomes. ${records.length - comparable} partial or uncertain.',
                style: TextStyle(color: appColors(context).muted, fontSize: 12),
              ),
              if (records.any((r) => r.rehearsal)) ...[
                const SizedBox(height: 8),
                Text(
                  records.any((r) => !r.rehearsal)
                      ? 'This view combines live and simulated rehearsal durations. Use the filters to compare each separately.'
                      : 'Rehearsal durations use simulated service time, not real clock time.',
                  style: TextStyle(
                    color: appColors(context).warning,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Service outcomes'),
              const SizedBox(height: 16),
              if (comparable > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        if (summary.ahead > 0)
                          Expanded(
                            flex: summary.ahead,
                            child: Container(color: appColors(context).info),
                          ),
                        if (summary.onTime > 0)
                          Expanded(
                            flex: summary.onTime,
                            child: Container(color: appColors(context).accent),
                          ),
                        if (summary.behind > 0)
                          Expanded(
                            flex: summary.behind,
                            child: Container(color: appColors(context).warning),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  Text(
                    'Ahead · ${summary.ahead}',
                    style: TextStyle(color: appColors(context).info),
                  ),
                  Text(
                    'On time · ${summary.onTime}',
                    style: TextStyle(color: appColors(context).accent),
                  ),
                  Text(
                    'Behind · ${summary.behind}',
                    style: TextStyle(color: appColors(context).warning),
                  ),
                ],
              ),
              if (comparable == 0)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Complete a service with recorded timing to see its outcome.',
                    style: TextStyle(color: appColors(context).muted),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label('Planned vs actual · oldest first'),
              const SizedBox(height: 8),
              Text(
                'All filtered records on one scale. Tap a service for its segment breakdown.',
                style: TextStyle(color: appColors(context).muted),
              ),
              const SizedBox(height: 16),
              DurationChart(
                entries: chronological
                    .map(
                      (r) => DurationEntry(
                        title: r.name,
                        subtitle:
                            '${reportDate(r.endedWall)} · ${reportMode(r)}',
                        planned: r.plannedMs,
                        actual: r.totalMs,
                        uncertain: !r.comparable,
                        onTap: () => openReport(r),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReportListRow extends StatelessWidget {
  final ServiceReport report;
  final VoidCallback onTap;
  const ReportListRow({super.key, required this.report, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final r = report, colors = appColors(context);
    final variance = r.comparable ? r.totalMs! - r.plannedMs : null;
    final outcomeColor = variance == null || variance >= 1000
        ? colors.warning
        : variance <= -1000
        ? colors.info
        : colors.accent;
    return InkWell(
      key: ValueKey('open-report-${r.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 8,
                    runSpacing: 3,
                    children: [
                      Text(
                        reportDate(r.startedWall ?? r.endedWall),
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                      Text(
                        r.totalMs == null
                            ? 'Duration not recorded'
                            : '${durationLabel(r.totalMs!)}${r.rehearsal ? ' simulated' : ''}',
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        variance == null
                            ? 'Partial or uncertain record'
                            : varianceLabel(variance),
                        style: TextStyle(color: outcomeColor, fontSize: 12),
                      ),
                      if (r.rehearsal)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.track,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            reportMode(r),
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.chevron_right, color: colors.muted, size: 22),
          ],
        ),
      ),
    );
  }
}

class DurationEntry {
  final String title, subtitle;
  final int planned;
  final int? actual;
  final bool uncertain;
  final VoidCallback? onTap;
  const DurationEntry({
    required this.title,
    required this.subtitle,
    required this.planned,
    required this.actual,
    this.uncertain = false,
    this.onTap,
  });
}

/// Paired bars share a zero baseline and scale; missing timing is never a zero.
class DurationChart extends StatelessWidget {
  final List<DurationEntry> entries;
  const DurationChart({super.key, required this.entries});
  @override
  Widget build(BuildContext context) {
    final maxMs = entries.fold<int>(
      0,
      (m, e) => math.max(m, math.max(e.planned, e.actual ?? 0)),
    );
    final scale = math.max(60000, (maxMs / 60000).ceil() * 60000);
    Widget bar(String label, int? value, Color color) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              label,
              style: TextStyle(color: appColors(context).muted, fontSize: 11),
            ),
          ),
          Expanded(
            child: Semantics(
              label:
                  '$label: ${value == null ? 'not recorded' : durationLabel(value)}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (value ?? 0) / scale,
                  minHeight: 11,
                  color: color,
                  backgroundColor: appColors(context).track,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 88,
            child: Text(
              value == null ? 'Not recorded' : durationLabel(value),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: value == null ? appColors(context).muted : color,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Bar scale  0 — ${durationLabel(scale)}',
          style: TextStyle(color: appColors(context).muted, fontSize: 11),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < entries.length; i++)
          InkWell(
            onTap: entries[i].onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ${entries[i].title}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    entries[i].subtitle,
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  bar('Plan', entries[i].planned, appColors(context).muted),
                  bar(
                    'Actual',
                    entries[i].actual,
                    entries[i].uncertain
                        ? appColors(context).warning
                        : appColors(context).accent,
                  ),
                  if (entries[i].uncertain)
                    Text(
                      'Partial or uncertain timing',
                      style: TextStyle(
                        color: appColors(context).warning,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ReportDetailPage extends StatefulWidget {
  final ServiceReport report;
  final Future<void> Function(String) onExport;
  final Future<bool> Function() onDelete;
  const ReportDetailPage({
    super.key,
    required this.report,
    required this.onExport,
    required this.onDelete,
  });
  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget block(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: reportSurface(
      context,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Scaffold(
      appBar: AppBar(title: const Text('Service report')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    block(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (r.churchName.isNotEmpty) ...[
                            Text(
                              r.churchName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Chip(
                            avatar: Icon(
                              r.rehearsal
                                  ? Icons.fast_forward
                                  : Icons.check_circle_outline,
                              size: 18,
                            ),
                            label: Text(reportMode(r)),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            r.name,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            reportDate(r.startedWall ?? r.endedWall),
                            style: TextStyle(color: appColors(context).muted),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 24,
                            runSpacing: 18,
                            children: [
                              reportMetric(
                                context,
                                'PLANNED',
                                durationLabel(r.plannedMs),
                              ),
                              reportMetric(
                                context,
                                'ACTUAL',
                                r.totalMs == null
                                    ? 'Not recorded'
                                    : durationLabel(r.totalMs!),
                              ),
                              reportMetric(
                                context,
                                'VARIANCE',
                                r.totalMs == null
                                    ? '—'
                                    : varianceLabel(r.totalMs! - r.plannedMs),
                                color: r.comparable
                                    ? appColors(context).accent
                                    : appColors(context).warning,
                              ),
                              reportMetric(
                                context,
                                'PAUSED',
                                durationLabel(r.pausedMs),
                              ),
                              reportMetric(
                                context,
                                'TIME ADJUSTMENTS',
                                '${r.adjustmentMs > 0
                                    ? '+'
                                    : r.adjustmentMs < 0
                                    ? '−'
                                    : ''}${durationLabel(r.adjustmentMs)}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Started: ${r.startedWall == null ? 'not recorded' : reportDate(r.startedWall!)}\nEnded: ${reportDate(r.endedWall)}',
                            style: TextStyle(
                              color: appColors(context).muted,
                              fontSize: 12,
                            ),
                          ),
                          if (!r.comparable)
                            Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Partial or uncertain timing. The service may have ended before all segments ran, or timing could not be recovered. Review the breakdown before comparing this record.',
                                style: TextStyle(
                                  color: appColors(context).warning,
                                ),
                              ),
                            ),
                          if (r.rehearsal)
                            Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Rehearsal durations are simulated time. Dates show real local clock time.',
                                style: TextStyle(
                                  color: appColors(context).muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () => run(() => widget.onExport('csv')),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Export report CSV'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => run(() => widget.onExport('json')),
                          icon: const Icon(Icons.code),
                          label: const Text('Export report JSON'),
                        ),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                  if (await widget.onDelete() &&
                                      context.mounted)
                                    Navigator.pop(context);
                                }),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear report'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    block(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'The service, segment by segment',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          DurationChart(
                            entries: r.rows
                                .map(
                                  (row) => DurationEntry(
                                    title: row.name,
                                    subtitle: row.actualMs == null
                                        ? 'Not recorded'
                                        : varianceLabel(
                                            row.actualMs! - row.plannedMs,
                                          ),
                                    planned: row.plannedMs,
                                    actual: row.actualMs,
                                    uncertain:
                                        r.uncertain || row.actualMs == null,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    block(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Activity timeline',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Latest ${r.events.length} events · controller acceptance is not visual confirmation.',
                            style: TextStyle(color: appColors(context).muted),
                          ),
                          if (r.events.isEmpty)
                            const Text(
                              'No activity events were recorded for this service.',
                            ),
                          ...r.events.map(
                            (event) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                event.kind == 'failed' || event.kind == 'hold'
                                    ? Icons.warning_amber
                                    : event.kind == 'accepted'
                                    ? Icons.check_circle_outline
                                    : Icons.history,
                              ),
                              title: Text(event.message),
                              subtitle: Text(
                                '${clockLabel(event.wall)}:${DateTime.fromMillisecondsSinceEpoch(event.wall).second.toString().padLeft(2, '0')}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...r.rows.asMap().entries.map(
                      (e) => block(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(e.key + 1).toString().padLeft(2, '0')}  ${e.value.name}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Plan ${durationLabel(e.value.plannedMs)} · Actual ${e.value.actualMs == null ? 'not recorded' : durationLabel(e.value.actualMs!)}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Paused ${durationLabel(e.value.pausedMs)} · Adjusted ${e.value.adjustmentMs > 0
                                  ? '+'
                                  : e.value.adjustmentMs < 0
                                  ? '−'
                                  : ''}${durationLabel(e.value.adjustmentMs)}',
                              style: TextStyle(color: appColors(context).muted),
                            ),
                            if (e.value.actualMs == null)
                              Text(
                                'This segment has no recorded duration.',
                                style: TextStyle(
                                  color: appColors(context).warning,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

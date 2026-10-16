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

Widget reportSurface({required Widget child}) => Material(
  color: const Color(0xff131d1a),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(18),
    side: const BorderSide(color: Color(0xff2a3932)),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);

Widget reportMetric(String label, String value, {Color color = accent}) =>
    SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
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
        'Cuekeeper-all-reports-${c.now.wall}.$format',
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
        const Text(
          'After the service.',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your service history, from the whole picture to each segment. Tap a record to explore its timing.',
          style: TextStyle(color: muted),
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
        Row(
          children: [
            Expanded(
              child: Text(
                '${history.length} ${history.length == 1 ? 'record' : 'records'}',
                style: const TextStyle(color: muted),
              ),
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
          ...history.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: reportSurface(
                child: InkWell(
                  key: ValueKey('open-report-${r.id}'),
                  onTap: () => openReport(r),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                    child: Row(
                      children: [
                        const Icon(Icons.event_note_outlined, color: accent),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${reportMode(r)} · ${reportDate(r.startedWall ?? r.endedWall)}',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                r.totalMs == null
                                    ? 'Duration not recorded'
                                    : 'Held for ${durationLabel(r.totalMs!)}${r.rehearsal ? ' · simulated' : ''}',
                              ),
                              if (r.comparable)
                                Text(
                                  varianceLabel(r.totalMs! - r.plannedMs),
                                  style: const TextStyle(
                                    color: accent,
                                    fontSize: 12,
                                  ),
                                )
                              else
                                const Text(
                                  'Partial or uncertain record',
                                  style: TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: ValueKey('clear-report-${r.id}'),
                          tooltip: 'Clear report',
                          onPressed: c.busy
                              ? null
                              : () => confirmClearReports(record: r),
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                        const Icon(Icons.chevron_right, color: muted),
                      ],
                    ),
                  ),
                ),
              ),
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
                  reportMetric('SERVICES', '${records.length}'),
                  reportMetric(
                    'RECORDED TIME',
                    summary.timedCount == 0
                        ? '—'
                        : durationLabel(summary.recordedMs),
                  ),
                  reportMetric(
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
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (records.any((r) => r.rehearsal)) ...[
                const SizedBox(height: 8),
                Text(
                  records.any((r) => !r.rehearsal)
                      ? 'This view combines live and simulated rehearsal durations. Use the filters to compare each separately.'
                      : 'Rehearsal durations use simulated service time, not real clock time.',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
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
                            child: Container(color: const Color(0xff7bcfe8)),
                          ),
                        if (summary.onTime > 0)
                          Expanded(
                            flex: summary.onTime,
                            child: Container(color: accent),
                          ),
                        if (summary.behind > 0)
                          Expanded(
                            flex: summary.behind,
                            child: Container(color: Colors.orangeAccent),
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
                    style: const TextStyle(color: Color(0xff7bcfe8)),
                  ),
                  Text(
                    'On time · ${summary.onTime}',
                    style: const TextStyle(color: accent),
                  ),
                  Text(
                    'Behind · ${summary.behind}',
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ],
              ),
              if (comparable == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Complete a service with recorded timing to see its outcome.',
                    style: TextStyle(color: muted),
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
              const Text(
                'All filtered records on one scale. Tap a service for its segment breakdown.',
                style: TextStyle(color: muted),
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
              style: const TextStyle(color: muted, fontSize: 11),
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
                  backgroundColor: const Color(0xff23312a),
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
                color: value == null ? muted : color,
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
          style: const TextStyle(color: muted, fontSize: 11),
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
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  bar('Plan', entries[i].planned, muted),
                  bar(
                    'Actual',
                    entries[i].actual,
                    entries[i].uncertain ? Colors.orangeAccent : accent,
                  ),
                  if (entries[i].uncertain)
                    const Text(
                      'Partial or uncertain timing',
                      style: TextStyle(
                        color: Colors.orangeAccent,
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
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 24,
                            runSpacing: 18,
                            children: [
                              reportMetric(
                                'PLANNED',
                                durationLabel(r.plannedMs),
                              ),
                              reportMetric(
                                'ACTUAL',
                                r.totalMs == null
                                    ? 'Not recorded'
                                    : durationLabel(r.totalMs!),
                              ),
                              reportMetric(
                                'VARIANCE',
                                r.totalMs == null
                                    ? '—'
                                    : varianceLabel(r.totalMs! - r.plannedMs),
                                color: r.comparable
                                    ? accent
                                    : Colors.orangeAccent,
                              ),
                              reportMetric('PAUSED', durationLabel(r.pausedMs)),
                              reportMetric(
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
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          if (!r.comparable)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Partial or uncertain timing. The service may have ended before all segments ran, or timing could not be recovered. Review the breakdown before comparing this record.',
                                style: TextStyle(color: Colors.orangeAccent),
                              ),
                            ),
                          if (r.rehearsal)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                'Rehearsal durations are simulated time. Dates show real local clock time.',
                                style: TextStyle(color: muted),
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
                              style: const TextStyle(color: muted),
                            ),
                            if (e.value.actualMs == null)
                              const Text(
                                'This segment has no recorded duration.',
                                style: TextStyle(color: Colors.orangeAccent),
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

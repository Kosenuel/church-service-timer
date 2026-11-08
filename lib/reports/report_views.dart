import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/list_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/church_banner.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/reports/service_pdf.dart';

export 'package:church_service_timer/reports/report_list_row.dart';
export 'package:church_service_timer/reports/report_charts.dart';
export 'package:church_service_timer/reports/report_detail_page.dart';

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
          color: color ?? appColors(context).text,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  ),
);

extension ReportViews on HomeState {
  /// Exports reports to a file, or with [share] sends them through the
  /// Android share sheet, where a PDF per report is also offered.
  Future<void> exportAllReports({
    List<ServiceReport>? selected,
    bool share = false,
  }) async {
    final records = List<ServiceReport>.unmodifiable(
      selected ?? c.state.reports,
    );
    if (records.isEmpty) return;
    final withNotes = records.where((r) => r.review != null).length;
    final picked = await showFormatSheet(
      title:
          '${share ? 'Share' : 'Export'} ${selected == null ? 'all ' : ''}${plural(records.length, 'report')}',
      subtitle: selected == null
          ? 'Every saved service, including rehearsals, whatever the filter. Includes every segment, pause and time adjustment.'
          : records.map((r) => r.name).toSet().join(', '),
      formats: [
        for (final f in reportFormats)
          if (share || f.id != 'pdf') f,
      ],
      keyPrefix: '${share ? 'share' : 'export'}-reports',
      share: share,
      extraTitle: withNotes == 0 ? null : 'Include review notes',
      extraHint: withNotes == 0
          ? null
          : '${withNotes == records.length ? (withNotes == 1 ? 'This report has' : 'All have') : '$withNotes of ${records.length} have'} review notes. Timings are included either way.',
      extraKey: 'include-review',
    );
    if (picked == null || !mounted) return;
    final (format, includeReview) = picked;
    final name =
        'Church-Service-Timer-${selected == null ? 'all' : 'selected'}-reports-${c.now.wall}.$format';
    String content() => format == 'csv'
        ? exportReportsCsv(records, includeReview: includeReview)
        : exportReportsJson(records, includeReview: includeReview);
    try {
      if (!share) {
        await c.port.exportFile(name, content());
        return;
      }
      final files = format == 'pdf'
          ? [
              for (final r in records)
                await reportPdf(r, includeReview: includeReview),
            ]
          : [
              SharedFile.text(
                name,
                content(),
                format == 'json' ? 'application/json' : 'text/csv',
              ),
            ];
      await c.port.shareFiles(
        files,
        subject: records.length == 1
            ? records.single.name
            : '${records.length} service reports',
      );
    } catch (e) {
      if (mounted)
        await showError('${share ? 'Sharing' : 'Export'} failed: $e');
    }
  }

  Future<SharedFile> reportPdf(
    ServiceReport r, {
    required bool includeReview,
  }) async {
    final document = ServicePrintDocument(
      program:
          r.program ??
          Timeline(
            r.name,
            r.rows
                .map(
                  (row) =>
                      Segment(row.name, (row.plannedMs ~/ 60000).clamp(1, 99)),
                )
                .toList(),
            DisplaySettings(),
          ),
      report: r,
      church: r.churchName,
      serviceDate: r.startedWall ?? r.endedWall,
      preparedAt: c.now.wall,
      banner: c.state.churchBanner,
      audience: 'operator',
      fullReport: true,
      includeReview: includeReview && r.review != null,
      watermark: c.state.printPreferences.watermark,
      inkSaving: c.state.printPreferences.inkSaving,
    );
    return SharedFile(
      servicePdfName(document),
      await servicePdfBytes(document),
      'application/pdf',
    );
  }

  Future<void> openReport(ServiceReport r) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReportDetailPage(
          report: r,
          controller: c,
          onExport: (format) => exportReport(r, format),
          onPrint: () => printServiceSheet(r.program, report: r),
          onDelete: () => confirmClearReports(record: r),
          onEditReview: () => editReviewNote(r),
        ),
      ),
    );
  }

  Future<void> pickReportDates() async {
    final dates =
        c.state.reports
            .map(
              (r) => DateTime.fromMillisecondsSinceEpoch(
                r.startedWall ?? r.endedWall,
              ),
            )
            .toList()
          ..sort();
    final now = DateTime.fromMillisecondsSinceEpoch(c.now.wall);
    final first = dates.isEmpty
        ? DateTime(2020)
        : DateTime(dates.first.year, 1, 1);
    final last = dates.isNotEmpty && dates.last.isAfter(now) ? dates.last : now;
    final result = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(last.year + 1, 12, 31),
      initialDateRange: reportsPage.dates,
      helpText: 'Filter service dates',
    );
    if (result != null && mounted)
      refreshHome(() {
        reportsPage.dates = result;
        reportsPage.open = null;
      });
  }

  /// Three quick facts about the most recent comparable live services.
  Widget reportSummary() {
    final colors = appColors(context);
    final recent =
        c.state.reports.where((r) => r.comparable && !r.rehearsal).toList()
          ..sort((a, b) => b.endedWall.compareTo(a.endedWall));
    final last = recent.take(4).toList();
    if (last.isEmpty) return const SizedBox.shrink();
    final variances = [for (final r in last) r.totalMs! - r.plannedMs];
    final avg = variances.reduce((a, b) => a + b) ~/ variances.length;
    final onTime = variances.where((v) => v.abs() < 60000).length;
    final over = <String, int>{};
    for (final r in last) {
      for (final row in r.rows) {
        if (row.skipped || row.actualMs == null) continue;
        over[row.name] = (over[row.name] ?? 0) + row.actualMs! - row.plannedMs;
      }
    }
    final worst = over.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String minutes(int ms) {
      final m = (ms.abs() / 60000).round();
      return m == 0 ? 'on time' : '${ms > 0 ? '+' : '−'}${m}m avg';
    }

    Widget tile(String label, String value, Color tone) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.muted),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      key: const ValueKey('report-summary'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          tile(
            'Last ${plural(last.length, 'service')}',
            minutes(avg),
            avg.abs() < 60000
                ? colors.accent
                : avg > 0
                ? colors.warning
                : colors.info,
          ),
          const SizedBox(width: 8),
          tile('On time', '$onTime of ${last.length}', colors.text),
          const SizedBox(width: 8),
          tile(
            'Longest over',
            worst.isEmpty ? 'None' : worst.first.key,
            worst.isEmpty ? colors.accent : colors.warning,
          ),
        ],
      ),
    );
  }

  Widget reports() {
    final history = c.state.reports.where((r) => reportMatches(r)).toList()
      ..sort((a, b) => b.endedWall.compareTo(a.endedWall));
    final colors = appColors(context);
    final total = c.state.reports.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reportsPage.selecting)
          selectionHeader(
            programs: false,
            shown: history.map((r) => r.id).toSet(),
          )
        else
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: c.state.churchBanner.isEmpty
                      ? ColoredBox(
                          color: colors.accent.withValues(alpha: .14),
                          child: Icon(Icons.insights, color: colors.accent),
                        )
                      : FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: 160,
                            height: 160,
                            child: ChurchProfileBanner(
                              image: c.state.churchBanner,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reports',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        if (c.state.churchName.isNotEmpty) c.state.churchName,
                        plural(total, 'service'),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (!reportsPage.selecting)
                IconButton(
                  key: const ValueKey('select-reports'),
                  tooltip: 'Select',
                  onPressed: total == 0
                      ? null
                      : () => refreshHome(() {
                          reportsPage.selecting = true;
                          reportsPage.view = 'list';
                          reportsPage.selected.clear();
                        }),
                  icon: const Icon(Icons.checklist),
                ),
              PopupMenuButton<String>(
                tooltip: 'Report list options',
                onSelected: (action) {
                  switch (action) {
                    case 'insights':
                      openSettingsDetail('Timing insights', timingInsightsPage);
                    case 'export':
                      exportAllReports();
                    case 'clear':
                      confirmClearReports();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem<String>(
                    value: 'insights',
                    height: appLayout(ctx).controlHeight,
                    child: const Text('Timing insights'),
                  ),
                  PopupMenuItem<String>(
                    value: 'export',
                    key: const ValueKey('export-all-reports'),
                    enabled: total > 0 && !c.busy,
                    height: appLayout(ctx).controlHeight,
                    child: const Text('Export all records'),
                  ),
                  PopupMenuItem<String>(
                    value: 'clear',
                    enabled: total > 0 && !c.busy,
                    key: const ValueKey('clear-all-reports'),
                    height: appLayout(ctx).controlHeight,
                    child: Text(
                      'Clear all reports',
                      style: TextStyle(color: appColors(ctx).error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 14),
        if (!reportsPage.selecting) reportSummary(),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('report-search'),
                initialValue: reportsPage.query,
                decoration: const InputDecoration(
                  hintText: 'Search reports',
                  labelText: 'Search reports',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => refreshHome(() {
                  reportsPage.query = v;
                  reportsPage.open = null;
                }),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey('report-date-filter'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54)),
              onPressed: pickReportDates,
              icon: const Icon(Icons.date_range, size: 20),
              label: Text(
                reportsPage.dates == null
                    ? 'Dates'
                    : '${reportsPage.dates!.start.day}/${reportsPage.dates!.start.month} – ${reportsPage.dates!.end.day}/${reportsPage.dates!.end.month}',
              ),
            ),
            if (reportsPage.dates != null)
              IconButton(
                tooltip: 'Clear date filter',
                onPressed: () => refreshHome(() => reportsPage.dates = null),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final option in {
                      'all': 'All',
                      'live': 'Live only',
                      'rehearsal': 'Rehearsals',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(option.value),
                          selected: reportsPage.filter == option.key,
                          onSelected: (_) => selectReportFilter(option.key),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Text(
              plural(history.length, 'record'),
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!reportsPage.selecting)
          Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                for (final view in const ['list', 'graph'])
                  Expanded(
                    child: InkWell(
                      onTap: () => selectReportView(view),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 3,
                              color: reportsPage.view == view
                                  ? colors.accent
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Semantics(
                          selected: reportsPage.view == view,
                          button: true,
                          child: Text(
                            view == 'list' ? 'List' : 'Graph',
                            style: TextStyle(
                              fontWeight: reportsPage.view == view
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: reportsPage.view == view
                                  ? colors.text
                                  : colors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        if (!reportsPage.selecting &&
            reportsPage.view == 'list' &&
            history.isNotEmpty)
          listHint(
            'reports-select',
            'Tap a report to open it · press and hold to select',
          ),
        if (history.isEmpty)
          panel(
            child: Text(
              c.state.reports.isEmpty
                  ? 'No completed services yet. End a live service or fast rehearsal to create a report.'
                  : 'No records match this filter.',
            ),
          )
        else if (reportsPage.view == 'graph')
          reportGraphs(history)
        else
          reportSurface(
            context,
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0) const AppDivider(),
                  ReportListRow(
                    report: history[i],
                    checked: reportsPage.selecting
                        ? reportsPage.selected.contains(history[i].id)
                        : null,
                    onChecked: reportsPage.selecting
                        ? (_) => refreshHome(
                            () => toggleExportSelection(
                              reportsPage.selected,
                              history[i].id,
                            ),
                          )
                        : null,
                    selected:
                        useMasterDetail && reportsPage.open == history[i].id,
                    onTap: () {
                      if (reportsPage.selecting) {
                        refreshHome(
                          () => toggleExportSelection(
                            reportsPage.selected,
                            history[i].id,
                          ),
                        );
                        return;
                      }
                      if (useMasterDetail)
                        refreshHome(() => reportsPage.open = history[i].id);
                      else
                        openReport(history[i]);
                    },
                    // Long-press starts selection with this report ticked;
                    // the selection bar then exports or deletes.
                    onMenu: () => refreshHome(() {
                      if (!reportsPage.selecting) {
                        reportsPage.selecting = true;
                        reportsPage.view = 'list';
                        reportsPage.selected.clear();
                      }
                      reportsPage.selected.add(history[i].id);
                    }),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// Minutes over or under plan for the last few complete services. A tap
  /// on a bar shows that service in a card with Open report.
  Widget overUnderPanel(List<ServiceReport> chronological) {
    final colors = appColors(context);
    final recent = chronological.where((r) => r.comparable).toList();
    final last = recent.sublist(math.max(0, recent.length - 8));
    if (last.isEmpty) return const SizedBox.shrink();
    final picked =
        last.where((r) => r.id == reportsPage.graph).firstOrNull ?? last.last;
    final pickedVariance = picked.totalMs! - picked.plannedMs;
    final when = DateTime.fromMillisecondsSinceEpoch(
      picked.startedWall ?? picked.endedWall,
    );
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Over or under plan',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      'Last ${last.length}',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OverUnderChart(
                  reports: last,
                  selectedId: picked.id,
                  onSelect: (id) => refreshHome(() => reportsPage.graph = id),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        reportDate(
                          last.first.startedWall ?? last.first.endedWall,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        reportDate(
                          last.last.startedWall ?? last.last.endedWall,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(color: colors.muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (name, tone) in [
                      ('Over', colors.warning),
                      ('Under', colors.info),
                    ])
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: tone,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(name, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: colors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tap a bar to see that service',
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            key: const ValueKey('graph-report-card'),
            color: colors.accent.withValues(alpha: .1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.accent.withValues(alpha: .5)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${days[when.weekday - 1]} ${when.day} ${months[when.month - 1]}',
                          style: TextStyle(
                            color: colors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          picked.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${durationLabel(picked.totalMs!)} · ${pickedVariance.abs() < 1000 ? 'on time' : '${durationLabel(pickedVariance.abs())} ${pickedVariance > 0 ? 'over' : 'under'} plan'}',
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('graph-open-report'),
                    onPressed: () => openReport(picked),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Open report'),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
        overUnderPanel(chronological),
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
                    style: TextStyle(color: appColors(context).success),
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

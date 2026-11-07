import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/list_views.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/shared/church_banner.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/reports/service_pdf.dart';

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
      initialDateRange: reportDates,
      helpText: 'Filter service dates',
    );
    if (result != null && mounted)
      refreshHome(() {
        reportDates = result;
        selectedReport = null;
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
        if (selectingReports)
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
              if (!selectingReports)
                IconButton(
                  key: const ValueKey('select-reports'),
                  tooltip: 'Select',
                  onPressed: total == 0
                      ? null
                      : () => refreshHome(() {
                          selectingReports = true;
                          reportView = 'list';
                          selectedReportExports.clear();
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
        if (!selectingReports) reportSummary(),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('report-search'),
                initialValue: reportQuery,
                decoration: const InputDecoration(
                  hintText: 'Search reports',
                  labelText: 'Search reports',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => refreshHome(() {
                  reportQuery = v;
                  selectedReport = null;
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
                reportDates == null
                    ? 'Dates'
                    : '${reportDates!.start.day}/${reportDates!.start.month} – ${reportDates!.end.day}/${reportDates!.end.month}',
              ),
            ),
            if (reportDates != null)
              IconButton(
                tooltip: 'Clear date filter',
                onPressed: () => refreshHome(() => reportDates = null),
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
                          selected: reportFilter == option.key,
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
        if (!selectingReports)
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
                              color: reportView == view
                                  ? colors.accent
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Semantics(
                          selected: reportView == view,
                          button: true,
                          child: Text(
                            view == 'list' ? 'List' : 'Graph',
                            style: TextStyle(
                              fontWeight: reportView == view
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: reportView == view
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
        if (!selectingReports && reportView == 'list' && history.isNotEmpty)
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
        else if (reportView == 'graph')
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
                    checked: selectingReports
                        ? selectedReportExports.contains(history[i].id)
                        : null,
                    onChecked: selectingReports
                        ? (_) => refreshHome(
                            () => toggleExportSelection(
                              selectedReportExports,
                              history[i].id,
                            ),
                          )
                        : null,
                    selected:
                        useMasterDetail && selectedReport == history[i].id,
                    onTap: () {
                      if (selectingReports) {
                        refreshHome(
                          () => toggleExportSelection(
                            selectedReportExports,
                            history[i].id,
                          ),
                        );
                        return;
                      }
                      if (useMasterDetail)
                        refreshHome(() => selectedReport = history[i].id);
                      else
                        openReport(history[i]);
                    },
                    // Long-press starts selection with this report ticked;
                    // the selection bar then exports or deletes.
                    onMenu: () => refreshHome(() {
                      if (!selectingReports) {
                        selectingReports = true;
                        reportView = 'list';
                        selectedReportExports.clear();
                      }
                      selectedReportExports.add(history[i].id);
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
        last.where((r) => r.id == graphReport).firstOrNull ?? last.last;
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
                  onSelect: (id) => refreshHome(() => graphReport = id),
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

class ReportListRow extends StatelessWidget {
  final ServiceReport report;
  final VoidCallback onTap;
  const ReportListRow({
    super.key,
    required this.report,
    required this.onTap,
    this.onMenu,
    this.menu,
    this.selected = false,
    this.checked,
    this.onChecked,
  });
  final VoidCallback? onMenu;
  final Widget? menu;
  final bool selected;
  final bool? checked;
  final ValueChanged<bool?>? onChecked;
  @override
  Widget build(BuildContext context) {
    final r = report, colors = appColors(context);
    final variance = r.comparable ? r.totalMs! - r.plannedMs : null;
    final outcome = variance == null
        ? 'Partial'
        : variance.abs() < 1000
        ? 'On time'
        : '${variance > 0 ? '+' : ''}${durationLabel(variance.abs())} ${variance > 0 ? 'over' : 'under'}';
    // Over is warm, under is cool, on time is the accent; they also differ
    // in lightness so they read apart without colour.
    final tone = variance == null
        ? colors.muted
        : variance >= 1000
        ? colors.warning
        : variance <= -1000
        ? colors.info
        : colors.accent;
    final when = DateTime.fromMillisecondsSinceEpoch(
      r.startedWall ?? r.endedWall,
    );
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final started = r.startedWall == null
        ? null
        : '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final meta = [
      r.totalMs == null
          ? 'Not fully recorded'
          : '${durationLabel(r.totalMs!)}${r.rehearsal ? ' simulated' : ''}',
      if (started != null) 'started $started',
      if (r.rehearsal) reportMode(r),
    ].join(' · ');
    return InkWell(
      key: ValueKey('open-report-${r.id}'),
      onTap: onTap,
      onLongPress: onMenu,
      highlightColor: colors.accent.withValues(alpha: .1),
      child: Container(
        color: selected || checked == true
            ? colors.accent.withValues(alpha: .12)
            : null,
        constraints: const BoxConstraints(minHeight: 72),
        padding: appLayout(context).rowInsets,
        child: Row(
          children: [
            if (checked != null) Checkbox(value: checked, onChanged: onChecked),
            Semantics(
              label: reportDate(r.startedWall ?? r.endedWall),
              child: ExcludeSemantics(
                child: Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.track,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        days[when.weekday - 1],
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${when.day}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (r.review != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 14,
                            color: colors.muted,
                            semanticLabel: 'Has review notes',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              key: ValueKey('report-outcome-${r.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                outcome,
                style: TextStyle(
                  color: tone,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (menu != null && checked == null) menu!,
            if (checked == null && menu == null && !selected)
              Icon(Icons.chevron_right, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// Bars above the line are minutes over plan, below are minutes under, on
/// one scale. Each bar is a button; the chosen one is highlighted.
class OverUnderChart extends StatelessWidget {
  final List<ServiceReport> reports;
  final String selectedId;
  final ValueChanged<String> onSelect;
  const OverUnderChart({
    super.key,
    required this.reports,
    required this.selectedId,
    required this.onSelect,
  });
  static const height = 200.0;
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final variances = [for (final r in reports) r.totalMs! - r.plannedMs];
    final most = variances.fold<int>(60000, (m, v) => math.max(m, v.abs()));
    const half = height / 2 - 8;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(child: Container(height: 1, color: colors.border)),
          ),
          Row(
            children: [
              for (var i = 0; i < reports.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 64),
                        child: Semantics(
                          button: true,
                          selected: reports[i].id == selectedId,
                          label:
                              '${reports[i].name}, ${reportDate(reports[i].startedWall ?? reports[i].endedWall)}, ${variances[i].abs() < 1000 ? 'on time' : '${durationLabel(variances[i].abs())} ${variances[i] > 0 ? 'over' : 'under'}'}',
                          child: Material(
                            color: reports[i].id == selectedId
                                ? colors.accent.withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              key: ValueKey('graph-bar-${reports[i].id}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => onSelect(reports[i].id),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FractionallySizedBox(
                                        widthFactor: .7,
                                        child: Container(
                                          height: variances[i] >= 1000
                                              ? math.max(
                                                  3,
                                                  half * variances[i] / most,
                                                )
                                              : variances[i] > -1000
                                              ? 4
                                              : 0,
                                          decoration: BoxDecoration(
                                            color: variances[i] >= 1000
                                                ? colors.warning
                                                : colors.accent,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(6),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: FractionallySizedBox(
                                        widthFactor: .7,
                                        child: Container(
                                          height: variances[i] <= -1000
                                              ? math.max(
                                                  3,
                                                  half * -variances[i] / most,
                                                )
                                              : 0,
                                          decoration: BoxDecoration(
                                            color: colors.info,
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  bottom: Radius.circular(6),
                                                ),
                                          ),
                                        ),
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
                  ),
                ),
            ],
          ),
        ],
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}. ${entries[i].title}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (entries[i].onTap != null)
                        Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: appColors(context).muted,
                        ),
                    ],
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
  final Future<void> Function()? onPrint;
  final AppController? controller;
  final bool embedded;
  final ServiceReport report;
  final Future<void> Function(String) onExport;
  final Future<bool> Function() onDelete;

  /// Opens the review-note editor; null hides the Review notes section.
  final Future<void> Function()? onEditReview;
  const ReportDetailPage({
    super.key,
    required this.report,
    required this.onExport,
    required this.onDelete,
    this.onPrint,
    this.onEditReview,
    this.controller,
    this.embedded = false,
  });
  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  bool busy = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The saved copy, so a review note edit shows straight away.
  ServiceReport get current =>
      widget.controller?.state.reports
          .where((r) => r.id == widget.report.id)
          .firstOrNull ??
      widget.report;
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
    padding: EdgeInsets.only(bottom: appLayout(context).gap * 2),
    child: reportSurface(
      context,
      child: Padding(
        padding: EdgeInsets.all(appLayout(context).panelPadding),
        child: child,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final r = current, colors = appColors(context);
    final actions = PopupMenuButton<String>(
      key: const ValueKey('report-actions'),
      tooltip: 'Report actions',
      enabled: !busy,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => run(() async {
        if (value == 'delete') {
          if (await widget.onDelete() && context.mounted && !widget.embedded)
            Navigator.pop(context);
        } else {
          await widget.onExport(value);
        }
      }),
      itemBuilder: (context) => appMenuEntries(context, const [
        AppMenuAction('csv', 'Export report CSV'),
        AppMenuAction('json', 'Export report JSON'),
        AppMenuAction('delete', 'Clear report', destructive: true),
      ]),
    );
    final content = SingleChildScrollView(
      padding: EdgeInsets.all(widget.embedded ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onPrint != null || widget.embedded)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onPrint != null)
                  FilledButton.icon(
                    onPressed: busy ? null : () => run(widget.onPrint!),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print Service'),
                  ),
                if (widget.embedded) actions,
              ],
            ),
          const SizedBox(height: 12),
          block(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.churchName.isNotEmpty)
                  Text(
                    r.churchName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                Chip(
                  avatar: Icon(
                    r.rehearsal
                        ? Icons.fast_forward
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(reportMode(r)),
                ),
                const SizedBox(height: 8),
                Text(
                  r.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  reportDate(r.startedWall ?? r.endedWall),
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 20,
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
                      color: r.totalMs == null
                          ? colors.muted
                          : r.totalMs! - r.plannedMs > 999
                          ? colors.warning
                          : colors.success,
                    ),
                    reportMetric(
                      context,
                      'PAUSED',
                      durationLabel(r.pausedMs),
                      color: r.pausedMs == 0 ? colors.muted : null,
                    ),
                    reportMetric(
                      context,
                      'TIME ADJUSTMENTS',
                      color: r.adjustmentMs == 0 ? colors.muted : null,
                      '${r.adjustmentMs > 0
                          ? '+'
                          : r.adjustmentMs < 0
                          ? '−'
                          : ''}${durationLabel(r.adjustmentMs)}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Started: ${r.startedWall == null ? 'not recorded' : reportDate(r.startedWall!)}\nEnded: ${reportDate(r.endedWall)}',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                if (!r.comparable)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Partial or uncertain timing. Review the breakdown before comparing this record.',
                      style: TextStyle(color: colors.warning),
                    ),
                  ),
                if (r.rehearsal)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Rehearsal durations are simulated time. Dates show real local clock time.',
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.onEditReview != null) ...[
            const SizedBox(height: 20),
            ReviewNoteSection(
              review: r.review,
              busy: busy,
              onEdit: () => run(widget.onEditReview!),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Segment breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          AppMenuList(
            key: const ValueKey('report-segment-breakdown'),
            children: [
              for (var i = 0; i < r.rows.length; i++)
                ReportSegmentRow(
                  row: r.rows[i],
                  number: i + 1,
                  segment: r.program != null && i < r.program!.segments.length
                      ? r.program!.segments[i]
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 20),
          block(
            ExpansionTile(
              key: const ValueKey('report-duration-chart'),
              tilePadding: EdgeInsets.zero,
              title: const Text('The service, segment by segment'),
              subtitle: const Text('Expand chart'),
              children: [
                DurationChart(
                  entries: r.rows
                      .map(
                        (row) => DurationEntry(
                          title: row.name,
                          subtitle: row.skipped
                              ? 'Skipped'
                              : row.actualMs == null
                              ? 'Not recorded'
                              : varianceLabel(row.actualMs! - row.plannedMs),
                          planned: row.plannedMs,
                          actual: row.actualMs,
                          uncertain: r.uncertain || row.actualMs == null,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          block(
            ExpansionTile(
              key: const ValueKey('report-activity'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Activity timeline'),
              subtitle: Text('${r.events.length} recorded events'),
              children: [
                const Text('Controller acceptance is not visual confirmation.'),
                if (r.events.isEmpty)
                  const Text(
                    'No activity events were recorded for this service.',
                  ),
                AppMenuList(
                  children: [
                    for (final event in r.events)
                      ListTile(
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.embedded)
      return Material(color: colors.background, child: content);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service report'),
        actions: [actions, const SizedBox(width: 4)],
        bottom: widget.controller?.liveSession.active == true
            ? RunningServiceBar.forContext(
                context,
                controller: widget.controller!,
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: content,
          ),
        ),
      ),
    );
  }
}

class ReportSegmentRow extends StatelessWidget {
  final ReportRow row;
  final int number;
  final Segment? segment;
  const ReportSegmentRow({
    super.key,
    required this.row,
    required this.number,
    this.segment,
  });
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final actual = row.skipped
        ? 'Skipped'
        : row.actualMs == null
        ? 'Not recorded'
        : durationLabel(row.actualMs!);
    final variance = row.skipped || row.actualMs == null
        ? '—'
        : varianceLabel(row.actualMs! - row.plannedMs);
    return ExpansionTile(
      tilePadding: appLayout(context).tileInsets,
      childrenPadding: appLayout(context).rowInsets,
      title: LayoutBuilder(
        builder: (context, space) => space.maxWidth < 570
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${number.toString().padLeft(2, '0')}  ${row.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Planned ${durationLabel(row.plannedMs)} · Actual $actual',
                    style: TextStyle(fontSize: 13, color: colors.muted),
                  ),
                  Text(
                    variance,
                    style: TextStyle(
                      fontSize: 13,
                      color: row.actualMs == null
                          ? colors.muted
                          : row.actualMs! > row.plannedMs
                          ? colors.warning
                          : colors.success,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 125,
                    child: Text(
                      'Planned ${durationLabel(row.plannedMs)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 135,
                    child: Text(
                      'Actual $actual',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(variance, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paused ${durationLabel(row.pausedMs)} · Adjusted ${row.adjustmentMs > 0
                    ? '+'
                    : row.adjustmentMs < 0
                    ? '−'
                    : ''}${durationLabel(row.adjustmentMs)}',
              ),
              if (segment?.speaker.isNotEmpty == true)
                Text('Speaker: ${segment!.speaker}'),
              if (segment?.notes.isNotEmpty == true)
                Text('Private note: ${segment!.notes}'),
              if (row.actualMs == null && !row.skipped)
                const Text('This segment has no recorded duration.'),
            ],
          ),
        ),
      ],
    );
  }
}

/// After-service reflection, shown apart from the recorded timings.
class ReviewNoteSection extends StatelessWidget {
  final ReviewNote? review;
  final bool busy;
  final VoidCallback onEdit;
  const ReviewNoteSection({
    super.key,
    required this.review,
    required this.busy,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return reportSurface(
      context,
      child: Padding(
        key: const ValueKey('review-note-section'),
        padding: EdgeInsets.all(appLayout(context).panelPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rate_review_outlined, color: colors.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Review notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (review != null)
                  TextButton(
                    key: const ValueKey('edit-review-note'),
                    onPressed: busy ? null : onEdit,
                    child: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (review == null) ...[
              Text(
                'Add what to remember for next time, such as "Reduce welcome next week". Notes never change the recorded timings.',
                style: TextStyle(color: colors.muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('add-review-note'),
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Add a review note'),
              ),
            ] else ...[
              Text(review!.text, key: const ValueKey('review-note-text')),
              const SizedBox(height: 8),
              Text(
                'Added after service · ${reportDate(review!.editedWall)}',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Edits a review note. Owns its text controller so the field stays valid
/// through the dialog's closing animation.
class ReviewNoteDialog extends StatefulWidget {
  final String? initial;
  const ReviewNoteDialog({super.key, this.initial});

  @override
  State<ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState extends State<ReviewNoteDialog> {
  late final text = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Add review note' : 'Edit review note',
    ),
    content: TextField(
      key: const ValueKey('review-note-field'),
      controller: text,
      autofocus: true,
      minLines: 3,
      maxLines: 8,
      maxLength: ReviewNote.maxLength,
      decoration: const InputDecoration(
        hintText: 'For example: Reduce welcome next week.',
      ),
    ),
    actions: [
      if (widget.initial != null)
        TextButton(
          key: const ValueKey('remove-review-note'),
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Remove note'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('save-review-note'),
        onPressed: () => Navigator.pop(context, text.text),
        child: const Text('Save note'),
      ),
    ],
  );
}

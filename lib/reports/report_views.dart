import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:church_service_timer/reports/report_outcome.dart';
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

const _months = [
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

String reportDate(int wall) {
  final d = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return '${d.day} ${_months[d.month - 1]} ${d.year} · ${clockLabel(wall)}';
}

/// "15 Jan", short enough to sit under one bar of the graph.
String shortReportDate(int wall) {
  final d = DateTime.fromMillisecondsSinceEpoch(wall).toLocal();
  return '${d.day} ${_months[d.month - 1]}';
}

String reportMode(ServiceReport r) => r.quickTimer
    ? 'Quick timer'
    : r.rehearsal
    ? 'Rehearsal ${r.rate}×'
    : 'Live';

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
    // A desktop layout shows the report beside the list.
    if (reportsFillWindow) {
      refreshHome(() {
        reportsPage.view = 'list';
        reportsPage.open = r.id;
      });
      return;
    }
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
      // Sentence case, like the rest of the app.
      fieldStartLabelText: 'Start date',
      fieldEndLabelText: 'End date',
      fieldStartHintText: 'Start date',
      fieldEndHintText: 'End date',
      saveText: 'Apply',
    );
    if (result != null && mounted)
      refreshHome(() {
        reportsPage.dates = result;
        reportsPage.open = null;
      });
  }

  /// Three quick facts about the most recent comparable live services.
  /// With [compact], one fact to a line for a narrow side column.
  Widget reportSummary({bool compact = false}) {
    final colors = appColors(context);
    final recent =
        c.state.reports
            .where((r) => r.comparable && !r.rehearsal && !r.quickTimer)
            .toList()
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
      // The same words as the rest of Reports, to the nearest minute; "avg"
      // only when more than one service is averaged.
      return m == 0
          ? 'On time'
          : '${durationLabel(m * 60000)} ${ms > 0 ? 'over' : 'under'}${last.length > 1 ? ' avg' : ''}';
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
    final facts = [
      (
        // Rehearsals are left out, so say "live": the graph below can
        // include a later rehearsal.
        last.length == 1
            ? 'Last live service'
            : 'Last ${last.length} live services',
        minutes(avg),
        avg.abs() < 60000
            ? colors.accent
            : avg > 0
            ? colors.warning
            : colors.info,
      ),
      ('On time', '$onTime of ${last.length}', colors.text),
      (
        'Most over',
        worst.isEmpty ? 'None' : worst.first.key,
        worst.isEmpty ? colors.accent : colors.warning,
      ),
    ];
    if (compact)
      return Padding(
        key: const ValueKey('report-summary'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          children: [
            for (final (label, value, tone) in facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    return Padding(
      key: const ValueKey('report-summary'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          for (final (i, (label, value, tone)) in facts.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            tile(label, value, tone),
          ],
        ],
      ),
    );
  }

  /// The report list with its search, filters and tabs. With [desktop] it
  /// is drawn flat for the side column of a desktop layout, where [openId]
  /// is the report shown beside it and the graphs take the main area.
  Widget reports({bool desktop = false, String? openId}) {
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
                    child: const Text('Export all reports'),
                  ),
                  PopupMenuItem<String>(
                    value: 'clear',
                    enabled: total > 0 && !c.busy,
                    key: const ValueKey('clear-all-reports'),
                    height: appLayout(ctx).controlHeight,
                    child: Text(
                      'Delete all reports',
                      style: TextStyle(color: appColors(ctx).error),
                    ),
                  ),
                ],
              ),
            ],
          ),
        const SizedBox(height: 14),
        if (!reportsPage.selecting) reportSummary(compact: desktop),
        // The Dates button takes the search field's height, whatever the
        // density and text size.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              // In a side column the search field needs the room, so the
              // button is its icon until dates are chosen.
              if (desktop && reportsPage.dates == null)
                Tooltip(
                  message: 'Filter by date',
                  child: OutlinedButton(
                    key: const ValueKey('report-date-filter'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: pickReportDates,
                    child: const Icon(
                      Icons.date_range,
                      size: 20,
                      semanticLabel: 'Dates',
                    ),
                  ),
                )
              else
                OutlinedButton.icon(
                  key: const ValueKey('report-date-filter'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
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
                      // Only once a quick timer has been saved.
                      if (c.state.reports.any((r) => r.quickTimer))
                        'quick': 'Quick timers',
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
            if (!desktop)
              Text(
                plural(history.length, 'record'),
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
          ],
        ),
        // Under the chips, where a side column has the room.
        if (desktop)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              plural(history.length, 'record'),
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
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
                  : 'No reports match this filter.',
            ),
          )
        else if (reportsPage.view == 'graph' && !desktop)
          reportGraphs(history)
        else
          (desktop
              ? (Widget child) => child
              : (Widget child) => reportSurface(context, child: child))(
            Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  if (i > 0)
                    desktop
                        ? const AppDivider(indent: 0, endIndent: 0)
                        : const AppDivider(),
                  ReportListRow(
                    report: history[i],
                    compact: desktop,
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
                    selected: desktop
                        ? openId == history[i].id
                        : useMasterDetail && reportsPage.open == history[i].id,
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
                      if (useMasterDetail || desktop)
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
                // One date under each bar, laid out like the bars above.
                Row(
                  key: const ValueKey('graph-dates'),
                  children: [
                    for (final r in last)
                      Expanded(
                        child: Text(
                          shortReportDate(r.startedWall ?? r.endedWall),
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          textAlign: TextAlign.center,
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
                        // What happened, then how it compares, in the same
                        // words and colour as the report rows.
                        Text(
                          'Ran ${durationLabel(picked.totalMs!)} · planned ${durationLabel(picked.plannedMs)}',
                          key: const ValueKey('graph-picked-times'),
                          style: TextStyle(color: colors.muted, fontSize: 13),
                        ),
                        Text(
                          outcomeLabel(pickedVariance),
                          key: const ValueKey('graph-picked-outcome'),
                          style: TextStyle(
                            color: outcomeColor(colors, pickedVariance),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
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
                        : outcomeLabel(summary.averageVarianceMs!),
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
                    'Under · ${summary.ahead}',
                    style: TextStyle(color: appColors(context).info),
                  ),
                  Text(
                    'On time · ${summary.onTime}',
                    style: TextStyle(color: appColors(context).accent),
                  ),
                  Text(
                    'Over · ${summary.behind}',
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

import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

extension ReportLibraryViews on HomeState {
  bool reportMatches(ServiceReport r) {
    final keep = switch (reportsPage.filter) {
      'live' => !r.rehearsal && !r.quickTimer,
      'rehearsal' => r.rehearsal,
      'quick' => r.quickTimer,
      _ => true,
    };
    if (!keep) return false;
    final text =
        '${r.name} ${r.churchName} ${r.rows.map((s) => s.name).join(' ')}'
            .toLowerCase();
    if (!reportsPage.query
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains))
      return false;
    final date = DateTime.fromMillisecondsSinceEpoch(
      r.startedWall ?? r.endedWall,
    );
    return reportsPage.dates == null ||
        (!date.isBefore(reportsPage.dates!.start) &&
            date.isBefore(
              DateTime(
                reportsPage.dates!.end.year,
                reportsPage.dates!.end.month,
                reportsPage.dates!.end.day + 1,
              ),
            ));
  }

  Widget reportsResponsive() {
    if (!useMasterDetail || reportsPage.view == 'graph') return reports();
    final r = c.state.reports
        .where((r) => r.id == reportsPage.open && reportMatches(r))
        .firstOrNull;
    return masterDetail(
      reports(),
      r == null
          ? panel(
              child: const Center(
                child: Text('Select a service to view its report.'),
              ),
            )
          : ReportDetailPage(
              key: ValueKey(r.id),
              report: r,
              embedded: true,
              controller: c,
              onExport: (format) => exportReport(r, format),
              onPrint: () => printServiceSheet(r.program, report: r),
              onDelete: () => confirmClearReports(record: r),
              onEditReview: () => editReviewNote(r),
            ),
    );
  }
}

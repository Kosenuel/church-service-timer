import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

extension ReportLibraryViews on HomeState {
  bool reportMatches(ServiceReport r) {
    if (reportFilter != 'all' &&
        (reportFilter == 'rehearsal' ? !r.rehearsal : r.rehearsal))
      return false;
    final text =
        '${r.name} ${r.churchName} ${r.rows.map((s) => s.name).join(' ')}'
            .toLowerCase();
    if (!reportQuery
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .every(text.contains))
      return false;
    final date = DateTime.fromMillisecondsSinceEpoch(
      r.startedWall ?? r.endedWall,
    );
    return reportDates == null ||
        (!date.isBefore(reportDates!.start) &&
            date.isBefore(
              DateTime(
                reportDates!.end.year,
                reportDates!.end.month,
                reportDates!.end.day + 1,
              ),
            ));
  }

  Widget reportsResponsive() {
    if (!useMasterDetail || reportView == 'graph') return reports();
    final r = c.state.reports
        .where((r) => r.id == selectedReport && reportMatches(r))
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
              onExport: (format) => exportReport(r, format),
              onPrint: () => printServiceSheet(r.program, report: r),
              onDelete: () => confirmClearReports(record: r),
            ),
    );
  }
}

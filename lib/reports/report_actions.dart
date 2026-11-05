import 'dart:async';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

extension ReportActions on HomeState {
  Future<bool> confirmClearReports({ServiceReport? record}) async {
    final ids = record == null
        ? c.state.reports.map((r) => r.id).toSet()
        : {record.id};
    if (ids.isEmpty) return false;
    if (await confirm(
      record == null ? 'Clear all reports?' : 'Clear this report?',
      record == null
          ? 'Delete all ${ids.length} currently saved report records from this device? Exported files and the current service are unaffected. This cannot be undone.'
          : 'Delete the report for “${record.name}” (${DateTime.fromMillisecondsSinceEpoch(record.endedWall).toLocal()})? Exported files and the current service are unaffected. This cannot be undone.',
      record == null ? 'Clear all reports' : 'Clear report',
    )) {
      final ok = await c.clearReports(ids);
      if (!ok && mounted)
        await showError(c.error ?? 'The report could not be cleared.');
      return ok;
    }
    return false;
  }

  Future<void> exportReport(ServiceReport r, String type) async {
    try {
      await c.port.exportFile(
        'Church-Service-Timer-report-${r.endedWall}.$type',
        type == 'csv' ? exportReportCsv(r) : exportReportJson(r),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
  }
}

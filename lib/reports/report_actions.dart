import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'dart:async';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

extension ReportActions on HomeState {
  Future<bool> confirmClearReports({ServiceReport? record}) async {
    if (!await ensureSettingsUnlocked(
      reason: 'Enter the Settings PIN to delete reports.',
    ))
      return false;
    final ids = record == null
        ? c.state.reports.map((r) => r.id).toSet()
        : {record.id};
    if (ids.isEmpty) return false;
    if (await confirm(
      record == null ? 'Clear all reports?' : 'Clear this report?',
      record == null
          ? 'Delete all ${ids.length} currently saved report records from this device? Exported files and the current service are unaffected. This cannot be undone.'
          : 'Delete the report for “${record.name}” (${reportDate(record.startedWall ?? record.endedWall)})? Exported files and the current service are unaffected. This cannot be undone.',
      record == null ? 'Clear all reports' : 'Clear report',
      destructive: true,
    )) {
      final ok = await c.clearReports(ids);
      if (!ok && mounted)
        await showError(c.error ?? 'The report could not be cleared.');
      return ok;
    }
    return false;
  }

  /// Asks whether exported or printed reports include their review notes.
  /// Returns false straight away when none of them has one; null cancels.
  Future<bool?> askIncludeReview(Iterable<ServiceReport> records) async {
    final withNotes = records.where((r) => r.review != null).length;
    if (withNotes == 0) return false;
    return showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Include review notes?'),
        content: Text(
          withNotes == 1 && records.length == 1
              ? 'This report has a review note. Recorded timings are exported either way.'
              : '$withNotes of these reports have review notes. Recorded timings are exported either way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('exclude-review'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Leave out'),
          ),
          FilledButton(
            key: const ValueKey('include-review'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Include'),
          ),
        ],
      ),
    );
  }

  /// Adds, edits or removes the review note on a saved report.
  Future<void> editReviewNote(ServiceReport report) async {
    final saved = c.state.reports.where((r) => r.id == report.id).firstOrNull;
    if (saved == null) return;
    final result = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (_) => ReviewNoteDialog(initial: saved.review?.text),
    );
    if (result == null) return;
    if (!await c.setReviewNote(saved.id, result) && mounted)
      await showError(c.error ?? 'The review note could not be saved.');
  }

  Future<void> exportReport(ServiceReport r, String type) async {
    final includeReview = await askIncludeReview([r]);
    if (includeReview == null) return;
    try {
      await c.port.exportFile(
        'Church-Service-Timer-report-${r.endedWall}.$type',
        type == 'csv'
            ? exportReportCsv(r, includeReview: includeReview)
            : exportReportJson(r, includeReview: includeReview),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
  }
}

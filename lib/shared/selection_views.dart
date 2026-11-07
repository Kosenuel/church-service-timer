import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

extension SelectionViews on HomeState {
  void toggleExportSelection(Set<String> selected, String id) {
    if (!selected.remove(id)) selected.add(id);
  }

  /// Compact Select toggle; Programs places it on the filter row.
  Widget selectToggle({required bool programs}) {
    final available = programs
        ? c.state.templates.isNotEmpty
        : c.state.reports.isNotEmpty;
    final narrow = MediaQuery.sizeOf(context).width < 480;
    void start() => refreshHome(() {
      if (programs) {
        selectingPrograms = true;
        selectedProgramExports.clear();
      } else {
        selectingReports = true;
        reportView = 'list';
        selectedReportExports.clear();
      }
    });
    if (narrow) {
      return IconButton(
        key: ValueKey('select-${programs ? 'programs' : 'reports'}'),
        tooltip: 'Select',
        onPressed: available ? start : null,
        icon: const Icon(Icons.checklist),
      );
    }
    return TextButton.icon(
      key: ValueKey('select-${programs ? 'programs' : 'reports'}'),
      onPressed: available
          ? () => refreshHome(() {
              if (programs) {
                selectingPrograms = true;
                selectedProgramExports.clear();
              } else {
                selectingReports = true;
                reportView = 'list';
                selectedReportExports.clear();
              }
            })
          : null,
      icon: const Icon(Icons.checklist),
      label: const Text('Select'),
    );
  }

  /// Deletes the selected programs or reports after confirmation, then
  /// offers a 10-second Undo that restores them exactly.
  Future<void> deleteSelected({
    required bool programs,
    required Set<String> chosen,
    required int hidden,
  }) async {
    if (!await ensureSettingsUnlocked(
      reason:
          'Enter the Settings PIN to delete ${programs ? 'programs' : 'reports'}.',
    ))
      return;
    final count = chosen.length;
    final noun = programs
        ? (count == 1 ? 'program' : 'programs')
        : (count == 1 ? 'report' : 'reports');
    final hiddenNote = hidden == 0
        ? ''
        : hidden == count
        ? count == 1
              ? ' It is hidden by your current search or filter.'
              : ' All of them are hidden by your current search or filter.'
        : ' $hidden of them ${hidden == 1 ? 'is' : 'are'} hidden by your current search or filter.';
    final keeps = programs
        ? ' A service already running and past reports stay unchanged.'
        : ' Exported files and the current service are unaffected.';
    if (!await confirm(
      'Delete $count $noun?',
      'Delete $count saved $noun from this device?$hiddenNote$keeps You can undo for 10 seconds.',
      'Delete $count',
      destructive: true,
    ))
      return;
    final selected = programs ? selectedProgramExports : selectedReportExports;
    if (programs) {
      final removed = await c.deletePrograms(chosen);
      if (removed == null) {
        if (mounted) await showError(c.error ?? 'Could not delete programs.');
        return;
      }
      refreshHome(() => selected.removeAll(chosen));
      if (mounted)
        offerUndo(
          '$count $noun deleted',
          () => c.restorePrograms(removed),
          duration: const Duration(seconds: 10),
        );
    } else {
      final removed = await c.deleteReports(chosen);
      if (removed == null) {
        if (mounted) await showError(c.error ?? 'Could not delete reports.');
        return;
      }
      refreshHome(() => selected.removeAll(chosen));
      if (mounted)
        offerUndo(
          '$count $noun deleted',
          () => c.restoreReports(removed),
          duration: const Duration(seconds: 10),
        );
    }
  }

  bool get useMasterDetail =>
      MediaQuery.sizeOf(context).width >= 1000 &&
      MediaQuery.textScalerOf(context).scale(16) <= 24;

  Widget masterDetail(Widget list, Widget detail) => SizedBox(
    key: const ValueKey('master-detail'),
    height:
        (MediaQuery.sizeOf(context).height - (c.liveSession.active ? 280 : 210))
            .clamp(400, 1200),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 4, child: SingleChildScrollView(child: list)),
        const SizedBox(width: 20),
        Expanded(
          flex: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: detail,
          ),
        ),
      ],
    ),
  );
}

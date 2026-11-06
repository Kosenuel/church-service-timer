import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
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

  Widget exportSelectionBar({
    required bool programs,
    required Set<String> shown,
    bool showToggle = true,
  }) {
    final selecting = programs ? selectingPrograms : selectingReports;
    final selected = programs ? selectedProgramExports : selectedReportExports;
    final available = programs
        ? c.state.templates.map((p) => p.name).toSet()
        : c.state.reports.map((r) => r.id).toSet();
    final chosen = selected.intersection(available);
    final hidden = chosen.difference(shown).length;
    void toggleMode() => refreshHome(() {
      if (programs)
        selectingPrograms = !selectingPrograms;
      else {
        selectingReports = !selectingReports;
        reportView = 'list';
      }
      selected.clear();
    });
    if (!selecting && !showToggle) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: !selecting
          ? Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: ValueKey('select-${programs ? 'programs' : 'reports'}'),
                onPressed: available.isEmpty ? null : toggleMode,
                icon: const Icon(Icons.checklist),
                label: const Text('Select'),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${chosen.length} selected${hidden == 0 ? '' : ' · $hidden hidden by filters'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: toggleMode,
                      child: const Text('Done'),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: shown.isEmpty
                          ? null
                          : () => refreshHome(() => selected.addAll(shown)),
                      child: const Text('Select all shown'),
                    ),
                    TextButton(
                      onPressed: chosen.isEmpty
                          ? null
                          : () => refreshHome(selected.clear),
                      child: const Text('Clear selection'),
                    ),
                    UnavailableAction(
                      reason: chosen.isEmpty
                          ? 'Select at least one item to export.'
                          : null,
                      child: FilledButton.icon(
                        key: ValueKey(
                          'export-selected-${programs ? 'programs' : 'reports'}',
                        ),
                        onPressed: chosen.isEmpty || c.busy
                            ? null
                            : () async {
                                if (programs)
                                  await exportAllPrograms(
                                    selected: c.state.templates
                                        .where((p) => chosen.contains(p.name))
                                        .toList(),
                                  );
                                else
                                  await exportAllReports(
                                    selected: c.state.reports
                                        .where((r) => chosen.contains(r.id))
                                        .toList(),
                                  );
                              },
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Export selected'),
                      ),
                    ),
                    if (programs)
                      Builder(
                        builder: (context) {
                          final allPinned =
                              chosen.isNotEmpty &&
                              chosen.every(
                                c.state.programLibrary.favourites.contains,
                              );
                          return OutlinedButton.icon(
                            key: const ValueKey('pin-selected-programs'),
                            onPressed: chosen.isEmpty || c.busy || c.corrupt
                                ? null
                                : () async {
                                    if (!await c.commit((draft, _) {
                                          final pins =
                                              draft.programLibrary.favourites;
                                          allPinned
                                              ? pins.removeAll(chosen)
                                              : pins.addAll(chosen);
                                        }) &&
                                        mounted)
                                      await showError(
                                        c.error ?? 'Could not update pins.',
                                      );
                                  },
                            icon: Icon(
                              allPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin,
                            ),
                            label: Text(
                              allPinned ? 'Unpin selected' : 'Pin selected',
                            ),
                          );
                        },
                      ),
                  ],
                ),
                // Kept apart from Export, at the opposite edge, in the
                // destructive colour, so it is hard to tap by accident.
                Align(
                  alignment: Alignment.centerRight,
                  child: UnavailableAction(
                    reason: chosen.isEmpty
                        ? 'Select at least one item to delete.'
                        : null,
                    child: TextButton.icon(
                      key: ValueKey(
                        'delete-selected-${programs ? 'programs' : 'reports'}',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: appColors(context).error,
                      ),
                      onPressed: chosen.isEmpty || c.busy || c.corrupt
                          ? null
                          : () => deleteSelected(
                              programs: programs,
                              chosen: chosen,
                              hidden: hidden,
                            ),
                      icon: const Icon(Icons.delete_outline),
                      label: Text('Delete selected (${chosen.length})'),
                    ),
                  ),
                ),
              ],
            ),
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

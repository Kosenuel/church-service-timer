import 'package:church_service_timer/main.dart';
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
                  ],
                ),
              ],
            ),
    );
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

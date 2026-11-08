import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';

/// One choice in the Share or Export sheet.
class FormatChoice {
  final String id, title, hint;
  const FormatChoice(this.id, this.title, this.hint);
}

const programFormats = [
  FormatChoice(
    'json',
    'Program file (JSON)',
    'Opens in Church Service Timer on another phone',
  ),
  FormatChoice('csv', 'Spreadsheet (CSV)', 'For Excel or Google Sheets'),
  FormatChoice('pdf', 'Printable sheet (PDF)', 'One page per program'),
];

const reportFormats = [
  FormatChoice('csv', 'Spreadsheet (CSV)', 'For Excel or Google Sheets'),
  FormatChoice(
    'json',
    'Report file (JSON)',
    'Every segment, pause and adjustment, for keeping or importing',
  ),
  FormatChoice('pdf', 'Printable report (PDF)', 'One page per service'),
];

/// Shared look for the grouped Programs and Reports lists: a dismissible
/// hint, the selection header and action bar, and the Share/Export sheet.
extension ListViews on HomeState {
  /// A small hint shown until it is dismissed on this phone.
  Widget listHint(String id, String text) {
    if (c.state.dismissedHints.contains(id)) return const SizedBox.shrink();
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: ValueKey('hint-$id'),
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
              IconButton(
                key: ValueKey('dismiss-hint-$id'),
                tooltip: 'Dismiss hint',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18),
                onPressed: c.busy
                    ? null
                    : () =>
                          c.commit((draft, _) => draft.dismissedHints.add(id)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Set<String> selectedFor(bool programs) =>
      programs ? programsPage.selected : reportsPage.selected;

  Set<String> chosenFor(bool programs) => selectedFor(programs).intersection(
    programs
        ? c.state.templates.map((p) => p.id).toSet()
        : c.state.reports.map((r) => r.id).toSet(),
  );

  /// The ids the current search and filters show.
  Set<String> shownIds(bool programs) => programs
      ? c.state.programLibrary
            .find(c.state.templates, programsPage.query, programsPage.filter)
            .map((p) => p.id)
            .toSet()
      : c.state.reports.where(reportMatches).map((r) => r.id).toSet();

  void finishSelecting() => refreshHome(() {
    programsPage.selecting = false;
    reportsPage.selecting = false;
    programsPage.selected.clear();
    reportsPage.selected.clear();
  });

  /// Replaces the page title while selecting: ✕ · N selected · Select all.
  Widget selectionHeader({required bool programs, required Set<String> shown}) {
    final chosen = chosenFor(programs);
    final hidden = chosen.difference(shown).length;
    final allShown = shown.isNotEmpty && shown.every(chosen.contains);
    final noun = programs ? 'programs' : 'reports';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: ValueKey('done-selecting-$noun'),
                tooltip: 'Done selecting',
                onPressed: finishSelecting,
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${chosen.length} selected',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              OutlinedButton(
                key: ValueKey('select-all-$noun'),
                onPressed: shown.isEmpty
                    ? null
                    : () => refreshHome(
                        () => allShown
                            ? selectedFor(programs).removeAll(shown)
                            : selectedFor(programs).addAll(shown),
                      ),
                child: Text(allShown ? 'Clear' : 'Select all'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Text(
              [
                'Tap $noun to add or remove them · Back to finish',
                if (hidden > 0) '$hidden selected hidden by filters',
              ].join(' · '),
              style: TextStyle(color: appColors(context).muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// The fixed bar at the bottom while selecting: Pin (programs), Share,
  /// Export and, apart and in red, Delete.
  Widget selectionActionBar({required bool programs}) {
    final colors = appColors(context);
    final chosen = chosenFor(programs);
    final noun = programs ? 'programs' : 'reports';
    final none = chosen.isEmpty || c.busy;
    final allPinned =
        programs &&
        chosen.isNotEmpty &&
        chosen.every(c.state.programLibrary.favourites.contains);
    List<T> picked<T>(List<T> all, String Function(T) id) =>
        all.where((x) => chosen.contains(id(x))).toList();
    Future<void> share(bool share) async {
      if (programs)
        await exportAllPrograms(
          share: share,
          selected: picked(c.state.templates, (p) => p.id),
        );
      else
        await exportAllReports(
          share: share,
          selected: picked(c.state.reports, (r) => r.id),
        );
    }

    Widget action(
      String key,
      String text,
      IconData icon,
      VoidCallback? onPressed, {
      Color? color,
      String? reason,
    }) => Expanded(
      child: UnavailableAction(
        reason: onPressed == null ? reason : null,
        child: TextButton(
          key: ValueKey(key),
          style: TextButton.styleFrom(
            foregroundColor: color ?? colors.text,
            minimumSize: const Size(0, 60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: onPressed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    return Material(
      key: ValueKey('selection-bar-$noun'),
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              if (programs)
                action(
                  'pin-selected-programs',
                  allPinned ? 'Unpin' : 'Pin',
                  allPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  none || c.corrupt
                      ? null
                      : () async {
                          if (!await c.commit((draft, _) {
                                final pins = draft.programLibrary.favourites;
                                allPinned
                                    ? pins.removeAll(chosen)
                                    : pins.addAll(chosen);
                              }) &&
                              mounted)
                            await showError(
                              c.error ?? 'Could not update pins.',
                            );
                        },
                  reason: 'Select at least one program to pin.',
                ),
              action(
                'share-selected-$noun',
                'Share',
                Icons.share_outlined,
                none ? null : () => share(true),
                reason: 'Select at least one item to share.',
              ),
              action(
                'export-selected-$noun',
                'Export',
                Icons.download_outlined,
                none ? null : () => share(false),
                reason: 'Select at least one item to export.',
              ),
              action(
                'delete-selected-$noun',
                'Delete',
                Icons.delete_outline,
                none || c.corrupt
                    ? null
                    : () => deleteSelected(
                        programs: programs,
                        chosen: chosen,
                        hidden: chosen.difference(shownIds(programs)).length,
                      ),
                color: colors.error,
                reason: 'Select at least one item to delete.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A bottom sheet to pick how to share or export: one format from a list,
  /// an optional extra (private notes, review notes) and a clear action.
  /// Returns the chosen format and the extra, or null when cancelled.
  Future<(String, bool)?> showFormatSheet({
    required String title,
    required String subtitle,
    required List<FormatChoice> formats,
    required String keyPrefix,
    required bool share,
    String? extraTitle,
    String? extraHint,
    String extraKey = 'format-extra',
  }) {
    var format = formats.first.id;
    var extra = false;
    return showModalBottomSheet<(String, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      sheetAnimationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) {
          final colors = appColors(ctx);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted),
                  ),
                  const SizedBox(height: 16),
                  label(share ? 'Send as' : 'Save as'),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: format,
                    onChanged: (v) => update(() => format = v ?? format),
                    child: Column(
                      children: [
                        for (final f in formats)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: format == f.id
                                  ? colors.accent.withValues(alpha: .12)
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: format == f.id
                                      ? colors.accent.withValues(alpha: .6)
                                      : colors.border,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: RadioListTile<String>(
                                key: ValueKey('$keyPrefix-${f.id}'),
                                value: f.id,
                                title: Text(
                                  f.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  f.hint,
                                  style: TextStyle(
                                    color: colors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (extraTitle != null)
                    CheckboxListTile(
                      key: ValueKey(extraKey),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: extra,
                      onChanged: (v) => update(() => extra = v ?? false),
                      title: Text(extraTitle),
                      subtitle: extraHint == null
                          ? null
                          : Text(
                              extraHint,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          key: ValueKey('$keyPrefix-go'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: () => Navigator.pop(ctx, (format, extra)),
                          icon: Icon(
                            share
                                ? Icons.share_outlined
                                : Icons.download_outlined,
                          ),
                          label: Text(share ? 'Share' : 'Export'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

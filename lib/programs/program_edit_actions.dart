import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/programs/import_mapping_views.dart';
import 'package:church_service_timer/main.dart';

/// Editing programs, and importing and exporting program files.
extension ProgramEditActions on HomeState {
  Future<Timeline?> editTemplate({int? index}) async {
    final initial = index == null
        ? Timeline('', [], c.state.defaults)
        : c.state.templates[index];
    final draftKey = index == null ? 'program:new' : 'program:${initial.id}';
    await c.flushEditDrafts();
    var editorInitial = initial;
    final savedDraft = c.state.editDrafts[draftKey];
    if (savedDraft != null) {
      if (!mounted) return null;
      final restore = await reviewSavedDraft(context);
      if (restore == null) return null;
      if (restore) {
        try {
          editorInitial = programFromDraft(savedDraft, initial.display);
        } catch (_) {
          if (mounted)
            await showError(
              'This draft could not be opened. The saved program is unchanged.',
            );
          return null;
        }
      } else {
        c.queueEditDraft(draftKey, null);
        await c.flushEditDrafts();
      }
    }
    if (!mounted) return null;
    final result = await Navigator.of(context).push<Timeline>(
      MaterialPageRoute(
        builder: (_) => TemplateEditor(
          initial: editorInitial,
          creating: index == null,
          reports: c.state.reports,
          onDraftChanged: (value) => c.queueEditDraft(draftKey, value),
          draftController: c,
          defaultEnd: c.state.defaults.end,
          existingNames: c.state.templates
              .asMap()
              .entries
              .where((e) => e.key != index)
              .map((e) => e.value.name.toLowerCase())
              .toSet(),
        ),
      ),
    );
    await c.flushEditDrafts();
    if (result == null) return null;
    final ok = await c.commit((draft, at) {
      draft.saveTemplate(
        result,
        replacing: index == null ? null : draft.templateIndex(initial),
        replacedAt: at.wall,
      );
      draft.editDrafts.remove(draftKey);
    });
    if (!ok) {
      if (mounted)
        await showError(c.error ?? 'The program could not be saved.');
      return null;
    }
    return result;
  }

  /// Explains files from this app that are not programs, so a shared
  /// report or backup does not fail with a parser error.
  String? otherExportKind(Map<String, dynamic> file) {
    final name = (file['name'] as String).toLowerCase();
    if (!name.endsWith('.json')) return null;
    try {
      final type =
          (jsonDecode((file['content'] as String).replaceFirst('\uFEFF', ''))
              as Map)['type'];
      if (type == 'church-service-timer-report' ||
          type == 'church-service-timer-reports')
        return 'This file contains service reports, not programs. Reports can be opened in a spreadsheet (CSV) or printed, but not imported.';
      if (type == 'church-service-timer-backup')
        return 'This file is a full backup. Restore it from Settings › Backup & restore.';
    } catch (_) {}
    return null;
  }

  Future<void> importFile({Map<String, dynamic>? received}) async {
    try {
      final file = received ?? await c.port.pickFile();
      if (file == null || !mounted) return;
      final other = otherExportKind(file);
      if (other != null) throw RuleError(other);
      // Someone else's spreadsheet: match its columns first.
      if ((file['name'] as String).toLowerCase().endsWith('.csv')) {
        final rows = spreadsheetRows(file['content'] as String);
        if (rows.isNotEmpty && !isStandardProgramCsv(rows)) {
          final mapped = await Navigator.of(context).push<List<Timeline>>(
            MaterialPageRoute(
              builder: (_) => ImportMappingPage(
                controller: c,
                rows: rows,
                fileName: file['name'] as String,
              ),
            ),
          );
          if (mapped != null && mounted) await importProgramBundle(mapped);
          return;
        }
      }
      final candidates = importPrograms(
        file['content'] as String,
        file['name'] as String,
        c.state.defaults,
      );
      final raw = (file['content'] as String).replaceFirst('\uFEFF', '');
      final bundle = (file['name'] as String).toLowerCase().endsWith('.json')
          ? (jsonDecode(raw) as Map)['type'] == 'church-service-timer-programs'
          : parseCsv(raw)
                .firstWhere((r) => r.any((v) => v.trim().isNotEmpty))
                .contains('Program');
      if (candidates.length > 1 || bundle) {
        await importProgramBundle(candidates);
        return;
      }
      final candidate = importTemplate(
        file['content'] as String,
        file['name'] as String,
        c.state.defaults,
      );
      for (final l in [
        ...candidate.display.cues,
        ...candidate.display.warnings.map((w) => w.cue),
        ?candidate.display.end,
        if (candidate.display.zero != null) candidate.display.zero!,
      ]) {
        await NativeDisplayFonts.prepare(l);
      }
      validateTimelinePixels(candidate);
      validateProgramDuration(candidate);
      if (!mounted) return;
      final name = TextEditingController(text: candidate.name);
      String? error;
      bool validName() {
        try {
          final n = nameValue(name.text, 'Program name');
          require(
            !c.state.templates.any(
              (e) => e.name.toLowerCase() == n.toLowerCase(),
            ),
            'This name already exists. Rename the incoming program.',
          );
          error = null;
          return true;
        } catch (e) {
          error = e.toString();
          return false;
        }
      }

      validName();
      final accepted = await showDialog<Timeline>(
        context: context,
        animationStyle: reduceAppMotion(context)
            ? AnimationStyle.noAnimation
            : null,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Preview program import'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The name problem shows on the field it is about.
                    TextField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: 'Program name',
                        errorText: error,
                        errorMaxLines: 2,
                      ),
                      onChanged: (_) => update(() {
                        validName();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${plural(candidate.segments.length, 'segment')} · ${durationLabel(candidate.segments.fold<int>(0, (a, s) => a + s.durationMs))}',
                      style: TextStyle(color: appColors(context).muted),
                    ),
                    const SizedBox(height: 8),
                    for (final s in candidate.segments)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(child: Text(s.name)),
                            const SizedBox(width: 12),
                            Text(
                              s.durationText,
                              style: TextStyle(color: appColors(context).muted),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    // The display settings fold away instead of filling the
                    // dialog with one long block of text.
                    Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        key: const ValueKey('import-display-settings'),
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 8),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        title: const Text('Display settings'),
                        subtitle: Text(
                          (file['name'] as String).toLowerCase().endsWith(
                                '.csv',
                              )
                              ? 'A spreadsheet has none, so your current defaults are used'
                              : 'Included in the file',
                          style: TextStyle(
                            color: appColors(context).muted,
                            fontSize: 12,
                          ),
                        ),
                        children: [
                          for (final (label, lines) in [
                            (
                              'Cues',
                              candidate.display.cues.map(styleSummary).toList(),
                            ),
                            (
                              'At zero',
                              [
                                candidate.display.zero == null
                                    ? '00:00'
                                    : styleSummary(candidate.display.zero!),
                              ],
                            ),
                            (
                              'End screen',
                              [
                                candidate.display.end == null
                                    ? noEndScreenLine
                                    : styleSummary(candidate.display.end!),
                              ],
                            ),
                            (
                              'Warnings',
                              candidate.display.warnings.isEmpty
                                  ? ['None']
                                  : [
                                      for (final w
                                          in candidate.display.warnings)
                                        '${w.enabled ? 'On' : 'Off'} · ${formatTime(w.seconds * 1000)} · ${w.destination} · ${styleSummary(w.cue)}',
                                    ],
                            ),
                          ]) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            for (final line in lines)
                              Text(
                                line,
                                style: TextStyle(
                                  color: appColors(context).muted,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !validName()
                    ? null
                    : () {
                        try {
                          final t = candidate.renamed(name.text);
                          require(
                            !c.state.templates.any(
                              (e) =>
                                  e.name.toLowerCase() == t.name.toLowerCase(),
                            ),
                            'This name already exists. Rename the incoming program.',
                          );
                          Navigator.pop(ctx, t);
                        } catch (e) {
                          update(() => error = e.toString());
                        }
                      },
                child: const Text('Import program'),
              ),
            ],
          ),
        ),
      );
      Future<void>.delayed(const Duration(seconds: 1), name.dispose);
      if (accepted != null)
        await c.commit((draft, _) {
          draft.saveTemplate(accepted);
          draft.addStageCues(accepted.display.cues);
        });
    } catch (e) {
      if (mounted) await showError(e.toString());
    }
  }

  Future<void> export(Timeline t, String type) async {
    if (type == 'csv' &&
        !await confirm(
          'Export segments only?',
          'CSV includes names, order and durations. Cue formatting, zero and end screens are omitted. Choose JSON to preserve the full program.',
          'Export CSV',
        ))
      return;
    try {
      await c.port.exportFile(
        '${t.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}.$type',
        type == 'json' ? exportJson(t) : exportCsv(t),
      );
    } catch (e) {
      if (mounted) showError('Export failed: $e');
    }
  }
}

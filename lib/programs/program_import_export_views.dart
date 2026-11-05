import 'dart:async';
import 'dart:math' as math;
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:flutter/material.dart';

extension ProgramImportExportViews on HomeState {
  Future<void> exportAllPrograms({List<Timeline>? selected}) async {
    final programs = List<Timeline>.of(selected ?? c.state.templates);
    if (programs.isEmpty) return;
    var notes = false;
    final format = await showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(
            selected == null
                ? 'Export all programs'
                : 'Export selected programs',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${programs.length} ${selected == null ? 'saved' : 'selected'} programs. JSON preserves formatting; CSV contains the rundown for spreadsheets.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include private operator notes'),
                value: notes,
                onChanged: (v) => update(() => notes = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            for (final f in ['json', 'csv'])
              FilledButton(
                onPressed: () => Navigator.pop(ctx, f),
                child: Text(f.toUpperCase()),
              ),
          ],
        ),
      ),
    );
    if (format == null) return;
    try {
      await c.port.exportFile(
        'Church-Service-Timer-${selected == null ? 'all' : 'selected'}-programs.$format',
        format == 'json'
            ? exportProgramsJson(programs, privateNotes: notes)
            : exportProgramsCsv(programs, privateNotes: notes),
      );
    } catch (e) {
      if (mounted) await showError('Export failed: $e');
    }
  }

  Future<void> importProgramBundle(List<Timeline> candidates) async {
    final names = c.state.templates.map((p) => p.name.toLowerCase()).toSet();
    final incoming = <Timeline>[];
    for (final candidate in candidates) {
      var name = candidate.name, index = 2;
      while (names.contains(name.toLowerCase())) {
        name =
            '${candidate.name.substring(0, math.min(65, candidate.name.length))} ($index)';
        index++;
      }
      names.add(name.toLowerCase());
      incoming.add(candidate.renamed(name));
      await NativeDisplayFonts.prepareState(
        AppState(
          [candidate],
          c.state.defaults,
          Session(id: 'import-preview', anchor: c.now),
        ),
      );
      validateTimelinePixels(candidate);
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: const Text('Preview program import'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'All programs are added together. Existing programs stay unchanged; duplicate names receive a numbered suffix.',
                ),
                SizedBox(height: appLayout(ctx).gap),
                AppMenuList(
                  children: [
                    for (final p in incoming)
                      ListTile(
                        title: Text(p.name),
                        subtitle: Text(templateSummary(p)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Import ${incoming.length} programs'),
          ),
        ],
      ),
    );
    if (accepted == true &&
        !await c.commit((draft, _) {
          for (final p in incoming) {
            draft.saveTemplate(p);
          }
        }) &&
        mounted)
      await showError(c.error ?? 'Nothing was imported.');
  }
}

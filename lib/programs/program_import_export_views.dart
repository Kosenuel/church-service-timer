import 'dart:async';
import 'dart:math' as math;
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/platform.dart';
import 'package:church_service_timer/reports/service_pdf.dart';
import 'package:church_service_timer/display/native_fonts.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:flutter/material.dart';

extension ProgramImportExportViews on HomeState {
  /// Exports programs to a file, or with [share] sends them through the
  /// Android share sheet (Bluetooth, messaging, email), where a PDF per
  /// program is also offered.
  Future<void> exportAllPrograms({
    List<Timeline>? selected,
    bool share = false,
  }) async {
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
            '${share ? 'Share' : 'Export'} ${selected == null ? 'all' : 'selected'} programs',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${programs.length} ${selected == null ? 'saved' : 'selected'} programs. JSON preserves formatting and can be imported on another phone; CSV contains the rundown for spreadsheets.${share ? ' PDF makes one printable sheet per program.' : ''}',
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
            for (final f in ['json', 'csv', if (share) 'pdf'])
              FilledButton(
                key: ValueKey('${share ? 'share' : 'export'}-programs-$f'),
                onPressed: () => Navigator.pop(ctx, f),
                child: Text(f.toUpperCase()),
              ),
          ],
        ),
      ),
    );
    if (format == null) return;
    final name =
        'Church-Service-Timer-${selected == null ? 'all' : 'selected'}-programs.$format';
    String content() => format == 'json'
        ? exportProgramsJson(programs, privateNotes: notes)
        : exportProgramsCsv(programs, privateNotes: notes);
    try {
      if (!share) {
        await c.port.exportFile(name, content());
        return;
      }
      final files = format == 'pdf'
          ? [for (final p in programs) await programPdf(p, privateNotes: notes)]
          : [
              SharedFile.text(
                name,
                content(),
                format == 'json' ? 'application/json' : 'text/csv',
              ),
            ];
      await c.port.shareFiles(
        files,
        subject: programs.length == 1
            ? programs.single.name
            : '${programs.length} service programs',
      );
    } catch (e) {
      if (mounted)
        await showError('${share ? 'Sharing' : 'Export'} failed: $e');
    }
  }

  Future<SharedFile> programPdf(
    Timeline p, {
    required bool privateNotes,
  }) async {
    final document = ServicePrintDocument(
      program: p,
      church: c.state.churchName,
      serviceDate: c.now.wall,
      preparedAt: c.now.wall,
      banner: c.state.churchBanner,
      audience: privateNotes ? 'operator' : 'stage',
      includeNotes: privateNotes,
      watermark: c.state.printPreferences.watermark,
      inkSaving: c.state.printPreferences.inkSaving,
    );
    return SharedFile(
      servicePdfName(document),
      await servicePdfBytes(document),
      'application/pdf',
    );
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

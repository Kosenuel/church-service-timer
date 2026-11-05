import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/reports/service_pdf.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

extension PlanningViews on HomeState {
  Future<void> editUpcoming() async {
    final s = c.state.session, revision = c.state.session.revision;
    final result = await Navigator.of(context).push<Timeline>(
      MaterialPageRoute(
        builder: (_) => TemplateEditor(
          initial: Timeline(
            s.timeline!.name,
            s.timeline!.segments.skip(s.index + 1).toList(),
            s.timeline!.display,
          ),
          defaultEnd: s.timeline!.display.end,
          existingNames: const {},
          upcomingOnly: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (!await confirm(
      'Update upcoming segments?',
      'Keep the current and completed segments unchanged. Apply ${result.segments.length} upcoming segments to this running service only. The saved program is unchanged.',
      'Update rundown',
    ))
      return;
    if (!await c.commit(
          (draft, at) => replaceUpcoming(draft.session, result.segments, at),
          revision: revision,
        ) &&
        mounted)
      await showError(c.error ?? 'Could not update rundown.');
  }

  Future<void> printServiceSheet(
    Timeline? timeline, {
    ServiceReport? report,
  }) async {
    var includeNotes = false, includeBanner = true, includeReview = false;
    var audience = 'stage';
    var watermark = c.state.printPreferences.watermark;
    var inkSaving = c.state.printPreferences.inkSaving;
    var fullReport = report != null;
    final session = c.state.session;
    final actualDate =
        report?.startedWall ??
        (report == null && identical(timeline, session.timeline)
            ? session.run?.startedWall
            : null) ??
        report?.endedWall;
    var selectedDate = DateTime.fromMillisecondsSinceEpoch(
      actualDate ?? c.now.wall,
    );
    final yes = await showDialog<bool>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Print Service'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Print or choose Save as PDF in Android’s print screen.',
                ),
                const SizedBox(height: 12),
                AppMenuList(
                  key: const ValueKey('print-service-options'),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Service date'),
                      subtitle: Text(
                        serviceDateLabel(selectedDate.millisecondsSinceEpoch),
                      ),
                      trailing: actualDate == null
                          ? const Icon(Icons.edit_calendar_outlined)
                          : null,
                      onTap: actualDate != null
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: ctx,
                                initialDate: selectedDate,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (date != null && ctx.mounted)
                                update(() => selectedDate = date);
                            },
                    ),
                    if (report != null)
                      ChoiceField<bool>(
                        value: fullReport,
                        decoration: const InputDecoration(
                          labelText: 'Document',
                        ),
                        options: const [
                          ChoiceOption(value: true, label: 'Service report'),
                          ChoiceOption(value: false, label: 'Service rundown'),
                        ],
                        onChanged: (value) => update(() => fullReport = value!),
                      ),
                    ChoiceField<String>(
                      value: audience,
                      decoration: const InputDecoration(
                        labelText: 'Print copy',
                      ),
                      options: const [
                        ChoiceOption(value: 'stage', label: 'Stage copy'),
                        ChoiceOption(value: 'operator', label: 'Operator copy'),
                      ],
                      onChanged: (v) => update(() {
                        audience = v!;
                        includeNotes =
                            v == 'operator' &&
                            (report == null || report.program != null);
                      }),
                    ),
                    CheckboxListTile(
                      title: const Text('Ink-saving'),
                      subtitle: const Text('Omit banner and watermark'),
                      value: inkSaving,
                      onChanged: (v) => update(() => inkSaving = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('Church-name watermark'),
                      value: watermark,
                      onChanged: inkSaving
                          ? null
                          : (v) => update(() => watermark = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('Include church banner'),
                      value: includeBanner,
                      onChanged: inkSaving
                          ? null
                          : (v) => update(() => includeBanner = v!),
                    ),
                    CheckboxListTile(
                      title: const Text('Include private operator notes'),
                      subtitle: report != null && report.program == null
                          ? const Text('Not recorded in this older report')
                          : null,
                      value: includeNotes,
                      onChanged:
                          audience == 'stage' ||
                              (report != null && report.program == null)
                          ? null
                          : (v) => update(() => includeNotes = v!),
                    ),
                    if (report?.review != null)
                      CheckboxListTile(
                        key: const ValueKey('print-include-review'),
                        title: const Text('Include review notes'),
                        subtitle: const Text('Added after the service'),
                        value: includeReview,
                        onChanged: (v) => update(() => includeReview = v!),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (yes != true) return;
    try {
      if (!await c.commit(
        (draft, _) => draft.printPreferences = PrintPreferences(
          watermark: watermark,
          inkSaving: inkSaving,
        ),
      )) {
        throw RuleError(c.error ?? 'Could not save print preferences.');
      }
      final printProgram =
          report?.program ??
          timeline ??
          Timeline(
            report!.name,
            report.rows
                .map(
                  (row) =>
                      Segment(row.name, (row.plannedMs ~/ 60000).clamp(1, 99)),
                )
                .toList(),
            DisplaySettings(),
          );
      final document = ServicePrintDocument(
        audience: audience,
        program: printProgram,
        report: report,
        church: report?.churchName ?? c.state.churchName,
        serviceDate: selectedDate.millisecondsSinceEpoch,
        preparedAt: c.now.wall,
        banner: c.state.churchBanner,
        includeBanner: includeBanner,
        includeNotes: audience == 'operator' && includeNotes,
        fullReport: fullReport,
        includeReview: includeReview,
        watermark: watermark,
        inkSaving: inkSaving,
      );
      final regular = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
      await c.port.printServicePdf(
        report?.name ?? printProgram.name,
        (width, height) => createServicePdf(
          document,
          regularFont: regular,
          boldFont: bold,
          width: width,
          height: height,
        ),
      );
    } catch (e) {
      if (mounted) await showError('Printing failed: $e');
    }
  }
}

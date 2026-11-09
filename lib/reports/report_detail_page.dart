import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';

class ReportDetailPage extends StatefulWidget {
  final Future<void> Function()? onPrint;
  final AppController? controller;
  final bool embedded;
  final ServiceReport report;
  final Future<void> Function(String) onExport;
  final Future<bool> Function() onDelete;

  /// Opens the review-note editor; null hides the Review notes section.
  final Future<void> Function()? onEditReview;
  const ReportDetailPage({
    super.key,
    required this.report,
    required this.onExport,
    required this.onDelete,
    this.onPrint,
    this.onEditReview,
    this.controller,
    this.embedded = false,
  });
  @override
  State<ReportDetailPage> createState() => _ReportDetailPageState();
}

class _ReportDetailPageState extends State<ReportDetailPage> {
  bool busy = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The saved copy, so a review note edit shows straight away.
  ServiceReport get current =>
      widget.controller?.state.reports
          .where((r) => r.id == widget.report.id)
          .firstOrNull ??
      widget.report;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget block(Widget child) => Padding(
    padding: EdgeInsets.only(bottom: appLayout(context).gap * 2),
    child: reportSurface(
      context,
      child: Padding(
        padding: EdgeInsets.all(appLayout(context).panelPadding),
        child: child,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final r = current, colors = appColors(context);
    final actions = PopupMenuButton<String>(
      key: const ValueKey('report-actions'),
      tooltip: 'Report actions',
      enabled: !busy,
      icon: const Icon(Icons.more_vert),
      onSelected: (value) => run(() async {
        if (value == 'delete') {
          if (await widget.onDelete() && context.mounted && !widget.embedded)
            Navigator.pop(context);
        } else {
          await widget.onExport(value);
        }
      }),
      itemBuilder: (context) => appMenuEntries(context, const [
        AppMenuAction('csv', 'Export report CSV'),
        AppMenuAction('json', 'Export report JSON'),
        AppMenuAction('delete', 'Clear report', destructive: true),
      ]),
    );
    final content = SingleChildScrollView(
      padding: EdgeInsets.all(widget.embedded ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onPrint != null || widget.embedded)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onPrint != null)
                  FilledButton.icon(
                    onPressed: busy ? null : () => run(widget.onPrint!),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print report'),
                  ),
                if (widget.embedded) actions,
              ],
            ),
          const SizedBox(height: 12),
          block(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.churchName.isNotEmpty)
                  Text(
                    r.churchName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                Chip(
                  avatar: Icon(
                    r.rehearsal
                        ? Icons.fast_forward
                        : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(reportMode(r)),
                ),
                const SizedBox(height: 8),
                Text(
                  r.name,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  reportDate(r.startedWall ?? r.endedWall),
                  style: TextStyle(color: colors.muted),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 20,
                  runSpacing: 18,
                  children: [
                    reportMetric(
                      context,
                      'PLANNED',
                      durationLabel(r.plannedMs),
                    ),
                    reportMetric(
                      context,
                      'ACTUAL',
                      r.totalMs == null
                          ? 'Not recorded'
                          : durationLabel(r.totalMs!),
                    ),
                    reportMetric(
                      context,
                      'VARIANCE',
                      r.totalMs == null
                          ? '—'
                          : varianceLabel(r.totalMs! - r.plannedMs),
                      color: r.totalMs == null
                          ? colors.muted
                          : r.totalMs! - r.plannedMs > 999
                          ? colors.warning
                          : colors.success,
                    ),
                    reportMetric(
                      context,
                      'PAUSED',
                      durationLabel(r.pausedMs),
                      color: r.pausedMs == 0 ? colors.muted : null,
                    ),
                    reportMetric(
                      context,
                      'TIME ADJUSTMENTS',
                      color: r.adjustmentMs == 0 ? colors.muted : null,
                      '${r.adjustmentMs > 0
                          ? '+'
                          : r.adjustmentMs < 0
                          ? '−'
                          : ''}${durationLabel(r.adjustmentMs)}',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Started: ${r.startedWall == null ? 'not recorded' : reportDate(r.startedWall!)}\nEnded: ${reportDate(r.endedWall)}',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                if (!r.comparable)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Partial or uncertain timing. Review the breakdown before comparing this record.',
                      style: TextStyle(color: colors.warning),
                    ),
                  ),
                if (r.rehearsal)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Rehearsal durations are simulated time. Dates show real local clock time.',
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (widget.onEditReview != null) ...[
            const SizedBox(height: 20),
            ReviewNoteSection(
              review: r.review,
              busy: busy,
              onEdit: () => run(widget.onEditReview!),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Segment breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          AppMenuList(
            key: const ValueKey('report-segment-breakdown'),
            children: [
              for (var i = 0; i < r.rows.length; i++)
                ReportSegmentRow(
                  row: r.rows[i],
                  number: i + 1,
                  segment: r.program != null && i < r.program!.segments.length
                      ? r.program!.segments[i]
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 20),
          block(
            ExpansionTile(
              key: const ValueKey('report-duration-chart'),
              tilePadding: EdgeInsets.zero,
              title: const Text('The service, segment by segment'),
              subtitle: const Text('Expand chart'),
              children: [
                DurationChart(
                  entries: r.rows
                      .map(
                        (row) => DurationEntry(
                          title: row.name,
                          subtitle: row.skipped
                              ? 'Skipped'
                              : row.actualMs == null
                              ? 'Not recorded'
                              : varianceLabel(row.actualMs! - row.plannedMs),
                          planned: row.plannedMs,
                          actual: row.actualMs,
                          uncertain: r.uncertain || row.actualMs == null,
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          block(
            ExpansionTile(
              key: const ValueKey('report-activity'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Activity timeline'),
              subtitle: Text('${r.events.length} recorded events'),
              children: [
                const Text('Controller acceptance is not visual confirmation.'),
                if (r.events.isEmpty)
                  const Text(
                    'No activity events were recorded for this service.',
                  ),
                AppMenuList(
                  children: [
                    for (final event in r.events)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          event.kind == 'failed' || event.kind == 'hold'
                              ? Icons.warning_amber
                              : event.kind == 'accepted'
                              ? Icons.check_circle_outline
                              : Icons.history,
                        ),
                        title: Text(event.message),
                        subtitle: Text(
                          '${clockLabel(event.wall)}:${DateTime.fromMillisecondsSinceEpoch(event.wall).second.toString().padLeft(2, '0')}',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.embedded)
      return Material(color: colors.background, child: content);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service report'),
        actions: [actions, const SizedBox(width: 4)],
        bottom: widget.controller?.liveSession.active == true
            ? RunningServiceBar.forContext(
                context,
                controller: widget.controller!,
              )
            : null,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: content,
          ),
        ),
      ),
    );
  }
}

class ReportSegmentRow extends StatelessWidget {
  final ReportRow row;
  final int number;
  final Segment? segment;
  const ReportSegmentRow({
    super.key,
    required this.row,
    required this.number,
    this.segment,
  });
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final actual = row.skipped
        ? 'Skipped'
        : row.actualMs == null
        ? 'Not recorded'
        : durationLabel(row.actualMs!);
    final variance = row.skipped || row.actualMs == null
        ? '—'
        : varianceLabel(row.actualMs! - row.plannedMs);
    return ExpansionTile(
      tilePadding: appLayout(context).tileInsets,
      childrenPadding: appLayout(context).rowInsets,
      title: LayoutBuilder(
        builder: (context, space) => space.maxWidth < 570
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${number.toString().padLeft(2, '0')}  ${row.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Planned ${durationLabel(row.plannedMs)} · Actual $actual',
                    style: TextStyle(fontSize: 13, color: colors.muted),
                  ),
                  Text(
                    variance,
                    style: TextStyle(
                      fontSize: 13,
                      color: row.actualMs == null
                          ? colors.muted
                          : row.actualMs! > row.plannedMs
                          ? colors.warning
                          : colors.success,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      row.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  SizedBox(
                    width: 125,
                    child: Text(
                      'Planned ${durationLabel(row.plannedMs)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 135,
                    child: Text(
                      'Actual $actual',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SizedBox(
                    width: 140,
                    child: Text(variance, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paused ${durationLabel(row.pausedMs)} · Adjusted ${row.adjustmentMs > 0
                    ? '+'
                    : row.adjustmentMs < 0
                    ? '−'
                    : ''}${durationLabel(row.adjustmentMs)}',
              ),
              if (segment?.speaker.isNotEmpty == true)
                Text('Speaker: ${segment!.speaker}'),
              if (segment?.notes.isNotEmpty == true)
                Text('Private note: ${segment!.notes}'),
              if (row.actualMs == null && !row.skipped)
                const Text('This segment has no recorded duration.'),
            ],
          ),
        ),
      ],
    );
  }
}

/// After-service reflection, shown apart from the recorded timings.
class ReviewNoteSection extends StatelessWidget {
  final ReviewNote? review;
  final bool busy;
  final VoidCallback onEdit;
  const ReviewNoteSection({
    super.key,
    required this.review,
    required this.busy,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return reportSurface(
      context,
      child: Padding(
        key: const ValueKey('review-note-section'),
        padding: EdgeInsets.all(appLayout(context).panelPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rate_review_outlined, color: colors.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Review notes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (review != null)
                  TextButton(
                    key: const ValueKey('edit-review-note'),
                    onPressed: busy ? null : onEdit,
                    child: const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (review == null) ...[
              Text(
                'Add what to remember for next time, such as "Reduce welcome next week". Notes never change the recorded timings.',
                style: TextStyle(color: colors.muted),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('add-review-note'),
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('Add a review note'),
              ),
            ] else ...[
              Text(review!.text, key: const ValueKey('review-note-text')),
              const SizedBox(height: 8),
              Text(
                'Added after service · ${reportDate(review!.editedWall)}',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Edits a review note. Owns its text controller so the field stays valid
/// through the dialog's closing animation.
class ReviewNoteDialog extends StatefulWidget {
  final String? initial;
  const ReviewNoteDialog({super.key, this.initial});

  @override
  State<ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState extends State<ReviewNoteDialog> {
  late final text = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Add review note' : 'Edit review note',
    ),
    content: TextField(
      key: const ValueKey('review-note-field'),
      controller: text,
      autofocus: true,
      minLines: 3,
      maxLines: 8,
      maxLength: ReviewNote.maxLength,
      decoration: const InputDecoration(
        hintText: 'For example: Reduce welcome next week.',
      ),
    ),
    actions: [
      StackedDialogActions(
        children: [
          FilledButton(
            key: const ValueKey('save-review-note'),
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save note'),
          ),
          if (widget.initial != null)
            TextButton(
              key: const ValueKey('remove-review-note'),
              style: TextButton.styleFrom(foregroundColor: destructiveColor),
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Remove note'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ],
  );
}

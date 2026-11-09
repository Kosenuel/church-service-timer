import 'dart:async';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

extension ItemMenuViews on HomeState {
  Future<String?> itemExportFormat({bool report = false}) => showDialog<String>(
    context: context,
    animationStyle: reduceAppMotion(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (ctx) => SimpleDialog(
      title: Text(report ? 'Export report' : 'Export program'),
      contentPadding: EdgeInsets.symmetric(vertical: appLayout(ctx).gap),
      children: [
        if (report) ...[
          ListTile(
            onTap: () => Navigator.pop(ctx, 'pdf'),
            leading: const Icon(Icons.print_outlined),
            title: const Text('PDF · Print report'),
          ),
          const AppDivider(),
        ],
        ListTile(
          onTap: () => Navigator.pop(ctx, 'json'),
          leading: const Icon(Icons.data_object),
          title: const Text('JSON'),
        ),
        const AppDivider(),
        ListTile(
          onTap: () => Navigator.pop(ctx, 'csv'),
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('CSV'),
        ),
      ],
    ),
  );

  Future<void> programItemAction(Timeline program, String action) async {
    if (c.busy || c.corrupt) return;
    if (action == 'export') {
      final format = await itemExportFormat();
      if (format != null) await export(program, format);
    }
    if (action == 'delete' &&
        await ensureSettingsUnlocked(
          reason: 'Enter the Settings PIN to delete programs.',
        ) &&
        await confirm(
          'Delete program?',
          'Delete “${program.name}”? A service already running from this program stays unchanged.',
          'Delete program',
          destructive: true,
        )) {
      if (!await c.commit((draft, _) => draft.deleteTemplate(program)) &&
          mounted)
        await showError(c.error ?? 'Could not delete program.');
    }
  }

  Future<void> reportItemAction(ServiceReport report, String action) async {
    if (c.busy || c.corrupt) return;
    if (action == 'delete') {
      await confirmClearReports(record: report);
      return;
    }
    final format = await itemExportFormat(report: true);
    if (format == 'pdf') {
      await printServiceSheet(report.program, report: report);
    } else if (format != null) {
      await exportReport(report, format);
    }
  }

  Future<void> showItemActions(
    String kind,
    Future<void> Function(String) action,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final point = overlay.globalToLocal(
      menuAnchor ?? Offset(overlay.size.width / 2, overlay.size.height / 2),
    );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromSize(
        Rect.fromLTWH(point.dx, point.dy, 1, 1),
        overlay.size,
      ),
      semanticLabel: '$kind actions',
      items: appMenuEntries(context, [
        AppMenuAction('export', 'Export ${kind.toLowerCase()}'),
        AppMenuAction(
          'delete',
          'Delete ${kind.toLowerCase()}',
          destructive: true,
        ),
      ]),
    );
    if (choice != null) await action(choice);
  }

  Widget itemMenu(String kind, void Function(String) action) =>
      PopupMenuButton<String>(
        tooltip: '$kind actions',
        enabled: !c.busy && !c.corrupt,
        onSelected: action,
        itemBuilder: (ctx) => appMenuEntries(ctx, [
          AppMenuAction('export', 'Export ${kind.toLowerCase()}'),
          AppMenuAction(
            'delete',
            'Delete ${kind.toLowerCase()}',
            destructive: true,
          ),
        ]),
      );
}

import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/programs/program_history_views.dart';
import 'package:church_service_timer/programs/send_program_views.dart';
import 'package:church_service_timer/programs/segment_library_views.dart';
import 'package:church_service_timer/shared/list_views.dart';

String templateSummary(Timeline t) {
  final total = t.segments.fold<int>(
    0,
    (sum, segment) => sum + segment.durationMs,
  );
  return '${t.segments.length} ${t.segments.length == 1 ? 'segment' : 'segments'} · ${durationLabel(total)}';
}

String lastUsedLabel(int? wall) {
  if (wall == null) return 'not used yet';
  final d = DateTime.fromMillisecondsSinceEpoch(wall);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return 'last used ${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// The program rows on the desktop Programs page: no card around them.
class FlatRows extends StatelessWidget {
  final Widget child;
  const FlatRows(this.child, {super.key});
  @override
  Widget build(BuildContext context) => child;
}

/// Proportional strip of a program's segments, alternating accent shades.
class SegmentBar extends StatelessWidget {
  final Timeline program;
  final double height;
  const SegmentBar({super.key, required this.program, this.height = 6});
  @override
  Widget build(BuildContext context) {
    final accent = appColors(context).accent;
    final segments = program.segments
        .where((s) => s.durationSeconds > 0)
        .toList();
    if (segments.isEmpty) return SizedBox(height: height);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: segments[i].durationSeconds,
                  child: ColoredBox(
                    color: accent.withValues(
                      alpha: const [1.0, .6, .8, .45, .7][i % 5],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

extension TemplateViews on HomeState {
  Widget templates() {
    final items = c.state.programLibrary.find(
      c.state.templates,
      programsPage.query,
      programsPage.filter,
    );
    final disabled = c.busy || c.corrupt;
    // The desktop Programs page shows the list as a flat column, with the
    // chosen program beside it.
    final flat = programsFillWindow;
    final beside = useMasterDetail || flat;
    Widget rows(List<Timeline> values) => (flat ? FlatRows.new : flatless)(
      Column(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const AppDivider(),
            InkWell(
              key: ValueKey('template-row:${values[i].name}'),
              onTap: () {
                if (programsPage.selecting) {
                  refreshHome(
                    () => toggleExportSelection(
                      programsPage.selected,
                      values[i].id,
                    ),
                  );
                  return;
                }
                if (beside)
                  refreshHome(() => programsPage.open = values[i].name);
                else
                  openTemplate(values[i].name);
              },
              // Long-press starts selection with this program ticked; the
              // selection bar then exports, pins or deletes.
              onLongPress: disabled
                  ? null
                  : () => refreshHome(() {
                      if (!programsPage.selecting) {
                        programsPage.selecting = true;
                        programsPage.selected.clear();
                      }
                      programsPage.selected.add(values[i].id);
                    }),
              highlightColor: appColors(context).accent.withValues(alpha: .1),
              child: Container(
                color:
                    (programsPage.selecting
                        ? programsPage.selected.contains(values[i].id)
                        : beside && programsPage.open == values[i].name)
                    ? appColors(context).accent.withValues(alpha: .12)
                    : null,
                constraints: const BoxConstraints(minHeight: 72),
                padding: appLayout(context).rowInsets,
                child: Row(
                  children: [
                    if (programsPage.selecting)
                      Checkbox(
                        value: programsPage.selected.contains(values[i].id),
                        onChanged: (_) => refreshHome(
                          () => toggleExportSelection(
                            programsPage.selected,
                            values[i].id,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            values[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SegmentBar(program: values[i]),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            children: [
                              Text(
                                templateSummary(values[i]),
                                style: TextStyle(
                                  color: appColors(context).muted,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '· ${lastUsedLabel(c.state.programLibrary.recent[values[i].id])}',
                                style: TextStyle(
                                  color: appColors(context).muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Every row keeps the pin's slot, so the segment bars
                    // end at the same place whether pinned or not.
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 18,
                        child:
                            c.state.programLibrary.favourites.contains(
                              values[i].id,
                            )
                            ? Icon(
                                Icons.push_pin,
                                key: ValueKey('pinned:${values[i].name}'),
                                size: 18,
                                color: appColors(context).accent,
                                semanticLabel: 'Pinned',
                              )
                            : null,
                      ),
                    ),
                    // A chevron says "opens"; selection shows checkboxes.
                    if (!programsPage.selecting && !beside)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.chevron_right,
                          color: appColors(context).muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final children = <Widget>[
      if (programsPage.selecting)
        selectionHeader(programs: true, shown: items.map((p) => p.id).toSet())
      else
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Programs',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    programsPage.query.trim().isNotEmpty ||
                            programsPage.filter != 'all'
                        ? '${items.length} of ${c.state.templates.length} programs'
                        : '${items.length} saved',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (!programsPage.selecting) ...[
              selectToggle(programs: true),
              PopupMenuButton<bool>(
                key: const ValueKey('program-list-options'),
                icon: const Icon(Icons.tune),
                tooltip: 'Program list options',
                enabled: !disabled,
                onSelected: (value) async {
                  await c.commit((draft, _) => draft.groupTemplates = value);
                },
                itemBuilder: (ctx) => appMenuEntries(ctx, [
                  AppMenuAction(
                    false,
                    'Single list',
                    checked: !c.state.groupTemplates,
                  ),
                  AppMenuAction(
                    true,
                    'Services & rehearsals',
                    checked: c.state.groupTemplates,
                  ),
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'More program actions',
                enabled: !disabled,
                onSelected: (action) => switch (action) {
                  'import' => importFile(),
                  'segments' => openSegmentLibrary(),
                  _ => exportAllPrograms(),
                },
                itemBuilder: (ctx) => appMenuEntries(ctx, [
                  const AppMenuAction(
                    'import',
                    'Import programs (JSON or CSV)',
                  ),
                  if (c.state.templates.isNotEmpty)
                    const AppMenuAction('export', 'Export all programs'),
                  AppMenuAction(
                    'segments',
                    c.state.segmentLibrary.isEmpty
                        ? 'Segment library'
                        : 'Segment library (${c.state.segmentLibrary.length})',
                  ),
                ]),
              ),
            ],
          ],
        ),
      if (programsPage.selecting)
        programSearch()
      else ...[
        const SizedBox(height: 14),
        ReceivedProgramCards(controller: c),
        programSearch(),
        // The desktop page has no room for the hint; its Select button
        // is always in view.
        if (c.state.templates.isNotEmpty && !flat)
          listHint(
            'programs-select',
            deviceText('Tap a program to open it · press and hold to select'),
          ),
      ],
      if (items.isEmpty && c.state.templates.isEmpty)
        // Nothing saved yet: say so and offer the two ways to start.
        panel(
          child: Column(
            key: const ValueKey('programs-empty'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'No programs yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Create one, or import a program file (JSON) or spreadsheet (CSV).',
                style: TextStyle(color: appColors(context).muted),
              ),
              if (c.port.isDesktop) ...[
                const SizedBox(height: 4),
                Text(
                  'Or drop a file on the window.',
                  key: const ValueKey('programs-drop-hint'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: appColors(context).muted,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => editTemplate(),
                    icon: const Icon(Icons.add),
                    label: const Text('Create program'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => importFile(),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Import'),
                  ),
                ],
              ),
            ],
          ),
        )
      else if (items.isEmpty)
        // Programs exist but the search or filter hides them all.
        panel(
          child: Column(
            key: const ValueKey('programs-no-match'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                programsPage.query.trim().isEmpty
                    ? 'No programs in this filter.'
                    : 'No programs match “${programsPage.query.trim()}”.',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('clear-program-search'),
                onPressed: () => refreshHome(() {
                  programsPage
                    ..query = ''
                    ..filter = 'all';
                  programsPage.searchReset++;
                }),
                icon: const Icon(Icons.clear),
                label: const Text('Show all programs'),
              ),
            ],
          ),
        )
      else if (!c.state.groupTemplates)
        rows(items)
      else
        for (final type in ['service', 'rehearsal'])
          if (items.any((t) => t.type == type)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: label(type == 'service' ? 'Services' : 'Rehearsals'),
            ),
            rows(items.where((t) => t.type == type).toList()),
            const SizedBox(height: 20),
          ],
      const SizedBox(height: 88),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in children)
          // Rows and panels reach the column's edges; the rest lines up
          // with their text.
          !flat || child is FlatRows || child is AppPanel
              ? child
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: child,
                ),
      ],
    );
  }

  Widget flatless(Widget list) => panel(padding: EdgeInsets.zero, child: list);

  Future<void> openTemplate(String name) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => programDetails(name)));

  /// Pin and the ⋮ menu for one saved program, shared by the detail page
  /// and the desktop Programs page. [select] shows another program (after
  /// Duplicate); [onDeleted] runs once the program is gone.
  List<Widget> programActionButtons(
    Timeline t, {
    required ValueChanged<String> select,
    required VoidCallback onDeleted,
  }) {
    final disabled = c.busy || c.corrupt;
    final pinned = c.state.programLibrary.favourites.contains(t.id);
    Future<void> duplicate() async {
      Timeline? copy;
      final ok = await c.commit(
        (draft, _) => copy = draft.duplicateTemplate(t),
      );
      if (ok)
        select(copy!.name);
      else if (mounted)
        await showError(c.error ?? 'Could not duplicate program.');
    }

    Future<void> delete() async {
      if (!await ensureSettingsUnlocked(
        reason: 'Enter the Settings PIN to delete programs.',
      ))
        return;
      if (!await confirm(
        'Delete ${t.name}?',
        'Delete this saved program? Any loaded service and its report remain unchanged.',
        'Delete program',
        destructive: true,
      ))
        return;
      final ok = await c.commit((draft, _) => draft.deleteTemplate(t));
      if (ok && mounted) {
        onDeleted();
      } else if (mounted)
        await showError(c.error ?? 'Could not delete program.');
    }

    return [
      IconButton(
        tooltip: pinned ? 'Unpin program' : 'Pin program',
        onPressed: disabled ? null : () => toggleFavourite(t),
        icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
      ),
      PopupMenuButton<String>(
        tooltip: 'Program options',
        enabled: !disabled,
        onSelected: (action) async {
          switch (action) {
            case 'duplicate':
              await duplicate();
            case 'json':
              await export(t, 'json');
            case 'csv':
              await export(t, 'csv');
            case 'print':
              await printServiceSheet(t);
            case 'history':
              await openVersionHistory(t);
            case 'send':
              await sendProgramToPhones(t);
            case 'delete':
              await delete();
          }
        },
        itemBuilder: (ctx) => appMenuEntries(ctx, [
          const AppMenuAction('duplicate', 'Duplicate'),
          const AppMenuAction('json', 'Export JSON'),
          const AppMenuAction('csv', 'Export CSV'),
          const AppMenuAction('print', 'Print order of service'),
          // Only while a phone that can receive is connected.
          if (c.pairing.hosting && c.pairing.programRecipients.isNotEmpty)
            const AppMenuAction('send', 'Send to paired phone'),
          AppMenuAction(
            'history',
            c.state.versionsOf(t.id).isEmpty
                ? 'Version history'
                : 'Version history (${c.state.versionsOf(t.id).length})',
          ),
          const AppMenuAction('delete', 'Delete program', destructive: true),
        ]),
      ),
    ];
  }

  /// Loads [t] into Live and shows it. Disabled, with the reason, while a
  /// service is running.
  Widget loadIntoLiveButton(Timeline t, BuildContext pageContext) {
    final canLoad =
        !c.busy &&
        !c.corrupt &&
        !c.state.session.active &&
        !c.reportSavePending &&
        !controlsLocked;
    Future<void> load() async {
      try {
        c.state.templateIndex(t);
        await c.act('load', value: t);
        if (!mounted) return;
        navigatePage(0);
        if (pageContext.mounted)
          Navigator.of(pageContext).popUntil((r) => r.isFirst);
      } catch (e) {
        if (mounted) await showError('$e');
      }
    }

    return UnavailableAction(
      reason: c.state.session.active
          ? 'End the current service before loading another program.'
          : null,
      child: FilledButton.icon(
        key: const ValueKey('load-into-live'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: canLoad ? load : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Load into Live'),
      ),
    );
  }

  /// Opens [t] in the program editor; a rename is passed to [select].
  Future<void> editProgram(
    Timeline t, {
    required ValueChanged<String> select,
  }) async {
    final index = c.state.templates.indexWhere((p) => p.id == t.id);
    if (index < 0) return;
    final result = await editTemplate(index: index);
    if (result != null) select(result.name);
  }

  Widget editProgramButton(
    Timeline t, {
    required ValueChanged<String> select,
    double height = 50,
  }) => OutlinedButton.icon(
    key: const ValueKey('edit-program'),
    style: OutlinedButton.styleFrom(minimumSize: Size(0, height)),
    onPressed: c.busy || c.corrupt
        ? null
        : () => editProgram(t, select: select),
    icon: const Icon(Icons.edit_outlined),
    label: const Text('Edit program'),
  );

  /// The end screen and shared warnings lines under a program's rundown.
  String endScreenLine(Timeline t) =>
      'End screen · ${styleSummary(t.display.end).substring(t.display.end.text.length + 3)}';
  String get programWarningsLine =>
      '${plural(c.state.defaults.warnings.where((w) => w.enabled).length, 'shared warning')} apply. Edits take effect the next time you load this program; your current service stays unchanged.';

  Widget programDetails(String name, {bool embedded = false}) {
    var selectedName = name;
    return StatefulBuilder(
      builder: (pageContext, update) => AnimatedBuilder(
        animation: c,
        builder: (_, _) {
          final index = c.state.templates.indexWhere(
            (t) => t.name == selectedName,
          );
          final t = index < 0 ? null : c.state.templates[index];
          void select(String next) {
            if (embedded)
              refreshHome(() => programsPage.open = next);
            else if (pageContext.mounted)
              update(() => selectedName = next);
          }

          final colors = appColors(pageContext);
          final actions = t == null
              ? <Widget>[]
              : programActionButtons(
                  t,
                  select: select,
                  onDeleted: () {
                    if (embedded)
                      refreshHome(() => programsPage.open = null);
                    else if (pageContext.mounted)
                      Navigator.pop(pageContext);
                  },
                );
          final body = SingleChildScrollView(
            padding: EdgeInsets.all(appLayout(pageContext).panelPadding),
            child: t == null
                ? const Text(
                    'This program is no longer available. Return to Programs.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (embedded) ...actions,
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${t.type == 'rehearsal' ? 'Rehearsal' : 'Service'} · ${templateSummary(t)} · ${lastUsedLabel(c.state.programLibrary.recent[t.id])}',
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      SegmentBar(program: t, height: 10),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: loadIntoLiveButton(t, pageContext)),
                          const SizedBox(width: 10),
                          editProgramButton(t, select: select),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: label('Rundown'),
                      ),
                      const SizedBox(height: 8),
                      panel(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < t.segments.length; i++) ...[
                              if (i > 0) const AppDivider(),
                              ListTile(
                                contentPadding: appLayout(
                                  pageContext,
                                ).tileInsets,
                                leading: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: colors.accent.withValues(
                                      alpha: const [
                                        1.0,
                                        .6,
                                        .8,
                                        .45,
                                        .7,
                                      ][i % 5],
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                minLeadingWidth: 10,
                                title: Text(
                                  t.segments[i].name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle:
                                    t.segments[i].speaker.isEmpty &&
                                        t.segments[i].notes.isEmpty
                                    ? null
                                    : Text(
                                        [
                                          if (t.segments[i].speaker.isNotEmpty)
                                            t.segments[i].speaker,
                                          if (t.segments[i].notes.isNotEmpty)
                                            'Private note: ${t.segments[i].notes}',
                                        ].join('\n'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.muted,
                                        ),
                                      ),
                                trailing: Text(
                                  t.segments[i].durationText,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      panel(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          contentPadding: appLayout(pageContext).tileInsets,
                          leading: Icon(
                            Icons.flag_outlined,
                            color: colors.muted,
                          ),
                          title: Text(
                            t.display.end.text,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            endScreenLine(t),
                            style: TextStyle(fontSize: 12, color: colors.muted),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        programWarningsLine,
                        style: TextStyle(fontSize: 12, color: colors.muted),
                      ),
                    ],
                  ),
          );
          if (embedded) return Material(color: colors.surface, child: body);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Program details'),
              actions: [...actions, const SizedBox(width: 4)],
              bottom: c.liveSession.active
                  ? RunningServiceBar.forContext(context, controller: c)
                  : null,
            ),
            body: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: body,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

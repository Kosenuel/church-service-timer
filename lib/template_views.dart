import 'dart:async';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_menu.dart';
import 'running_service_bar.dart';
import 'domain.dart';
import 'main.dart';

String templateSummary(Timeline t) {
  final total = t.segments.fold<int>(
    0,
    (sum, segment) => sum + segment.durationMs,
  );
  return '${t.segments.length} ${t.segments.length == 1 ? 'segment' : 'segments'} · ${total % 60000 == 0 ? '${total ~/ 60000} min' : durationLabel(total)}';
}

extension TemplateViews on HomeState {
  Widget templates() {
    final items = c.state.programLibrary.find(
      c.state.templates,
      programQuery,
      programFilter,
    );
    final disabled = c.busy || c.corrupt;
    Widget rows(List<Timeline> values) => panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const AppDivider(),
            InkWell(
              key: ValueKey('template-row:${values[i].name}'),
              onTap: () {
                if (selectingPrograms) {
                  refreshHome(
                    () => toggleExportSelection(
                      selectedProgramExports,
                      values[i].name,
                    ),
                  );
                  return;
                }
                if (useMasterDetail)
                  refreshHome(() => selectedProgram = values[i].name);
                else
                  openTemplate(values[i].name);
              },
              onLongPress: () => showItemActions(
                'Program',
                (a) => programItemAction(values[i], a),
              ),
              child: Container(
                color: useMasterDetail && selectedProgram == values[i].name
                    ? appColors(context).accent.withValues(alpha: .12)
                    : null,
                padding: appLayout(context).rowInsets,
                child: Row(
                  children: [
                    if (selectingPrograms)
                      Checkbox(
                        value: selectedProgramExports.contains(values[i].name),
                        onChanged: (_) => refreshHome(
                          () => toggleExportSelection(
                            selectedProgramExports,
                            values[i].name,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            values[i].name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            templateSummary(values[i]),
                            style: TextStyle(
                              color: appColors(context).muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!selectingPrograms)
                      IconButton(
                        tooltip:
                            c.state.programLibrary.favourites.contains(
                              values[i].name,
                            )
                            ? 'Unpin ${values[i].name}'
                            : 'Pin ${values[i].name}',
                        onPressed: disabled
                            ? null
                            : () => toggleFavourite(values[i]),
                        icon: Icon(
                          c.state.programLibrary.favourites.contains(
                                values[i].name,
                              )
                              ? Icons.star
                              : Icons.star_border,
                          size: 20,
                        ),
                      ),
                    if (!selectingPrograms)
                      itemMenu(
                        'Program',
                        (a) => programItemAction(values[i], a),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Programs',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    programQuery.trim().isNotEmpty || programFilter != 'all'
                        ? '${items.length} of ${c.state.templates.length} programs'
                        : '${items.length} saved ${items.length == 1 ? 'program' : 'programs'}',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('new-template'),
              onPressed: disabled
                  ? null
                  : () async {
                      await editTemplate();
                    },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New program'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        programSearch(
          trailing: [
            if (!selectingPrograms) ...[
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
              selectToggle(programs: true),
            ],
          ],
        ),
        exportSelectionBar(
          programs: true,
          shown: items.map((p) => p.name).toSet(),
          showToggle: false,
        ),
        if (items.isEmpty)
          panel(
            child: const Text(
              'No matching programs. Try All or another search, create a program, or import JSON / CSV.',
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
        const SizedBox(height: 16),
        ControlGrid(
          maxColumns: 2,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('import-programs'),
              onPressed: disabled ? null : importFile,
              icon: const Icon(Icons.file_open_outlined, size: 20),
              label: const Text('Import programs', textAlign: TextAlign.center),
            ),
            OutlinedButton.icon(
              key: const ValueKey('export-programs'),
              onPressed: disabled || c.state.templates.isEmpty
                  ? null
                  : exportAllPrograms,
              icon: const Icon(Icons.ios_share, size: 20),
              label: const Text('Export all', textAlign: TextAlign.center),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'JSON or CSV',
          style: TextStyle(color: appColors(context).muted, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> openTemplate(String name) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => programDetails(name)));

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
          final disabled = c.busy || c.corrupt;
          void select(String next) {
            if (embedded)
              refreshHome(() => selectedProgram = next);
            else if (pageContext.mounted)
              update(() => selectedName = next);
          }

          final body = SingleChildScrollView(
            padding: EdgeInsets.all(appLayout(pageContext).panelPadding),
            child: t == null
                ? const Text(
                    'This program is no longer available. Return to Programs.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t.name,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${t.type == 'rehearsal' ? 'Rehearsal' : 'Service'} · ${templateSummary(t)}',
                        style: TextStyle(color: appColors(pageContext).muted),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: disabled
                                ? null
                                : () async {
                                    final result = await editTemplate(
                                      index: index,
                                    );
                                    if (result != null) select(result.name);
                                  },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit Program'),
                          ),
                          OutlinedButton.icon(
                            onPressed: disabled
                                ? null
                                : () async {
                                    Timeline? copy;
                                    final ok = await c.commit(
                                      (draft, _) =>
                                          copy = draft.duplicateTemplate(t),
                                    );
                                    if (ok)
                                      select(copy!.name);
                                    else if (mounted)
                                      await showError(
                                        c.error ??
                                            'Could not duplicate program.',
                                      );
                                  },
                            icon: const Icon(Icons.copy_outlined),
                            label: const Text('Duplicate'),
                          ),
                          OutlinedButton.icon(
                            onPressed: disabled
                                ? null
                                : () => toggleFavourite(t),
                            icon: Icon(
                              c.state.programLibrary.favourites.contains(t.name)
                                  ? Icons.star
                                  : Icons.star_border,
                            ),
                            label: Text(
                              c.state.programLibrary.favourites.contains(t.name)
                                  ? 'Unpin program'
                                  : 'Pin program',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      label('Segments'),
                      const SizedBox(height: 12),
                      panel(
                        padding: EdgeInsets.zero,
                        child: AppMenuList(
                          children: [
                            for (var i = 0; i < t.segments.length; i++)
                              ListTile(
                                leading: Text('${i + 1}'),
                                title: Text(t.segments[i].name),
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
                                      ),
                                trailing: Text(t.segments[i].durationText),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label('End screen'),
                            const SizedBox(height: 8),
                            Text(
                              t.display.end.text,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(height: 6),
                            Text(styleSummary(t.display.end)),
                            const SizedBox(height: 12),
                            Text(
                              '${c.state.defaults.warnings.where((w) => w.enabled).length} shared automatic warnings enabled',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: disabled
                                ? null
                                : () => export(t, 'json'),
                            icon: const Icon(Icons.code),
                            label: const Text('Export JSON'),
                          ),
                          OutlinedButton.icon(
                            onPressed: disabled ? null : () => export(t, 'csv'),
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Export CSV'),
                          ),
                          OutlinedButton.icon(
                            onPressed: disabled
                                ? null
                                : () => printServiceSheet(t),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Print Service'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'JSON includes speaker names and private notes. CSV contains segment names and durations only.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Edits apply the next time you load this program. Your current service stays unchanged.',
                        style: TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      const AppDivider(essential: true),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: appColors(pageContext).error,
                          ),
                          onPressed: disabled
                              ? null
                              : () async {
                                  if (!await confirm(
                                    'Delete ${t.name}?',
                                    'Delete this saved program? Any loaded service and its report remain unchanged.',
                                    'Delete program',
                                  ))
                                    return;
                                  final ok = await c.commit(
                                    (draft, _) => draft.deleteTemplate(t),
                                  );
                                  if (ok && mounted) {
                                    if (embedded)
                                      refreshHome(() => selectedProgram = null);
                                    else if (pageContext.mounted)
                                      Navigator.pop(pageContext);
                                  } else if (mounted)
                                    await showError(
                                      c.error ?? 'Could not delete program.',
                                    );
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete program'),
                        ),
                      ),
                    ],
                  ),
          );
          if (embedded)
            return Material(color: appColors(pageContext).surface, child: body);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Program details'),
              bottom: c.liveSession.active
                  ? RunningServiceBar.forContext(context, controller: c)
                  : null,
            ),
            body: SafeArea(
              child: Center(
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

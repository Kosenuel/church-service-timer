part of 'main.dart';

String templateSummary(Timeline t) =>
    '${t.segments.length} ${t.segments.length == 1 ? 'segment' : 'segments'} · ${t.segments.fold<int>(0, (sum, segment) => sum + segment.minutes)} min';

extension TemplateViews on _HomeState {
  Widget templates() {
    final items = c.state.templates;
    final disabled = c.busy || c.corrupt;
    Widget rows(List<Timeline> values) => panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            InkWell(
              key: ValueKey('template-row:${values[i].name}'),
              onTap: () => openTemplate(values[i].name),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
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
                    const SizedBox(width: 12),
                    Icon(
                      Icons.chevron_right,
                      color: appColors(context).muted,
                      size: 22,
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
                    'Templates',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${items.length} saved ${items.length == 1 ? 'template' : 'templates'}',
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
              label: const Text('New'),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<bool>(
            tooltip: 'Template list options',
            enabled: !disabled,
            initialValue: c.state.groupTemplates,
            onSelected: (value) async {
              await c.commit((draft, _) => draft.groupTemplates = value);
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                value: false,
                checked: !c.state.groupTemplates,
                child: const Text('Single list'),
              ),
              CheckedPopupMenuItem(
                value: true,
                checked: c.state.groupTemplates,
                child: const Text('Services & rehearsals'),
              ),
            ],
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'List options',
                    style: TextStyle(
                      color: appColors(context).muted,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.tune, size: 18, color: appColors(context).muted),
                ],
              ),
            ),
          ),
        ),
        if (items.isEmpty)
          panel(
            child: const Text(
              'No templates yet. Create one with New, or import a CSV or JSON file.',
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
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: disabled ? null : importFile,
            icon: const Icon(Icons.file_open_outlined, size: 20),
            label: const Text('Import CSV / JSON'),
          ),
        ),
      ],
    );
  }

  Future<void> openTemplate(String name) async {
    var selectedName = name;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (pageContext, update) => AnimatedBuilder(
            animation: c,
            builder: (_, _) {
              final index = c.state.templates.indexWhere(
                (t) => t.name == selectedName,
              );
              final t = index < 0 ? null : c.state.templates[index];
              final disabled = c.busy || c.corrupt;
              return Scaffold(
                appBar: AppBar(title: const Text('Template details')),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: t == null
                            ? const Text(
                                'This template is no longer available. Return to Templates.',
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
                                    style: TextStyle(
                                      color: appColors(context).muted,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  label('Segments'),
                                  const SizedBox(height: 12),
                                  panel(
                                    padding: EdgeInsets.zero,
                                    child: Column(
                                      children: [
                                        for (
                                          var i = 0;
                                          i < t.segments.length;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            const Divider(
                                              height: 1,
                                              indent: 16,
                                              endIndent: 16,
                                            ),
                                          Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                SizedBox(
                                                  width: 28,
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: TextStyle(
                                                      color: appColors(
                                                        context,
                                                      ).muted,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(t.segments[i].name),
                                                      if (t
                                                          .segments[i]
                                                          .speaker
                                                          .isNotEmpty)
                                                        Text(
                                                          t.segments[i].speaker,
                                                          style: TextStyle(
                                                            color: appColors(
                                                              context,
                                                            ).muted,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      if (t
                                                          .segments[i]
                                                          .notes
                                                          .isNotEmpty)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets.only(
                                                                top: 6,
                                                              ),
                                                          child: Text(
                                                            'Private note: ${t.segments[i].notes}',
                                                            style: TextStyle(
                                                              color: appColors(
                                                                context,
                                                              ).muted,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  '${t.segments[i].minutes} min',
                                                  style: TextStyle(
                                                    color: appColors(
                                                      context,
                                                    ).muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  panel(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        label('End screen'),
                                        const SizedBox(height: 8),
                                        Text(
                                          t.display.end.text,
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          styleSummary(t.display.end),
                                          style: TextStyle(
                                            color: appColors(context).muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          '${c.state.defaults.warnings.where((w) => w.enabled).length} shared automatic warnings enabled',
                                          style: TextStyle(
                                            color: appColors(context).muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: disabled
                                            ? null
                                            : () async {
                                                final result =
                                                    await editTemplate(
                                                      index: index,
                                                    );
                                                if (result != null &&
                                                    pageContext.mounted)
                                                  update(
                                                    () => selectedName =
                                                        result.name,
                                                  );
                                              },
                                        icon: const Icon(Icons.edit_outlined),
                                        label: const Text('Edit template'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: disabled
                                            ? null
                                            : () async {
                                                Timeline? copy;
                                                final ok = await c.commit(
                                                  (draft, _) => copy = draft
                                                      .duplicateTemplate(t),
                                                );
                                                if (ok && pageContext.mounted) {
                                                  update(
                                                    () => selectedName =
                                                        copy!.name,
                                                  );
                                                } else if (!ok && mounted) {
                                                  await showError(
                                                    c.error ??
                                                        'The duplicate could not be saved.',
                                                  );
                                                }
                                              },
                                        icon: const Icon(Icons.copy_outlined),
                                        label: const Text('Duplicate'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: disabled
                                            ? null
                                            : () => export(t, 'json'),
                                        icon: const Icon(Icons.ios_share),
                                        label: const Text('Export JSON'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: disabled
                                            ? null
                                            : () => export(t, 'csv'),
                                        icon: const Icon(Icons.ios_share),
                                        label: const Text('Export CSV'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: disabled
                                            ? null
                                            : () => printServiceSheet(t),
                                        icon: const Icon(Icons.print_outlined),
                                        label: const Text(
                                          'Print service sheet',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'JSON includes speaker names and private notes. CSV contains segment names and durations only.',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 16),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: appColors(
                                          context,
                                        ).error,
                                      ),
                                      onPressed: disabled
                                          ? null
                                          : () async {
                                              if (!await confirm(
                                                'Delete ${t.name}?',
                                                'Delete this saved template? Any loaded service and its report remain unchanged.',
                                                'Delete template',
                                              ))
                                                return;
                                              final ok = await c.commit(
                                                (draft, _) =>
                                                    draft.deleteTemplate(t),
                                              );
                                              if (ok) {
                                                if (pageContext.mounted)
                                                  Navigator.pop(pageContext);
                                              } else if (mounted) {
                                                await showError(
                                                  c.error ??
                                                      'The template could not be deleted.',
                                                );
                                              }
                                            },
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Delete template'),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Edits apply the next time you load this template. Your current service stays unchanged.',
                                    style: TextStyle(
                                      color: appColors(context).muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

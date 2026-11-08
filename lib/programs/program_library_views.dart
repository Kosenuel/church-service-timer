import 'dart:async';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';

class ProgramChooser extends StatefulWidget {
  final AppController controller;
  final VoidCallback onCreate;

  /// The program already in Ready, when changing it; shown as loaded.
  final String? current;
  const ProgramChooser({
    super.key,
    required this.controller,
    required this.onCreate,
    this.current,
  });
  @override
  State<ProgramChooser> createState() => _ProgramChooserState();
}

class _ProgramChooserState extends State<ProgramChooser> {
  String query = '', filter = 'all';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final programs = c.state.programLibrary.find(
        c.state.templates,
        query,
        filter,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.current == null
                ? 'Choose a program to load into Ready. Timing begins only when you start the first segment.'
                : 'Switch the program in Ready. The start time and service mode stay; timing begins only when you start the first segment.',
          ),
          SizedBox(height: appLayout(context).gap),
          TextField(
            key: const ValueKey('start-program-search'),
            decoration: const InputDecoration(
              labelText: 'Search programs',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 8),
          ProgramFilters(
            value: filter,
            onChanged: (v) => setState(() => filter = v),
          ),
          const SizedBox(height: 8),
          AppMenuList(
            key: const ValueKey('start-service-programs'),
            children: [
              for (final p in programs)
                ListTile(
                  key: ValueKey('start-program:${p.name}'),
                  title: Text(p.name),
                  subtitle: Text(
                    p.name == widget.current
                        ? 'Loaded · ${templateSummary(p)}'
                        : templateSummary(p),
                  ),
                  leading: c.state.programLibrary.favourites.contains(p.id)
                      ? const Icon(Icons.push_pin, semanticLabel: 'Pinned')
                      : null,
                  trailing: Icon(
                    p.name == widget.current
                        ? Icons.check
                        : Icons.chevron_right,
                  ),
                  onTap: c.busy || p.name == widget.current
                      ? null
                      : () => Navigator.pop(context, p),
                ),
            ],
          ),
          if (programs.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No programs match. Try All or another search.'),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Create Program'),
          ),
        ],
      );
    },
  );
}

class ProgramFilters extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const ProgramFilters({
    super.key,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final e in {
        'all': 'All',
        'favourites': 'Pinned',
        'recent': 'Recent',
        'rehearsal': 'Rehearsals',
      }.entries)
        ChoiceChip(
          label: Text(e.value),
          selected: value == e.key,
          onSelected: (_) => onChanged(e.key),
        ),
    ],
  );
}

extension ProgramLibraryViews on HomeState {
  Future<void> toggleFavourite(Timeline p) async {
    final ok = await c.commit((draft, _) {
      draft.templateIndex(p);
      if (!draft.programLibrary.favourites.remove(p.id))
        draft.programLibrary.favourites.add(p.id);
    });
    if (!ok && mounted) await showError(c.error ?? 'Could not save favourite.');
  }

  Widget programSearch({List<Widget> trailing = const []}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: const ValueKey('program-search'),
        initialValue: programsPage.query,
        decoration: const InputDecoration(
          labelText: 'Search programs',
          hintText: 'Search programs, segments or speakers',
          floatingLabelBehavior: FloatingLabelBehavior.never,
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => refreshHome(() => programsPage.query = v),
      ),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ProgramFilters(
                value: programsPage.filter,
                onChanged: (v) => refreshHome(() => programsPage.filter = v),
              ),
            ),
          ),
          ...trailing,
        ],
      ),
      const SizedBox(height: 12),
    ],
  );

  Widget programsResponsive() => !useMasterDetail
      ? templates()
      : masterDetail(
          templates(),
          !c.state.programLibrary
                  .find(
                    c.state.templates,
                    programsPage.query,
                    programsPage.filter,
                  )
                  .any((p) => p.name == programsPage.open)
              ? panel(
                  child: const Center(
                    child: Text('Select a program to view its details.'),
                  ),
                )
              : programDetails(programsPage.open!, embedded: true),
        );
}

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/choice_field.dart';
import 'package:church_service_timer/programs/program_views.dart'
    show templateSummary;
import 'package:flutter/material.dart';

/// Spreadsheet column letters: A, B … Z, AA.
String columnLetter(int i) => i < 26
    ? String.fromCharCode(65 + i)
    : '${columnLetter(i ~/ 26 - 1)}${columnLetter(i % 26)}';

/// Lets the person say which column of someone else's spreadsheet holds
/// the segment name, duration, speaker, notes and program. Returns the
/// programs for the usual import review, or null when cancelled.
class ImportMappingPage extends StatefulWidget {
  final AppController controller;
  final List<List<String>> rows;
  final String fileName;
  const ImportMappingPage({
    super.key,
    required this.controller,
    required this.rows,
    required this.fileName,
  });
  @override
  State<ImportMappingPage> createState() => _ImportMappingPageState();
}

class _ImportMappingPageState extends State<ImportMappingPage> {
  late ColumnMapping mapping;
  late final TextEditingController programName;
  bool remembered = false;

  List<String> get header => widget.rows.first;
  int get width => widget.rows.fold(0, (n, r) => r.length > n ? r.length : n);

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.state.rememberedMapping(header);
    remembered = saved != null;
    mapping = saved ?? guessMapping(widget.rows);
    final base = widget.fileName.replaceFirst(RegExp(r'\.[^.]+$'), '').trim();
    programName = TextEditingController(
      text: base.isEmpty
          ? 'Imported program'
          : String.fromCharCodes(base.runes.take(80)),
    );
  }

  @override
  void dispose() {
    programName.dispose();
    super.dispose();
  }

  String columnTitle(int i) {
    final title = mapping.headerRow && i < header.length ? header[i] : '';
    final sample = widget.rows
        .skip(mapping.headerRow ? 1 : 0)
        .map((r) => i < r.length ? r[i] : '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    return [
      'Column ${columnLetter(i)}',
      if (title.isNotEmpty) title else if (sample.isNotEmpty) 'e.g. $sample',
    ].join(' · ');
  }

  Widget column(
    String label,
    int? value,
    void Function(int?) set, {
    bool optional = false,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ChoiceField<int>(
      key: key,
      value: value ?? -1,
      decoration: InputDecoration(labelText: label),
      options: [
        ChoiceOption(value: -1, label: optional ? 'None' : 'Choose a column'),
        for (var i = 0; i < width; i++)
          ChoiceOption(value: i, label: columnTitle(i)),
      ],
      onChanged: (v) => setState(() => set(v == null || v < 0 ? null : v)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final name = programName.text.trim().isEmpty
        ? 'Imported program'
        : programName.text.trim();
    final result = applyMapping(widget.rows, mapping, programName: name);
    final preview = widget.rows.take(6).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Match spreadsheet columns')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              remembered
                  ? 'This layout was used before, so its columns are already chosen. Check the preview, then continue.'
                  : '“${widget.fileName}” uses its own column names. Tell the app which column is which; the choice is remembered for the next sheet laid out the same way.',
              style: TextStyle(color: colors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            // The sheet as it is, so columns can be recognised by eye.
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  key: const ValueKey('mapping-preview'),
                  headingRowHeight: 32,
                  dataRowMinHeight: 30,
                  dataRowMaxHeight: 36,
                  columnSpacing: 18,
                  columns: [
                    for (var i = 0; i < width; i++)
                      DataColumn(
                        label: Text(
                          columnLetter(i),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                  rows: [
                    for (final r in preview)
                      DataRow(
                        cells: [
                          for (var i = 0; i < width; i++)
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Text(
                                  i < r.length ? r[i] : '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            SwitchListTile(
              key: const ValueKey('mapping-header-row'),
              contentPadding: EdgeInsets.zero,
              title: const Text('First row is column titles'),
              value: mapping.headerRow,
              onChanged: (v) =>
                  setState(() => mapping = mapping.copyWith(headerRow: v)),
            ),
            const SizedBox(height: 8),
            column(
              'Segment name',
              mapping.name,
              (v) => mapping = mapping.copyWith(name: () => v),
              key: const ValueKey('map-name'),
            ),
            column(
              'Duration',
              mapping.duration,
              (v) => mapping = mapping.copyWith(duration: () => v),
              key: const ValueKey('map-duration'),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ChoiceField<DurationFormat>(
                value: mapping.format,
                decoration: const InputDecoration(
                  labelText: 'Durations are written as',
                ),
                options: [
                  for (final f in DurationFormat.values)
                    ChoiceOption(value: f, label: f.label),
                ],
                onChanged: (v) =>
                    setState(() => mapping = mapping.copyWith(format: v)),
              ),
            ),
            column(
              'Speaker (optional)',
              mapping.speaker,
              (v) => mapping = mapping.copyWith(speaker: () => v),
              optional: true,
            ),
            column(
              'Private operator notes (optional)',
              mapping.notes,
              (v) => mapping = mapping.copyWith(notes: () => v),
              optional: true,
            ),
            column(
              'Program name column (optional, for several programs)',
              mapping.program,
              (v) => mapping = mapping.copyWith(program: () => v),
              optional: true,
            ),
            if (mapping.program == null)
              TextField(
                key: const ValueKey('mapping-program-name'),
                controller: programName,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Program name'),
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('mapping-result'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (result.errors.isEmpty ? colors.accent : colors.warning)
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: result.errors.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.errors.length == 1
                              ? 'Fix this before importing:'
                              : 'Fix these ${result.errors.length} problems before importing:',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        for (final e in result.errors.take(6)) Text('• $e'),
                        if (result.errors.length > 6)
                          Text('… and ${result.errors.length - 6} more'),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final p in result.programs) ...[
                          Text(
                            '${p.name} · ${templateSummary(p)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          for (final s in p.segments.take(6))
                            Text(
                              '${s.durationText} · ${s.name}${s.speaker.isEmpty ? '' : ' · ${s.speaker}'}',
                            ),
                          if (p.segments.length > 6)
                            Text('… and ${p.segments.length - 6} more'),
                          const SizedBox(height: 6),
                        ],
                        if (result.skipped > 0)
                          Text(
                            '${result.skipped} empty row${result.skipped == 1 ? '' : 's'} left out.',
                            style: TextStyle(color: colors.muted),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('mapping-continue'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: result.errors.isNotEmpty || result.programs.isEmpty
                  ? null
                  : () async {
                      final c = widget.controller;
                      await c.commit(
                        (draft, _) => draft.rememberMapping(header, mapping),
                      );
                      if (context.mounted)
                        Navigator.pop(context, result.programs);
                    },
              child: const Text('Continue to review'),
            ),
          ],
        ),
      ),
    );
  }
}

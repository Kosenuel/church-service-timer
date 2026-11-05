import 'dart:convert';
import 'package:church_service_timer/domain/domain.dart';

void validateProgramDuration(Timeline program) {
  for (final segment in program.segments) {
    require(
      segment.durationMs > 0 && segment.durationMs <= supportedCountdownMs,
      '${segment.name}: use a duration from 00:01 to 59:59. Edit older longer segments before starting.',
    );
  }
}

Timeline programWithoutNotes(Timeline program) => Timeline(
  program.name,
  [
    for (final s in program.segments)
      Segment(
        s.name,
        s.minutes,
        seconds: s.seconds,
        speaker: s.speaker,
        protected: s.protected,
      ),
  ],
  program.display,
  type: program.type,
);

String exportProgramsJson(
  List<Timeline> programs, {
  bool privateNotes = false,
}) => const JsonEncoder.withIndent('  ').convert({
  'type': 'church-service-timer-programs',
  'schemaVersion': 1,
  'programs': [
    for (final p in programs)
      (privateNotes ? p : programWithoutNotes(p)).toJson(),
  ],
});

String exportProgramsCsv(List<Timeline> programs, {bool privateNotes = false}) {
  final rows = <String>[
    'Program,Type,Segment number,Segment Name,Duration (Seconds),Speaker,Protected${privateNotes ? ',Private notes' : ''}',
  ];
  for (final p in programs) {
    for (final e in p.segments.asMap().entries) {
      final s = e.value;
      rows.add(
        [
          reportCsvText(p.name),
          p.type,
          '${e.key + 1}',
          reportCsvText(s.name),
          '${s.durationSeconds}',
          reportCsvText(s.speaker),
          '${s.protected}',
          if (privateNotes) reportCsvText(s.notes),
        ].join(','),
      );
    }
  }
  return '${rows.join('\r\n')}\r\n';
}

/// A complete import candidate; callers must review names before one atomic save.
List<Timeline> importPrograms(
  String raw,
  String filename,
  DisplaySettings defaults,
) {
  require(
    utf8.encode(raw).length <= backupLimitBytes,
    'Program bundle exceeds 16 MiB.',
  );
  List<Timeline> programs;
  if (filename.toLowerCase().endsWith('.json')) {
    final j = Map<String, dynamic>.from(
      jsonDecode(raw.replaceFirst('\uFEFF', '')),
    );
    if (j['type'] != 'church-service-timer-programs')
      return [importTemplate(raw, filename, defaults)];
    keys(j, {'type', 'schemaVersion', 'programs'}, 'Program bundle');
    require(
      j['schemaVersion'] == 1 && j['programs'] is List,
      'Unsupported program bundle.',
    );
    programs = [
      for (final p in j['programs'])
        Timeline.fromJson(Map<String, dynamic>.from(p)),
    ];
  } else {
    final rows = parseCsv(
      raw.replaceFirst('\uFEFF', ''),
    ).where((r) => r.any((v) => v.trim().isNotEmpty)).toList();
    if (rows.isEmpty || !rows.first.contains('Program'))
      return [importTemplate(raw, filename, defaults)];
    final header = rows.first;
    for (final col in [
      'Program',
      'Type',
      'Segment number',
      'Segment Name',
      'Duration (Seconds)',
      'Speaker',
      'Protected',
    ]) {
      require(
        header.where((v) => v == col).length == 1,
        'Missing or duplicate column: $col.',
      );
    }
    final groups = <String, List<Segment>>{}, types = <String, String>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      require(
        row.length == header.length,
        'Row ${i + 1}: incorrect column count.',
      );
      String get(String name) {
        final index = header.indexOf(name);
        return index < 0 ? '' : row[index];
      }

      // Undo only our spreadsheet-formula guard, never strip ordinary apostrophes.
      String text(String name) {
        final v = get(name);
        return RegExp(r"^'\s*[=+@\-]").hasMatch(v) ? v.substring(1) : v;
      }

      final name = nameValue(text('Program'), 'Program name'),
          type = get('Type');
      require(
        {'service', 'rehearsal'}.contains(type),
        'Row ${i + 1}: invalid program type.',
      );
      require(
        types[name] == null || types[name] == type,
        'Program type changes within $name.',
      );
      types[name] = type;
      final list = groups.putIfAbsent(name, () => []),
          seconds = int.tryParse(get('Duration (Seconds)'));
      require(
        int.tryParse(get('Segment number')) == list.length + 1,
        'Segments in $name must be ordered from 1.',
      );
      require(
        seconds != null && seconds > 0 && seconds <= 3599,
        'Row ${i + 1}: use 1–3599 seconds.',
      );
      require(
        {'true', 'false'}.contains(get('Protected')),
        'Row ${i + 1}: Protected must be true or false.',
      );
      list.add(
        Segment.fromJson({
          'name': text('Segment Name'),
          'minutes': seconds! ~/ 60,
          'seconds': seconds % 60,
          'speaker': text('Speaker'),
          'notes': text('Private notes'),
          'protected': get('Protected') == 'true',
        }),
      );
    }
    programs = [
      for (final e in groups.entries)
        Timeline(e.key, e.value, defaults, type: types[e.key]!),
    ];
  }
  require(
    programs.isNotEmpty && programs.length <= 200,
    'Import 1–200 programs at a time.',
  );
  require(
    programs.map((p) => p.name.toLowerCase()).toSet().length == programs.length,
    'Bundle contains duplicate program names.',
  );
  for (final p in programs) {
    require(
      p.segments.isNotEmpty && p.segments.length <= 200,
      'A program needs 1–200 segments.',
    );
    validateProgramDuration(p);
  }
  return [
    for (final p in programs)
      p.withDisplay(
        p.display.withZero(defaults.zero).withWarnings(defaults.warnings),
      ),
  ];
}

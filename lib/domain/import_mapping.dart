import 'package:church_service_timer/domain/domain.dart';

/// How a duration cell is written in someone else's spreadsheet.
enum DurationFormat {
  auto('Detect automatically'),
  minutes('Minutes (5 or 5.5)'),
  clock('Minutes:seconds (05:30)'),
  seconds('Seconds (330)');

  final String label;
  const DurationFormat(this.label);
}

/// Which spreadsheet column holds what. Columns are 0-based; null means
/// the spreadsheet has no such column.
class ColumnMapping {
  final int? name, duration, speaker, notes, program;
  final DurationFormat format;

  /// The first non-blank row holds column titles, not a segment.
  final bool headerRow;
  const ColumnMapping({
    this.name,
    this.duration,
    this.speaker,
    this.notes,
    this.program,
    this.format = DurationFormat.auto,
    this.headerRow = true,
  });

  ColumnMapping copyWith({
    int? Function()? name,
    int? Function()? duration,
    int? Function()? speaker,
    int? Function()? notes,
    int? Function()? program,
    DurationFormat? format,
    bool? headerRow,
  }) => ColumnMapping(
    name: name == null ? this.name : name(),
    duration: duration == null ? this.duration : duration(),
    speaker: speaker == null ? this.speaker : speaker(),
    notes: notes == null ? this.notes : notes(),
    program: program == null ? this.program : program(),
    format: format ?? this.format,
    headerRow: headerRow ?? this.headerRow,
  );

  bool get complete => name != null && duration != null;

  Json toJson() => {
    'name': name,
    'duration': duration,
    'speaker': speaker,
    'notes': notes,
    'program': program,
    'format': format.name,
    'headerRow': headerRow,
  };

  factory ColumnMapping.fromJson(Json j) {
    int? col(String k) {
      final v = j[k];
      return v is int && v >= 0 && v < 100 ? v : null;
    }

    return ColumnMapping(
      name: col('name'),
      duration: col('duration'),
      speaker: col('speaker'),
      notes: col('notes'),
      program: col('program'),
      format:
          DurationFormat.values
              .where((f) => f.name == j['format'])
              .firstOrNull ??
          DurationFormat.auto,
      headerRow: j['headerRow'] != false,
    );
  }
}

/// How many spreadsheet layouts are remembered.
const importMappingLimit = 20;

extension ImportMappings on AppState {
  ColumnMapping? rememberedMapping(List<String> header) {
    final j = importMappings[headerSignature(header)];
    return j == null ? null : ColumnMapping.fromJson(j);
  }

  /// Remembers [mapping] for this layout, newest kept, oldest dropped.
  void rememberMapping(List<String> header, ColumnMapping mapping) {
    final key = headerSignature(header);
    importMappings
      ..remove(key)
      ..[key] = mapping.toJson();
    while (importMappings.length > importMappingLimit) {
      importMappings.remove(importMappings.keys.first);
    }
  }
}

/// The spreadsheet's non-blank rows, trimmed.
List<List<String>> spreadsheetRows(String raw) => [
  for (final r in parseCsv(raw.replaceFirst('﻿', '')))
    if (r.any((v) => v.trim().isNotEmpty)) [for (final v in r) v.trim()],
];

/// Whether the app's own CSV formats can read these rows without help.
bool isStandardProgramCsv(List<List<String>> rows) {
  if (rows.isEmpty) return true;
  final h = rows.first;
  return (h.contains('Segment Name') && h.contains('Duration (Minutes)')) ||
      (h.contains('Program') && h.contains('Segment Name'));
}

/// A stable key for a header row, so a mapping chosen once is offered
/// again for the next spreadsheet laid out the same way.
String headerSignature(List<String> header) =>
    header.map((v) => v.toLowerCase().trim()).join('|');

const _nameWords = [
  'segment',
  'item',
  'activity',
  'title',
  'name',
  'order',
  'part',
  'event',
  'programme item',
];
const _durationWords = [
  'duration',
  'minutes',
  'mins',
  'min',
  'length',
  'time',
  'allotted',
];
const _speakerWords = [
  'speaker',
  'leader',
  'minister',
  'presenter',
  'person',
  'who',
  'by',
  'responsible',
];
const _notesWords = ['note', 'comment', 'remark', 'detail', 'instruction'];
const _programWords = ['program', 'programme', 'service', 'event name'];

/// Guesses a mapping from column titles, then from the values themselves.
ColumnMapping guessMapping(List<List<String>> rows) {
  if (rows.isEmpty) return const ColumnMapping();
  final header = [for (final v in rows.first) v.toLowerCase()];
  final taken = <int>{};
  int? find(List<String> words, {bool Function(int)? also}) {
    for (final w in words) {
      for (var i = 0; i < header.length; i++) {
        if (taken.contains(i)) continue;
        if (RegExp('\\b${RegExp.escape(w)}').hasMatch(header[i]) &&
            (also == null || also(i))) {
          taken.add(i);
          return i;
        }
      }
    }
    return null;
  }

  final body = rows.skip(1).take(20).toList();
  bool looksLikeDurations(int i) =>
      body.isNotEmpty &&
      body.where((r) => i < r.length && parseDuration(r[i]) != null).length >=
          (body.length / 2).ceil();
  // Duration first: "Time" or "Minutes" must not be taken as a name.
  final duration = find(_durationWords, also: looksLikeDurations);
  final program = find(_programWords);
  final name = find(_nameWords);
  final speaker = find(_speakerWords);
  final notes = find(_notesWords);
  final headerRow =
      duration == null ||
      !looksLikeDurations(duration) ||
      parseDuration(rows.first[duration]) == null;
  if (name != null || duration != null) {
    return ColumnMapping(
      name: name,
      duration: duration,
      speaker: speaker,
      notes: notes,
      program: program,
      headerRow: headerRow,
    );
  }
  // No useful titles: take the first text column and the first duration-like
  // column from the values.
  final width = rows.fold(0, (n, r) => r.length > n ? r.length : n);
  int? durationByValue, nameByValue;
  final sample = rows.take(20).toList();
  for (var i = 0; i < width; i++) {
    final values = [
      for (final r in sample)
        if (i < r.length && r[i].isNotEmpty) r[i],
    ];
    if (values.isEmpty) continue;
    final timed = values.where((v) => parseDuration(v) != null).length;
    if (durationByValue == null && timed >= (values.length * .8)) {
      durationByValue = i;
    } else if (nameByValue == null && timed < values.length / 2) {
      nameByValue = i;
    }
  }
  return ColumnMapping(
    name: nameByValue,
    duration: durationByValue,
    headerRow: false,
  );
}

/// Reads a duration cell as seconds, or null when it is not a duration.
/// Accepts 5, 5.5, "5 min", "5m 30s", "90s", "05:30" and "1:05:30".
int? parseDuration(String cell, [DurationFormat format = DurationFormat.auto]) {
  final v = cell.trim().toLowerCase().replaceAll(',', '.');
  if (v.isEmpty) return null;
  int? whole(double minutes) {
    final s = (minutes * 60).round();
    return s > 0 ? s : null;
  }

  final clock = RegExp(r'^(?:(\d{1,2}):)?(\d{1,3}):(\d{2})$').firstMatch(v);
  final number = double.tryParse(v);
  switch (format) {
    case DurationFormat.minutes:
      return number == null ? null : whole(number);
    case DurationFormat.seconds:
      return number == null || number < 1 ? null : number.round();
    case DurationFormat.clock:
      if (clock == null) return null;
    case DurationFormat.auto:
      break;
  }
  if (clock != null) {
    final h = int.parse(clock.group(1) ?? '0');
    final m = int.parse(clock.group(2)!);
    final s = int.parse(clock.group(3)!);
    if (s > 59) return null;
    // "1:05:30" is h:mm:ss; "05:30" is mm:ss.
    final total = h * 3600 + m * 60 + s;
    return total > 0 ? total : null;
  }
  if (number != null) return whole(number);
  final units = RegExp(
    r'^(?:(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hours?))?\s*(?:(\d+(?:\.\d+)?)\s*(?:m|min|mins|minutes?))?\s*(?:(\d+)\s*(?:s|sec|secs|seconds?))?$',
  ).firstMatch(v);
  if (units == null ||
      (units.group(1) ?? units.group(2) ?? units.group(3)) == null)
    return null;
  final total =
      (double.parse(units.group(1) ?? '0') * 3600 +
              double.parse(units.group(2) ?? '0') * 60 +
              int.parse(units.group(3) ?? '0'))
          .round();
  return total > 0 ? total : null;
}

class MappedImport {
  final List<Timeline> programs;

  /// Problems by spreadsheet row (1-based, as the spreadsheet numbers it).
  final List<String> errors;

  /// Rows left out because both name and duration were empty.
  final int skipped;
  const MappedImport(this.programs, this.errors, this.skipped);
}

/// Builds programs from [rows] with [mapping]. Every row with a name or a
/// duration must be valid, so nothing is half-imported.
MappedImport applyMapping(
  List<List<String>> rows,
  ColumnMapping mapping, {
  required String programName,
}) {
  final errors = <String>[];
  if (!mapping.complete) {
    return const MappedImport([], ['Choose the name and duration columns.'], 0);
  }
  String cell(List<String> r, int? i) => i == null || i >= r.length ? '' : r[i];
  final groups = <String, List<Segment>>{};
  var skipped = 0;
  for (var i = mapping.headerRow ? 1 : 0; i < rows.length; i++) {
    final r = rows[i];
    final name = cell(r, mapping.name), time = cell(r, mapping.duration);
    if (name.isEmpty && time.isEmpty) {
      skipped++;
      continue;
    }
    final row = 'Row ${i + 1}';
    final seconds = parseDuration(time, mapping.format);
    if (name.isEmpty) {
      errors.add('$row: no segment name.');
      continue;
    }
    if (seconds == null) {
      errors.add('$row: “$time” is not a duration.');
      continue;
    }
    if (seconds > 59 * 60 + 59) {
      errors.add('$row: “$name” is longer than 59:59.');
      continue;
    }
    try {
      final segment = Segment.fromJson({
        'name': name,
        'minutes': seconds ~/ 60,
        'seconds': seconds % 60,
        'speaker': cell(r, mapping.speaker),
        'notes': cell(r, mapping.notes),
      });
      final program = mapping.program == null
          ? programName
          : (cell(r, mapping.program).isEmpty
                ? programName
                : cell(r, mapping.program));
      (groups[program] ??= []).add(segment);
    } catch (e) {
      errors.add('$row: $e');
    }
  }
  final programs = <Timeline>[];
  for (final e in groups.entries) {
    try {
      final t = Timeline(
        nameValue(e.key, 'Program name'),
        e.value,
        DisplaySettings(),
      );
      require(
        t.segments.length <= 200,
        '“${e.key}” has more than 200 segments.',
      );
      validateProgramDuration(t);
      programs.add(t);
    } catch (err) {
      errors.add('$err');
    }
  }
  if (programs.isEmpty && errors.isEmpty) errors.add('No segments were found.');
  return MappedImport(errors.isEmpty ? programs : const [], errors, skipped);
}

/// Program files: JSON and CSV export, CSV parsing and import.
library;

import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';

String exportJson(Timeline t) =>
    const JsonEncoder.withIndent('  ').convert(portableProgram(t.toJson()));

/// Program JSON for other phones and backups: without this phone's program
/// ID, which earlier versions do not accept.
Json portableProgram(Json program) => Map.of(program)..remove('id');
String exportCsv(Timeline t) {
  final precise = t.segments.any((s) => s.seconds != 0);
  String field(String s) => '"${s.replaceAll('"', '""')}"';
  return 'Segment Name,Duration (Minutes)${precise ? ',Seconds' : ''}\r\n${t.segments.map((s) => '${field(s.name)},${s.minutes}${precise ? ',${s.seconds}' : ''}').join('\r\n')}\r\n';
}

List<List<String>> parseCsv(String raw) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  var closed = false;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < raw.length && raw[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      require(
        field.isEmpty && !closed,
        'Malformed CSV quoting near row ${rows.length + 1}.',
      );
      quoted = true;
    } else if (c == ',' || c == '\n' || c == '\r') {
      row.add(field.toString());
      field = StringBuffer();
      closed = false;
      if (c != ',') {
        rows.add(row);
        row = [];
        if (c == '\r' && i + 1 < raw.length && raw[i + 1] == '\n') i++;
      }
    } else {
      require(!closed, 'Unexpected text after a quoted CSV field.');
      field.write(c);
    }
  }
  require(!quoted, 'CSV contains an unclosed quote.');
  if (field.isNotEmpty || row.isNotEmpty || closed) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

Timeline importTemplate(
  String content,
  String filename,
  DisplaySettings defaults,
) {
  require(utf8.encode(content).length <= 1048576, 'Import exceeds 1 MiB.');
  final raw = content.startsWith('\uFEFF') ? content.substring(1) : content;
  if (filename.toLowerCase().endsWith('.json')) {
    try {
      final t = Timeline.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
      return t.withDisplay(
        t.display.withZero(defaults.zero).withWarnings(defaults.warnings),
      );
    } on RuleError {
      rethrow;
    } catch (_) {
      throw RuleError(
        'Invalid JSON structure. Select a version 1, 2 or 3 program file.',
      );
    }
  }
  require(
    filename.toLowerCase().endsWith('.csv'),
    'Choose CSV or JSON. Export Excel files as CSV first.',
  );
  final rows = parseCsv(raw);
  final nonblank = rows
      .asMap()
      .entries
      .where((e) => e.value.any((v) => v.trim().isNotEmpty))
      .toList();
  require(nonblank.isNotEmpty, 'The CSV is empty.');
  final header = nonblank.first.value.map((v) => v.trim()).toList();
  require(
    header.where((h) => h == 'Segment Name').length == 1 &&
        header.where((h) => h == 'Duration (Minutes)').length == 1,
    'Required CSV columns: Segment Name,Duration (Minutes).',
  );
  final ni = header.indexOf('Segment Name'),
      di = header.indexOf('Duration (Minutes)');
  final segs = <Segment>[];
  final errors = <String>[];
  for (final row in nonblank.skip(1)) {
    try {
      require(
        row.value.length == header.length,
        'Column count does not match the header.',
      );
      final value = row.value[di].trim();
      require(
        RegExp(r'^\d+$').hasMatch(value),
        'Duration must be an integer from 1 to 99.',
      );
      segs.add(
        Segment.fromJson({
          'name': row.value[ni],
          'minutes': int.tryParse(value),
          'seconds': header.contains('Seconds')
              ? int.tryParse(row.value[header.indexOf('Seconds')])
              : 0,
        }),
      );
    } catch (e) {
      errors.add('Row ${row.key + 1}: $e');
    }
  }
  require(
    errors.isEmpty,
    '${errors.join('\n')}\nNothing was imported. Correct the file and select it again.',
  );
  require(
    segs.isNotEmpty && segs.length <= 200,
    'Import must contain 1–200 segments.',
  );
  return Timeline(
    nameValue(filename.replaceFirst(RegExp(r'\.[^.]+$'), ''), 'Program name'),
    segs,
    DisplaySettings.fromJson(defaults.toJson()),
  );
}

/// Segments, program IDs and programs (timelines).
library;

import 'dart:math' as math;

import 'package:church_service_timer/domain/domain.dart';

class Segment {
  final String name, speaker, notes;
  final int minutes;
  final int seconds;
  int get durationSeconds => minutes * 60 + seconds;
  int get durationMs => durationSeconds * 1000;
  String get durationText => durationLabel(durationMs);
  final bool protected;
  const Segment(
    this.name,
    this.minutes, {
    this.seconds = 0,
    this.speaker = '',
    this.notes = '',
    this.protected = false,
  });
  factory Segment.fromJson(Json j) {
    keys(j, {
      'name',
      'minutes',
      'seconds',
      'speaker',
      'notes',
      'protected',
    }, 'Segment');
    require(
      j['minutes'] is int &&
          j['minutes'] >= 0 &&
          j['minutes'] <= 99 &&
          (j['seconds'] ?? 0) is int &&
          (j['seconds'] ?? 0) >= 0 &&
          (j['seconds'] ?? 0) <= 59 &&
          j['minutes'] * 60 + (j['seconds'] ?? 0) > 0,
      'Enter a positive duration with seconds from 0 to 59.',
    );
    String optional(
      dynamic value,
      int limit,
      String label, {
      bool multiline = false,
    }) {
      require(value == null || value is String, '$label must be text.');
      final text = ((value ?? '') as String).replaceAll('\r\n', '\n').trim();
      require(
        text.runes.length <= limit &&
            !RegExp(
              multiline ? r'[\x00-\x08\x0b-\x1f\x7f]' : r'[\x00-\x1f\x7f]',
            ).hasMatch(text),
        '$label must contain at most $limit characters without control characters.',
      );
      return text;
    }

    return Segment(
      nameValue(j['name'], 'Segment name'),
      j['minutes'],
      seconds: j['seconds'] ?? 0,
      speaker: optional(j['speaker'], 80, 'Speaker'),
      notes: optional(j['notes'], 1000, 'Private notes', multiline: true),
      protected: boolSetting(j['protected'] ?? false),
    );
  }
  Json toJson() => {
    'name': name,
    'minutes': minutes,
    if (seconds != 0) 'seconds': seconds,
    if (speaker.isNotEmpty) 'speaker': speaker,
    if (notes.isNotEmpty) 'notes': notes,
    if (protected) 'protected': true,
  };
}

/// Stable identity for a saved program, independent of its name. Local
/// only: portable exports and backups leave it out so earlier versions can
/// read them, and the receiving phone assigns its own.
String newProgramId([math.Random? random]) {
  final r = random ?? math.Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return 'p${List.generate(12, (_) => chars[r.nextInt(chars.length)]).join()}';
}

/// A repeatable ID for a program saved before IDs existed, so migrating
/// the same saved state twice gives the same IDs.
String legacyProgramId(String name) {
  var hash = 0xcbf29ce484222325;
  for (final unit in name.toLowerCase().codeUnits) {
    hash = ((hash ^ unit) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return 'm${hash.toRadixString(36)}';
}

final _programIdPattern = RegExp(r'^[a-z0-9-]{4,40}$');

class Timeline {
  final String name;
  final String type;
  final List<Segment> segments;
  final DisplaySettings display;

  /// Empty until the program is saved to this phone's library.
  final String id;
  Timeline(
    this.name,
    List<Segment> segments,
    this.display, {
    this.type = 'service',
    this.id = '',
  }) : segments = List.unmodifiable(segments);
  factory Timeline.fromJson(Json j) {
    keys(j, {
      'schemaVersion',
      'name',
      'segments',
      'display',
      'type',
      'id',
    }, 'Program');
    require(
      j['id'] == null ||
          (j['id'] is String && _programIdPattern.hasMatch(j['id'] as String)),
      'Invalid program id.',
    );
    require(
      j['schemaVersion'] is int && {1, 2, 3, 4, 5}.contains(j['schemaVersion']),
      'Supported program schema versions are 1–5.',
    );
    final type =
        j['type'] ??
        (j['schemaVersion'] >= 3
            ? null
            : j['name'] == 'Quick rehearsal'
            ? 'rehearsal'
            : 'service');
    require(
      {'service', 'rehearsal'}.contains(type),
      'Program type must be service or rehearsal.',
    );
    require(j['segments'] is List, 'segments must be a list.');
    final entries = j['segments'] as List;
    require(
      entries.isNotEmpty && entries.length <= 200,
      'A program needs 1–200 segments.',
    );
    final segs = <Segment>[];
    for (var i = 0; i < entries.length; i++) {
      try {
        segs.add(Segment.fromJson(Map<String, dynamic>.from(entries[i])));
      } catch (e) {
        throw RuleError('segments[$i]: $e');
      }
    }
    return Timeline(
      nameValue(j['name'], 'Program name'),
      segs,
      DisplaySettings.fromJson(Map<String, dynamic>.from(j['display'])),
      type: type as String,
      id: j['id'] as String? ?? '',
    );
  }
  Timeline renamed(String n) => Timeline(
    nameValue(n, 'Program name'),
    segments,
    display,
    type: type,
    id: id,
  );
  Timeline withDisplay(DisplaySettings value) =>
      Timeline(name, segments, value, type: type, id: id);
  Timeline withId(String value) =>
      Timeline(name, segments, display, type: type, id: value);
  Json toJson() => {
    'schemaVersion': segments.any((s) => s.seconds != 0) ? 5 : 4,
    if (id.isNotEmpty) 'id': id,
    'name': name,
    'type': type,
    'segments': segments.map((s) => s.toJson()).toList(),
    'display': display.toJson(),
  };
}

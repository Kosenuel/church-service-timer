import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';

/// A program another phone sent, kept on this phone until it is reviewed.
class ReceivedProgram {
  final Timeline program;
  final String from;
  final int receivedWall;
  const ReceivedProgram(this.program, this.from, this.receivedWall);

  factory ReceivedProgram.fromJson(Json j) {
    keys(j, {'program', 'from', 'receivedWall'}, 'Received program');
    require(
      j['from'] is String && j['receivedWall'] is int,
      'Invalid received program.',
    );
    return ReceivedProgram(
      Timeline.fromJson(
        Map<String, dynamic>.from(j['program'] as Map),
      ).withId(''),
      j['from'] as String,
      j['receivedWall'] as int,
    );
  }

  Json toJson() => {
    'program': portableProgram(program.toJson()),
    'from': from,
    'receivedWall': receivedWall,
  };
}

/// Keep at most this many received programs waiting for review.
const receivedProgramLimit = 5;

List<ReceivedProgram> readReceivedPrograms(Object? raw) {
  if (raw == null) return [];
  require(
    raw is List && raw.length <= receivedProgramLimit,
    'Invalid received programs.',
  );
  return [
    for (final e in raw as List)
      ReceivedProgram.fromJson(Map<String, dynamic>.from(e as Map)),
  ];
}

/// How many earlier versions each program keeps.
const programHistoryLimit = 10;

/// An earlier version of a saved program, kept when it was replaced.
class ProgramRevision {
  /// When this version was replaced by a newer save (or a restore).
  final int replacedWall;
  final Timeline program;
  const ProgramRevision(this.replacedWall, this.program);

  factory ProgramRevision.fromJson(Json j) {
    keys(j, {'replacedWall', 'program'}, 'Program version');
    require(
      j['replacedWall'] is int &&
          j['replacedWall'] >= 0 &&
          j['replacedWall'] <= 8640000000000000,
      'Invalid program version time.',
    );
    require(j['program'] is Map, 'Program version has no program.');
    return ProgramRevision(
      j['replacedWall'] as int,
      // Versions never carry an ID: they belong to the program they sit under.
      Timeline.fromJson(
        Map<String, dynamic>.from(j['program'] as Map),
      ).withId(''),
    );
  }

  Json toJson() => {
    'replacedWall': replacedWall,
    'program': portableProgram(program.toJson()),
  };
}

/// Reads a `{key: [version, …]}` map, newest version first.
Map<String, List<ProgramRevision>> readProgramHistory(Object? raw) {
  if (raw == null) return {};
  require(raw is Map, 'Invalid program history.');
  final result = <String, List<ProgramRevision>>{};
  for (final e in (raw as Map).entries) {
    require(
      e.key is String && e.value is List,
      'Invalid program history entry.',
    );
    final list = e.value as List;
    require(
      list.length <= programHistoryLimit,
      'Keep at most $programHistoryLimit versions of a program.',
    );
    result[e.key as String] = [
      for (final v in list)
        ProgramRevision.fromJson(Map<String, dynamic>.from(v as Map)),
    ];
  }
  return result;
}

Json writeProgramHistory(Map<String, List<ProgramRevision>> history) => {
  for (final e in history.entries)
    if (e.value.isNotEmpty) e.key: [for (final v in e.value) v.toJson()],
};

bool sameProgram(Timeline a, Timeline b) =>
    jsonEncode(portableProgram(a.toJson())) ==
    jsonEncode(portableProgram(b.toJson()));

extension ProgramHistory on AppState {
  /// Keeps a program from another phone for review, newest first. The same
  /// name sent again replaces the waiting one.
  void receiveProgram(Timeline program, String from, int at) {
    programInbox
      ..removeWhere(
        (p) => p.program.name.toLowerCase() == program.name.toLowerCase(),
      )
      ..insert(0, ReceivedProgram(program.withId(''), from, at));
    if (programInbox.length > receivedProgramLimit)
      programInbox.removeRange(receivedProgramLimit, programInbox.length);
  }

  /// Removes a reviewed (saved or discarded) program from the inbox.
  void dismissReceived(ReceivedProgram received) {
    programInbox.removeWhere(
      (p) =>
          p.receivedWall == received.receivedWall &&
          p.program.name == received.program.name,
    );
  }

  /// Earlier versions of the program with [id], newest first.
  List<ProgramRevision> versionsOf(String id) => programHistory[id] ?? const [];

  /// Keeps [previous] as an earlier version of program [id], unless nothing
  /// changed. The oldest version beyond the limit is dropped.
  void recordVersion(String id, Timeline previous, int at) {
    final list = programHistory[id] ?? [];
    final current = programById(id);
    if (current != null && sameProgram(current, previous)) return;
    if (list.isNotEmpty && sameProgram(list.first.program, previous)) return;
    list.insert(0, ProgramRevision(at, previous.withId('')));
    if (list.length > programHistoryLimit) {
      list.removeRange(programHistoryLimit, list.length);
    }
    programHistory[id] = list;
  }

  /// The saved program named [name], ignoring case.
  Timeline? programNamed(String name) {
    for (final t in templates) {
      if (t.name.toLowerCase() == name.toLowerCase()) return t;
    }
    return null;
  }

  /// Saves a program received from another phone. With [update], it replaces
  /// the program of the same name, whose current version goes into history;
  /// otherwise it is added, with a numbered name if that name is taken.
  Timeline saveReceivedProgram(
    Timeline program, {
    required bool update,
    required int at,
  }) {
    final existing = programNamed(program.name);
    if (update && existing != null) {
      final i = templates.indexOf(existing);
      saveTemplate(
        program.renamed(existing.name),
        replacing: i,
        replacedAt: at,
      );
      return templates[i];
    }
    var name = program.name;
    for (var n = 2; programNamed(name) != null; n++) {
      final base = String.fromCharCodes(program.name.runes.take(74));
      name = '$base ($n)';
    }
    saveTemplate(program.renamed(name).withId(''));
    return templates.last;
  }

  /// Puts version [index] of program [id] back, keeping the current name.
  /// The version it replaces is kept in history, so a restore can itself
  /// be undone from there.
  Timeline restoreVersion(String id, int index, int at) {
    final i = templates.indexWhere((t) => t.id == id);
    require(i >= 0, 'This program was removed.');
    final list = versionsOf(id);
    require(index >= 0 && index < list.length, 'This version is gone.');
    final current = templates[i];
    saveTemplate(
      list[index].program.renamed(current.name),
      replacing: i,
      replacedAt: at,
    );
    return templates[i];
  }
}

/// A short, plain description of what changed from [older] to [newer].
String describeProgramChange(Timeline older, Timeline newer) {
  final parts = <String>[];
  if (older.name != newer.name) parts.add('renamed from “${older.name}”');
  final before = {for (final s in older.segments) s.name};
  final after = {for (final s in newer.segments) s.name};
  final added = after.difference(before), removed = before.difference(after);
  String names(Set<String> n) => n.length <= 2
      ? n.map((v) => '“$v”').join(' and ')
      : '${n.length} segments';
  if (added.isNotEmpty) parts.add('added ${names(added)}');
  if (removed.isNotEmpty) parts.add('removed ${names(removed)}');
  int total(Timeline t) => t.segments.fold(0, (n, s) => n + s.durationMs);
  final delta = total(newer) - total(older);
  if (delta != 0) {
    final minutes = (delta.abs() / 60000).round();
    parts.add(
      minutes == 0
          ? 'timing changed'
          : '${delta > 0 ? '+' : '−'}$minutes min in total',
    );
  } else if (added.isEmpty &&
      removed.isEmpty &&
      older.segments.length == newer.segments.length) {
    for (var i = 0; i < older.segments.length; i++) {
      final a = older.segments[i], b = newer.segments[i];
      if (a.name != b.name) {
        parts.add('segments reordered');
        break;
      }
      if (a.durationMs != b.durationMs) {
        parts.add('timing changed');
        break;
      }
    }
  }
  if (parts.isEmpty) parts.add('notes, speakers or display settings changed');
  final text = parts.join(', ');
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

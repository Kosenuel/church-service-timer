import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  // Ends on the clock, as a program made in the app does: the stock end
  // screen would make every backup a version 14 one.
  AppState withProgram() => AppState.fresh(start)
    ..saveTemplate(timeline().withDisplay(timeline().display.withEnd(null)));
  Timeline edit(Timeline t, String extra) => Timeline(
    t.name,
    [...t.segments, Segment(extra, 3)],
    t.display,
    type: t.type,
  );
  // Saves over the app's one user program, as the editor does.
  void save(AppState s, Timeline next, int at) =>
      s.saveTemplate(next, replacing: s.templates.length - 1, replacedAt: at);

  test('Each saved change keeps the version before it, newest first', () {
    final s = withProgram();
    final id = s.templates.last.id;
    final first = s.templates.last;
    save(s, edit(first, 'Offering'), 100);
    save(s, edit(s.templates.last, 'Notices'), 200);
    final versions = s.versionsOf(id);
    expect(versions, hasLength(2));
    expect(versions.first.replacedWall, 200);
    expect(versions.last.program.segments.length, first.segments.length);
    expect(versions.every((v) => v.program.id.isEmpty), isTrue);
  });

  test('Saving without changes adds no version', () {
    final s = withProgram();
    save(s, s.templates.last, 100);
    expect(s.versionsOf(s.templates.last.id), isEmpty);
  });

  test('Only the last ten versions are kept', () {
    final s = withProgram();
    for (var i = 0; i < 14; i++) {
      save(s, edit(s.templates.last, 'Item $i'), i);
    }
    final versions = s.versionsOf(s.templates.last.id);
    expect(versions, hasLength(programHistoryLimit));
    expect(versions.first.replacedWall, 13);
    expect(versions.last.replacedWall, 4);
  });

  test('Restore puts a version back and keeps the current one', () {
    final s = withProgram();
    final id = s.templates.last.id;
    final original = s.templates.last;
    save(s, edit(original, 'Offering').renamed('Sunday Main'), 100);
    final restored = s.restoreVersion(id, 0, 200);
    expect(restored.id, id);
    expect(restored.name, 'Sunday Main', reason: 'The current name stays');
    expect(restored.segments.length, original.segments.length);
    expect(s.versionsOf(id).first.program.segments.last.name, 'Offering');
    // Restoring that one undoes the restore.
    s.restoreVersion(id, 0, 300);
    expect(s.templates.last.segments.last.name, 'Offering');
  });

  test('History survives saving and goes with a deleted program', () {
    final s = withProgram();
    final id = s.templates.last.id;
    save(s, edit(s.templates.last, 'Offering'), 100);
    final reloaded = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())));
    expect(reloaded.versionsOf(id), hasLength(1));
    reloaded.deleteTemplate(reloaded.programById(id)!);
    expect(reloaded.programHistory, isEmpty);
  });

  test('Backups carry history only when there is some', () {
    final s = withProgram();
    final plain = jsonDecode(exportBackup(s, start)) as Json;
    expect(plain['schemaVersion'], 7);
    expect(plain['data'], isNot(contains('programHistory')));
    save(s, edit(s.templates.last, 'Offering'), 100);
    final raw = exportBackup(s, start);
    final backup = jsonDecode(raw) as Json;
    expect(backup['schemaVersion'], 9);
    expect(raw, isNot(contains('"id"')));
    final restored = importBackup(raw, start);
    final program = restored.templates.firstWhere((t) => t.name == 'Sunday');
    final versions = restored.versionsOf(program.id);
    expect(versions, hasLength(1));
    expect(versions.single.replacedWall, 100);
    expect(versions.single.program.segments.length, timeline().segments.length);
  });

  test('Change descriptions are short and plain', () {
    final a = timeline();
    expect(
      describeProgramChange(a, edit(a, 'Offering')),
      'Added “Offering”, +3 min in total',
    );
    expect(
      describeProgramChange(a, a.renamed('Evening')),
      'Renamed from “Sunday”',
    );
    expect(
      describeProgramChange(
        a,
        Timeline(a.name, a.segments.reversed.toList(), a.display),
      ),
      'Segments reordered',
    );
  });
}

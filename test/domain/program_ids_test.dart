import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import 'service_timing_test.dart' show FakePort, start, timeline;

void main() {
  /// Saved state as version 13 wrote it: no IDs, library keyed by name.
  Json legacyState() {
    final s = AppState.fresh(start)..saveTemplate(timeline());
    final j = jsonDecode(jsonEncode(s.toJson())) as Json;
    j['version'] = 13;
    for (final t in j['templates'] as List) {
      (t as Json).remove('id');
    }
    j['programLibrary'] = {
      'favourites': ['Sunday', 'Gone'],
      'recent': {'Sunday': 5, 'Quick rehearsal': 7},
    };
    j['editDrafts'] = {
      'program:Sunday': {'draft': true},
      'program:new': {'draft': 'new'},
    };
    return j;
  }

  test('Saved programs get IDs; pins, recents and drafts move to them', () {
    final a = AppState.fromJson(legacyState());
    expect(a.templates.every((t) => t.id.isNotEmpty), isTrue);
    expect(a.templates.map((t) => t.id).toSet(), hasLength(a.templates.length));
    final sunday = a.templates.firstWhere((t) => t.name == 'Sunday').id;
    final rehearsal = a.templates
        .firstWhere((t) => t.name == 'Quick rehearsal')
        .id;
    expect(a.programLibrary.favourites, {sunday}, reason: 'Gone is dropped');
    expect(a.programLibrary.recent, {sunday: 5, rehearsal: 7});
    expect(a.editDrafts.keys, containsAll(['program:$sunday', 'program:new']));
    // Repeatable, so loading the same old state twice agrees.
    final again = AppState.fromJson(legacyState());
    expect(
      again.templates.map((t) => t.id).toList(),
      a.templates.map((t) => t.id).toList(),
    );
    // And IDs survive a save and reload.
    final reloaded = AppState.fromJson(jsonDecode(jsonEncode(a.toJson())));
    expect(
      reloaded.templates.map((t) => t.id).toList(),
      a.templates.map((t) => t.id).toList(),
    );
    expect(reloaded.programLibrary.favourites, {sunday});
  });

  test('Renaming keeps the ID, the pin and the review note link', () async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.commit((d, _) => d.saveTemplate(timeline()));
    final saved = c.state.templates.last;
    await c.commit((d, _) => d.programLibrary.favourites.add(saved.id));
    await c.act('load', value: saved);
    await c.act('start');
    await c.act('end');
    await c.setReviewNote(c.state.reports.last.id, 'Start on time.');
    await c.commit(
      (d, _) => d.saveTemplate(
        saved.renamed('Sunday Morning'),
        replacing: d.templateIndex(saved),
      ),
    );
    final renamed = c.state.templates.last;
    expect(renamed.name, 'Sunday Morning');
    expect(renamed.id, saved.id);
    expect(c.state.programLibrary.favourites, {saved.id});
    expect(c.state.latestReviewFor(renamed)!.note.text, 'Start on time.');
  });

  test('Shared files and backups leave IDs out', () {
    final s = AppState.fresh(start)..saveTemplate(timeline());
    final t = s.templates.last;
    expect(t.id, isNotEmpty);
    expect(jsonDecode(exportJson(t)), isNot(contains('id')));
    final bundle = jsonDecode(exportProgramsJson([t])) as Json;
    expect(bundle['programs'][0], isNot(contains('id')));
    final backup = jsonDecode(exportBackup(s, start)) as Json;
    for (final p in backup['data']['templates'] as List) {
      expect(p, isNot(contains('id')));
    }
  });

  test('An imported program with a taken ID gets its own', () {
    final s = AppState.fresh(start);
    final existing = s.templates.first;
    s.saveTemplate(existing.renamed('Copy from elsewhere'));
    final copy = s.templates.last;
    expect(copy.id, isNot(existing.id));
    expect(s.templates.map((t) => t.id).toSet(), hasLength(s.templates.length));
  });

  test('A duplicate gets a new ID', () {
    final s = AppState.fresh(start);
    final copy = s.duplicateTemplate(s.templates.first);
    expect(copy.id, isNotEmpty);
    expect(copy.id, isNot(s.templates.first.id));
  });
}

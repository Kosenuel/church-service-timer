import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stock_end_screen.dart';
import 'feature_cases.dart' show epoch;

/// What a service shows when it ends is the clock unless an end screen was
/// chosen: new installs start that way, saved choices are never changed.
void main() {
  AppState roundTrip(AppState a) =>
      AppState.fromJson(jsonDecode(jsonEncode(a.toJson())) as Json, now: epoch);

  test('a new install ends on the clock, for new programs and the app', () {
    final a = AppState.fresh(epoch);
    expect(a.defaults.end, isNull);
    expect(a.templates, isNotEmpty);
    for (final t in a.templates) {
      expect(t.display.end, isNull, reason: t.name);
    }
    // New programs, quick timers and imports take the app-wide choice.
    expect(
      const QuickTimerChoice('', 300).timeline(a.defaults).display.end,
      isNull,
    );
    expect(roundTrip(a).defaults.end, isNull);
  });

  test('a state saved at the current version keeps a stock end screen', () {
    // A church that picks the stock Hallelujah again after updating keeps it.
    final stock = AppState.fresh(epoch)
      ..defaults = DisplaySettings()
      ..templates = [
        Timeline('Old', const [Segment('A', 1)], DisplaySettings()),
      ];
    final a = roundTrip(stock);
    expect(a.defaults.end!.text, 'Hallelujah');
    expect(a.templates.single.display.end!.text, 'Hallelujah');
    // And it is not migrated again on the next load.
    expect(roundTrip(a).defaults.end!.text, 'Hallelujah');
  });

  test('a customised end screen is kept, in a program and in the app', () {
    const mine = TextLayout('Go in peace', bold: true, height: 2);
    final custom = AppState.fresh(epoch)
      ..defaults = DisplaySettings(end: mine)
      ..templates = [
        Timeline('Mine', const [Segment('A', 1)], DisplaySettings(end: mine)),
        Timeline('Clock', const [Segment('A', 1)], DisplaySettings(end: null)),
      ];
    final a = roundTrip(custom);
    expect(a.defaults.end!.text, 'Go in peace');
    expect(a.templates.first.display.end!.text, 'Go in peace');
    expect(a.templates.last.display.end, isNull);
  });

  Json older(int version, TextLayout defaultEnd) {
    final j = AppState.fresh(epoch).toJson();
    j['version'] = version;
    (j['defaults'] as Map)['end'] = defaultEnd.toJson();
    for (final t in j['templates'] as List) {
      (t['display'] as Map)['end'] = defaultEndScreen.toJson();
    }
    return jsonDecode(jsonEncode(j)) as Json;
  }

  test('older state with the stock end screen moves to the clock', () {
    for (final version in [5, 15, 16]) {
      final a = AppState.fromJson(older(version, defaultEndScreen), now: epoch);
      expect(a.defaults.end, isNull, reason: 'version $version');
      // Programs already saved that hold the stock end screen move too.
      expect(a.templates, isNotEmpty);
      for (final t in a.templates) {
        expect(t.display.end, isNull, reason: '${t.name}, version $version');
      }
      // Quick timers follow the app-wide default.
      expect(
        const QuickTimerChoice('', 300).timeline(a.defaults).display.end,
        isNull,
      );
      expect(roundTrip(a).toJson()['version'], 17);
    }
  });

  test('older state with a customised default keeps it, any difference', () {
    for (final mine in [
      const TextLayout('Go in peace', bold: true, italic: true, height: 2),
      const TextLayout('Hallelujah'),
      const TextLayout(
        'Hallelujah',
        bold: true,
        italic: true,
        height: 2,
        speed: 20,
      ),
      const TextLayout(
        'Hallelujah',
        bold: true,
        italic: true,
        height: 2,
        screenColor: 'amber',
      ),
    ]) {
      final a = AppState.fromJson(older(16, mine), now: epoch);
      expect(a.defaults.end!.toJson(), mine.toJson(), reason: mine.text);
    }
  });

  test('older programs with their own end screen keep it', () {
    const mine = TextLayout('Go in peace', bold: true, height: 2);
    // Same word as the stock one, another look: someone made it.
    const plain = TextLayout('Hallelujah');
    final j = older(16, defaultEndScreen);
    final stockProgram = (j['templates'] as List).first as Map;
    Json program(String name, TextLayout? end) =>
        jsonDecode(jsonEncode(stockProgram)) as Json
          ..['name'] = name
          ..remove('id')
          ..['display'] = ({
            ...stockProgram['display'] as Map,
            'end': end?.toJson(),
          });
    j['templates'] = [
      program('Mine', mine),
      program('Plain', plain),
      program('Clock', null),
      program('Stock', defaultEndScreen),
    ];
    final a = AppState.fromJson(j, now: epoch);
    TextLayout? endOf(String name) =>
        a.templates.singleWhere((t) => t.name == name).display.end;
    expect(endOf('Mine')!.toJson(), mine.toJson());
    expect(endOf('Plain')!.toJson(), plain.toJson());
    expect(endOf('Clock'), isNull);
    expect(endOf('Stock'), isNull);
    // A customised default with stock programs: the programs still move.
    final custom = AppState.fromJson(older(16, mine), now: epoch);
    expect(custom.defaults.end!.text, 'Go in peace');
    for (final t in custom.templates) {
      expect(t.display.end, isNull, reason: t.name);
    }
  });

  test('older state with no end screen stays on the clock', () {
    final j = older(16, defaultEndScreen);
    (j['defaults'] as Map)['end'] = null;
    expect(AppState.fromJson(j, now: epoch).defaults.end, isNull);
  });

  test('a backup from an older version gets the same migration', () {
    final stock = stockEndState(epoch);
    final raw = exportBackup(stock, epoch);
    final envelope = jsonDecode(raw) as Json;
    // A backup that holds the stock end screen says it is from this version.
    expect(envelope['schemaVersion'], 14);
    expect(importBackup(raw, epoch).defaults.end!.text, 'Hallelujah');
    // The same backup as an older version wrote it.
    envelope['schemaVersion'] = 13;
    final restored = importBackup(jsonEncode(envelope), epoch);
    expect(restored.defaults.end, isNull);
    // Its programs with the stock end screen move to the clock too.
    expect(restored.templates, isNotEmpty);
    for (final t in restored.templates) {
      expect(t.display.end, isNull, reason: t.name);
    }
    // A stock end screen chosen for one program only, after updating, also
    // marks the backup as from this version, so the restore keeps it.
    final one = AppState.fresh(epoch);
    one.templates = [
      one.templates.first.withDisplay(
        one.templates.first.display.withEnd(defaultEndScreen),
      ),
      ...one.templates.skip(1),
    ];
    final oneRaw = exportBackup(one, epoch);
    expect((jsonDecode(oneRaw) as Json)['schemaVersion'], 14);
    final oneBack = importBackup(oneRaw, epoch);
    expect(oneBack.defaults.end, isNull);
    expect(oneBack.templates.first.display.end!.text, 'Hallelujah');
    // With no stock end screen anywhere the backup is written as before.
    expect(
      (jsonDecode(exportBackup(AppState.fresh(epoch), epoch))
          as Json)['schemaVersion'],
      lessThan(14),
    );
    // A customised default is kept either way.
    final mine = AppState.fresh(epoch)
      ..defaults = DisplaySettings(end: const TextLayout('Go in peace'));
    final custom = jsonDecode(exportBackup(mine, epoch)) as Json;
    expect(
      importBackup(jsonEncode(custom), epoch).defaults.end!.text,
      'Go in peace',
    );
  });
}

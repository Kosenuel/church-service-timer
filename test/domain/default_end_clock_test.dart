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

  test('older state with the stock default: new programs get the clock', () {
    for (final version in [5, 15, 16]) {
      final a = AppState.fromJson(older(version, defaultEndScreen), now: epoch);
      expect(a.defaults.end, isNull, reason: 'version $version');
      // Programs already saved keep the end screen they hold.
      for (final t in a.templates) {
        expect(t.display.end!.text, 'Hallelujah');
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
    // Programs in it keep their end screen.
    for (final t in restored.templates) {
      expect(t.display.end!.text, 'Hallelujah');
    }
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

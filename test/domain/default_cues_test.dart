import 'dart:convert';

import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// The stage cues and automatic warnings a new install starts with, and
/// the upgrade that gives an earlier install the same ones.
void main() {
  const now = Stamp(0, 0, 'test');
  String json(Object? value) => jsonEncode(value);
  List<String> texts(List<TextLayout> cues) => [for (final c in cues) c.text];

  test('a new install has the seven cues, in key order', () {
    final a = AppState.fresh(now);
    expect(texts(a.stageCues), [
      'WRAP UP',
      "TIME'S UP",
      'SPEAK UP',
      'SLOW DOWN',
      'MIC OFF?',
      'FINAL SONG',
      'SEE ME',
    ]);
    expect(
      [for (final c in a.stageCues) '${c.screenColor} ${c.screenPosition}'],
      [
        'amber bottom',
        'red full',
        'white top',
        'white top',
        'amber top',
        'green bottom',
        'accent full',
      ],
    );
    expect(texts(a.defaults.cues), texts(a.stageCues));
    for (final t in a.templates) {
      expect(texts(t.display.cues), texts(a.stageCues));
    }
  });

  test('a new install has the four warnings, all on the stage', () {
    final a = AppState.fresh(now);
    expect(
      [
        for (final w in a.defaults.warnings)
          '${w.seconds} ${w.cue.text} ${w.cue.screenColor} ${w.cue.screenPosition} ${w.destination}',
      ],
      [
        '300 5 MIN LEFT white top stage',
        '120 2 MIN LEFT amber bottom stage',
        '30 WRAP UP amber bottom stage',
        "0 TIME'S UP red full stage",
      ],
    );
  });

  test('every default is legible on the LED sign and holds still on '
      'screens', () {
    for (final cue in [
      ...defaultStageCues,
      ...defaultWarnings.map((w) => w.cue),
    ]) {
      // Each is wider than the sign, so it scrolls there, in tall letters.
      expect(textWidth(cue), greaterThan(32), reason: cue.text);
      expect(cue.effect, 'scroll', reason: cue.text);
      expect(cue.bold && cue.height == 2, isTrue, reason: cue.text);
      expect(cue.screenWrap, isTrue, reason: cue.text);
      validateLayout(cue);
    }
    // Each warning shows long enough to pass across the sign twice.
    for (final w in defaultWarnings) {
      final pass = (textWidth(w.cue) + 6) * 1000 / w.cue.speed;
      expect(w.durationSeconds * 1000, greaterThanOrEqualTo(2 * pass));
    }
  });

  test('saved state from before is given the new cues and warnings', () {
    const own = TextLayout('BAND TO STAGE', bold: true);
    final old = AppState.fresh(now).toJson()
      ..['version'] = 14
      ..['stageCues'] = [
        for (final c in legacyDefaultStageCues) c.toJson(),
        own.toJson(),
      ];
    final display = Map<String, dynamic>.from(old['defaults'])
      ..['cues'] = [for (final c in legacyDefaultStageCues) c.toJson()]
      ..['warnings'] = [for (final w in legacyDefaultWarnings) w.toJson()];
    old['defaults'] = display;
    old['templates'] = [
      for (final t in old['templates'] as List)
        Map<String, dynamic>.from(t)..['display'] = display,
    ];
    final a = AppState.fromJson(jsonDecode(jsonEncode(old)), now: now);
    expect(json(a.stageCues), json([...defaultStageCues, own]));
    expect(json(a.defaults.cues), json(defaultStageCues));
    expect(json(a.defaults.warnings), json(defaultWarnings));
    for (final t in a.templates) {
      expect(json(t.display.cues), json(defaultStageCues));
      expect(json(t.display.warnings), json(defaultWarnings));
    }
    // Saved again, it reads back the same.
    final again = AppState.fromJson(a.toJson(), now: now);
    expect(json(again.toJson()), json(a.toJson()));
  });

  test('warnings a church changed are kept', () {
    final mine = [
      const WarningRule(60, TextLayout('1 MIN'), destination: 'stage'),
    ];
    final old = AppState.fresh(now).toJson()..['version'] = 14;
    old['defaults'] = Map<String, dynamic>.from(old['defaults'])
      ..['warnings'] = [for (final w in mine) w.toJson()];
    final a = AppState.fromJson(jsonDecode(jsonEncode(old)), now: now);
    expect(json(a.defaults.warnings), json(mine));
  });

  test('a backup is read for what it holds, not upgraded twice', () {
    // Made by this version: the church removed most cues and restyled
    // WRAP UP. Restoring it keeps that.
    final mine = AppState.fresh(now)
      ..stageCues = [const TextLayout('WRAP UP', italic: true)];
    final restored = importBackup(exportBackup(mine, now), now);
    expect(json(restored.stageCues), json(mine.stageCues));
    expect(json(restored.defaults.warnings), json(defaultWarnings));
    // Made by an earlier version, with the old cues: upgraded.
    final earlier = AppState.fresh(now)
      ..stageCues = [...legacyDefaultStageCues]
      ..defaults = DisplaySettings(
        cues: legacyDefaultStageCues,
        warnings: legacyDefaultWarnings,
      );
    final upgraded = importBackup(exportBackup(earlier, now), now);
    expect(json(upgraded.stageCues), json(defaultStageCues));
    expect(json(upgraded.defaults.warnings), json(defaultWarnings));
  });
}

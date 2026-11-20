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
    final all = [...defaultStageCues, ...defaultWarnings.map((w) => w.cue)];
    expect(
      [for (final cue in all) '${cue.text}: ${cue.effect}'],
      [
        'WRAP UP: pulse',
        "TIME'S UP: flash",
        'SPEAK UP: scroll',
        'SLOW DOWN: scroll',
        'MIC OFF?: scroll',
        'FINAL SONG: scroll',
        'SEE ME: slideIn',
        '5 MIN LEFT: scroll',
        '2 MIN LEFT: scroll',
        'WRAP UP: scroll',
        "TIME'S UP: screenFlash",
      ],
    );
    for (final cue in all) {
      // Each is wider than the sign, in tall letters, and wraps on screens.
      expect(textWidth(cue), greaterThan(32), reason: cue.text);
      expect(cue.height, 2, reason: cue.text);
      expect(cue.screenWrap, isTrue, reason: cue.text);
      validateLayout(cue);
      // On the sign it scrolls, or shows a word or two at a time.
      expect(
        scrollsOnSign(cue) != (signWordGroups(cue) != null),
        isTrue,
        reason: cue.text,
      );
    }
    // Bold, except TIME'S UP flashing a word at a time: in bold, TIME'S
    // alone would be too wide for the sign.
    expect(
      [
        for (final cue in all)
          if (!cue.bold) cue.effect,
      ],
      ['flash'],
    );
    expect(signWordGroups(defaultStageCues[0]), ['WRAP', 'UP']);
    expect(signWordGroups(defaultStageCues[1]), ["TIME'S", 'UP']);
    // TIME'S UP cannot flash then hold in any built-in pixel font.
    for (final font in ['i-proton_matrix', 'i-proton_sq_matrix']) {
      for (final height in [1, 2]) {
        expect(
          textWidth(TextLayout("TIME'S UP", font: font, height: height)),
          greaterThan(32),
        );
      }
    }
    // Each warning shows long enough to pass across the sign twice.
    for (final w in defaultWarnings) {
      expect(scrollsOnSign(w.cue), isTrue, reason: w.cue.text);
      final pass = (textWidth(w.cue) + 6) * 1000 / w.cue.speed;
      expect(w.durationSeconds * 1000, greaterThanOrEqualTo(2 * pass));
    }
  });

  test('cues and warnings still as version 15 made them are renewed', () {
    const own = TextLayout('BAND TO STAGE', bold: true);
    // The church changed SPEAK UP's colour; it is kept as it is.
    final speakUp = TextLayout.fromJson({
      ...version15DefaultStageCues[2].toJson(),
      'screenColor': 'green',
    });
    final cues = [...version15DefaultStageCues]..[2] = speakUp;
    final old = AppState.fresh(now).toJson()
      ..['version'] = 15
      ..['stageCues'] = [
        for (final c in [...cues, own]) c.toJson(),
      ];
    // The warnings as version 15 made them, but for 2 MIN LEFT, switched
    // off.
    final warnings = [for (final w in version15DefaultWarnings) w.toJson()]
      ..[1] = {...version15DefaultWarnings[1].toJson(), 'enabled': false};
    final display = Map<String, dynamic>.from(old['defaults'])
      ..['cues'] = [for (final c in version15DefaultStageCues) c.toJson()]
      ..['warnings'] = warnings;
    old['defaults'] = display;
    old['templates'] = [
      for (final t in old['templates'] as List)
        Map<String, dynamic>.from(t)..['display'] = display,
    ];
    final a = AppState.fromJson(jsonDecode(jsonEncode(old)), now: now);
    expect(
      json(a.stageCues),
      json([
        ...[...defaultStageCues]..[2] = speakUp,
        own,
      ]),
    );
    expect(json(a.defaults.cues), json(defaultStageCues));
    expect(
      json(a.defaults.warnings),
      json([
        defaultWarnings[0],
        WarningRule.fromJson(warnings[1]),
        defaultWarnings[2],
        defaultWarnings[3],
      ]),
    );
    expect(a.defaults.warnings[3].cue.effect, 'screenFlash');
    for (final t in a.templates) {
      expect(json(t.display.cues), json(defaultStageCues));
      expect(json(t.display.warnings), json(a.defaults.warnings));
    }
    // Saved again, it reads back the same.
    final again = AppState.fromJson(a.toJson(), now: now);
    expect(json(again.toJson()), json(a.toJson()));
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

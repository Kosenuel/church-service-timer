import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';

void main() {
  const look = SavedLook(
    name: 'Sunday morning',
    layout: 'classic',
    themeId: 'royal_navy',
    density: 'compact',
    keyHints: 'on',
    highContrast: true,
  );

  test('a new or updated install starts in Three panes', () {
    expect(const AppearancePreferences().desktopLayout, 'three_panes');
    // Preferences saved before desktop layouts existed.
    final old = AppearancePreferences.fromJson({
      'density': 'spacious',
      'dividers': 'strong',
    });
    expect(old.desktopLayout, 'three_panes');
    expect(old.keyHints, 'automatic');
    expect(old.density, 'spacious');
    expect(
      () => AppearancePreferences.fromJson({'desktopLayout': 'sideways'}),
      throwsA(isA<RuleError>()),
    );
    expect(
      () => AppearancePreferences.fromJson({'keyHints': 'sometimes'}),
      throwsA(isA<RuleError>()),
    );
  });

  test('every layout is built, and an unknown one falls back', () {
    expect(builtDesktopLayouts.toSet(), desktopLayoutIds);
    expect(builtDesktopLayouts.first, defaultDesktopLayout);
    expect(effectiveDesktopLayout('classic'), 'classic');
    // Not a stored value, but the app must still draw something.
    expect(effectiveDesktopLayout('sideways'), 'three_panes');
  });

  test('a saved look round-trips and applies only what it covers', () {
    final back = SavedLook.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(look.toJson()))),
    );
    expect(back.toJson(), look.toJson());
    const before = AppearancePreferences(
      dividers: 'hidden',
      reducedMotion: true,
      pickerFeedback: 'off',
    );
    final after = look.applyTo(before);
    expect(after.desktopLayout, 'classic');
    expect(after.density, 'compact');
    expect(after.keyHints, 'on');
    expect(after.highContrast, isTrue);
    expect(after.dividers, 'hidden');
    expect(after.reducedMotion, isTrue);
    expect(after.pickerFeedback, 'off');
    expect(SavedLook.of('x', after, 'royal_navy').toJson(), {
      ...look.toJson(),
      'name': 'x',
    });
  });

  test('saved looks are checked when read', () {
    Json with_(String key, dynamic value) => {...look.toJson(), key: value};
    for (final bad in [
      with_('name', ''),
      with_('name', 'x' * 41),
      with_('name', 'two\nlines'),
      with_('layout', 'sideways'),
      with_('themeId', 'missing'),
      with_('density', 'huge'),
      with_('keyHints', 'sometimes'),
      with_('highContrast', 'yes'),
      {...look.toJson(), 'extra': 1},
    ]) {
      expect(
        () => readSavedLooks([bad]),
        throwsA(isA<RuleError>()),
        reason: '$bad',
      );
    }
    expect(readSavedLooks(null), isEmpty);
    expect(
      () => readSavedLooks([look.toJson(), with_('name', 'SUNDAY MORNING')]),
      throwsA(isA<RuleError>()),
    );
    expect(
      () => readSavedLooks([
        for (var i = 0; i <= savedLookLimit; i++) with_('name', 'Look $i'),
      ]),
      throwsA(isA<RuleError>()),
    );
    // A custom theme can be part of a look.
    expect(
      readSavedLooks([
        with_('themeId', 'custom:9e4059:edf5fc:f9fcff'),
      ]).single.themeId,
      'custom:9e4059:edf5fc:f9fcff',
    );
  });

  test('saved looks travel in a backup; the layout in use stays local', () {
    final state = AppState.fresh(after(0))
      ..savedLooks = [look]
      ..appearance = const AppearancePreferences(desktopLayout: 'classic');
    final raw = exportBackup(state, after(1));
    expect(jsonDecode(raw)['schemaVersion'], 11);
    final restored = importBackup(raw, after(2));
    expect(restored.savedLooks.single.toJson(), look.toJson());
    expect(restored.appearance.desktopLayout, 'three_panes');
    // The saved state itself keeps both.
    final reloaded = AppState.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(state.toJson()))),
      now: after(3),
    );
    expect(reloaded.savedLooks.single.name, 'Sunday morning');
    expect(reloaded.appearance.desktopLayout, 'classic');
  });

  test(
    'a backup without saved looks is still readable by earlier versions',
    () {
      final raw = exportBackup(AppState.fresh(after(0)), after(1));
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      expect(envelope['schemaVersion'], lessThan(11));
      expect((envelope['data'] as Map).containsKey('savedLooks'), isFalse);
      expect(importBackup(raw, after(2)).savedLooks, isEmpty);
    },
  );

  test('a damaged look in a backup is refused, not half restored', () {
    final state = AppState.fresh(after(0))..savedLooks = [look];
    final envelope =
        jsonDecode(exportBackup(state, after(1))) as Map<String, dynamic>;
    ((envelope['data'] as Map)['savedLooks'] as List).first['layout'] = 'x';
    expect(
      () => importBackup(jsonEncode(envelope), after(2)),
      throwsA(isA<RuleError>()),
    );
  });

  test('each layout has a name and the theme it arrives with', () {
    expect(desktopLayoutName('three_panes'), 'Three panes');
    expect(desktopLayoutTheme('three_panes'), 'midnight_lime');
    expect(desktopLayoutTheme('classic'), isNull);
    expect(defaultLook.layout, defaultDesktopLayout);
    expect(defaultLook.themeId, 'midnight_lime');
  });
}

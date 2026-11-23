import 'dart:convert';

import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('saved choices are kept: an end screen stays, even the stock one', () {
    // Saved data cannot tell "never chosen" from "chose the old default":
    // both are an explicit Hallelujah, and both are kept.
    final stock = AppState.fresh(epoch)
      ..defaults = DisplaySettings()
      ..templates = [
        Timeline('Old', const [Segment('A', 1)], DisplaySettings()),
      ];
    final a = roundTrip(stock);
    expect(a.defaults.end!.text, 'Hallelujah');
    expect(a.templates.single.display.end!.text, 'Hallelujah');
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

  test('state saved by an older version still reads, with its end screen', () {
    final j = AppState.fresh(epoch).toJson();
    j['version'] = 5;
    // Older versions always wrote the end screen.
    (j['defaults'] as Map)['end'] = defaultEndScreen.toJson();
    for (final t in j['templates'] as List) {
      (t['display'] as Map)['end'] = defaultEndScreen.toJson();
    }
    final a = AppState.fromJson(j, now: epoch);
    expect(a.defaults.end!.text, 'Hallelujah');
    expect(a.templates.first.display.end!.text, 'Hallelujah');
  });
}

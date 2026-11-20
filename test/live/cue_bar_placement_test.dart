import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import '../support/widget_setup.dart';

/// A countdown bar cue with half its time left, as a host sends it.
Json barCue(String text, {Json? more}) => {
  'phase': 'active',
  'stageSharing': true,
  'stageLayout': 'timer',
  'displayText': text,
  'displayIsTimer': false,
  'outputMode': 'Cue',
  'bold': true,
  ...stageEffectFields(
    TextLayout(text, effect: 'bar'),
    time: (total: 60000, left: 60000),
  ),
  ...?more,
};

Future<void> show(
  WidgetTester t,
  Json data, {
  Size size = const Size(1920, 1080),
  double textScale = 1,
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
}

final track = find.byKey(const ValueKey('stage-cue-bar-track'));

/// The words' rect as drawn: wrapped text or a single line.
Rect words(WidgetTester t, String text) {
  final wrapped = find.byKey(const ValueKey('stage-wrapped'));
  return t.getRect(wrapped.evaluate().isEmpty ? find.text(text) : wrapped);
}

/// Checks the bar sits just under [text], as wide as it, and that the
/// words and bar together stay centred in [box].
void expectUnder(WidgetTester t, String text, Rect box, {String? reason}) {
  final w = words(t, text), bar = t.getRect(track);
  final thickness = bar.height;
  expect(thickness, inInclusiveRange(3.99, 10.01), reason: reason);
  // Just under the words: one and a half times its thickness below the
  // line they stand on, which is above the bottom of the words' line box
  // (the room kept for letters such as g and y).
  expect(
    bar.top - w.bottom,
    lessThanOrEqualTo(thickness * 1.5 + 1),
    reason: reason,
  );
  expect(bar.top, greaterThan(w.top + w.height * .7), reason: reason);
  // As wide as nine tenths of the words, never under 80 px.
  expect(
    bar.width,
    closeTo(math.min(box.width, math.max(w.width * .9, 80)), 1.5),
    reason: reason,
  );
  expect(bar.center.dx, closeTo(w.center.dx, 1), reason: reason);
  // The words and bar together stay centred.
  expect((w.top + bar.bottom) / 2, closeTo(box.center.dy, 2), reason: reason);
  expect(w.left, greaterThanOrEqualTo(box.left - .5), reason: reason);
  expect(w.right, lessThanOrEqualTo(box.right + .5), reason: reason);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the bar sits just under the words on every screen', (t) async {
    for (final size in const [
      Size(1920, 1080),
      Size(1280, 720),
      Size(844, 390),
      Size(568, 320),
      Size(390, 844),
    ]) {
      for (final text in ['WRAP UP', 'GO', 'PLEASE FINISH YOUR MESSAGE NOW']) {
        await show(t, barCue(text), size: size);
        expect(t.takeException(), isNull, reason: '$size $text');
        // The screen inside its 12 px margin.
        final box = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
        expectUnder(t, text, box, reason: '$size $text');
        // About 2% of the screen's height thick.
        expect(
          t.getRect(track).height,
          closeTo((box.height * .02).clamp(4, 10), .5),
          reason: '$size $text',
        );
        await t.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('the bar runs down under the words', (t) async {
    await show(t, barCue('WRAP UP'));
    final fill = find.byKey(const ValueKey('stage-cue-bar'));
    final full = t.getRect(fill).width;
    // Full, but for the moment it has run so far.
    expect(full, closeTo(t.getRect(track).width, full * .01));
    await t.pump(const Duration(seconds: 30));
    expect(t.getRect(fill).width, closeTo(full / 2, full * .02));
    expect(t.getRect(fill).left, closeTo(t.getRect(track).left, .5));
  });

  testWidgets('under a wrapped block, as wide as its longest line', (t) async {
    const long = 'PLEASE MAKE YOUR WAY TO THE FRONT FOR PRAYER';
    await show(t, barCue(long, more: {'screenWrap': true}));
    expect(find.byKey(const ValueKey('stage-wrapped')), findsOne);
    expectUnder(t, long, const Rect.fromLTWH(12, 12, 1896, 1056));
    expect(t.takeException(), isNull);
  });

  testWidgets('inside a banner, under its words', (t) async {
    await show(
      t,
      barCue(
        'WRAP UP',
        more: {
          'cueColor': '#ffa833',
          'cuePosition': 'bottom',
          'underText': '12:34',
          'underMode': 'Countdown',
        },
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
    final bar = t.getRect(track), w = words(t, 'WRAP UP');
    expect(band.contains(bar.topLeft) && band.contains(bar.bottomRight), true);
    expect(bar.top - w.bottom, lessThanOrEqualTo(bar.height * 1.5 + 1));
    expect(bar.top, greaterThan(w.top + w.height * .7));
    expect(bar.width, closeTo(w.width * .9, 1.5));
    expect(bar.height, 10);
    expect(t.takeException(), isNull);
  });

  testWidgets('clear of letters that reach below the line', (t) async {
    await show(t, barCue('Praying'));
    final w = words(t, 'Praying'), bar = t.getRect(track);
    // Below the whole line box, so the g and y stay clear of it.
    expect(bar.top - w.bottom, closeTo(bar.height * 1.5, 1));
    await show(t, barCue('PRAYING'));
    final caps = words(t, 'PRAYING'), under = t.getRect(track);
    expect(under.top, lessThan(caps.bottom));
  });

  testWidgets('on a coloured cue, clear of the rule', (t) async {
    await show(t, barCue('WRAP UP', more: {'cueColor': '#ff4d4d'}));
    final rule = t.getRect(find.byKey(const ValueKey('stage-card-rule')));
    expect(t.getRect(track).bottom, lessThan(rule.top));
    expectUnder(t, 'WRAP UP', Rect.fromLTRB(12, 30, 1908, 1050));
  });

  testWidgets('no overflow on a small phone with large text', (t) async {
    await show(
      t,
      barCue('PLEASE FINISH', more: {'screenWrap': true}),
      size: const Size(320, 568),
      textScale: 1.6,
    );
    expect(t.takeException(), isNull);
    final bar = t.getRect(track);
    expect(bar.right, lessThanOrEqualTo(320));
    expect(bar.left, greaterThanOrEqualTo(0));
  });

  test('the web page puts the bar under the words', () {
    for (final part in [
      'function placeBar',
      'range.selectNodeContents(node)',
      'Math.max(80, r.width * 0.9)',
      'Math.min(10, Math.max(4, h * 0.02))',
    ]) {
      expect(webStagePage, contains(part), reason: part);
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import '../support/widget_setup.dart';

/// A stage screen showing [data], as a paired screen, the second screen
/// and host full screen draw it.
Future<void> stage(
  WidgetTester t,
  Json data, {
  Size size = const Size(1920, 1080),
}) async {
  setScreen(t, size);
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: StageSurface(data: data, stale: false),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

/// Where the digits of the time are drawn: its line without the empty
/// space Roboto leaves above the digits and below the line they stand on.
Rect digits(WidgetTester t) {
  final line = t.getRect(find.byKey(const ValueKey('stage-time-width')));
  // 1.1 em tall; the digits run from 0.16 em to 0.87 em down it.
  final em = line.height / 1.1;
  return Rect.fromLTRB(
    line.left,
    line.top + .155 * em,
    line.right,
    line.top + .875 * em,
  );
}

const countdown = <String, dynamic>{
  'phase': 'active',
  'displayText': '12:34',
  'effect': 'static',
  'displayIsTimer': true,
  'outputMode': 'Countdown',
  'paused': true,
  'segment': 'Sermon',
  'nextSegment': 'Offering',
};

Json banner(String position, {String color = '#ffa833', Json? more}) => {
  ...countdown,
  'displayText': 'WRAP UP',
  'displayIsTimer': false,
  'outputMode': 'Cue',
  'bold': true,
  'cueColor': color,
  'cuePosition': position,
  'underText': '12:34',
  'underMode': 'Countdown',
  ...?more,
};

void main() {
  setUpAll(loadAppFonts);

  testWidgets('A red cue fills the stage screen', (t) async {
    await stage(t, {
      ...countdown,
      'displayText': "TIME'S UP",
      'displayIsTimer': false,
      'outputMode': 'Cue',
      'bold': true,
      'cueColor': '#ff7979',
    });
    // Red words on charcoal, with the cue's colour in a rule along the
    // bottom of the screen too.
    expect(
      t.widget<Text>(find.text("TIME'S UP")).style!.color,
      const Color(0xffff7979),
    );
    final rule = find.byKey(const ValueKey('stage-card-rule'));
    expect(t.widget<ColoredBox>(rule).color, const Color(0xffff7979));
    expect(t.getRect(rule), const Rect.fromLTWH(0, 1062, 1920, 18));
    expect(find.byKey(const ValueKey('stage-banner')), findsNothing);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/stage-cue-red-full.png'),
    );
  });

  testWidgets('An amber banner sits under the countdown', (t) async {
    await stage(t, banner('bottom'));
    expect(t.takeException(), isNull);
    final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
    expect(band.bottom, 1080);
    expect(band.left, 0);
    expect(band.right, 1920);
    expect(band.height, closeTo(216, .1));
    expect(
      t.widget<Text>(find.text('WRAP UP')).style!.color,
      const Color(0xffffa833),
    );
    // The countdown is still there, white, and clear of the band.
    expect(digits(t).bottom, lessThan(band.top - 16));
    expect(
      t
          .widget<ClockText>(find.byKey(const ValueKey('stage-time-width')))
          .text
          .replaceAll(RegExp('[0-9]'), '0'),
      '00:00',
    );
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/stage-cue-amber-banner.png'),
    );
  });

  testWidgets('A green banner over the countdown and segment on a phone', (
    t,
  ) async {
    await stage(
      t,
      banner(
        'top',
        color: '#4ade80',
        more: {'displayText': 'MIC IS LIVE', 'stageLayout': 'current'},
      ),
      size: const Size(844, 390),
    );
    expect(t.takeException(), isNull);
    expect(find.text('Sermon'), findsOne);
    await expectLater(
      find.byType(StageSurface),
      matchesGoldenFile('../goldens/stage-cue-green-top-banner-phone.png'),
    );
  });

  testWidgets('The countdown stays centred when a banner comes and goes', (
    t,
  ) async {
    Rect time() => t.getRect(find.byKey(const ValueKey('stage-time-width')));
    for (final layout in ['timer', 'current']) {
      final plain = {...countdown, 'stageLayout': layout};
      await stage(t, plain);
      final before = time();
      final element = t.element(find.byKey(const ValueKey('stage-time-width')));
      for (final position in ['top', 'bottom']) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.black,
              body: StageSurface(
                data: banner(position, more: {'stageLayout': layout}),
                stale: false,
              ),
            ),
          ),
        );
        // Part-way in, the band is sliding and the time has not jumped.
        await t.pump(const Duration(milliseconds: 80));
        expect(time().center.dy, closeTo(before.center.dy, .6));
        expect(time().center.dx, closeTo(before.center.dx, .6));
        await t.pump(const Duration(milliseconds: 400));
        final during = time();
        expect(during.center.dy, closeTo(before.center.dy, .6), reason: layout);
        expect(during.center.dx, closeTo(before.center.dx, .6));
        // A little smaller at most, never larger, and still large.
        expect(during.height, lessThanOrEqualTo(before.height + 1));
        expect(during.height, greaterThan(before.height * .8));
        final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
        expect(digits(t).overlaps(band.inflate(12)), isFalse);
        if (layout == 'segment') {
          // The segment name stays, between the countdown and the edge.
          final name = t.getRect(find.text('Sermon'));
          expect(name.overlaps(band), isFalse);
          expect(name.overlaps(digits(t)), isFalse);
        }
        // The same countdown, not a new one built from scratch.
        expect(
          t.element(find.byKey(const ValueKey('stage-time-width'))),
          same(element),
        );
        await stage(t, plain);
        expect(time(), before);
        expect(find.byKey(const ValueKey('stage-banner')), findsNothing);
      }
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('A banner fits small and odd-shaped screens', (t) async {
    for (final size in const [
      Size(568, 320),
      Size(844, 390),
      Size(1024, 768),
      Size(1366, 768),
      Size(2560, 1080),
      Size(390, 844),
    ]) {
      for (final effect in ['static', 'flash', 'scroll']) {
        await stage(
          t,
          banner(
            'top',
            more: {
              'displayText': 'PLEASE FINISH YOUR MESSAGE NOW',
              'effect': effect,
              'screenSpeed': 40,
              'underText': '1:02:03',
            },
          ),
          size: size,
        );
        expect(t.takeException(), isNull, reason: '$size $effect');
        final band = t.getRect(find.byKey(const ValueKey('stage-banner')));
        expect(band.top, 0);
        expect(band.width, size.width);
        final time = digits(t);
        expect(time.top, greaterThan(band.bottom));
        expect(time.left, greaterThanOrEqualTo(0));
        expect(time.right, lessThanOrEqualTo(size.width));
        if (effect != 'scroll') {
          final cue = t.getRect(find.text('PLEASE FINISH YOUR MESSAGE NOW'));
          expect(cue.left, greaterThanOrEqualTo(0));
          expect(cue.right, lessThanOrEqualTo(size.width));
          expect(cue.top, greaterThanOrEqualTo(band.top));
          expect(cue.bottom, lessThanOrEqualTo(band.bottom));
        }
        await t.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('A banner over the clock, and a snapshot without one', (t) async {
    await stage(
      t,
      banner(
        'top',
        color: 'javascript:1',
        more: {'underText': '09:41', 'underMode': 'Clock'},
      ),
    );
    // A colour that is not a colour is white, as cues always were.
    expect(t.widget<Text>(find.text('WRAP UP')).style!.color, Colors.white);
    expect(find.text('Sermon'), findsNothing);
    // Without the countdown to sit over, the cue fills the screen.
    await stage(t, banner('bottom')..remove('underText'));
    expect(find.byKey(const ValueKey('stage-banner')), findsNothing);
    expect(t.getRect(find.text('WRAP UP')).height, greaterThan(300));
    await stage(t, banner('middle'));
    expect(find.byKey(const ValueKey('stage-banner')), findsNothing);
    // A blank screen stays blank.
    await stage(t, banner('bottom', more: {'blank': true}));
    expect(find.byKey(const ValueKey('stage-banner')), findsNothing);
    expect(find.text('WRAP UP'), findsNothing);
    expect(t.takeException(), isNull);
  });

  group('A full-screen cue in a colour', () {
    Json coloured(String color, {Json? more}) => {
      ...countdown,
      'displayText': 'WRAP UP',
      'displayIsTimer': false,
      'outputMode': 'Cue',
      'bold': true,
      'cueColor': color,
      ...?more,
    };
    final rule = find.byKey(const ValueKey('stage-card-rule'));
    Color? background(WidgetTester t) =>
        (t
                    .widget<DecoratedBox>(
                      find.byKey(const ValueKey('stage-screen-flash')).first,
                    )
                    .decoration
                as BoxDecoration)
            .color;
    Color? ink(WidgetTester t, [String text = 'WRAP UP']) =>
        t.widget<Text>(find.text(text)).style!.color;

    test('is told apart from white cues, banners and the time', () {
      expect(stageColouredCard(coloured('#ff7979')), isTrue);
      expect(stageColouredCard(coloured('#ffffff')), isFalse);
      expect(
        stageColouredCard({...coloured('#ff7979'), 'cueColor': null}),
        false,
      );
      expect(stageColouredCard(banner('bottom')), isFalse);
      // A banner after the service has ended fills the screen.
      expect(
        stageColouredCard({...banner('bottom'), 'underText': null}),
        isTrue,
      );
      expect(stageColouredCard(coloured('#ff7979', more: countdown)), false);
      expect(
        stageColouredCard(coloured('#ff7979', more: {'outputMode': 'Clock'})),
        isFalse,
      );
      expect(
        stageColouredCard(coloured('#ff7979', more: {'blank': true})),
        false,
      );
      expect(
        stageColouredCard(coloured('#ff7979', more: {'displayText': ' '})),
        isFalse,
      );
      expect(stageCardRule(1080), 18);
      expect(stageCardRule(100), 4);
    });

    testWidgets('is in its colour on charcoal with a rule at the bottom', (
      t,
    ) async {
      await stage(t, coloured('#4ade80'));
      expect(background(t), const Color(0xff1a1712));
      expect(ink(t), const Color(0xff4ade80));
      expect(t.widget<ColoredBox>(rule).color, const Color(0xff4ade80));
      expect(t.getRect(rule), const Rect.fromLTWH(0, 1062, 1920, 18));
      // The words stay clear of the rule.
      expect(t.getRect(find.text('WRAP UP')).bottom, lessThan(1062));
    });

    testWidgets('a rule at least 4 px on a small screen', (t) async {
      await stage(t, coloured('#4ade80'), size: const Size(320, 180));
      expect(t.getSize(rule).height, 4);
      expect(t.takeException(), isNull);
    });

    testWidgets('a white cue and a banner are as they were', (t) async {
      await stage(t, coloured('#ffffff'));
      expect(rule, findsNothing);
      expect(background(t), Colors.transparent);
      expect(ink(t), Colors.white);
      await stage(t, banner('bottom', color: '#ff7979'));
      expect(rule, findsNothing);
      // The countdown under the banner keeps its own ground, not the
      // charcoal of a coloured full-screen cue.
      expect(
        t
            .widget<ColoredBox>(
              find.byKey(const ValueKey('stage-countdown-ground')),
            )
            .color,
        Colors.black,
      );
      expect(ink(t), const Color(0xffff7979));
    });

    testWidgets('pulse and slide in move the words, not the rule', (t) async {
      for (final effect in ['pulse', 'slideIn', 'flashHold']) {
        await stage(t, {
          ...coloured('#ffa833'),
          ...stageEffectFields(TextLayout('WRAP UP', effect: effect)),
        });
        await t.pump(const Duration(milliseconds: 100));
        expect(rule, findsOne, reason: effect);
        for (final moving in ['stage-cue-opacity', 'stage-cue-slide']) {
          expect(
            find.ancestor(of: rule, matching: find.byKey(ValueKey(moving))),
            findsNothing,
            reason: effect,
          );
        }
        expect(t.getRect(rule).top, 1062, reason: effect);
        expect(ink(t), const Color(0xfffff4dc), reason: effect);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('a countdown bar fills in the cue colour on grey', (t) async {
      await stage(t, {
        ...coloured('#ff7979'),
        ...stageEffectFields(
          const TextLayout('WRAP UP', effect: 'bar'),
          time: (total: 60000, left: 30000),
        ),
      });
      await t.pump(const Duration(milliseconds: 100));
      final fill = find.byKey(const ValueKey('stage-cue-bar'));
      expect(
        (t.widget<DecoratedBox>(fill).decoration as BoxDecoration).color,
        const Color(0xffff7979),
      );
      final track = find
          .ancestor(of: fill, matching: find.byType(DecoratedBox))
          .first;
      expect(
        (t.widget<DecoratedBox>(track).decoration as BoxDecoration).color,
        Colors.white.withValues(alpha: .14),
      );
      expect(t.getRect(fill).bottom, lessThan(t.getRect(rule).top));
      expect(ink(t), const Color(0xffff7979));
    });

    testWidgets('amber words stay warm white; the theme colour is its own', (
      t,
    ) async {
      await stage(t, coloured('#ffa833'));
      expect(ink(t), const Color(0xfffff4dc));
      expect(t.widget<ColoredBox>(rule).color, const Color(0xffffa833));
      final accent = stageColorHex(stageAccentRgb('meadow'));
      await stage(t, coloured(accent));
      expect(ink(t), Color(0xff000000 | stageAccentRgb('meadow')));
      expect(t.widget<ColoredBox>(rule).color, ink(t));
      expect(t.takeException(), isNull);
    });

    test('each colour reads on the charcoal', () {
      const card = Color(0xff000000 | stageCardBackground);
      // Every theme's colour at 7:1 or better, and so on black too.
      for (final p in appPalettes) {
        final accent = Color(0xff000000 | stageAccentRgb(p.id));
        expect(contrast(accent, card), greaterThanOrEqualTo(7), reason: p.id);
        // Lightened only as far as needed: a step less would not do.
        final base = p.accent;
        if (contrast(base, card) < 7) {
          expect(contrast(accent, card), lessThan(7.6), reason: p.id);
        } else {
          expect(accent, Color(0xff000000 | (base.toARGB32() & 0xffffff)));
        }
      }
      // Red and green read at 7:1 or better too, red lightened only as
      // far as that needs; amber's words are warm white.
      for (final name in ['red', 'green']) {
        final ink = Color(0xff000000 | stageCardInkFor(screenCueColors[name]!));
        expect(contrast(ink, card), greaterThanOrEqualTo(7), reason: name);
      }
      final red = Color(0xff000000 | screenCueColors['red']!);
      final darker = Color.lerp(red, Colors.black, .02)!;
      expect(contrast(darker, card), lessThan(7));
      // Still clearly red: no green or blue to speak of beside its red.
      expect(red.r, 1.0);
      expect(red.g, red.b);
      expect(stageCardInkFor(screenCueColors['amber']!), stageCardInk);
      expect(stageCardInkFor(screenCueColors['red']!), 0xff7979);
    });

    testWidgets('wrapped text is in the cue colour too', (t) async {
      await stage(
        t,
        coloured(
          '#ff7979',
          more: {
            'displayText': 'PLEASE COME FORWARD FOR PRAYER',
            'screenWrap': true,
          },
        ),
      );
      final wrapped = find.byKey(const ValueKey('stage-wrapped'));
      expect(t.widget<Text>(wrapped).style!.color, const Color(0xffff7979));
      expect(t.getRect(wrapped).bottom, lessThan(t.getRect(rule).top));
    });

    test('the web page draws the same', () {
      for (final part in [
        "'#1a1712'",
        "'#fff4dc'",
        "c.toLowerCase() === '#ffa833' ? '#fff4dc' : c",
        'card ? cardInk(s.color)',
        '#stage.fx-screenFlash.coloured .text',
        'id="stageRule"',
        'height:max(4px, 1.667vh)',
      ]) {
        expect(webStagePage, contains(part), reason: part);
      }
    });
  });
}

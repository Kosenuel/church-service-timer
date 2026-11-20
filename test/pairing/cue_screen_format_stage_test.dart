import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
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

Json banner(String position, {String color = '#ffc247', Json? more}) => {
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
      'cueColor': '#ff4d4d',
    });
    expect(
      t.widget<Text>(find.text("TIME'S UP")).style!.color,
      const Color(0xffff4d4d),
    );
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
      const Color(0xffffc247),
    );
    // The countdown is still there, white, and clear of the band.
    expect(digits(t).bottom, lessThan(band.top - 16));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('stage-time-width'))).data,
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
        more: {'displayText': 'MIC IS LIVE', 'stageLayout': 'segment'},
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
    for (final layout in ['timer', 'segment']) {
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
}

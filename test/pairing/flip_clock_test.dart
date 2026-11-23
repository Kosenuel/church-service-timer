import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/flip_clock.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The flip clock: the time of day on cards that turn over, wherever a
/// stage screen is filled with the clock.
void main() {
  setUpAll(loadAppFonts);

  Json theme(String id) => StageColors.fieldsOf(paletteFor(id));
  int wall(int h, int m, {int day = 23}) =>
      DateTime(2026, 11, day, h, m).millisecondsSinceEpoch;

  /// A snapshot as the host sends it while the clock shows.
  Json clock(int at, String format, {String themeId = 'midnight_lime'}) => {
    'stageSharing': true,
    'displayText': stageClockText(at, format),
    'effect': 'static',
    'displayIsTimer': false,
    'outputMode': 'Clock',
    ...stageClockDateFields(at),
    'stageTheme': theme(themeId),
  };

  group('what the clock shows', () {
    test('12 hour: no leading zero, and the current of AM and PM', () {
      StageClockFace face(int h, int m) =>
          stageClockFace(clock(wall(h, m), '12h'))!;
      expect(face(0, 0).time, '12:00 AM');
      expect(face(0, 0).pm, isFalse);
      expect(face(12, 0).time, '12:00 PM');
      expect(face(12, 0).pm, isTrue);
      expect(face(8, 59).hours, '8');
      expect(face(8, 59).minutes, '59');
      expect(face(9, 59).time, '9:59 AM');
      expect(face(10, 0).time, '10:00 AM');
      expect(face(13, 5).time, '1:05 PM');
      expect(face(23, 59).time, '11:59 PM');
      expect(face(8, 59).twelveHour, isTrue);
    });

    test('24 hour: two digits and no AM or PM', () {
      StageClockFace face(int h, int m) =>
          stageClockFace(clock(wall(h, m), '24h'))!;
      expect(face(0, 0).time, '00:00');
      expect(face(8, 59).time, '08:59');
      expect(face(9, 59).time, '09:59');
      expect(face(10, 0).time, '10:00');
      expect(face(12, 0).time, '12:00');
      expect(face(23, 59).time, '23:59');
      expect(face(8, 59).pm, isNull);
      expect(face(8, 59).twelveHour, isFalse);
    });

    test('the weekday and a day-first date, changing at midnight', () {
      final before = stageClockFace(clock(wall(23, 59), '12h'))!;
      final after = stageClockFace(clock(wall(0, 0, day: 24), '12h'))!;
      expect((before.weekday, before.date), ('Monday', '23 November 2026'));
      expect((after.weekday, after.date), ('Tuesday', '24 November 2026'));
      expect(after.time, '12:00 AM');
      // The year and month roll over too.
      final year = stageClockDateFields(
        DateTime(2027, 1, 1).millisecondsSinceEpoch,
      );
      expect(year, {'clockWeekday': 'Friday', 'clockDate': '1 January 2027'});
    });

    test('a host from before the flip clock sends no date, so the screen '
        'uses its own', () {
      final old = clock(wall(8, 59), '24h')
        ..remove('clockWeekday')
        ..remove('clockDate')
        ..remove('stageTheme');
      final face = stageClockFace(old, now: DateTime(2026, 11, 23))!;
      expect((face.weekday, face.date), ('Monday', '23 November 2026'));
      // And no theme: white on black, as ever.
      expect(StageColors.of(old).background, Colors.black);
      expect(StageColors.of(old).text, Colors.white);
    });

    test('only a time is a clock', () {
      expect(
        stageClockFace({'outputMode': 'Clock', 'displayText': 'AMEN'}),
        isNull,
      );
      expect(
        stageClockFace({'outputMode': 'Countdown', 'displayText': '12:34'}),
        isNull,
      );
    });

    test('the theme in a snapshot is read only if every colour is one', () {
      final good = clock(wall(8, 59), '24h', themeId: 'warm_ivory');
      expect(StageColors.of(good).light, isTrue);
      expect(
        StageColors.of(good).background,
        paletteFor('warm_ivory').background,
      );
      final bad = clock(wall(8, 59), '24h')
        ..['stageTheme'] = {'background': 'red'};
      expect(stageThemeOf(bad), isNull);
      expect(StageColors.of(bad), same(StageColors.classic));
    });
  });

  group('every place the time of day fills a stage screen', () {
    late AppController c;
    setUp(() async {
      c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
    });

    Json snap(Session s, Stamp at) =>
        c.pairedSnapshot(false, session: s, at: at);

    Session twelveHour(Session s) => s..clockFormat = '12h';

    test('Show clock', () {
      final s = twelveHour(transition(running(), 'clock', after(5)));
      final data = snap(s, after(5));
      expect(data['outputMode'], 'Clock');
      expect(stageClockFace(data), isNotNull);
      expect(data['stageTheme'], isA<Map>());
      expect(data['clockDate'], isNotEmpty);
    });

    test('a service ended with no end screen', () {
      final ended = transition(
        transition(
          Session(id: 'idle', anchor: start),
          'load',
          start,
          value: Timeline('Prayer', const [
            Segment('One', 10),
          ], DisplaySettings(end: null)),
        ),
        'start',
        start,
      );
      final over = transition(ended, 'end', after(5));
      expect(over.timeline!.display.end, isNull);
      final data = snap(over, after(6));
      expect(data['outputMode'], 'Clock');
      expect(stageClockFace(data), isNotNull);
      // With an end screen set, that shows instead.
      final withEnd = transition(running(), 'end', after(5));
      expect(snap(withEnd, after(6))['outputMode'], 'End screen');
      expect(stageClockFace(snap(withEnd, after(6))), isNull);
    });

    test('a Quick timer that has ended', () {
      final timer = transition(
        transition(
          Session(id: 'idle', anchor: start),
          'load',
          start,
          value: const QuickTimerChoice(
            'Offering',
            300,
          ).timeline(DisplaySettings(end: null)),
        ),
        'start',
        start,
      )..quickTimer = true;
      final ended = transition(timer, 'end', after(10));
      final data = snap(ended, after(11));
      expect(data['outputMode'], 'Clock');
      expect(stageClockFace(data), isNotNull);
    });

    test('before a scheduled service starts, until its countdown begins', () {
      final ready = transition(
        loaded(),
        'schedule',
        start,
        value: start.wall + 90 * 60000,
      );
      final early = snap(ready, after(10 * 60));
      expect(early['outputMode'], 'Pre-service');
      expect(early['clockFace'], isTrue);
      expect(stageClockFace(early), isNotNull);
      // From the last hour it is the countdown, not a clock.
      final late = snap(ready, after(60 * 60));
      expect(late['clockFace'], isNull);
      expect(stageClockFace(late), isNull);
    });

    test('a clock under a banner cue', () {
      final data = {
        ...clock(wall(8, 59), '12h'),
        'displayText': 'Welcome',
        'outputMode': 'Cue',
        'cuePosition': 'top',
        'underText': stageClockText(wall(8, 59), '12h'),
        'underMode': 'Clock',
      };
      expect(stageClockFace(stageUnderBanner(data)), isNotNull);
    });

    test('what is not a clock: the zero screen, a countdown, standing by', () {
      final running0 = running();
      expect(stageClockFace(snap(running0, after(2))), isNull);
      // The At zero screen is text the operator writes, not the clock.
      expect(stageClockFace(snap(running0, after(2)), now: null), isNull);
      // Standing by shows nothing on a stage screen today (the LED sign
      // keeps its last output): this is not changed here.
      final idle = snap(Session(id: 'idle', anchor: start), start);
      expect(idle['outputMode'], 'Standby');
      expect(stageClockFace(idle), isNull);
    });
  });

  group('the picture', () {
    Future<void> pump(
      WidgetTester t,
      Json data,
      Size size, {
      bool reduceMotion = false,
    }) async {
      setScreen(t, size);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: reduceMotion),
            child: Scaffold(
              backgroundColor: stageBackdropOf(data),
              body: StageSurface(data: data, stale: false),
            ),
          ),
        ),
      );
      await t.pump();
    }

    for (final (name, format, size, at, id) in [
      ('wide-12h', '12h', const Size(1280, 720), (8, 59), 'midnight_lime'),
      ('wide-24h', '24h', const Size(1280, 720), (8, 59), 'midnight_lime'),
      ('phone-12h', '12h', const Size(360, 780), (8, 59), 'midnight_lime'),
      ('phone-24h', '24h', const Size(360, 780), (8, 59), 'midnight_lime'),
      ('light', '12h', const Size(1280, 720), (10, 7), 'warm_ivory'),
    ]) {
      testWidgets('golden: $name', (t) async {
        await pump(t, clock(wall(at.$1, at.$2), format, themeId: id), size);
        expect(find.byType(FlipClock), findsOneWidget);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/flip-clock-$name.png'),
        );
      });
    }

    testWidgets('a single hour digit stays in one row with the minutes', (
      t,
    ) async {
      await pump(t, clock(wall(8, 59), '12h'), const Size(360, 780));
      final hours = t.getRect(find.byKey(const ValueKey('flip-h-0')));
      final minutes = t.getRect(find.byKey(const ValueKey('flip-m-0')));
      expect(hours.top, minutes.top);
      expect(hours.bottom, minutes.bottom);
      expect(hours.right, lessThan(minutes.left));
      // AM and PM are a centred row below, not beside the time.
      final am = t.getRect(find.byKey(const ValueKey('flip-am-lit')));
      expect(am.top, greaterThan(hours.bottom));
      expect(t.getRect(find.byType(FlipClock)).width, 360 - 24);
    });

    testWidgets('AM and PM are stacked beside the time on a wide screen, the '
        'current one lit', (t) async {
      await pump(t, clock(wall(15, 5), '12h'), const Size(1280, 720));
      final pm = t.getRect(find.byKey(const ValueKey('flip-pm-lit')));
      final minutes = t.getRect(find.byKey(const ValueKey('flip-m-1')));
      expect(pm.left, greaterThan(minutes.right));
      expect(find.byKey(const ValueKey('flip-am-lit')), findsNothing);
      expect(find.byKey(const ValueKey('flip-am')), findsOneWidget);
    });

    testWidgets('a 24 hour clock has no tiles', (t) async {
      await pump(t, clock(wall(15, 5), '24h'), const Size(1280, 720));
      expect(find.text('AM'), findsNothing);
      expect(find.text('PM'), findsNothing);
      expect(find.text('MONDAY'), findsOneWidget);
      expect(find.text('23 November 2026'), findsOneWidget);
    });

    testWidgets('nothing overflows at any supported size', (t) async {
      for (final size in const [
        Size(1920, 1080),
        Size(1366, 768),
        Size(844, 390),
        Size(360, 780),
        Size(320, 480),
        Size(1000, 1000),
      ]) {
        for (final format in ['12h', '24h']) {
          await pump(t, clock(wall(10, 28), format), size);
          expect(t.takeException(), isNull, reason: '$size $format');
          final box = t.getRect(find.byType(FlipClock));
          for (final key in ['flip-time', 'flip-weekday', 'flip-date']) {
            final r = t.getRect(find.byKey(ValueKey(key)));
            expect(box.inflate(1).contains(r.topLeft), isTrue, reason: key);
            expect(box.inflate(1).contains(r.bottomRight), isTrue, reason: key);
          }
        }
      }
    });

    testWidgets('a digit that changes folds over, then shows the new one', (
      t,
    ) async {
      await pump(t, clock(wall(8, 59), '24h'), const Size(1280, 720));
      expect(find.byKey(const ValueKey('flip-digit-9')), findsOneWidget);
      await pump(t, clock(wall(9, 0), '24h'), const Size(1280, 720));
      await t.pump(const Duration(milliseconds: 200));
      // Mid-turn: the old digit is still drawn as well as the new one.
      expect(find.text('8'), findsWidgets);
      expect(find.text('9'), findsWidgets);
      await t.pump(const Duration(seconds: 1));
      expect(find.text('8'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('with reduced motion a digit changes without turning', (
      t,
    ) async {
      await pump(
        t,
        clock(wall(8, 59), '24h'),
        const Size(1280, 720),
        reduceMotion: true,
      );
      await pump(
        t,
        clock(wall(9, 0), '24h'),
        const Size(1280, 720),
        reduceMotion: true,
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('8'), findsNothing);
    });

    testWidgets('a banner cue still shows over the clock', (t) async {
      final data = {
        ...clock(wall(8, 59), '12h'),
        'displayText': 'WELCOME',
        'outputMode': 'Cue',
        'cuePosition': 'bottom',
        'underText': stageClockText(wall(8, 59), '12h'),
        'underMode': 'Clock',
        'cueColor': '#ffa833',
      };
      await pump(t, data, const Size(1280, 720));
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(FlipClock), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-banner')), findsOneWidget);
      expect(find.text('WELCOME'), findsOneWidget);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/flip-clock-banner.png'),
      );
    });

    testWidgets('a cue over the whole screen is not a clock', (t) async {
      await pump(t, {
        'stageSharing': true,
        'displayText': 'AMEN',
        'effect': 'static',
        'outputMode': 'Cue',
        'displayIsTimer': false,
      }, const Size(1280, 720));
      expect(find.byType(FlipClock), findsNothing);
    });
  });

  group('web screens', () {
    final settings = const WebStageSettings(
      orderCode: 'abcd',
      localName: 'church-timer',
    );

    test('the page gets the clock and the theme', () {
      final view = viewFor(WebRole.stage, {
        ...clock(wall(15, 5), '12h', themeId: 'warm_ivory'),
        'phase': 'ended',
      }, settings);
      expect(view['clock'], {
        'hours': '3',
        'minutes': '05',
        'pm': true,
        'weekday': 'Monday',
        'date': '23 November 2026',
      });
      expect(view['theme'], {
        'background': '#f7f4eb',
        'surface': '#fffcf5',
        'accent': '#266347',
        'muted': '#626b61',
        'text': '#202f28',
      });
      final h24 = viewFor(WebRole.stage, clock(wall(8, 5), '24h'), settings);
      expect(h24['clock']['hours'], '08');
      expect(h24['clock'].containsKey('pm'), isFalse);
    });

    test('a countdown, or an old host, carries no clock or theme', () {
      final countdown = viewFor(WebRole.stage, {
        'stageSharing': true,
        'displayText': '12:34',
        'effect': 'static',
        'displayIsTimer': true,
        'outputMode': 'Countdown',
      }, settings);
      expect(countdown.containsKey('clock'), isFalse);
      expect(countdown.containsKey('theme'), isFalse);
    });

    test('a clock under a banner is still a clock, with its banner', () {
      final view = viewFor(WebRole.stage, {
        ...clock(wall(8, 59), '24h'),
        'displayText': 'WELCOME',
        'outputMode': 'Cue',
        'cuePosition': 'top',
        'underText': '08:59',
        'underMode': 'Clock',
      }, settings);
      expect(view['clock']['hours'], '08');
      expect(view['banner']['text'], 'WELCOME');
    });

    test('the page draws the flip clock with its own cards and tiles', () {
      for (final part in [
        'id="flip"',
        'function renderFlip(',
        'flipTurn(',
        '.fdow',
        'prefers-reduced-motion',
        "s.clock && !s.message",
      ]) {
        expect(webStagePage, contains(part), reason: part);
      }
    });
  });
}

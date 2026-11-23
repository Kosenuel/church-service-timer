import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/pairing/flip_clock.dart';
import 'package:church_service_timer/shared/stage_layout_tiles.dart';
import 'package:church_service_timer/web_stage/web_page.dart';
import 'package:church_service_timer/web_stage/web_stage_server.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/stage_colors.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/windows/second_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The countdown layouts: Timer only, Timer and segment name, Timer and up
/// next, and Up next only, in the theme's colours, with a progress line and
/// a colour for the moment.
void main() {
  setUpAll(loadAppFonts);

  const wide = Size(1920, 1080), phone = Size(360, 780);

  Json countdown({
    String layout = 'timer',
    String time = '12:34',
    String moment = 'normal',
    String themeId = 'midnight_lime',
    String alert = 'strong',
    double progress = .58,
    String segment = 'Sermon',
    String next = 'Response',
    String? end,
  }) => {
    'stageSharing': true,
    'stageLayout': layout,
    'displayText': moment == 'overtime' ? '+00:42' : time,
    'effect': 'static',
    'displayIsTimer': true,
    'outputMode': 'Countdown',
    'phase': 'active',
    'segment': segment,
    'speaker': 'Pastor Daniel',
    'nextSegment': next,
    if (next.isNotEmpty) 'upNext': 'Next: $next · Worship team · 6 min 30 s',
    'overtime': moment == 'overtime',
    'paused': moment == 'paused',
    if (moment == 'warning') 'warning': true,
    'progress': progress,
    'overtimeAlert': alert,
    'stageTheme': StageColors.fieldsOf(paletteFor(themeId)),
  };

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
    await t.pump(const Duration(seconds: 2));
  }

  Future<void> golden(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/countdown-$name.png'),
    );
  }

  group('the four layouts', () {
    for (final layout in stageLayouts.keys) {
      for (final (label, size) in [('wide', wide), ('phone', phone)]) {
        testWidgets('golden: $layout, $label', (t) async {
          await pump(t, countdown(layout: layout), size);
          await golden(t, '$layout-$label');
        });
      }
    }
  });

  Color digitsColour(WidgetTester t) =>
      t.widget<ClockText>(find.byType(ClockText)).style.color!;
  Color ground(WidgetTester t) => t
      .widget<ColoredBox>(find.byKey(const ValueKey('stage-countdown-ground')))
      .color;
  final colors = StageColors.of(countdown());

  group('Up next only and the other layouts, in words', () {
    test('four layouts, in the words every chooser uses', () {
      expect(stageLayouts, {
        'timer': 'Timer only',
        'current': 'Timer and segment name',
        'next': 'Timer and up next',
        'only': 'Up next only',
      });
      expect(stageLayoutValue('only'), 'only');
      expect(stageLayoutValue('nonsense'), 'timer');
    });

    test('the layout line is empty for Up next only', () {
      expect(stageLayoutLine(countdown(layout: 'only'), 'only'), '');
      expect(stageLayoutLine(countdown(), 'timer'), '');
      expect(stageLayoutLine(countdown(), 'current'), 'Sermon');
      expect(
        stageLayoutLine(countdown(), 'next'),
        'Next: Response · Worship team · 6 min 30 s',
      );
    });

    test('the next item: name, then who and how long', () {
      final next = stageUpNext(countdown())!;
      expect(next.name, 'Response');
      expect(next.detail, 'Worship team · 6 min 30 s');
      // No speaker: just the length.
      final bare = stageUpNext({
        'nextSegment': 'Closing',
        'upNext': 'Next: Closing · 2 min',
      })!;
      expect((bare.name, bare.detail), ('Closing', '2 min'));
      // A host from before the up next line sends only the name.
      final old = stageUpNext({'nextSegment': 'Offering'})!;
      expect((old.name, old.detail), ('Offering', ''));
      // Nothing next: the last segment, a Quick timer, no program.
      expect(stageUpNext({'nextSegment': ''}), isNull);
      expect(stageUpNext({}), isNull);
    });

    test('moments follow the host: overtime, paused, warning, normal', () {
      expect(stageMoment(countdown()), 'normal');
      expect(stageMoment(countdown(moment: 'warning')), 'warning');
      expect(stageMoment(countdown(moment: 'paused')), 'paused');
      expect(stageMoment(countdown(moment: 'overtime')), 'overtime');
      // A host from before the warning colour never says warning.
      expect(stageMoment({'displayIsTimer': true}), 'normal');
      expect(stageProgress({'progress': 1.7}), 1);
      expect(stageProgress({'progress': -1}), 0);
      expect(stageProgress({}), 0);
      expect(stageProgress({'overtime': true, 'progress': .4}), 1);
    });

    test('a paired screen can be set to Up next only, and old saved '
        'choices still read', () {
      expect(screenLayouts.containsKey('only'), isTrue);
      expect(secondScreenLayouts.containsKey('only'), isTrue);
      // A version that does not know it reads its saved choice as timer.
      expect(stageLayoutValue('only-later'), 'timer');
      expect(stageLayoutValue(null), 'timer');
    });
  });

  group('what Up next only shows with nothing next', () {
    Json lastSegment({Json? after}) => {
      ...countdown(layout: 'only', next: ''),
      'afterEnd':
          after ??
          {
            'outputMode': 'End screen',
            'displayText': 'Hallelujah',
            'effect': 'static',
          },
    };

    test('the end screen set for the program, or the clock', () {
      final end = stageForLayout(lastSegment(), 'only');
      expect(end['displayText'], 'Hallelujah');
      expect(end['displayIsTimer'], isFalse);
      expect(end['outputMode'], 'End screen');
      expect(end.containsKey('afterEnd'), isFalse);
      final clock = stageForLayout(
        lastSegment(
          after: {
            'outputMode': 'Clock',
            'displayText': '08:59',
            'effect': 'static',
          },
        ),
        'only',
      );
      expect(stageClockFace(clock), isNotNull);
    });

    test('other layouts, and a next item, are left alone', () {
      final data = lastSegment();
      expect(stageForLayout(data, 'timer'), same(data));
      final withNext = {...countdown(layout: 'only'), 'afterEnd': {}};
      expect(stageForLayout(withNext, 'only'), same(withNext));
    });

    test('the host sends it on the last segment, in a Quick timer and with '
        'no end screen', () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      Json snap(Session s, Stamp at) =>
          c.pairedSnapshot(false, session: s, at: at);
      // The middle of a program: something is next, so nothing is sent.
      expect(snap(running(), after(5)).containsKey('afterEnd'), isFalse);
      // The last segment: the program's own end screen.
      final last = transition(
        transition(running(), 'advance', after(5)),
        'advance',
        after(6),
      );
      final end = snap(last, after(7))['afterEnd'] as Map;
      expect(end['outputMode'], 'End screen');
      expect(end['displayText'], 'Hallelujah');
      // A program with no end screen: the clock.
      final noEnd = transition(
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
      final clock = snap(noEnd, after(5))['afterEnd'] as Map;
      expect(clock['outputMode'], 'Clock');
      expect(
        clock['displayText'],
        stageClockText(after(5).wall, noEnd.clockFormat),
      );
      // A Quick timer, whose one segment has nothing after it.
      final quick = transition(
        transition(
          Session(id: 'idle', anchor: start),
          'load',
          start,
          value: const QuickTimerChoice(
            'Offering',
            300,
          ).timeline(DisplaySettings()),
        ),
        'start',
        start,
      )..quickTimer = true;
      expect(
        (snap(quick, after(5))['afterEnd'] as Map)['displayText'],
        'Hallelujah',
      );
      // Not counting down: nothing.
      expect(
        snap(Session(id: 'idle', anchor: start), start).containsKey('afterEnd'),
        isFalse,
      );
    });

    testWidgets('the screen shows the end screen, or the clock', (t) async {
      await pump(t, lastSegment(), wide);
      expect(find.text('Hallelujah'), findsOneWidget);
      expect(find.byType(ClockText), findsNothing);
      expect(find.text('12:34'), findsNothing);
      await pump(
        t,
        lastSegment(
          after: {
            'outputMode': 'Clock',
            'displayText': '08:59',
            'effect': 'static',
          },
        ),
        wide,
      );
      expect(find.byType(FlipClock), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-next-name')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('the host snapshot', () {
    test(
      'carries the speaker, the warning, the progress and the strength',
      () async {
        final c = AppController(FakePort());
        await c.initialize(startTicker: false);
        addTearDown(c.dispose);
        Json snap(Session s, Stamp at) =>
            c.pairedSnapshot(false, session: s, at: at);
        final early = snap(running(), after(5));
        expect(early['warning'], isNull);
        expect(early['overtimeAlert'], 'strong');
        expect(early['progress'], closeTo(5 / 600, .001));
        // Inside the default 5-minute warning, as the operator's timer is.
        final warning = snap(running(), after(400));
        expect(warning['warning'], isTrue);
        expect(warning['progress'], closeTo(400 / 600, .001));
        expect(await c.setOvertimeAlert('gentle'), isTrue);
        expect(snap(running(), after(5))['overtimeAlert'], 'gentle');
        expect(await c.setOvertimeAlert('nonsense'), isFalse);
        expect(c.state.overtimeAlert, 'gentle');
        // Past zero: the whole segment has gone.
        final over = snap(running(), after(660));
        expect(over['overtime'], isTrue);
        expect(over['progress'], 1);
      },
    );
  });

  group('overtime alert setting', () {
    test('Strong unless chosen, and old saved data reads', () {
      expect(AppState.fresh(start).overtimeAlert, 'strong');
      final saved = AppState.fresh(start).toJson()..remove('overtimeAlert');
      expect(AppState.fromJson(saved).overtimeAlert, 'strong');
      for (final value in overtimeAlerts.keys) {
        final json = AppState.fresh(start).toJson()..['overtimeAlert'] = value;
        expect(AppState.fromJson(json).overtimeAlert, value);
        expect(
          AppState.fromJson(AppState.fromJson(json).toJson()).overtimeAlert,
          value,
        );
      }
      // Anything unknown is Strong, not an error.
      final odd = AppState.fresh(start).toJson()..['overtimeAlert'] = 'loud';
      expect(AppState.fromJson(odd).overtimeAlert, 'strong');
      expect(overtimeAlertValue(null), 'strong');
    });

    test('kept on this device, never in a backup', () async {
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      addTearDown(c.dispose);
      await c.setOvertimeAlert('strongest');
      expect(c.state.overtimeAlert, 'strongest');
      expect(AppState.fromJson(c.state.toJson()).overtimeAlert, 'strongest');
      expect(exportBackup(c.state, c.now), isNot(contains('overtimeAlert')));
    });
  });

  group('the layouts as drawn', () {
    testWidgets('Timer only has the digits and the progress line only', (
      t,
    ) async {
      await pump(t, countdown(), wide);
      expect(find.byType(ClockText), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-band-now')), findsNothing);
      expect(find.byKey(const ValueKey('stage-band-up next')), findsNothing);
      expect(find.byKey(const ValueKey('stage-progress')), findsOneWidget);
    });

    testWidgets('Timer and segment name: a Now band across the top', (t) async {
      await pump(t, countdown(layout: 'current'), wide);
      final band = t.getRect(find.byKey(const ValueKey('stage-band-now')));
      final time = t.getRect(find.byType(ClockText));
      expect(band.top, lessThan(100));
      expect(band.bottom, lessThan(time.top));
      expect(find.text('NOW'), findsOneWidget);
      expect(find.text('Sermon'), findsOneWidget);
      expect(find.text('Pastor Daniel'), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-band-up next')), findsNothing);
    });

    testWidgets('Timer and up next: an Up next band along the bottom', (
      t,
    ) async {
      await pump(t, countdown(layout: 'next'), wide);
      final band = t.getRect(find.byKey(const ValueKey('stage-band-up next')));
      final time = t.getRect(find.byType(ClockText));
      expect(band.top, greaterThan(time.bottom - 1));
      expect(band.bottom, lessThan(1080));
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('Worship team · 6 min 30 s'), findsOneWidget);
    });

    testWidgets('Up next only shows the item and no time at all', (t) async {
      await pump(t, countdown(layout: 'only'), wide);
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-next-name')), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('Worship team · 6 min 30 s'), findsOneWidget);
      expect(find.byType(ClockText), findsNothing);
      expect(find.text('12:34'), findsNothing);
      expect(find.textContaining('Starts in'), findsNothing);
      // The line along the bottom edge still shows.
      expect(find.byKey(const ValueKey('stage-progress')), findsOneWidget);
    });

    testWidgets('a long name ends in an ellipsis wide and wraps upright', (
      t,
    ) async {
      const long =
          'Congregational response and prayers of the people for the church';
      await pump(t, countdown(layout: 'next', next: long), wide);
      var name = t.widget<Text>(find.byKey(const ValueKey('stage-band-name')));
      expect(name.maxLines, 1);
      expect(name.overflow, TextOverflow.ellipsis);
      await pump(t, countdown(layout: 'next', next: long), phone);
      name = t.widget<Text>(find.byKey(const ValueKey('stage-band-name')));
      expect(name.maxLines, greaterThan(1));
      expect(t.takeException(), isNull);
      // The same for Up next only.
      await pump(t, countdown(layout: 'only', next: long), phone);
      expect(find.text(long), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('digits keep one size and place as the time changes', (
      t,
    ) async {
      for (final layout in ['timer', 'current', 'next']) {
        Rect? first;
        for (final time in ['48:03', '11:11', '00:00', '20:01']) {
          await pump(t, countdown(layout: layout, time: time), wide);
          final box = t.getRect(find.byKey(const ValueKey('stage-time-width')));
          expect(box, first ??= box, reason: '$layout $time');
        }
      }
    });

    testWidgets('nothing overflows at any supported size', (t) async {
      for (final size in const [
        Size(1920, 1080),
        Size(1366, 768),
        Size(844, 390),
        Size(360, 780),
        Size(320, 480),
      ]) {
        for (final layout in stageLayouts.keys) {
          for (final moment in ['normal', 'paused', 'overtime']) {
            await pump(t, countdown(layout: layout, moment: moment), size);
            expect(t.takeException(), isNull, reason: '$layout $moment $size');
          }
        }
      }
    });

    testWidgets('the progress line shows how much of the segment has gone', (
      t,
    ) async {
      await pump(t, countdown(progress: .58), wide);
      final line = t.getRect(find.byKey(const ValueKey('stage-progress')));
      expect(line.width, closeTo(1920 * .58, 2));
      expect(line.bottom, 1080);
      await pump(t, countdown(progress: .1), wide);
      expect(
        t.getRect(find.byKey(const ValueKey('stage-progress'))).width,
        closeTo(192, 2),
      );
    });
  });

  group('the colour of the moment', () {
    testWidgets('the theme gives the background and the digits', (t) async {
      await pump(t, countdown(), wide);
      expect(ground(t), colors.background);
      expect(digitsColour(t), colors.text);
      expect(
        t
            .widget<ColoredBox>(find.byKey(const ValueKey('stage-progress')))
            .color,
        colors.accent,
      );
    });

    testWidgets('the warning period turns the digits and line amber', (
      t,
    ) async {
      await pump(t, countdown(moment: 'warning'), wide);
      expect(digitsColour(t), colors.warn);
      expect(
        t
            .widget<ColoredBox>(find.byKey(const ValueKey('stage-progress')))
            .color,
        colors.warn,
      );
      expect(find.byKey(const ValueKey('stage-tag')), findsNothing);
    });

    testWidgets('a light theme gets a deeper amber that still reads', (
      t,
    ) async {
      await pump(t, countdown(moment: 'warning', themeId: 'warm_ivory'), wide);
      final light = StageColors.of(countdown(themeId: 'warm_ivory'));
      expect(digitsColour(t), light.warn);
      expect(contrast(light.warn, light.background), greaterThan(4.5));
      expect(contrast(light.over, light.background), greaterThan(4.5));
    });

    testWidgets('paused dims the digits and says PAUSED', (t) async {
      await pump(t, countdown(moment: 'paused'), wide);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(ClockText),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity < .6,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an older host, with no theme or warning, looks as it did', (
      t,
    ) async {
      final old = countdown()
        ..remove('stageTheme')
        ..remove('progress')
        ..remove('overtimeAlert');
      await pump(t, old, wide);
      expect(ground(t), Colors.black);
      expect(digitsColour(t), Colors.white);
      expect(t.takeException(), isNull);
    });
  });

  group('overtime', () {
    testWidgets('Strong: the whole screen is solid red with large dark '
        'digits and OVER TIME', (t) async {
      await pump(t, countdown(moment: 'overtime'), wide);
      expect(ground(t), StageColors.overtimeRed);
      expect(digitsColour(t), StageColors.overtimeInk);
      expect(find.text('OVER TIME'), findsOneWidget);
      expect(find.byKey(const ValueKey('stage-overtime-frame')), findsNothing);
      // The digits are large: most of the screen's width.
      expect(t.getRect(find.byType(ClockText)).width, greaterThan(1920 * .6));
      // Readable at a distance: ink on red is at least 4.5:1.
      expect(
        contrast(StageColors.overtimeInk, StageColors.overtimeRed),
        greaterThan(4.5),
      );
      // The host's margin is red too, so no frame of another colour.
      expect(
        stageBackdropOf(countdown(moment: 'overtime')),
        StageColors.overtimeRed,
      );
    });

    testWidgets('Strong is steady: no change from one moment to the next', (
      t,
    ) async {
      await pump(t, countdown(moment: 'overtime'), wide);
      final a = ground(t);
      await t.pump(const Duration(milliseconds: 700));
      expect(ground(t), a);
      await t.pump(const Duration(milliseconds: 700));
      expect(ground(t), a);
    });

    testWidgets('Gentle: the theme background, red digits, a thick red '
        'frame', (t) async {
      await pump(t, countdown(moment: 'overtime', alert: 'gentle'), wide);
      expect(ground(t), colors.background);
      expect(digitsColour(t), colors.over);
      final frame = t.widget<DecoratedBox>(
        find.byKey(const ValueKey('stage-overtime-frame')),
      );
      final border = (frame.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, colors.over);
      expect(border.top.width, greaterThanOrEqualTo(1080 * .03));
      expect(find.text('OVER TIME'), findsOneWidget);
      expect(
        stageBackdropOf(countdown(moment: 'overtime', alert: 'gentle')),
        colors.background,
      );
    });

    testWidgets('Strongest: the red slowly pulses, about every two seconds', (
      t,
    ) async {
      await pump(t, countdown(moment: 'overtime', alert: 'strongest'), wide);
      final seen = <Color>{};
      // Sample across one period: it changes and then comes back.
      final start = ground(t);
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
        seen.add(ground(t));
      }
      expect(seen.length, greaterThan(5));
      // One period on, it is the same red again.
      expect(ground(t).r, closeTo(start.r, .02));
      expect(ground(t).g, closeTo(start.g, .02));
    });

    testWidgets('Strongest stays steady with reduced motion', (t) async {
      await pump(
        t,
        countdown(moment: 'overtime', alert: 'strongest'),
        wide,
        reduceMotion: true,
      );
      final a = ground(t);
      expect(a, StageColors.overtimeRed);
      await t.pump(const Duration(milliseconds: 500));
      expect(ground(t), a);
      await t.pump(const Duration(milliseconds: 500));
      expect(ground(t), a);
    });

    testWidgets('overtime over a banner cue keeps the banner', (t) async {
      final data = {
        ...countdown(moment: 'overtime'),
        'displayText': 'WRAP UP',
        'displayIsTimer': false,
        'outputMode': 'Cue',
        'cuePosition': 'top',
        'underText': '+00:42',
        'underMode': 'Countdown',
        'cueColor': '#ffa833',
      };
      await pump(t, data, wide);
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('stage-banner')), findsOneWidget);
      expect(find.text('WRAP UP'), findsOneWidget);
      expect(ground(t), StageColors.overtimeRed);
      expect(t.takeException(), isNull);
    });

    testWidgets('Up next only is not changed by overtime: it shows no time', (
      t,
    ) async {
      await pump(t, countdown(layout: 'only', moment: 'overtime'), wide);
      expect(ground(t), colors.background);
      expect(find.text('OVER TIME'), findsNothing);
    });
  });

  group('goldens', () {
    for (final (name, data, size) in [
      ('warning-wide', countdown(layout: 'current', moment: 'warning'), wide),
      ('warning-phone', countdown(layout: 'next', moment: 'warning'), phone),
      ('paused-wide', countdown(layout: 'current', moment: 'paused'), wide),
      ('paused-phone', countdown(moment: 'paused'), phone),
      (
        'overtime-strong-wide',
        countdown(layout: 'next', moment: 'overtime'),
        wide,
      ),
      (
        'overtime-strong-phone',
        countdown(layout: 'next', moment: 'overtime'),
        phone,
      ),
      (
        'overtime-gentle-wide',
        countdown(layout: 'current', moment: 'overtime', alert: 'gentle'),
        wide,
      ),
      (
        'overtime-gentle-phone',
        countdown(layout: 'current', moment: 'overtime', alert: 'gentle'),
        phone,
      ),
      (
        'overtime-strongest-wide',
        countdown(moment: 'overtime', alert: 'strongest'),
        wide,
      ),
      (
        'light-current-wide',
        countdown(layout: 'current', themeId: 'warm_ivory'),
        wide,
      ),
      (
        'light-warning-phone',
        countdown(layout: 'next', moment: 'warning', themeId: 'warm_ivory'),
        phone,
      ),
      (
        'light-overtime-gentle',
        countdown(moment: 'overtime', alert: 'gentle', themeId: 'warm_ivory'),
        wide,
      ),
    ]) {
      testWidgets('golden: $name', (t) async {
        await pump(t, data, size, reduceMotion: true);
        await golden(t, name);
      });
    }
  });

  group('the layout chooser', () {
    Future<void> chooser(
      WidgetTester t,
      Size size, {
      String value = 'timer',
      double textScale = 1.0,
      ValueChanged<String>? onChanged,
    }) async {
      setScreen(t, size);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('midnight_lime'),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('What the second screen shows'),
                      const SizedBox(height: 8),
                      StageLayoutTiles(
                        keyPrefix: 'tile',
                        value: value,
                        onChanged: onChanged ?? (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
    }

    testWidgets('four tiles in one row on a desktop, with a tick on the '
        'chosen one', (t) async {
      await chooser(t, const Size(1000, 400), value: 'next');
      final tops = {
        for (final k in stageLayouts.keys)
          k: t.getRect(find.byKey(ValueKey('tile-$k'))).top,
      };
      expect(tops.values.toSet().length, 1);
      for (final name in stageLayouts.values) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('layout-tick-on')), findsOneWidget);
      expect(
        t
            .widget<StageLayoutTile>(find.byKey(const ValueKey('tile-next')))
            .selected,
        isTrue,
      );
      for (final k in stageLayouts.keys) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('tile-$k')),
            matching: find.byKey(ValueKey('layout-miniature-$k')),
          ),
          findsOneWidget,
        );
      }
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/layout-tiles-desktop.png'),
      );
    });

    testWidgets('two to a row on a phone, and one to a row at text scale 1.6', (
      t,
    ) async {
      await chooser(t, phone, value: 'only');
      var rects = [
        for (final k in stageLayouts.keys)
          t.getRect(find.byKey(ValueKey('tile-$k'))),
      ];
      expect(rects[0].top, rects[1].top);
      expect(rects[2].top, rects[3].top);
      expect(rects[2].top, greaterThan(rects[0].bottom));
      expect(rects[0].height, rects[1].height);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/layout-tiles-phone.png'),
      );
      await chooser(t, phone, value: 'current', textScale: 1.6);
      rects = [
        for (final k in stageLayouts.keys)
          t.getRect(find.byKey(ValueKey('tile-$k'))),
      ];
      expect(t.takeException(), isNull);
      for (final r in rects) {
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/layout-tiles-phone-text-1-6.png'),
      );
    });

    testWidgets('tapping a tile chooses it; a locked chooser does nothing', (
      t,
    ) async {
      final chosen = <String>[];
      await chooser(t, phone, onChanged: chosen.add);
      await t.tap(find.byKey(const ValueKey('tile-only')));
      await t.pump();
      expect(chosen, ['only']);
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme('midnight_lime'),
          home: const Scaffold(
            body: StageLayoutTiles(
              keyPrefix: 'tile',
              value: 'timer',
              onChanged: null,
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('tile-only')), warnIfMissed: false);
      expect(chosen, ['only']);
      expect(t.takeException(), isNull);
    });
  });

  group('web screens', () {
    final base = const WebStageSettings(orderCode: 'abcd', localName: 'church');
    // The snapshot carries the display's group's layout.
    Json view(String layout, [Json? data]) => viewFor(WebRole.stage, {
      ...data ?? countdown(),
      'stageLayout': layout,
    }, base);

    test('every layout is offered and saved, and an unknown one is timer', () {
      for (final layout in stageLayouts.keys) {
        final saved = WebStageSettings.fromJson(
          base.copyWith(stageLayout: layout).toJson(),
          churchName: '',
        );
        expect(saved.stageLayout, layout);
      }
      expect(
        WebStageSettings.fromJson({
          ...base.toJson(),
          'stageLayout': 'nonsense',
        }, churchName: '').stageLayout,
        'timer',
      );
    });

    test('the page gets the countdown with its bands and moment', () {
      final current = view('current', countdown(moment: 'warning'));
      expect(current['layout'], 'current');
      expect(current['countdown'], {
        'moment': 'warning',
        'progress': .58,
        'alert': 'strong',
        'now': {'name': 'Sermon', 'by': 'Pastor Daniel'},
        'next': {'name': 'Response', 'detail': 'Worship team · 6 min 30 s'},
      });
      expect(current['theme'], isA<Map>());
      expect(view('only')['layout'], 'only');
    });

    test('overtime carries its strength', () {
      for (final alert in overtimeAlerts.keys) {
        final v = view('timer', countdown(moment: 'overtime', alert: alert));
        expect(v['countdown']['moment'], 'overtime');
        expect(v['countdown']['alert'], alert);
        expect(v['countdown']['progress'], 1);
      }
      // An old host sends no strength: Strong.
      final old = countdown(moment: 'overtime')..remove('overtimeAlert');
      expect(view('timer', old)['countdown']['alert'], 'strong');
    });

    test('Up next only on the last segment gets the end screen or clock', () {
      final last = {
        ...countdown(next: ''),
        'afterEnd': {
          'outputMode': 'End screen',
          'displayText': 'Hallelujah',
          'effect': 'static',
        },
      };
      final v = view('only', last);
      expect(v['displayText'], 'Hallelujah');
      expect(v.containsKey('countdown'), isFalse);
      // The other layouts still count down.
      expect(view('timer', last)['countdown'], isNotNull);
    });

    test('nothing but a countdown has countdown fields', () {
      expect(
        view('timer', {
          'stageSharing': true,
          'displayText': 'AMEN',
          'effect': 'static',
          'outputMode': 'Cue',
        }).containsKey('countdown'),
        isFalse,
      );
    });

    test('the page draws the bands, tag, progress line and red screens', () {
      for (final part in [
        'function renderCountdown(',
        'id="cdProg"',
        'id="cdNow"',
        'id="cdNext"',
        'id="cdOnly"',
        'cdpulse',
        "'OVER TIME'",
        "'UP NEXT'",
        'prefers-reduced-motion',
      ]) {
        expect(webStagePage, contains(part), reason: part);
      }
      expect(webStagePage, isNot(contains('innerHTML')));
    });
  });
}

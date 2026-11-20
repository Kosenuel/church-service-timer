import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/service_check.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// Sunday: 65 minutes, with the default warnings at 2 min, 30 s and zero,
/// a 5 MIN LEFT warning that cannot fire in the 5-minute Welcome (a
/// warning never fires as a segment starts) or the 3-minute Notices, and
/// neither 5 MIN LEFT nor 2 MIN LEFT in the 2-minute Closing.
Timeline sunday() => Timeline(
  'Sunday Service',
  const [
    Segment('Welcome', 5),
    Segment('Notices', 3),
    Segment('Sermon', 40, speaker: 'Pastor Ade'),
    Segment('Response', 15, speaker: 'Worship team'),
    Segment('Closing', 2),
  ],
  // The suggested warnings: 5:00, 2:00, 0:30 and 0:00.
  DisplaySettings(),
);

const checkStart = Stamp(1000, 1700000000000, 'boot');

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  group('the run', () {
    test('runs the whole service in 10 to 20 seconds', () {
      final run = ServiceCheckRun(sunday(), checkStart);
      // 65 minutes in about 12 seconds.
      expect(run.rate, serviceCheckRate(65 * 60000, warnings: 16));
      expect(run.rate, greaterThan(60));
      expect(run.expectedMs, inInclusiveRange(10000, 20000));
      var ticks = 0;
      while (!run.done && ticks < 10000) {
        run.step(50);
        ticks++;
      }
      expect(run.done, isTrue);
      expect(run.elapsedMs, inInclusiveRange(10000, 20000));
      expect(run.elapsedMs, closeTo(run.expectedMs, 400));
      // A 90-minute service also fits.
      final long = ServiceCheckRun(
        Timeline('Long', const [
          Segment('Worship', 45),
          Segment('Sermon', 45),
        ], DisplaySettings()),
        checkStart,
      );
      while (!long.done) {
        long.step(50);
      }
      expect(long.elapsedMs, inInclusiveRange(10000, 20000));
    });

    test('lists every warning that fired, where and at what time', () {
      final run = ServiceCheckRun(sunday(), checkStart);
      while (!run.done) {
        run.step(50);
      }
      // Four warnings in each segment, except Welcome, which starts at
      // 5:00, Notices, too short for 5 MIN LEFT, and Closing, which starts
      // at 2:00.
      expect(run.fired, hasLength(16));
      final welcome = run.firedIn(0);
      expect(
        [for (final w in welcome) w.rule.cue.text],
        ['2 MIN LEFT', 'WRAP UP', "TIME'S UP"],
      );
      expect(
        [for (final w in welcome) formatTime(w.remainingMs!)],
        ['02:00', '00:30', '00:00'],
      );
      // The suggested warnings all show on the stage too.
      expect(welcome.map((w) => w.where).toSet(), {'Operator and stage'});
      expect(run.unreachable, hasLength(4));
      expect(run.unreachableIn(0).single.rule.cue.text, '5 MIN LEFT');
      expect(run.unreachableIn(4).map((w) => w.rule.cue.text), [
        '5 MIN LEFT',
        '2 MIN LEFT',
      ]);
      expect(run.unreachableIn(1).single.rule.cue.text, '5 MIN LEFT');
      expect(run.firedIn(1).map((w) => w.rule.cue.text), [
        '2 MIN LEFT',
        'WRAP UP',
        "TIME'S UP",
      ]);
    });

    test('holds each stage warning on screen for a moment', () {
      final run = ServiceCheckRun(sunday(), checkStart);
      while (run.fired.isEmpty) {
        run.step(50);
      }
      // 2 MIN LEFT has just fired: the stage shows it and the time waits.
      expect(run.session.intended(run.now)!.text, '2 MIN LEFT');
      final left = run.session.remaining(run.now);
      for (var i = 0; i < (run.holdMs ~/ 50) - 1; i++) {
        run.step(50);
        expect(run.session.intended(run.now)!.text, '2 MIN LEFT');
        expect(run.session.remaining(run.now), left);
      }
      expect(run.holdMs, greaterThanOrEqualTo(serviceCheckHoldMinMs));
      run.step(100);
      expect(run.session.intended(run.now)!.text, isNot('2 MIN LEFT'));
      expect(run.session.remaining(run.now), lessThan(left));
    });

    test('a program without warnings still runs through', () {
      final run = ServiceCheckRun(
        Timeline('Plain', const [
          Segment('One', 10),
          Segment('Two', 20),
        ], DisplaySettings(warnings: const [])),
        checkStart,
      );
      while (!run.done) {
        run.step(50);
      }
      expect(run.fired, isEmpty);
      expect(run.elapsedMs, inInclusiveRange(17000, 19000));
    });
  });

  group('the app', () {
    late AppController c;
    late FakePort port;

    Future<void> open(
      WidgetTester t, {
      Size size = const Size(430, 1000),
    }) async {
      setScreen(t, size);
      await t.runAsync(() async {
        port = FakePort();
        c = AppController(port);
        await c.initialize(startTicker: false);
        await c.commit((draft, _) => draft.saveTemplate(sunday()));
        await c.setSimulatorKind('stage');
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
    }

    HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));

    Future<void> begin(WidgetTester t) async {
      unawaited(home(t).checkService(sunday()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('runs on the Simulator only and saves nothing', (t) async {
      await open(t);
      final before = c.state.toJson().toString();
      final saved = port.data;
      final pixels = [...c.simulator.pixels];
      await begin(t);
      expect(find.byType(ServiceCheckPage), findsOneWidget);
      // No question first: nothing real is touched.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('service-check-preview')), findsOne);
      // 14 seconds or so, on a faked clock.
      for (var i = 0; i < 400; i++) {
        await t.pump(const Duration(milliseconds: 50));
        if (find
            .byKey(const ValueKey('service-check-list'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      final page = t.state<ServiceCheckPageState>(
        find.byType(ServiceCheckPage),
      );
      expect(page.run.done, isTrue);
      expect(page.run.elapsedMs, inInclusiveRange(10000, 20000));
      expect(find.text('Check complete'), findsOneWidget);
      expect(find.text('16 warnings fired · 4 could not fire'), findsOneWidget);
      expect(find.textContaining('5 MIN LEFT cannot fire'), findsNWidgets(3));
      expect(find.textContaining('2 MIN LEFT cannot fire'), findsOneWidget);
      // Welcome is 5 min and Closing 2 min: each starts at the warning.
      expect(
        find.textContaining('the whole of this 5 min segment'),
        findsOneWidget,
      );
      expect(
        find.textContaining('the whole of this 2 min segment'),
        findsOneWidget,
      );
      expect(find.text('Planned finish'), findsOneWidget);
      // Nothing was saved, started or sent.
      expect(c.state.session.phase, 'idle');
      expect(c.state.reports, isEmpty);
      expect(c.state.toJson().toString(), before);
      expect(port.data, saved);
      expect(c.simulator.pixels, pixels);
      expect(c.pairedSnapshot(false)['phase'], 'idle');
      expect(c.hardware.sending, isFalse);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const ValueKey('service-check-done')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('service-check-done')));
      await t.pumpAndSettle();
      expect(find.byType(ServiceCheckPage), findsNothing);
    });

    testWidgets('stops at any time', (t) async {
      await open(t);
      await begin(t);
      await t.pump(const Duration(seconds: 3));
      await t.tap(find.byKey(const ValueKey('service-check-stop')));
      await t.pump();
      expect(find.text('Check stopped'), findsOneWidget);
      final page = t.state<ServiceCheckPageState>(
        find.byType(ServiceCheckPage),
      );
      final at = page.run.elapsedMs;
      await t.pump(const Duration(seconds: 5));
      expect(page.run.elapsedMs, at);
      expect(page.run.done, isFalse);
      expect(find.text('Not reached'), findsWidgets);
      await t.ensureVisible(find.byKey(const ValueKey('service-check-done')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('service-check-done')));
      await t.pumpAndSettle();
    });

    testWidgets('cannot start while a service is running', (t) async {
      await open(t);
      await t.runAsync(() async {
        await c.act('load', value: sunday());
        await c.act('start');
      });
      await t.pump();
      expect(c.serviceCheckUnavailable, isNotNull);
      expect(
        home(t).serviceCheckUnavailable,
        'End the current service before checking one.',
      );
      unawaited(home(t).checkService(sunday()));
      await t.pumpAndSettle();
      // It says why, and nothing opens.
      expect(
        find.text('End the current service before checking one.'),
        findsOneWidget,
      );
      expect(find.byType(ServiceCheckPage), findsNothing);
    });

    testWidgets('a service started elsewhere stops the check', (t) async {
      await open(t);
      await begin(t);
      await t.runAsync(() async {
        await c.act('load', value: sunday());
        await c.act('start');
      });
      await t.pump();
      expect(find.text('Check stopped'), findsOneWidget);
    });

    testWidgets('locked controls block it', (t) async {
      await open(t);
      home(t).lockControls();
      await t.pump();
      expect(
        home(t).serviceCheckUnavailable,
        'Unlock the controls to check a service.',
      );
    });

    testWidgets('locked controls block Stop and going back', (t) async {
      await open(t);
      await begin(t);
      home(t).lockControls();
      await t.pump(const Duration(milliseconds: 100));
      expect(
        t
            .widget<OutlinedButton>(
              find.ancestor(
                of: find.text('Stop check'),
                matching: find.byWidgetPredicate((w) => w is OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(t.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
      await t.pump(const Duration(seconds: 25));
    });

    testWidgets('nothing real moves while it runs', (t) async {
      await open(t);
      final saved = port.data;
      await begin(t);
      for (var i = 0; i < 100; i++) {
        await t.pump(const Duration(milliseconds: 50));
        // The service, the sign, stage and web screens and the second
        // screen all stay as they were.
        expect(c.state.session.phase, 'idle');
        expect(c.pairedSnapshot(false)['phase'], 'idle');
        expect(c.stageWindowSnapshot()['phase'], 'idle');
        expect(c.web.snapshot()['phase'], 'idle');
      }
      final page = t.state<ServiceCheckPageState>(
        find.byType(ServiceCheckPage),
      );
      // Meanwhile the check's own stage preview counts down.
      expect(page.stageSnapshot()['phase'], 'active');
      expect(page.stageSnapshot()['stageSharing'], isTrue);
      expect(port.data, saved);
      await t.pump(const Duration(seconds: 25));
    });

    testWidgets('Programs offers it on a program\'s menu', (t) async {
      await open(t);
      await t.tap(find.byType(NavigationDestination).at(1));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('template-row:Sunday Service')));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Program options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Check this service'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(ServiceCheckPage), findsOneWidget);
      await t.pump(const Duration(seconds: 25));
      expect(find.text('Check complete'), findsOneWidget);
    });

    testWidgets('Live offers it beside Start while a service is set up', (
      t,
    ) async {
      await open(t);
      expect(find.byKey(const ValueKey('check-service')), findsNothing);
      await t.runAsync(() => c.act('load', value: sunday()));
      await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('check-service'));
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(ServiceCheckPage), findsOneWidget);
      // The set-up service is left as it was.
      expect(c.state.session.phase, 'ready');
      await t.pump(const Duration(seconds: 25));
      expect(c.state.session.phase, 'ready');
      expect(c.state.reports, isEmpty);
    });

    testWidgets('on the LED simulator it shows the LED sign', (t) async {
      await open(t);
      await t.runAsync(() => c.setSimulatorKind('led'));
      await begin(t);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('service-check-preview')),
          matching: find.byType(LedMatrix),
        ),
        findsOneWidget,
      );
      await t.pump(const Duration(seconds: 25));
      expect(find.text('Check complete'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('while it runs it shows the stage and a warning', (t) async {
      await open(t, size: const Size(430, 932));
      await t.runAsync(() => c.setSimulatorLayout('next'));
      await begin(t);
      final page = t.state<ServiceCheckPageState>(
        find.byType(ServiceCheckPage),
      );
      // On to Notices' 2 MIN LEFT, held on the stage.
      while (page.run.fired.length < 4) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Segment 2 of 5 · Notices'), findsOneWidget);
      expect(page.run.session.intended(page.run.now)!.text, '2 MIN LEFT');
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(ServiceCheckPage),
        matchesGoldenFile('../goldens/service-check-running-phone.png'),
      );
      await t.pump(const Duration(seconds: 25));
    });

    for (final (name, size, desktop) in [
      ('service-check-phone', const Size(430, 1600), false),
      ('desktop-service-check', const Size(1366, 1320), true),
    ]) {
      testWidgets('the checklist looks right: $name', (t) async {
        desktopWording = desktop;
        await open(t, size: size);
        await begin(t);
        await t.pump(const Duration(seconds: 25));
        expect(find.text('Check complete'), findsOneWidget);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(ServiceCheckPage),
          matchesGoldenFile('../goldens/$name.png'),
        );
      });
    }
  });
}

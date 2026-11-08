import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import '../domain/feature_cases.dart' show epoch, at, service;
import 'overtime_cases.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  for (final e in revision05Cases.entries) {
    test(e.key, e.value);
  }
  setUpAll(loadAppFonts);
  void size(WidgetTester t, [Size value = const Size(700, 1500)]) =>
      setScreen(t, value);

  Future<AppController> setup(FakePort port) async {
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.setSharedWarnings([]);
    await c.act(
      'load',
      value: Timeline('Sunday Service', const [
        Segment('Praise & Worship', 10),
        Segment('Announcements', 5),
      ], DisplaySettings(warnings: [])),
    );
    await c.act('start');
    return c;
  }

  testWidgets(
    'Custom removes time only after confirmation, saving allocation',
    (t) async {
      size(t);
      final port = FakePort()..at = epoch;
      final c = await setup(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Custom'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove time'));
      await t.pumpAndSettle();
      await t.tapAt(t.getCenter(find.byType(CupertinoPicker).first));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '1');
      await t.tap(find.text('Use value'));
      await t.pumpAndSettle();
      await t.pumpAndSettle();
      expect(find.text('08:30'), findsOneWidget);
      expect(c.state.session.allocatedMs, 600000);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.remaining(c.now), 600000);
      await t.tap(find.text('Custom'));
      await t.pumpAndSettle();
      await t.tap(find.text('Remove time'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm remove time'));
      await t.pumpAndSettle();
      expect(c.state.session.remaining(c.now), 570000);
      expect(c.state.session.allocatedMs, 570000);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = AppController(port);
      await restored.initialize(startTicker: false);
      expect(restored.state.session.allocatedMs, 570000);
      restored.dispose();
    },
  );

  testWidgets(
    'Adjustment preview updates with time and rejects a stale segment',
    (t) async {
      size(t);
      final port = FakePort()..at = epoch;
      final c = await setup(port);
      port.at = at(61);
      await c.tick();
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('+2 min'));
      await t.pumpAndSettle();
      expect(find.text('10:59'), findsOneWidget);
      port.at = at(64);
      await c.tick();
      await t.pumpAndSettle();
      expect(find.text('10:56'), findsOneWidget);
      await c.act('advance');
      await t.pumpAndSettle();
      expect(find.textContaining('The service changed.'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm +2 min'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);
      expect(c.state.session.allocatedMs, 300000);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Next names destination; Undo always confirms the paused state', (
    t,
  ) async {
    size(t);
    final port = FakePort()..at = epoch;
    final c = await setup(port);
    await c.act('pause');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Next segment'));
    await t.pumpAndSettle();
    expect(find.text('Start Announcements?'), findsOneWidget);
    expect(find.textContaining('Announcements · 5 min.'), findsOneWidget);
    expect(c.state.session.index, 0);
    await t.tap(find.text('Start Announcements'));
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    expect(c.state.session.paused, false);
    await t.tap(find.byKey(const ValueKey('undo')));
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    expect(
      find.textContaining('Its timer will remain paused.'),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    await t.tap(find.byKey(const ValueKey('undo')));
    await t.pumpAndSettle();
    await t.tap(find.text('Restore previous segment'));
    await t.pumpAndSettle();
    expect(c.state.session.index, 0);
    expect(c.state.session.paused, true);
    expect(c.state.session.undo, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Connection banner follows simulator transport and retains stale frame',
    (t) async {
      size(t);
      final port = FakePort()..at = epoch;
      final c = await setup(port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('header-connection')),
          matching: find.text('Simulator'),
        ),
        findsOneWidget,
      );
      expect(find.text('Display connected'), findsNothing);
      await c.act('disconnect');
      port.at = at(30);
      await c.tick();
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('display-disconnected-banner')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('header-connection')),
          matching: find.text('Disconnected'),
        ),
        findsOneWidget,
      );
      expect(c.simulator.delivered!.text, '10:00');
      expect(c.state.session.formatted(c.now), '09:30');
      await c.act('connect');
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('display-disconnected-banner')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('header-connection')),
          matching: find.text('Simulator'),
        ),
        findsOneWidget,
      );
      expect(c.simulator.delivered!.text, '09:30');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Overtime uses an empty arc and adding time pays it down', (
    t,
  ) async {
    size(t, const Size(430, 1200));
    final port = FakePort()..at = epoch;
    final c = await setup(port);
    port.at = at(623);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.text('+00:23'), findsOneWidget);
    expect(find.text('OVERTIME'), findsOneWidget);
    final painter = t
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<TimerArcPainter>()
        .single;
    expect(painter.progress, 0);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/phone-overtime.png'),
    );
    await t.ensureVisible(find.text('+2 min'));
    await t.tap(find.text('+2 min'));
    await t.pumpAndSettle();
    expect(find.text('01:37'), findsOneWidget);
    await t.tap(find.text('Confirm +2 min'));
    await t.pumpAndSettle();
    expect(c.state.session.balance(c.now), 97000);
    expect(c.state.session.allocatedMs, 720000);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Gauge handles large text, narrow width and zero allocation', (
    t,
  ) async {
    size(t, const Size(320, 900));
    var s = service(firstMinutes: 1, warnings: []);
    s = transition(s, 'adjust', epoch, value: -60);
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(40),
              child: SegmentGauge(session: s, now: at(23)),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('of 00:00 allocated'), findsOneWidget);
    expect(find.text('+00:23'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Phone Live controls and Custom dialog reflow with large text', (
    t,
  ) async {
    size(t, const Size(320, 1100));
    final port = FakePort()..at = epoch;
    final c = await setup(port);
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Home(controller: c),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.text('+2 min')).dy,
      greaterThan(t.getTopLeft(find.text('−2 min')).dy),
    );
    expect(t.takeException(), isNull);
    await Scrollable.ensureVisible(
      t.element(find.text('Custom')),
      alignment: .5,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Custom'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });
}

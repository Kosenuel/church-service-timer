import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

import '../support/live_helpers.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAppFonts);
  testWidgets('Phone dashboard loads Ready and starts only on confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await tester.pumpWidget(TimerApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start service'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quick rehearsal'));
    await tester.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    expect(c.simulator.delivered, isNull);
    await tester.ensureVisible(find.text('Start first segment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start first segment'));
    await tester.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Start first segment').last,
    );
    await tester.pumpAndSettle();
    expect(c.state.session.active, true);
    expect(c.simulator.delivered!.text, '01:00');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/phone-live.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Tablet active dashboard lays out and keeps alert over countdown',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await c.act('cue', value: const TextLayout('WRAP UP', bold: true));
      port.at = after(90);
      await c.tick();
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('13:30'), findsOneWidget);
      expect(find.text('Showing cue: WRAP UP'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/tablet-live.png'),
      );
      await tester.ensureVisible(find.text('Show timer'));
      await tester.scrollUntilVisible(
        find.text('Show timer').hitTestable(),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await passShowTimerGuard(tester);
      await tester.tap(find.text('Show timer').hitTestable());
      await tester.pumpAndSettle();
      expect(c.state.session.alert, isNull);
      expect(c.simulator.delivered!.text, '13:30');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Display settings edit is isolated from the running snapshot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakePort()..at = start;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await tester.pumpWidget(TimerApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display settings'));
    await tester.pumpAndSettle();
    expect(find.text('Default end screen'), findsOneWidget);
    await tester.ensureVisible(find.text('Default end screen'));
    await tester.tap(find.text('Default end screen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Edit end screen'));
    await tester.tap(find.text('Edit end screen'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).first, 'Amen');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Save end screen'));
    await tester.pumpAndSettle();
    expect(c.state.defaults.end.text, 'Amen');
    expect(c.state.session.timeline!.display.end.text, 'Hallelujah');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

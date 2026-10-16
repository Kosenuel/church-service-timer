import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/controller.dart';
import 'feature_cases.dart';
import 'domain_test.dart' show FakePort;

void main() {
  setUpAll(() async {
    final fonts = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  void size(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'Ready selects fast rehearsal and live overview labels simulated time',
    (tester) async {
      size(tester, const Size(500, 1100));
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live timing · 1×'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fast rehearsal · 10×').last);
      await tester.pumpAndSettle();
      expect(c.state.session.rate, 10);
      await c.act('start');
      port.at = at(2);
      await c.tick();
      await tester.pumpAndSettle();
      expect(find.text('00:40'), findsOneWidget);
      await tester.ensureVisible(find.text('REHEARSAL TIMING · 10×'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Durations are simulated at 10×'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Saving a stage cue preserves chosen font, bold, italic and size after restart',
    (tester) async {
      size(tester, const Size(500, 1100));
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Display'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create saved cue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create saved cue'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.widgetWithText(TextField, 'Display text'),
        'WRAP UP',
      );
      await tester.tap(find.text('Bold'));
      await tester.tap(find.text('Italic'));
      await tester.tap(find.text('Tall · 14 px'));
      await tester.ensureVisible(find.text('Cuekeeper Matrix'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Cuekeeper Matrix'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Service Serif').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Name and save'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save formatted cue'));
      await tester.pumpAndSettle();
      final cue = c.state.savedCues.single;
      expect(cue.layout.font, 'service_serif');
      expect(cue.layout.bold, true);
      expect(cue.layout.italic, true);
      expect(cue.layout.height, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      final restored = AppController(port);
      await restored.initialize(startTicker: false);
      expect(
        restored.state.savedCues.single.layout.toJson(),
        cue.layout.toJson(),
      );
      restored.dispose();
    },
  );

  testWidgets(
    'Warning editor changes destination without modifying the running snapshot',
    (tester) async {
      size(tester, const Size(500, 1100));
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Display'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('02:00 · 2 MIN LEFT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('02:00 · 2 MIN LEFT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operator screen only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operator + simulated stage').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save warning'));
      await tester.pumpAndSettle();
      expect(c.state.defaults.warnings.first.destination, 'stage');
      expect(
        c.state.session.timeline!.display.warnings.first.destination,
        'operator',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Report displays completed segment durations and rehearsal label',
    (tester) async {
      size(tester, const Size(1050, 1050));
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await c.act('rate', value: 10);
      await c.act('start');
      port.at = at(8);
      await c.act('advance');
      port.at = at(19);
      await c.act('advance');
      port.at = at(25);
      await c.act('end');
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      expect(find.text('Rehearsal 10×'), findsOneWidget);
      expect(find.text('Planned 4m 0s · Actual 4m 10s'), findsOneWidget);
      expect(find.text('Export report CSV'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/service-report.png'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

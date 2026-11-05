import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import '../domain/feature_cases.dart';
import '../domain/service_timing_test.dart' show FakePort;

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
      // The one-line status opens the full rehearsal overview.
      await tester.tap(find.byKey(const ValueKey('timing-status-line')));
      await tester.pumpAndSettle();
      expect(find.text('REHEARSAL TIMING · 10×'), findsOneWidget);
      expect(
        find.textContaining('Durations are simulated at 10×'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Settings cue editing persists formatting; Live sends without a dialog',
    (tester) async {
      size(tester, const Size(700, 1500));
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Saved cue library'), findsNothing);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Stage cues'));
      await tester.tap(find.text('Stage cues'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WRAP UP'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.widgetWithText(TextField, 'Display text'),
        'FINISH NOW',
      );
      await tester.tap(find.text('Bold'));
      await tester.tap(find.text('Italic'));
      await tester.tap(find.text('I-Proton Matrix'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('I-Proton Sq-Matrix').last);
      await tester.tap(find.text('I-Proton Sq-Matrix').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Tall · 14 px'));
      await tester.tap(find.text('Tall · 14 px'));
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save cue'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save cue'));
      await tester.pumpAndSettle();
      final saved = c.state.stageCues.first;
      expect(saved.text, 'FINISH NOW');
      expect(saved.bold && saved.italic, true);
      expect(saved.height, 2);
      expect(saved.font, 'cuekeeper_sq_matrix');
      expect(c.state.session.alert, isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Live'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'FINISH NOW'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'FINISH NOW'));
      await tester.pumpAndSettle();
      expect(find.byType(TextComposer), findsNothing);
      expect(c.state.session.alert!.toJson(), saved.toJson());
      await c.act('end');
      await c.act('load', value: c.state.templates.first);
      expect(c.state.stageCues.first.toJson(), saved.toJson());
      await tester.pumpWidget(const SizedBox());
      final restarted = AppController(port);
      await restarted.initialize(startTicker: false);
      expect(restarted.state.stageCues.first.toJson(), saved.toJson());
      restarted.dispose();
    },
  );

  testWidgets(
    'Warning editor updates shared rules including the running snapshot',
    (tester) async {
      size(tester, const Size(500, 1100));
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Warnings & alerts'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('2 MIN LEFT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 MIN LEFT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operator + stage display'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Operator + phone notification').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save warning'));
      await tester.pumpAndSettle();
      expect(c.state.defaults.warnings.first.destination, 'operator');
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
      await tester.tap(
        find.byKey(ValueKey('open-report-${c.state.reports.single.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ReportDetailPage),
          matching: find.text('Rehearsal 10×'),
        ),
        findsOneWidget,
      );
      expect(find.text('4m 0s'), findsOneWidget);
      expect(find.text('4m 10s'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-actions')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/service-report.png'),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}

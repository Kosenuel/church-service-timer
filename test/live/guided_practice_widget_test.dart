import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('Live offers practice, coaches each step and sums it up', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('start-practice')));
    await t.tap(find.byKey(const ValueKey('start-practice')));
    await t.pumpAndSettle();
    expect(c.practice.active, isTrue);
    expect(find.byKey(const ValueKey('practice-coach')), findsOneWidget);
    expect(find.text('Step 1 · Start the service'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/practice-coach.png'),
    );
    await c.act('start');
    await t.pumpAndSettle();
    expect(find.text('Step 2 · Pause, then resume'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('practice-skip')));
    await t.pumpAndSettle();
    expect(find.textContaining('Step 3 ·'), findsOneWidget);
    await c.act('end');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('practice-summary')), findsOneWidget);
    expect(find.textContaining('No report was saved'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('practice-done')));
    await t.pumpAndSettle();
    expect(c.state.reports, isEmpty);
    expect(c.state.practisedWall, isNotNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Don’t show again hides the invitation', (t) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('hide-practice-prompt')));
    await t.tap(find.byKey(const ValueKey('hide-practice-prompt')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('start-practice')), findsNothing);
    expect(c.state.practicePrompt, isFalse);
    await t.pumpWidget(const SizedBox());
  });
}

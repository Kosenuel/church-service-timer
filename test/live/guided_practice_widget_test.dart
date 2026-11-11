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

  testWidgets('Starting practice from Settings › About opens Live', (t) async {
    setScreen(t, const Size(430, 1000));
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('About', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('About'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('about-practice')));
    await t.tap(find.byKey(const ValueKey('about-practice')));
    await t.pumpAndSettle();
    expect(c.practice.active, isTrue);
    // The About page is closed and the Live tab shows the coach.
    expect(find.byKey(const ValueKey('about-practice')), findsNothing);
    expect(t.state<HomeState>(find.byType(Home)).page, 0);
    expect(find.byKey(const ValueKey('practice-coach')), findsOneWidget);
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

  testWidgets('Not now hides the invitation without turning it off', (t) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(
      find.text(
        'You can also start it any time from Settings › About › Guided practice.',
      ),
      findsOneWidget,
    );
    await t.ensureVisible(find.byKey(const ValueKey('snooze-practice-prompt')));
    await t.tap(find.byKey(const ValueKey('snooze-practice-prompt')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('start-practice'), skipOffstage: false),
      findsNothing,
    );
    // Only hidden for now: the saved choice is unchanged.
    expect(c.state.practicePrompt, isTrue);

    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The practice pointer follows each step', (t) async {
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
    final pointer = find.byKey(
      const ValueKey('practice-pointer'),
      skipOffstage: false,
    );
    // Exactly one control is pointed at, and it is the one the step needs.
    Future<void> expectPointerOn(String id, Finder target) async {
      await t.pumpAndSettle();
      expect(c.practice.pointer, id);
      expect(pointer, findsOneWidget);
      final ring = t.getRect(pointer);
      final control = t.getRect(target);
      expect(ring.contains(control.center), isTrue, reason: id);
    }

    await expectPointerOn('start', find.text('Start first segment'));
    await c.act('start');
    await expectPointerOn(
      'pause',
      find.byKey(const ValueKey('pause-resume'), skipOffstage: false),
    );
    await c.act('pause');
    await c.act('pause');
    await expectPointerOn('plus', find.text('+2 min', skipOffstage: false));
    await c.act('adjust', value: 120);
    await expectPointerOn('minus', find.text('−2 min', skipOffstage: false));
    expect(find.text('Tap −2 min', skipOffstage: false), findsOneWidget);
    await c.act('adjust', value: -120);
    await expectPointerOn(
      'next',
      find.byKey(const ValueKey('next-segment'), skipOffstage: false),
    );
    await c.act('advance');
    await expectPointerOn(
      'undo',
      find.byKey(const ValueKey('undo'), skipOffstage: false),
    );
    await c.practice.leave();
    await t.pumpAndSettle();
    expect(c.practice.pointer, isNull);
    expect(pointer, findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import '../domain/service_timing_test.dart' show FakePort, timeline;
import '../support/live_helpers.dart';

void main() {
  void size(WidgetTester t, [Size value = const Size(430, 1000)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<AppController> running(WidgetTester t, {Size? at}) async {
    size(t, at ?? const Size(430, 1000));
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: timeline());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> tapVisible(WidgetTester t, Finder target) async {
    await Scrollable.ensureVisible(t.element(target), alignment: .5);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  testWidgets('Header names the program and labels the display destination', (
    t,
  ) async {
    await running(t);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('header-title'))).data,
      'Sunday',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('header-connection')),
        matching: find.text('Simulator'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('control-lock')), findsOneWidget);
    expect(find.text('Lock controls'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'A sent cue swaps to Show timer, ignores an immediate second tap and returns',
    (t) async {
      final c = await running(t);
      final cue = c.state.stageCues.first;
      await tapVisible(t, find.text(cue.text));
      expect(c.state.session.outputMode(c.now), 'Cue');
      final swap = find.byKey(const ValueKey('show-timer-cue-0'));
      expect(swap, findsOneWidget);
      expect(find.text('${cue.text} in simulator'), findsOneWidget);
      // A quick second tap lands on the swapped button and is ignored.
      await t.tap(swap);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Cue');
      await passShowTimerGuard(t);
      await t.tap(swap);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown');
      expect(find.text(cue.text), findsOneWidget);
      expect(swap, findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Sending another cue moves the swap to that button', (t) async {
    final c = await running(t);
    final cues = c.state.stageCues;
    await tapVisible(t, find.text(cues[0].text));
    await tapVisible(t, find.text(cues[1].text));
    expect(c.state.session.alert?.text, cues[1].text);
    expect(find.byKey(const ValueKey('show-timer-cue-0')), findsNothing);
    expect(find.byKey(const ValueKey('show-timer-cue-1')), findsOneWidget);
    expect(find.text(cues[0].text), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Show clock swaps to Show timer, which restores the countdown', (
    t,
  ) async {
    final c = await running(t);
    await tapVisible(t, find.text('Show clock'));
    expect(c.state.session.outputMode(c.now), 'Clock');
    expect(find.text('Show clock'), findsNothing);
    await passShowTimerGuard(t);
    await tapVisible(t, find.byKey(const ValueKey('show-timer-clock')));
    expect(c.state.session.outputMode(c.now), 'Countdown');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Wide windows use a navigation rail and the timing bar', (
    t,
  ) async {
    await running(t, at: const Size(1280, 900));
    expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('timing-status-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('timing-status-line')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Phones keep the bottom bar and show the one-line status', (
    t,
  ) async {
    await running(t);
    expect(find.byKey(const ValueKey('navigation-rail')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('timing-status-line')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

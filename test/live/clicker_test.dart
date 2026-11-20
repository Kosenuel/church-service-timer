import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  Future<AppController> running(WidgetTester t) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('B pauses and resumes; Page Down needs a second press', (
    t,
  ) async {
    final c = await running(t);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(c.state.session.index, 0);
    expect(find.textContaining('Press again to start'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A slow second press only arms Next again', (t) async {
    final c = await running(t);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 5)));
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(c.state.session.index, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Clicker keys do nothing when turned off or away from Live', (
    t,
  ) async {
    final c = await running(t);
    await c.commit((draft, _) => draft.clickerControls = false);
    for (final key in [
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
      expect(find.textContaining('Press again to start'), findsNothing);
    }
    expect(c.state.session.paused, isFalse);
    expect(c.state.session.index, 0);
    await c.commit((draft, _) => draft.clickerControls = true);
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    await t.pumpWidget(const SizedBox());
  });
}

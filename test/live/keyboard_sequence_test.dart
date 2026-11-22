import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../windows/mini_timer_test.dart' show DesktopPort, FakeMiniWindow;
import 'desktop_layout_test.dart' show sunday;

/// Keyboard regression: a shortcut that works once must work every time.
/// The owner saw Ctrl+K work once and then only now and then on Windows,
/// so these press every Ctrl shortcut again and again, in the orders a
/// real service makes: across dialogs, pages, locking and the mini timer.
void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  const size = Size(1366, 768);

  Future<AppController> running(
    WidgetTester t, {
    String layout = 'three_panes',
  }) async {
    setScreen(t, size);
    final port = DesktopPort()..mini = FakeMiniWindow(t, size);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: layout),
    );
    await c.act('load', value: sunday());
    await c.act('start');
    port.at = after(340);
    await c.tick();
    await c.act('advance');
    port.at = after(700);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));
  final palette = find.byKey(const ValueKey('command-palette'));
  final sheet = find.byKey(const ValueKey('shortcuts-sheet'));

  Future<void> ctrl(WidgetTester t, LogicalKeyboardKey key) async {
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(key);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
  }

  Future<void> esc(WidgetTester t) async {
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
  }

  testWidgets('Ctrl+K opens the palette every time, after Esc', (t) async {
    await running(t);
    for (var i = 0; i < 3; i++) {
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: 'press ${i + 1}');
      await esc(t);
      expect(palette, findsNothing, reason: 'close ${i + 1}');
      expect(home(t).typingInField, isFalse, reason: 'focus after ${i + 1}');
    }
  });

  testWidgets('Ctrl+K again after choosing a command', (t) async {
    await running(t);
    for (var i = 0; i < 4; i++) {
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: 'open ${i + 1}');
      await t.enterText(find.byKey(const ValueKey('command-search')), 'keys');
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(sheet, findsOneWidget, reason: 'sheet ${i + 1}');
      expect(palette, findsNothing);
      await esc(t);
      expect(home(t).typingInField, isFalse, reason: 'focus ${i + 1}');
    }
    await ctrl(t, LogicalKeyboardKey.keyK);
    expect(palette, findsOneWidget);
  });

  testWidgets('every Ctrl shortcut, round after round', (t) async {
    final c = await running(t);
    final ask = find.byType(AlertDialog);
    for (var round = 1; round <= 2; round++) {
      final r = 'round $round';
      // Commands, closed with Esc, then again.
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: '$r Ctrl+K');
      // Ctrl+K inside the palette does not stack another.
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: '$r Ctrl+K inside');
      await esc(t);
      // The keys list over Live, with Ctrl+K pressed on top of it.
      await t.sendKeyEvent(LogicalKeyboardKey.f1);
      await t.pumpAndSettle();
      expect(sheet, findsOneWidget, reason: '$r F1');
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsNothing, reason: '$r Ctrl+K over the sheet');
      await esc(t);
      expect(sheet, findsNothing);
      // Undo asks first, and Esc cancels.
      await ctrl(t, LogicalKeyboardKey.keyZ);
      expect(ask, findsOneWidget, reason: '$r Ctrl+Z');
      await esc(t);
      expect(ask, findsNothing);
      // Ctrl+K straight after a question closes.
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: '$r Ctrl+K after a question');
      await esc(t);
      // A page away and back.
      await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
      await t.pumpAndSettle();
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: '$r Ctrl+K on Programs');
      await esc(t);
      await t.tap(find.byKey(const ValueKey('desktop-tab-0')));
      await t.pumpAndSettle();
      // Mini timer in and out.
      await ctrl(t, LogicalKeyboardKey.keyM);
      expect(home(t).miniTimer, isTrue, reason: '$r Ctrl+M in');
      await ctrl(t, LogicalKeyboardKey.keyM);
      expect(home(t).miniTimer, isFalse, reason: '$r Ctrl+M out');
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: '$r Ctrl+K after mini');
      await esc(t);
      // Lock, then Ctrl+K does nothing, then unlock and it works.
      await ctrl(t, LogicalKeyboardKey.keyL);
      expect(c.uiLocked, isTrue, reason: '$r Ctrl+L');
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsNothing, reason: '$r Ctrl+K locked');
      await t.longPress(find.byKey(const ValueKey('unlock-controls')));
      await t.pumpAndSettle();
      expect(c.uiLocked, isFalse);
      await ctrl(t, LogicalKeyboardKey.keyK);
      expect(palette, findsOneWidget, reason: '$r Ctrl+K after unlock');
      await esc(t);
    }
  });

  testWidgets('a lost key-up does not make Ctrl+K work every other time', (
    t,
  ) async {
    await running(t);
    var now = Duration.zero;
    home(t).keyClock = () => now;
    // Windows sometimes never reports the key-up (a window or an input
    // method took it); the next press then arrives as a repeat. Held
    // keys repeat within milliseconds; a repeat after a pause is a press.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await t.pumpAndSettle();
    expect(palette, findsOneWidget);
    // K is never released. Close the palette, wait, press again.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(palette, findsNothing);
    for (var i = 0; i < 3; i++) {
      now += const Duration(seconds: 5);
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
      await t.pumpAndSettle();
      expect(palette, findsOneWidget, reason: 'press ${i + 2}');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
    }
    // A key held down still counts once, however long it repeats.
    now += const Duration(seconds: 5);
    await t.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
    await t.pumpAndSettle();
    expect(palette, findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      now += const Duration(milliseconds: 33);
      await t.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
      await t.pumpAndSettle();
    }
    expect(palette, findsNothing);
    await t.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Ctrl+K works with a field still holding the keyboard', (
    t,
  ) async {
    await running(t);
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    final field = find.byType(EditableText).first;
    await t.tap(field);
    await t.pumpAndSettle();
    expect(home(t).typingInField, isTrue);
    await ctrl(t, LogicalKeyboardKey.keyK);
    expect(palette, findsOneWidget);
    await esc(t);
    // Typing a question mark is still typing.
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
    await t.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pumpAndSettle();
    expect(sheet, findsNothing);
  });

  testWidgets('the list of Ctrl shortcuts is the one these tests press', (
    t,
  ) async {
    // A new Ctrl or Alt shortcut must be added to the sequences above.
    final withCtrl = {
      for (final s in shortcuts)
        if (s.presses.any((p) => p.control == true)) s.id,
    };
    expect(withCtrl, {'undo', 'lock', 'commands', 'mini'});
  });

  testWidgets(
    'plain keys and dialogs, round after round, with Ctrl+K between',
    (t) async {
      await running(t);
      final ask = find.byType(AlertDialog);
      final dialogs = find.byType(Dialog);
      for (var round = 1; round <= 2; round++) {
        for (final key in [
          LogicalKeyboardKey.space, // pause asks first
          LogicalKeyboardKey.equal, // adjust time
          LogicalKeyboardKey.keyJ, // jump
        ]) {
          await t.sendKeyEvent(key);
          await t.pumpAndSettle();
          expect(
            ask.evaluate().isNotEmpty || dialogs.evaluate().isNotEmpty,
            isTrue,
            reason: 'round $round, ${key.keyLabel}',
          );
          await esc(t);
          expect(ask, findsNothing);
          await ctrl(t, LogicalKeyboardKey.keyK);
          expect(palette, findsOneWidget, reason: 'round $round after $key');
          await esc(t);
        }
        // ? and F1, F11 in and out.
        await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await t.sendKeyDownEvent(LogicalKeyboardKey.slash, character: '?');
        await t.sendKeyUpEvent(LogicalKeyboardKey.slash);
        await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await t.pumpAndSettle();
        expect(sheet, findsOneWidget, reason: 'round $round ?');
        await esc(t);
        await t.sendKeyEvent(LogicalKeyboardKey.f11);
        await t.pumpAndSettle();
        expect(home(t).hostFullScreen.showing, isTrue, reason: 'round $round');
        await t.sendKeyEvent(LogicalKeyboardKey.f11);
        await t.pumpAndSettle();
        expect(home(t).hostFullScreen.showing, isFalse);
        await ctrl(t, LogicalKeyboardKey.keyK);
        expect(palette, findsOneWidget, reason: 'round $round after F11');
        await esc(t);
      }
    },
  );
}

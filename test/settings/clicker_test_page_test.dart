import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/settings/clicker_test_page.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show sunday;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../windows/mini_timer_test.dart' show DesktopPort, FakeMiniWindow;

/// Settings › Warnings & alerts › Test a clicker or pedal: it names each
/// key and says what it does on Live, and nothing pressed there reaches
/// the service.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  const full = Size(1920, 1080);

  /// A service in its second segment, with the test page open.
  Future<AppController> testing(
    WidgetTester t, {
    Size size = full,
    bool desktop = true,
    bool clickerOn = true,
    bool start = true,
  }) async {
    desktopWording = desktop;
    setScreen(t, size);
    final port = desktop
        ? (DesktopPort()..mini = FakeMiniWindow(t, size))
        : FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) => draft.clickerControls = clickerOn);
    if (start) {
      await c.act('load', value: sunday());
      await c.act('start');
      port.at = after(340);
      await c.tick();
      await c.act('advance');
      port.at = after(700);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final home = t.state<HomeState>(find.byType(Home, skipOffstage: false));
    home.navigatePage(3);
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Warnings & alerts'));
    await t.pumpAndSettle();
    await t.tap(find.text('Warnings & alerts'));
    await t.pumpAndSettle();
    final row = find.text('Test a clicker or pedal');
    await t.ensureVisible(row);
    await t.pumpAndSettle();
    // The row sits right under the setting it tests.
    expect(
      t.getTopLeft(row).dy,
      greaterThan(
        t.getTopLeft(find.byKey(const ValueKey('clicker-controls'))).dy,
      ),
    );
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('clicker-test')), findsOneWidget);
    expect(clickerTestOpen, isTrue);
    return c;
  }

  Future<void> press(
    WidgetTester t,
    LogicalKeyboardKey key, {
    bool control = false,
  }) async {
    if (control) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(key);
    if (control) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
  }

  String shownKey(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('clicker-test-key'))).data!;
  String shownExplanation(WidgetTester t) => t
      .widget<Text>(find.byKey(const ValueKey('clicker-test-explanation')))
      .data!;

  /// The whole service as text: anything a key did to it would show.
  String service(AppController c) => c.state.session.toJson().toString();

  void expectUntouched(WidgetTester t, String before, AppController c) {
    expect(service(c), before);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    final home = t.state<HomeState>(find.byType(Home, skipOffstage: false));
    expect(home.miniTimer, isFalse);
    expect(home.controlsLocked, isFalse);
    // Still on the test page.
    expect(find.byKey(const ValueKey('clicker-test')), findsOneWidget);
  }

  testWidgets('a running service is untouched by Page Down, Space and B', (
    t,
  ) async {
    final c = await testing(t);
    final before = service(c);
    expect(find.text('Waiting for a press'), findsOneWidget);
    expect(
      find.text('A service is running. Nothing you press here reaches it.'),
      findsOneWidget,
    );

    await press(t, LogicalKeyboardKey.pageDown);
    expect(shownKey(t), 'Page Down');
    expect(shownExplanation(t), 'Next segment: press twice to confirm');
    expectUntouched(t, before, c);
    // The second press, which on Live would start the next segment.
    await press(t, LogicalKeyboardKey.pageDown);
    expect(c.state.session.index, 1);
    expectUntouched(t, before, c);

    await press(t, LogicalKeyboardKey.arrowRight);
    expect(shownKey(t), 'Right arrow');
    expect(shownExplanation(t), 'Next segment: press twice to confirm');
    expectUntouched(t, before, c);

    await press(t, LogicalKeyboardKey.space);
    expect(shownKey(t), 'Space');
    expect(shownExplanation(t), 'Pause or resume: asks first');
    expectUntouched(t, before, c);

    await press(t, LogicalKeyboardKey.keyB);
    expect(shownKey(t), 'B');
    expect(shownExplanation(t), 'Pause or resume: asks first');
    expect(c.state.session.paused, isFalse);
    expectUntouched(t, before, c);
    expect(t.takeException(), isNull);
  });

  testWidgets('no other shortcut reaches the service either', (t) async {
    final c = await testing(t);
    final before = service(c);
    // Every listed press, Ctrl held where it matters: undo, lock, the
    // mini timer, the cues, Commands and the shortcuts sheet among them.
    for (final s in shortcuts) {
      for (final p in s.presses) {
        // The test keyboard has no key of its own for these two.
        if (p.key == LogicalKeyboardKey.add ||
            p.key == LogicalKeyboardKey.question) {
          continue;
        }
        if (p.key == LogicalKeyboardKey.escape ||
            p.key == LogicalKeyboardKey.enter ||
            p.key == LogicalKeyboardKey.numpadEnter) {
          continue;
        }
        if (p.shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await press(t, p.key, control: p.control ?? false);
        if (p.shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(
          shownExplanation(t),
          s.explanation(desktop: true),
          reason: shownKey(t),
        );
        expectUntouched(t, before, c);
      }
    }
    expect(find.byKey(const ValueKey('shortcuts-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('command-palette')), findsNothing);
    await press(t, LogicalKeyboardKey.keyZ, control: true);
    expect(shownKey(t), 'Ctrl + Z');
    expect(shownExplanation(t), 'Undo the last segment change: asks first');
    expect(t.takeException(), isNull);
  });

  testWidgets('a key the app does not use says so', (t) async {
    final c = await testing(t);
    final before = service(c);
    for (final (key, name) in [
      (LogicalKeyboardKey.f5, 'F5'),
      (LogicalKeyboardKey.pageUp, 'Page Up'),
      (LogicalKeyboardKey.arrowLeft, 'Left arrow'),
      (LogicalKeyboardKey.period, 'Full stop'),
      (LogicalKeyboardKey.keyQ, 'Q'),
    ]) {
      await press(t, key);
      expect(shownKey(t), name);
      expect(shownExplanation(t), 'Nothing: the app does not use this key');
      expectUntouched(t, before, c);
    }
  });

  testWidgets('keeps the last few presses, newest first, and clears', (
    t,
  ) async {
    await testing(t);
    expect(find.text('BEFORE THAT'), findsNothing);
    final keys = [
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.f2,
      LogicalKeyboardKey.f3,
      LogicalKeyboardKey.f4,
      LogicalKeyboardKey.f5,
      LogicalKeyboardKey.f6,
      LogicalKeyboardKey.f7,
      LogicalKeyboardKey.pageDown,
    ];
    for (final key in keys) {
      await press(t, key);
    }
    expect(shownKey(t), 'Page Down');
    expect(find.text('8 presses so far'), findsOneWidget);
    final history = find.byKey(const ValueKey('clicker-test-history'));
    Finder earlier(String name) =>
        find.descendant(of: history, matching: find.text(name));
    // Five before the last one; the oldest have gone.
    for (final name in ['F7', 'F6', 'F5', 'F4', 'F3']) {
      expect(earlier(name), findsOneWidget);
    }
    expect(earlier('F2'), findsNothing);
    expect(earlier('F1'), findsNothing);
    expect(
      t.getTopLeft(earlier('F7')).dy,
      lessThan(t.getTopLeft(earlier('F3')).dy),
    );
    await t.ensureVisible(find.byKey(const ValueKey('clicker-test-clear')));
    await t.tap(find.byKey(const ValueKey('clicker-test-clear')));
    await t.pumpAndSettle();
    expect(find.text('Waiting for a press'), findsOneWidget);
    expect(find.text('BEFORE THAT'), findsNothing);
  });

  testWidgets('leaving the page gives the keys back to Live', (t) async {
    final c = await testing(t);
    await press(t, LogicalKeyboardKey.space);
    expect(find.byType(AlertDialog), findsNothing);
    final home = t.state<HomeState>(find.byType(Home, skipOffstage: false));
    Navigator.of(home.context).popUntil((route) => route.isFirst);
    home.navigatePage(0);
    await t.pumpAndSettle();
    expect(clickerTestOpen, isFalse);
    await press(t, LogicalKeyboardKey.space);
    expect(find.text('Confirm pause'), findsOneWidget);
    expect(c.state.session.paused, isFalse);
  });

  testWidgets('a wide window lists what a typical clicker sends beside it', (
    t,
  ) async {
    await testing(t);
    expect(find.text('WHAT A TYPICAL CLICKER SENDS'), findsOneWidget);
    final pane = find.byKey(const ValueKey('typical-clicker-keys'));
    expect(pane, findsOneWidget);
    expect(
      t.getTopLeft(pane).dx,
      greaterThan(t.getTopRight(find.byKey(const ValueKey('clicker-test'))).dx),
    );
    for (final heading in ['Forward', 'Back', 'Blank screen']) {
      expect(
        find.descendant(of: pane, matching: find.text(heading)),
        findsOneWidget,
      );
    }
    await press(t, LogicalKeyboardKey.pageDown);
    await press(t, LogicalKeyboardKey.f5);
    await press(t, LogicalKeyboardKey.keyB);
    await press(t, LogicalKeyboardKey.pageDown);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-clicker-test.png'),
    );
  });

  testWidgets('fits the smallest and the largest desktop window', (t) async {
    for (final size in const [Size(1200, 600), Size(2560, 1440)]) {
      await testing(t, size: size, clickerOn: false);
      for (final key in [
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
      ]) {
        await press(t, key);
      }
      expect(t.takeException(), isNull, reason: '$size');
      // On a computer too, the setting turns the clicker's keys off.
      expect(
        find.textContaining('from a clicker or from the keyboard'),
        findsOneWidget,
      );
      expect(shownExplanation(t), unusedKeyExplanation);
      await t.pumpWidget(const SizedBox());
    }
  });

  group('on a phone', () {
    testWidgets('a clicker\'s keys are named and nothing reaches the service', (
      t,
    ) async {
      final c = await testing(t, size: const Size(430, 1000), desktop: false);
      final before = service(c);
      await press(t, LogicalKeyboardKey.f5);
      await press(t, LogicalKeyboardKey.keyB);
      // On a phone B would pause at once; here it does not.
      expect(shownExplanation(t), 'Pause or resume: at once, without asking');
      expectUntouched(t, before, c);
      await press(t, LogicalKeyboardKey.space);
      expectUntouched(t, before, c);
      await press(t, LogicalKeyboardKey.pageDown);
      await press(t, LogicalKeyboardKey.pageDown);
      expect(shownExplanation(t), 'Next segment: press twice to confirm');
      expectUntouched(t, before, c);
      // The computer's keys are not a phone's.
      await press(t, LogicalKeyboardKey.keyM);
      expect(shownExplanation(t), unusedKeyExplanation);
      await press(t, LogicalKeyboardKey.pageDown);
      // No pane beside the page: the usual keys are listed under it.
      expect(
        find.byKey(const ValueKey('typical-clicker-keys')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/clicker-test-phone.png'),
      );
    });

    testWidgets('says when the clicker setting is off, and can turn it on', (
      t,
    ) async {
      final c = await testing(
        t,
        size: const Size(430, 1000),
        desktop: false,
        clickerOn: false,
      );
      final before = service(c);
      expect(
        find.text(
          'Clicker and foot pedal is switched off, so a clicker or pedal does nothing on Live.',
        ),
        findsOneWidget,
      );
      await press(t, LogicalKeyboardKey.pageDown);
      expect(shownKey(t), 'Page Down');
      expect(
        shownExplanation(t),
        'Nothing while Clicker and foot pedal is switched off',
      );
      expectUntouched(t, before, c);
      await t.tap(find.byKey(const ValueKey('clicker-test-turn-on')));
      await t.pumpAndSettle();
      expect(c.state.clickerControls, isTrue);
      expect(find.byKey(const ValueKey('clicker-test-off')), findsNothing);
      await press(t, LogicalKeyboardKey.pageDown);
      expect(shownExplanation(t), 'Next segment: press twice to confirm');
      expect(service(c), before);
    });

    testWidgets('on a PC, says the clicker keys are off from the keyboard too', (
      t,
    ) async {
      final c = await testing(t, clickerOn: false);
      final before = service(c);
      expect(
        find.text(
          'Clicker and foot pedal is switched off, so Space, B, Page Down and → do nothing on Live, from a clicker or from the keyboard. The other keyboard shortcuts still work.',
        ),
        findsOneWidget,
      );
      for (final key in [
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyB,
      ]) {
        await press(t, key);
        expect(
          shownExplanation(t),
          'Nothing while Clicker and foot pedal is switched off',
          reason: '$key',
        );
      }
      // A computer's own shortcuts do not depend on it.
      await press(t, LogicalKeyboardKey.keyM);
      expect(shownExplanation(t), startsWith('Send message'));
      expectUntouched(t, before, c);
      await t.tap(find.byKey(const ValueKey('clicker-test-turn-on')));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.pageDown);
      expect(shownExplanation(t), 'Next segment: press twice to confirm');
      expect(service(c), before);
    });

    testWidgets('fits a 320 px phone with large text', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await testing(
        t,
        size: const Size(320, 640),
        desktop: false,
        clickerOn: false,
        start: false,
      );
      for (final key in [
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.f5,
      ]) {
        await press(t, key);
      }
      expect(
        find.text('Nothing you press here starts or changes a service.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('Settings search finds the test page, not the sheet', (
      t,
    ) async {
      desktopWording = false;
      setScreen(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      t
          .state<HomeState>(find.byType(Home, skipOffstage: false))
          .navigatePage(3);
      await t.pumpAndSettle();
      for (final word in ['clicker', 'pedal', 'test', 'keyboard']) {
        await t.enterText(find.byType(TextField).first, word);
        await t.pumpAndSettle();
        expect(
          find.text('Test a clicker or pedal'),
          findsOneWidget,
          reason: word,
        );
        expect(find.text('Keyboard shortcuts'), findsNothing);
      }
      await t.tap(find.text('Test a clicker or pedal'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('clicker-test')), findsOneWidget);
    });
  });

  test('keys are named in words', () {
    expect(keyName(LogicalKeyboardKey.pageDown), 'Page Down');
    expect(keyName(LogicalKeyboardKey.arrowRight), 'Right arrow');
    expect(keyName(LogicalKeyboardKey.keyB), 'B');
    expect(keyName(LogicalKeyboardKey.f5), 'F5');
    expect(keyName(LogicalKeyboardKey.digit3), '3');
    expect(keyName(LogicalKeyboardKey.numpad3), '3');
    expect(keyName(LogicalKeyboardKey.keyL, control: true), 'Ctrl + L');
    expect(keyName(LogicalKeyboardKey.slash, shift: true), 'Question mark');
  });
}

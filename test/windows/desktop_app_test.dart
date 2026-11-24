import 'dart:ui' show AppExitResponse;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/desktop_live.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/tab_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The app as it runs on a Windows PC: a desktop port and a wide window.
class DesktopFakePort extends FakePort {
  @override
  bool get isDesktop => true;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': false,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<(AppController, DesktopFakePort)> running(
    WidgetTester t, {
    Size size = const Size(1366, 768),
  }) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.first);
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  testWidgets('the Classic layout keeps the side rail in a wide window', (
    t,
  ) async {
    final (c, _) = await running(t);
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'classic',
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsNothing);
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a wide window shows Mission control and the running service', (
    t,
  ) async {
    final (c, port) = await running(t);
    port.at = after(75);
    await c.tick();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/windows-live.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the smallest window still lays out without overflow', (t) async {
    await running(t, size: const Size(420, 640));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Space asks before it pauses', (t) async {
    final (c, _) = await running(t);
    // Space opens the Pause button's own question and changes nothing.
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.text('Pause Praise & Worship?'), findsOneWidget);
    expect(c.state.session.paused, isFalse);
    // Esc backs out.
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('Pause Praise & Worship?'), findsNothing);
    expect(c.state.session.paused, isFalse);
    // Space again, then Space or Enter to confirm.
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isTrue);
    expect(find.text('Pause Praise & Worship?'), findsNothing);
    // Resuming asks too; B is the same key as Space.
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.pumpAndSettle();
    expect(find.text('Resume Praise & Worship?'), findsOneWidget);
    expect(c.state.session.paused, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Clicker and foot pedal off turns the clicker keys off on a PC '
      'and leaves the other shortcuts', (t) async {
    final (c, _) = await running(t);
    final index = c.state.session.index;
    Finder hint(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(KeyHint),
    );
    // On, as a new install has it: the buttons show their keys.
    expect(hint('pause-resume'), findsOneWidget);
    expect(hint('next-segment'), findsOneWidget);
    expect(
      find.textContaining('PgDn PgDn', findRichText: true),
      findsOneWidget,
    );
    await c.commit((draft, _) => draft.clickerControls = false);
    await t.pumpAndSettle();
    // The keys a clicker sends do nothing, from a clicker or the keyboard.
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.keyB,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing, reason: '$key');
      expect(find.byKey(const ValueKey('clicker-confirm')), findsNothing);
    }
    expect(c.state.session.paused, isFalse);
    expect(c.state.session.index, index);
    // Nothing on screen offers them.
    expect(hint('pause-resume'), findsNothing);
    expect(hint('next-segment'), findsNothing);
    expect(find.textContaining('PgDn PgDn', findRichText: true), findsNothing);
    expect(
      find.textContaining('+ −  Adjust time', findRichText: true),
      findsOneWidget,
    );
    // The buttons themselves still work, and still ask first.
    await t.tap(find.byKey(const ValueKey('pause-resume')));
    await t.pumpAndSettle();
    expect(find.text('Pause Praise & Worship?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    // The other keyboard shortcuts are left alone: + opens Adjust time.
    await t.sendKeyEvent(LogicalKeyboardKey.equal);
    await t.pumpAndSettle();
    expect(find.byType(TimeAdjustmentDialog), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    // The shortcuts sheet says the clicker keys are off.
    await t.sendKeyEvent(LogicalKeyboardKey.f1);
    await t.pumpAndSettle();
    expect(find.text(shortcutsClickerOffRule), findsOneWidget);
    expect(
      find.text('Off: Clicker and foot pedal is switched off'),
      findsNWidgets(2),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    // Back on, Space asks again.
    await c.commit((draft, _) => draft.clickerControls = true);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.text('Pause Praise & Worship?'), findsOneWidget);
    expect(c.state.session.paused, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the clicker switch says what it does on a PC', (t) async {
    await running(t);
    final home = t.state<HomeState>(find.byType(Home, skipOffstage: false));
    home.navigatePage(3);
    await t.pumpAndSettle();
    await t.tap(find.text('Warnings & alerts'));
    await t.pumpAndSettle();
    final tile = find.byKey(const ValueKey('clicker-controls'));
    await t.ensureVisible(tile);
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: tile,
        matching: find.textContaining(
          'Off, these keys do nothing from the keyboard either.',
        ),
      ),
      findsOneWidget,
    );
    // Two lines at most in a 1366 × 768 window.
    final subtitle = find.descendant(
      of: tile,
      matching: find.textContaining('twice for Next'),
    );
    final paragraph = t.renderObject<RenderParagraph>(subtitle);
    final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
    final lines = (paragraph.size.height / line).round();
    expect(lines, lessThanOrEqualTo(2));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('End service is never one key press from Space or Enter', (
    t,
  ) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Next still needs a second press', (t) async {
    final (c, _) = await running(t);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(c.state.session.index, 0);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('+ and − open Adjust time, which still asks before changing', (
    t,
  ) async {
    final (c, _) = await running(t);
    final allocated = c.state.session.allocatedMs;
    for (final key in [
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadAdd,
      LogicalKeyboardKey.numpadSubtract,
      LogicalKeyboardKey.equal,
    ]) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
      expect(find.byType(TimeAdjustmentDialog), findsOneWidget, reason: '$key');
      expect(c.state.session.allocatedMs, allocated);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(find.byType(TimeAdjustmentDialog), findsNothing);
    }
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl+Z offers to undo the last segment change', (t) async {
    final (c, _) = await running(t);
    // Nothing to undo yet.
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.text('Undo segment change?'), findsNothing);
    await c.act('advance');
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    // Z on its own does nothing.
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.pumpAndSettle();
    expect(find.text('Undo segment change?'), findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pumpAndSettle();
    expect(find.text('Undo segment change?'), findsOneWidget);
    expect(c.state.session.index, 1);
    await t.tap(find.text('Restore previous segment'));
    await t.pumpAndSettle();
    expect(c.state.session.index, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Lock controls blocks every key', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    for (final key in [
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.numpadAdd,
    ]) {
      await t.sendKeyEvent(key);
      await t.pumpAndSettle();
    }
    expect(c.state.session.paused, isFalse);
    expect(c.state.session.index, 0);
    expect(find.byType(TimeAdjustmentDialog), findsNothing);
    expect(find.textContaining('Press again'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('keys are left alone on other tabs', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.byType(TimeAdjustmentDialog), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('closing the window during a service asks first', (t) async {
    final (c, _) = await running(t);
    final home = t.state<HomeState>(find.byType(Home));
    final answer = home.confirmWindowClose();
    await t.pumpAndSettle();
    expect(find.text('Close during the service?'), findsOneWidget);
    // A second click on the close button does not stack another dialog.
    expect(await home.confirmWindowClose(), AppExitResponse.cancel);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await answer, AppExitResponse.cancel);
    expect(c.state.session.active, isTrue);

    final again = home.confirmWindowClose();
    await t.pumpAndSettle();
    await t.tap(find.text('Close the app'));
    await t.pumpAndSettle();
    expect(await again, AppExitResponse.exit);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('with no service running the window just closes', (t) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final home = t.state<HomeState>(find.byType(Home));
    expect(await home.confirmWindowClose(), AppExitResponse.exit);
    expect(find.text('Close during the service?'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('minimising the window does not suspend the service', (t) async {
    final (c, port) = await running(t);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
      await t.pumpAndSettle();
    }
    port.at = after(30);
    await c.tick();
    expect(c.now.mono, after(30).mono);
    expect(c.state.session.held, isFalse);
    expect(c.state.session.uncertain, isFalse);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
      await t.pumpAndSettle();
    }
    expect(c.state.session.active, isTrue);
    expect(c.state.session.held, isFalse);
    expect(find.textContaining('Review'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a mouse drag does not change tab; a finger still does', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final home = t.state<HomeState>(find.byType(Home));
    expect(
      t.widget<TabSwipeDetector>(find.byType(TabSwipeDetector)).touchOnly,
      isTrue,
    );
    await t.dragFrom(
      const Offset(900, 400),
      const Offset(-500, 0),
      kind: PointerDeviceKind.mouse,
    );
    await t.pumpAndSettle();
    expect(home.page, 0);
    await t.dragFrom(const Offset(900, 400), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(home.page, lyricsPage);
    await t.pumpWidget(const SizedBox());
  });

  test('wording for a computer leaves other people\'s phones alone', () {
    expect(
      deviceText('Saved on this phone’s programs. This phone keeps it.'),
      'Saved on this computer’s programs. This computer keeps it.',
    );
    expect(
      deviceText('Open Android Wi-Fi settings to join the sign, then retry.'),
      'Open Windows Wi-Fi settings to join the sign, then retry.',
    );
    expect(
      deviceText('phones on it may not reach this phone.'),
      'phones on it may not reach this computer.',
    );
    desktopWording = false;
    expect(deviceText('Saved on this phone'), 'Saved on this phone');
  });
}

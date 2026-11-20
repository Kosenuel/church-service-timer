import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/mini_window.dart';
import 'package:church_service_timer/windows/window_memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// Stands in for the Windows window: records what it was asked to do.
class FakePinWindow implements PinnableWindow {
  WindowPlace? place;
  bool pinned = false, pinWorks = true;

  /// Whether a frame is on a screen; everything is unless a test says.
  bool Function(List<int> frame) onScreen = (_) => true;
  final restored = <WindowPlace>[];
  final calls = <String>[];
  @override
  WindowPlace? read() => place;
  @override
  bool restore(WindowPlace p) {
    if (!onScreen(p.frame)) return false;
    calls.add('place');
    restored.add(p);
    place = p;
    return true;
  }

  @override
  bool pin(bool onTop) {
    calls.add(onTop ? 'pin' : 'unpin');
    if (!pinWorks) return false;
    pinned = onTop;
    return true;
  }
}

/// Stands in for the whole mini window, for the tests of the app itself.
/// It resizes the test screen the way the real one resizes the window.
class FakeMiniWindow implements MiniWindow {
  final WidgetTester tester;
  final Size normal;
  FakeMiniWindow(this.tester, this.normal);
  final calls = <String>[];
  bool works = true;
  @override
  Future<bool> enter({required double width, required double height}) async {
    calls.add('enter ${width.round()}x${height.round()}');
    if (works) tester.view.physicalSize = Size(width, height);
    return works;
  }

  @override
  Future<void> leave() async {
    calls.add('leave');
    tester.view.physicalSize = normal;
  }
}

class DesktopPort extends FakePort {
  MiniWindow? mini;
  @override
  bool get isDesktop => true;
  @override
  MiniWindow? get miniWindow => mini;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': false,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

/// A place as text, because two records holding lists are never equal.
String shown(WindowPlace? p) => '${p?.frame} ${p?.maximised}';

const longName =
    'Praise, Worship and Thanksgiving with the Combined Youth and Adult Choirs';

Timeline sunday({String second = 'Sermon'}) => Timeline('Sunday Service', [
  const Segment('Welcome', 5),
  Segment(second, 40),
  const Segment('Response', 10),
], DisplaySettings());

void main() {
  group('the window', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cst-mini'));
    tearDown(() => dir.deleteSync(recursive: true));
    JsonPrefs prefs() => JsonPrefs(File('${dir.path}/window.json'));

    // A 1280 × 800 window whose inside is 1264 × 761: the usual Windows
    // frame of 16 across and 39 down.
    const normal = (frame: [100, 80, 1380, 880], maximised: false);
    ViewMetrics inside({double scale = 1}) =>
        (scale: scale, width: 1264, height: 761);

    test('becomes small and on top, then goes back exactly', () async {
      final window = FakePinWindow()..place = normal;
      final memory = WindowMemory(prefs(), window, metrics: inside);
      expect(await memory.enter(width: 380, height: 150), isTrue);
      expect(memory.mini, isTrue);
      // On top before it is made small, as the runner requires.
      expect(window.calls, ['pin', 'place']);
      // 380 × 150 inside, plus the frame, at the normal window's top right.
      expect(shown(window.restored.single), '[984, 80, 1380, 269] false');
      expect(window.pinned, isTrue);

      await memory.leave();
      expect(shown(window.restored.last), shown(normal));
      expect(window.pinned, isFalse);
      expect(memory.mini, isFalse);
      expect(window.calls, ['pin', 'place', 'place', 'unpin']);
      // Leaving twice changes nothing more.
      await memory.leave();
      expect(window.calls.length, 4);
    });

    test('a maximised window comes back maximised', () async {
      const maximised = (frame: [100, 80, 1380, 880], maximised: true);
      final window = FakePinWindow()..place = maximised;
      final memory = WindowMemory(
        prefs(),
        window,
        // Maximised, the inside is the screen; it says nothing of the frame.
        metrics: () => (scale: 1, width: 1920, height: 1040),
      );
      expect(await memory.enter(width: 380, height: 150), isTrue);
      expect(window.place!.maximised, isFalse);
      expect(window.place!.frame, [1380 - 396, 80, 1380, 80 + 189]);
      await memory.leave();
      expect(shown(window.place), shown(maximised));
    });

    test('the size follows the screen scale', () async {
      final window = FakePinWindow()
        ..place = (frame: [0, 0, 1920, 1200], maximised: false);
      final memory = WindowMemory(
        prefs(),
        window,
        metrics: () => (scale: 1.5, width: 1896, height: 1142),
      );
      await memory.enter(width: 380, height: 150);
      final f = window.place!.frame;
      expect([f[2] - f[0], f[3] - f[1]], [570 + 24, 225 + 58]);
    });

    test('a usual frame is assumed when it cannot be measured', () async {
      for (final metrics in <ViewMetrics Function()?>[
        null,
        () => throw StateError('no view'),
        // A snapped window: the place is the one before it was snapped.
        () => (scale: 1, width: 960, height: 1040),
        () => (scale: double.nan, width: 1264, height: 761),
      ]) {
        final window = FakePinWindow()..place = normal;
        final memory = WindowMemory(prefs(), window, metrics: metrics);
        expect(await memory.enter(width: 380, height: 150), isTrue);
        final f = window.place!.frame;
        expect([f[2] - f[0], f[3] - f[1]], [396, 189]);
        await memory.leave();
      }
    });

    test('its place is remembered apart from the normal window', () async {
      final window = FakePinWindow()..place = normal;
      final memory = WindowMemory(prefs(), window, metrics: inside);
      await memory.save();
      await memory.enter(width: 380, height: 150);
      // Dragged to the bottom left; the two-second save notices.
      window.place = (frame: [20, 700, 416, 889], maximised: false);
      await memory.save();
      expect(await prefs().get('mini'), {
        'at': [20, 700],
      });
      expect((await prefs().get('window') as Map)['frame'], normal.frame);
      // Dragged again, then expanded straight away.
      window.place = (frame: [40, 600, 436, 789], maximised: false);
      await memory.leave();
      expect(shown(window.place), shown(normal));
      expect(await prefs().get('mini'), {
        'at': [40, 600],
      });

      // The normal window moves; the mini timer still opens where it was.
      const moved = (frame: [300, 200, 1580, 1000], maximised: false);
      window.place = moved;
      await memory.save();
      await memory.enter(width: 380, height: 150);
      expect(window.place!.frame, [40, 600, 436, 789]);
      await memory.leave();
      expect(shown(window.place), shown(moved));
      expect((await prefs().get('window') as Map)['frame'], moved.frame);
    });

    test('closing while small opens the normal window next time', () async {
      final window = FakePinWindow()..place = normal;
      // Never saved before: entering must record the normal place itself.
      final memory = WindowMemory(prefs(), window, metrics: inside);
      await memory.enter(width: 380, height: 150);
      window.place = (frame: [20, 700, 416, 889], maximised: false);
      await memory.save();
      await memory.save();
      // The app is closed here, still small.
      final next = FakePinWindow()
        ..place = (frame: [10, 10, 1290, 730], maximised: false);
      final restarted = WindowMemory(prefs(), next, metrics: inside);
      await restarted.restore();
      expect(shown(next.restored.single), shown(normal));
      expect(next.calls, ['place']);
      expect(restarted.mini, isFalse);
      // And the mini timer opens where it was left.
      await restarted.enter(width: 380, height: 150);
      expect(next.place!.frame, [20, 700, 416, 889]);
    });

    test('a remembered place that is off every screen is not used', () async {
      await prefs().set('mini', {
        'at': [5000, 100],
      });
      final window = FakePinWindow()
        ..place = normal
        ..onScreen = (f) => f[0] < 3000;
      final memory = WindowMemory(prefs(), window, metrics: inside);
      expect(await memory.enter(width: 380, height: 150), isTrue);
      expect(window.place!.frame, [984, 80, 1380, 269]);
    });

    test('if the normal place has gone, the normal size is kept', () async {
      final window = FakePinWindow()..place = normal;
      final memory = WindowMemory(prefs(), window, metrics: inside);
      await memory.enter(width: 380, height: 150);
      window.place = (frame: [20, 30, 416, 219], maximised: false);
      // The screen the normal window was on has been unplugged.
      window.onScreen = (f) => f[0] < 100;
      await memory.leave();
      expect(shown(window.place), '[20, 30, 1300, 830] false');
      expect(window.pinned, isFalse);
      expect(memory.mini, isFalse);
    });

    test('nothing changes when Windows refuses', () async {
      final refused = FakePinWindow()
        ..place = normal
        ..pinWorks = false;
      var memory = WindowMemory(prefs(), refused, metrics: inside);
      expect(await memory.enter(width: 380, height: 150), isFalse);
      expect(shown(refused.place), shown(normal));
      expect(memory.mini, isFalse);

      final nowhere = FakePinWindow()
        ..place = normal
        ..onScreen = (_) => false;
      memory = WindowMemory(prefs(), nowhere, metrics: inside);
      expect(await memory.enter(width: 380, height: 150), isFalse);
      expect(shown(nowhere.place), shown(normal));
      expect(nowhere.pinned, isFalse);
      expect(memory.mini, isFalse);

      final noWindow = FakePinWindow();
      memory = WindowMemory(prefs(), noWindow, metrics: inside);
      expect(await memory.enter(width: 380, height: 150), isFalse);
      expect(noWindow.calls, isEmpty);
      expect(await prefs().get('mini'), isNull);
    });

    test('an old saved file, and nonsense, still load', () async {
      await prefs().set('window', {'frame': normal.frame, 'maximised': false});
      for (final bad in [
        null,
        'text',
        {'at': 'x'},
        {
          'at': [1],
        },
        {
          'at': [1.5, 2],
        },
      ]) {
        if (bad == null) {
          await prefs().remove('mini');
        } else {
          await prefs().set('mini', bad);
        }
        final window = FakePinWindow()
          ..place = (frame: [0, 0, 900, 700], maximised: false);
        final memory = WindowMemory(prefs(), window, metrics: inside);
        await memory.restore();
        expect(shown(window.place), shown(normal), reason: '$bad');
        expect(await memory.enter(width: 380, height: 150), isTrue);
        expect(window.place!.frame, [984, 80, 1380, 269], reason: '$bad');
        await memory.leave();
      }
    });
  });

  group('the app', () {
    setUpAll(loadAppFonts);
    setUp(() => desktopWording = true);
    tearDown(() => desktopWording = false);

    const full = Size(1366, 768);

    /// A Sunday service in its second segment with 12:38 left, on a PC.
    Future<(AppController, DesktopPort, FakeMiniWindow)> running(
      WidgetTester t, {
      String second = 'Sermon',
      bool start = true,
    }) async {
      setScreen(t, full);
      final window = FakeMiniWindow(t, full);
      final port = DesktopPort()..mini = window;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((draft, _) => draft.themeId = 'graphite');
      if (start) {
        await c.act('load', value: sunday(second: second));
        await c.act('start');
        port.at = after(340);
        await c.tick();
        await c.act('advance');
        port.at = after(340 + 1642);
        await c.tick();
      }
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      return (c, port, window);
    }

    HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));

    Future<void> openMini(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('live-menu')));
      await t.pumpAndSettle();
      await t.tap(find.text('Mini timer'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('mini-timer')), findsOneWidget);
    }

    Future<void> resize(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      await t.pumpAndSettle();
    }

    Finder key(String name) => find.byKey(ValueKey(name));

    testWidgets('a button on Live opens it, and not while locked', (t) async {
      final (c, _, window) = await running(t);
      // In the header while a service runs, where it can be seen.
      expect(key('mini-timer-button'), findsOneWidget);
      await t.tap(key('mini-timer-button'));
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsOneWidget);
      expect(window.calls, ['enter 380x150']);
      await t.tap(key('mini-expand'));
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsNothing);
      // Lock controls blocks it like every other button.
      await t.tap(key('control-lock'));
      await t.pumpAndSettle();
      expect(t.widget<IconButton>(key('mini-timer-button')).onPressed, isNull);
      // After the service it is still there, for the clock.
      await t.longPress(key('unlock-controls'));
      await t.pumpAndSettle();
      await c.act('end');
      await t.pumpAndSettle();
      expect(key('mini-timer-button'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('on a PC the button is on every page, service or not', (
      t,
    ) async {
      for (final start in [false, true]) {
        final (c, _, window) = await running(t, start: start);
        for (final page in [0, 1, 2, 3, 0]) {
          await home(t).goToPage(page);
          await t.pumpAndSettle();
          expect(
            key('mini-timer-button'),
            findsOneWidget,
            reason: 'page $page, ${start ? 'running' : 'no service'}',
          );
          expect(
            t.widget<IconButton>(key('mini-timer-button')).onPressed,
            isNotNull,
          );
        }
        // From Settings it opens, and expanding comes back to Live.
        await home(t).goToPage(3);
        await t.pumpAndSettle();
        await t.tap(key('mini-timer-button'));
        await t.pumpAndSettle();
        expect(key('mini-timer'), findsOneWidget);
        expect(key(start ? 'mini-pause' : 'mini-standing-by'), findsOneWidget);
        await t.tap(key('mini-expand'));
        await t.pumpAndSettle();
        expect(window.calls, ['enter 380x150', 'leave']);
        expect(key('mini-timer'), findsNothing);
        expect(c.state.session.active, start);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Ctrl+M works from another page with nothing running', (
      t,
    ) async {
      await running(t, start: false);
      await home(t).goToPage(2);
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyM);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(home(t).miniTimer, isTrue);
      expect(key('mini-standing-by'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('locked, the button is there but does nothing', (t) async {
      final (c, _, window) = await running(t);
      await t.tap(key('control-lock'));
      await t.pumpAndSettle();
      // However it got there, a locked app stays as it is.
      home(t).navigatePage(1);
      await t.pumpAndSettle();
      expect(t.widget<IconButton>(key('mini-timer-button')).onPressed, isNull);
      await t.tap(key('mini-timer-button'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(window.calls, isEmpty);
      expect(c.state.session.active, isTrue);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('not on a phone or tablet, on any page', (t) async {
      desktopWording = false;
      setScreen(t, const Size(430, 1000));
      final phone = AppController(FakePort());
      await phone.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: phone));
      await t.pumpAndSettle();
      for (final page in [0, 1, 2, 3]) {
        await home(t).goToPage(page);
        await t.pumpAndSettle();
        expect(key('mini-timer-button'), findsNothing, reason: 'page $page');
      }
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('with nothing running it shows the clock', (t) async {
      final (c, port, window) = await running(t, start: false);
      await t.tap(key('mini-timer-button'));
      await t.pumpAndSettle();
      expect(window.calls, ['enter 380x150']);
      expect(key('mini-standing-by'), findsOneWidget);
      expect(find.text(clockLabel(port.at.wall)), findsOneWidget);
      expect(find.text('No service running'), findsOneWidget);
      expect(find.text('Load a service in the full window.'), findsOneWidget);
      expect(key('mini-pause'), findsNothing);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/mini-timer-standing-by.png'),
      );

      // A loaded service: its name, then its start time, then the
      // pre-service countdown.
      await c.act('load', value: sunday());
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsOneWidget);
      expect(find.text('Sunday Service'), findsOneWidget);
      expect(find.text('No start time set'), findsOneWidget);
      expect(
        find.text('Start the service in the full window.'),
        findsOneWidget,
      );
      final at = port.at.wall + 90 * 60000;
      await c.act('schedule', value: at);
      await t.pumpAndSettle();
      expect(find.text('Starts at ${clockLabel(at)}'), findsOneWidget);
      port.at = after(60 * 60);
      await c.tick();
      await t.pumpAndSettle();
      expect(
        find.text('Starts in 30:00 · at ${clockLabel(at)}'),
        findsOneWidget,
      );
      expect(find.text(clockLabel(port.at.wall)), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/mini-timer-pre-service.png'),
      );
      port.at = after(91 * 60);
      await c.tick();
      await t.pumpAndSettle();
      expect(
        find.text('Start time reached · ${clockLabel(at)}'),
        findsOneWidget,
      );
      // Small windows keep to the name and the clock.
      await resize(t, const Size(240, 100));
      expect(key('mini-compact'), findsOneWidget);
      await resize(t, const Size(110, 50));
      expect(find.text(clockLabel(port.at.wall)), findsOneWidget);
      expect(t.takeException(), isNull);

      // Started from elsewhere, it becomes the running timer; ending
      // brings the full window back.
      await resize(t, const Size(380, 150));
      await c.act('start');
      await t.pumpAndSettle();
      expect(key('mini-pause'), findsOneWidget);
      await c.act('end');
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('with nothing running, locked shows Hold to unlock', (t) async {
      await running(t, start: false);
      home(t).lockControls();
      await t.pumpAndSettle();
      // The header button is disabled; other code may still open it.
      expect(await home(t).setMiniTimer(true), isTrue);
      await t.pumpAndSettle();
      expect(key('mini-standing-by'), findsOneWidget);
      expect(key('mini-locked'), findsOneWidget);
      expect(key('mini-expand'), findsNothing);
      await t.longPress(key('mini-unlock'));
      await t.pumpAndSettle();
      expect(key('mini-expand'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the menu opens it and Expand leaves it', (t) async {
      final (_, _, window) = await running(t);
      await openMini(t);
      expect(window.calls, ['enter 380x150']);
      expect(key('mini-full'), findsOneWidget);
      expect(find.text('Sermon'), findsOneWidget);
      expect(find.text('12:38'), findsOneWidget);
      expect(find.text('Next · Response · 10 min'), findsOneWidget);
      expect(find.text('40 s behind'), findsOneWidget);
      expect(key('live-menu'), findsNothing);
      expect(t.takeException(), isNull);

      await t.tap(key('mini-expand'));
      await t.pumpAndSettle();
      expect(window.calls, ['enter 380x150', 'leave']);
      expect(key('mini-timer'), findsNothing);
      expect(key('live-menu'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('other code can open and close it', (t) async {
      final (_, _, window) = await running(t);
      expect(await home(t).setMiniTimer(true), isTrue);
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsOneWidget);
      // Asking again changes nothing.
      expect(await home(t).setMiniTimer(true), isTrue);
      expect(await home(t).setMiniTimer(false), isFalse);
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsNothing);
      expect(window.calls, ['enter 380x150', 'leave']);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Ctrl+M opens and closes it, but not when locked', (t) async {
      final (c, _, window) = await running(t);
      Future<void> ctrlM() async {
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyM);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pumpAndSettle();
      }

      await ctrlM();
      expect(home(t).miniTimer, isTrue);
      await ctrlM();
      expect(home(t).miniTimer, isFalse);
      // M on its own is Send message, not the mini timer.
      await t.sendKeyEvent(LogicalKeyboardKey.keyM);
      await t.pumpAndSettle();
      expect(home(t).miniTimer, isFalse);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      home(t).lockControls();
      await t.pumpAndSettle();
      await ctrlM();
      expect(home(t).miniTimer, isFalse);
      expect(c.state.session.active, isTrue);
      expect(window, isNotNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('it does not open over a dialog', (t) async {
      final (_, _, window) = await running(t);
      await t.tap(key('pause-resume'));
      await t.pumpAndSettle();
      expect(await home(t).setMiniTimer(true), isFalse);
      expect(window.calls, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the window that will not shrink leaves the app as it was', (
      t,
    ) async {
      final (_, _, window) = await running(t);
      window.works = false;
      await t.tap(key('live-menu'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mini timer'));
      await t.pumpAndSettle();
      expect(key('mini-timer'), findsNothing);
      expect(find.text('The window could not be made small.'), findsOneWidget);
      expect(home(t).miniTimer, isFalse);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the menu entry is there on a computer, service or not', (
      t,
    ) async {
      Future<bool> offered() async {
        await t.tap(key('live-menu'));
        await t.pumpAndSettle();
        final there = find.text('Mini timer').evaluate().isNotEmpty;
        expect(find.text('Focused operator view'), findsOneWidget);
        await t.tapAt(const Offset(5, 5));
        await t.pumpAndSettle();
        return there;
      }

      // A computer with no service running.
      var (c, port, window) = await running(t, start: false);
      expect(await offered(), isTrue);
      // Loaded but not started.
      await c.act('load', value: sunday());
      await t.pumpAndSettle();
      expect(await offered(), isTrue);
      await c.act('start');
      await t.pumpAndSettle();
      expect(await offered(), isTrue);
      expect(window.calls, isEmpty);
      await t.pumpWidget(const SizedBox());

      // A computer whose window cannot do it.
      (c, port, window) = await running(t);
      port.mini = null;
      await t.pumpAndSettle();
      expect(await offered(), isFalse);
      expect(await home(t).setMiniTimer(true), isFalse);
      await t.pumpWidget(const SizedBox());

      // A phone or tablet, in a running service.
      desktopWording = false;
      setScreen(t, const Size(430, 1000));
      final phone = AppController(FakePort());
      await phone.initialize(startTicker: false);
      await phone.act('load', value: sunday());
      await phone.act('start');
      await t.pumpWidget(TimerApp(controller: phone));
      await t.pumpAndSettle();
      expect(await offered(), isFalse);
      expect(await home(t).setMiniTimer(true), isFalse);
      expect(key('mini-timer'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('ending the service brings the full window back', (t) async {
      final (c, _, window) = await running(t);
      await openMini(t);
      await c.act('end');
      await t.pumpAndSettle();
      expect(window.calls, ['enter 380x150', 'leave']);
      expect(key('mini-timer'), findsNothing);
      expect(home(t).miniTimer, isFalse);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Pause asks first, in the same words', (t) async {
      final (c, _, _) = await running(t);
      await openMini(t);
      await t.tap(key('mini-pause'));
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      expect(
        find.text(
          'Hold the timer at 12:38 remaining. It stays paused until you resume.\n\nAny stage cue stays visible. Service elapsed time includes pauses.',
        ),
        findsOneWidget,
      );
      expect(find.text('Confirm pause'), findsOneWidget);
      expect(c.state.session.paused, isFalse);
      expect(t.takeException(), isNull);
      // The buttons are inside the small window.
      final window = Offset.zero & t.view.physicalSize;
      for (final button in ['mini-confirm-cancel', 'mini-confirm-action']) {
        final rect = t.getRect(key(button));
        expect(window.contains(rect.topLeft), isTrue, reason: button);
        expect(window.contains(rect.bottomRight), isTrue, reason: button);
      }

      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsNothing);
      expect(c.state.session.paused, isFalse);

      await t.tap(key('mini-pause'));
      await t.pumpAndSettle();
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, isTrue);
      expect(find.text('Resume'), findsOneWidget);

      await t.tap(key('mini-pause'));
      await t.pumpAndSettle();
      expect(find.text('Resume Sermon?'), findsOneWidget);
      expect(find.text('Confirm resume'), findsOneWidget);
      expect(c.state.session.paused, isTrue);
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, isFalse);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Next asks first, in the same words', (t) async {
      final (c, port, _) = await running(t);
      await openMini(t);
      await t.tap(key('mini-next-segment'));
      await t.pumpAndSettle();
      expect(find.text('Start Response?'), findsOneWidget);
      expect(
        find.textContaining(
          'Finish Sermon and start Response · 10 min. Previous cues are cleared and the new countdown is sent.',
        ),
        findsOneWidget,
      );
      expect(c.state.session.index, 1);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);

      // A question about a service that has since changed cannot be
      // confirmed.
      await t.tap(key('mini-next-segment'));
      await t.pumpAndSettle();
      await c.act('pause');
      await t.pumpAndSettle();
      expect(find.text(staleActionText), findsOneWidget);
      expect(
        t.widget<FilledButton>(key('mini-confirm-action')).onPressed,
        isNull,
      );
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      await c.act('pause');
      await t.pumpAndSettle();

      await t.tap(key('mini-next-segment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Start Response'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 2);
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('Final segment'), findsOneWidget);
      // Nothing follows the final segment.
      expect(
        t.widget<OutlinedButton>(key('mini-next-segment')).onPressed,
        isNull,
      );
      expect(port.at, isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the first cue sends, then offers Show timer', (t) async {
      final (c, _, _) = await running(t);
      await openMini(t);
      expect(find.text('WRAP UP'), findsOneWidget);
      await t.tap(key('mini-cue'));
      await t.pumpAndSettle();
      expect(c.state.session.alert?.text, 'WRAP UP');
      expect(c.state.session.outputMode(c.now), 'Cue');
      expect(key('mini-cue'), findsNothing);
      expect(find.text('Show timer'), findsOneWidget);
      // A second click straight after the first is ignored.
      await t.tap(key('mini-show-timer'));
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Cue');
      await t.pump(const Duration(milliseconds: 700));
      await t.tap(key('mini-show-timer'));
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown');
      expect(key('mini-cue'), findsOneWidget);
      expect(find.text('Show timer'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Lock controls swaps the buttons for Hold to unlock', (
      t,
    ) async {
      final (c, _, _) = await running(t);
      await t.tap(key('control-lock'));
      await t.pumpAndSettle();
      await openMini(t);
      expect(key('mini-locked'), findsOneWidget);
      expect(find.text('Controls locked'), findsOneWidget);
      expect(find.text('Hold to unlock'), findsOneWidget);
      for (final button in [
        'mini-pause',
        'mini-next-segment',
        'mini-cue',
        'mini-expand',
      ]) {
        expect(key(button), findsNothing, reason: button);
      }
      // Keys are blocked too.
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.paused, isFalse);
      expect(c.state.session.alert, isNull);
      // A tap explains; only holding unlocks.
      await t.tap(key('mini-unlock'));
      await t.pump();
      expect(find.text('Click and hold to unlock controls.'), findsOneWidget);
      expect(key('mini-locked'), findsOneWidget);
      await t.longPress(key('mini-unlock'));
      await t.pumpAndSettle();
      expect(key('mini-locked'), findsNothing);
      expect(key('mini-pause'), findsOneWidget);
      expect(c.uiLocked, isFalse);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('overtime counts up in red, a warning is amber', (t) async {
      final (c, port, _) = await running(t);
      await openMini(t);
      final colors = appColors(t.element(key('mini-clock')));
      Color clock() => t.widget<Text>(key('mini-clock')).style!.color!;
      expect(clock(), colors.text);

      // Inside the last minutes of the segment.
      port.at = after(340 + 40 * 60 - 20);
      await c.tick();
      await t.pumpAndSettle();
      expect(c.state.session.nearWarning(c.now), isTrue);
      expect(find.text('00:20'), findsOneWidget);
      expect(clock(), colors.warning);

      port.at = after(340 + 40 * 60 + 95);
      await c.tick();
      await t.pumpAndSettle();
      expect(find.text('+01:35'), findsOneWidget);
      expect(clock(), colors.error);
      expect(find.text('2 min 15 s behind'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a narrow window shows only the name and countdown', (t) async {
      await running(t);
      await openMini(t);
      await resize(t, const Size(250, 150));
      expect(key('mini-compact'), findsOneWidget);
      expect(find.text('Sermon'), findsOneWidget);
      expect(find.text('12:38'), findsOneWidget);
      for (final gone in [
        'mini-pause',
        'mini-next-segment',
        'mini-cue',
        'mini-expand',
        'mini-next',
        'mini-variance',
      ]) {
        expect(key(gone), findsNothing, reason: gone);
      }
      expect(t.takeException(), isNull);
      // Wide again, the buttons return.
      await resize(t, const Size(380, 150));
      expect(key('mini-pause'), findsOneWidget);
      // Smaller than any title bar allows: the countdown alone.
      await resize(t, const Size(100, 30));
      expect(find.text('12:38'), findsOneWidget);
      expect(find.text('Sermon'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('nothing overflows with a long name and large text', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final (c, port, _) = await running(t, second: longName);
      await openMini(t);
      for (final size in const [
        Size(380, 150),
        Size(240, 90),
        Size(260, 120),
        Size(180, 90),
        Size(600, 400),
      ]) {
        await resize(t, size);
        expect(find.text(longName), findsOneWidget, reason: '$size');
        expect(t.takeException(), isNull, reason: '$size');
      }
      // The questions fit too, locked or in overtime.
      await resize(t, const Size(380, 150));
      port.at = after(340 + 40 * 60 + 3600);
      await c.tick();
      await t.pumpAndSettle();
      expect(find.text('+60:00'), findsOneWidget);
      for (final size in const [Size(380, 150), Size(260, 120)]) {
        await resize(t, size);
        await t.tap(key('mini-pause'));
        await t.pumpAndSettle();
        expect(find.text('Pause $longName?'), findsOneWidget);
        expect(t.takeException(), isNull, reason: 'pause $size');
        await t.tap(key('mini-confirm-cancel'));
        await t.pumpAndSettle();
        await t.tap(key('mini-next-segment'));
        await t.pumpAndSettle();
        expect(find.text('Start Response'), findsOneWidget);
        expect(t.takeException(), isNull, reason: 'next $size');
        await t.tap(key('mini-confirm-cancel'));
        await t.pumpAndSettle();
      }
      home(t).refreshHome(() => c.uiLocked = home(t).controlsLocked = true);
      await resize(t, const Size(380, 150));
      expect(find.text('Hold to unlock'), findsOneWidget);
      expect(t.takeException(), isNull);
      await resize(t, const Size(260, 120));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('the keys still work, with the same guards', (t) async {
      final (c, _, _) = await running(t);
      await openMini(t);
      // Space asks first, in the small card; Space again confirms.
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsOneWidget);
      expect(c.state.session.paused, isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(c.state.session.paused, isTrue);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(c.state.session.paused, isFalse);
      expect(key('mini-dialog'), findsNothing);

      // A number sends its cue; the same number goes back to the timer.
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.alert?.text, 'WRAP UP');
      expect(find.text('Show timer'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown');

      // Adjust time needs the full window, and says so.
      await t.sendKeyEvent(LogicalKeyboardKey.equal);
      await t.pump();
      expect(find.byType(TimeAdjustmentDialog), findsNothing);
      expect(
        find.text('Expand the window to adjust the time.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);

      // Nothing happens under a question.
      await t.tap(key('mini-pause'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);
      // Esc is Cancel.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsNothing);
      expect(c.state.session.paused, isFalse);

      // Next still needs a second press.
      await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await t.pump();
      expect(c.state.session.index, 1);
      expect(t.takeException(), isNull);
      await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await t.pumpAndSettle();
      expect(c.state.session.index, 2);

      // Ctrl+Z asks in the small form.
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsOneWidget);
      expect(find.text('Undo segment change?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.text('Restore previous segment'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('closing the small window during a service asks first', (
      t,
    ) async {
      await running(t);
      await openMini(t);
      final answer = home(t).confirmWindowClose();
      await t.pumpAndSettle();
      expect(key('mini-dialog'), findsOneWidget);
      expect(find.text('Close during the service?'), findsOneWidget);
      expect(find.text('Close the app'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(await answer, AppExitResponse.cancel);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a quick timer has no Next', (t) async {
      final (c, _, _) = await running(t, start: false);
      await c.act('load', value: sunday());
      await c.act('start');
      c.state.session.quickTimer = true;
      await t.pumpAndSettle();
      await openMini(t);
      expect(key('mini-pause'), findsOneWidget);
      expect(key('mini-next-segment'), findsNothing);
      expect(key('mini-next'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('looks right at 380 × 150', (t) async {
      await running(t);
      await openMini(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/mini-timer.png'),
      );
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('looks right locked', (t) async {
      await running(t);
      await t.tap(key('control-lock'));
      await t.pumpAndSettle();
      await openMini(t);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/mini-timer-locked.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  });
}

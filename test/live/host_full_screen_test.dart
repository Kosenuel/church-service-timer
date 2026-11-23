import 'dart:async';
import 'dart:io';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/host_full_screen.dart';
import 'package:church_service_timer/live/shortcuts.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/screen_orientation.dart';
import 'package:church_service_timer/windows/atomic_store.dart';
import 'package:church_service_timer/windows/mini_window.dart';
import 'package:church_service_timer/windows/window_memory.dart';
import 'package:flutter/gestures.dart';
import 'package:church_service_timer/pairing/flip_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/live_helpers.dart';
import '../support/steady_time.dart';
import '../support/widget_setup.dart';
import '../windows/second_screen_live_test.dart' show SecondPort;

/// Stands in for the Windows window: records what it was asked to do.
class FakeFillWindow implements FillableWindow, PinnableWindow {
  WindowPlace? place;
  bool fillWorks = true, filled = false;
  final calls = <String>[];
  @override
  WindowPlace? read() => place;
  @override
  bool restore(WindowPlace p) {
    calls.add('place');
    place = p;
    return true;
  }

  @override
  bool pin(bool onTop) {
    calls.add(onTop ? 'pin' : 'unpin');
    return true;
  }

  @override
  bool fill() {
    calls.add('fill');
    if (!fillWorks) return false;
    filled = true;
    // Windows reports the screen as the place of a window that covers it.
    place = (frame: [0, 0, 1920, 1080], maximised: false);
    return true;
  }

  @override
  void unfill(WindowPlace p) {
    calls.add('unfill');
    filled = false;
    place = p;
  }
}

/// Stands in for the whole window, for the tests of the app itself.
class FakeFullScreenWindow implements FullScreenWindow {
  final calls = <String>[];
  bool works = true;
  @override
  Future<bool> enterFullScreen() async {
    calls.add('enter');
    return works;
  }

  @override
  Future<void> leaveFullScreen() async => calls.add('leave');
}

class DesktopPort extends FakePort {
  final window = FakeFullScreenWindow();
  @override
  bool get isDesktop => true;
  @override
  FullScreenWindow? get fullScreenWindow => window;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': false,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

String shown(WindowPlace? p) => '${p?.frame} ${p?.maximised}';

/// The Sunday service; with [noEnd], it has no end screen.
Timeline sunday({bool noEnd = false}) => Timeline('Sunday Service', const [
  Segment('Welcome', 5),
  Segment('Sermon', 40),
  Segment('Response', 10),
], noEnd ? DisplaySettings(end: null) : DisplaySettings());

void main() {
  group('the window', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('cst-full'));
    tearDown(() => dir.deleteSync(recursive: true));
    JsonPrefs prefs() => JsonPrefs(File('${dir.path}/window.json'));
    const normal = (frame: [100, 80, 1380, 880], maximised: false);

    test('covers its screen, then goes back exactly', () async {
      for (final before in [
        normal,
        (frame: [100, 80, 1380, 880], maximised: true),
      ]) {
        final window = FakeFillWindow()..place = before;
        final memory = WindowMemory(prefs(), window);
        expect(await memory.enterFullScreen(), isTrue);
        expect(memory.full, isTrue);
        expect(window.filled, isTrue);
        // Entering twice asks Windows once.
        expect(await memory.enterFullScreen(), isTrue);
        expect(window.calls, ['fill']);
        await memory.leaveFullScreen();
        expect(shown(window.place), shown(before));
        expect(window.filled, isFalse);
        expect(memory.full, isFalse);
        await memory.leaveFullScreen();
        expect(window.calls, ['fill', 'unfill']);
      }
    });

    test(
      'closing while full screen opens the normal window next time',
      () async {
        final window = FakeFillWindow()..place = normal;
        final memory = WindowMemory(prefs(), window);
        await memory.enterFullScreen();
        // The two-second save does not take the screen for the window.
        await memory.save();
        await memory.save();
        expect((await prefs().get('window') as Map)['frame'], normal.frame);
        final next = FakeFillWindow()
          ..place = (frame: [10, 10, 1290, 730], maximised: false);
        await WindowMemory(prefs(), next).restore();
        expect(shown(next.place), shown(normal));
      },
    );

    test('nothing changes when Windows refuses', () async {
      final window = FakeFillWindow()
        ..place = normal
        ..fillWorks = false;
      final memory = WindowMemory(prefs(), window);
      expect(await memory.enterFullScreen(), isFalse);
      expect(memory.full, isFalse);
      expect(shown(window.place), shown(normal));
      await memory.leaveFullScreen();
      expect(window.calls, ['fill']);
      // No window at all.
      final none = FakeFillWindow();
      expect(await WindowMemory(prefs(), none).enterFullScreen(), isFalse);
      expect(none.calls, isEmpty);
    });

    test(
      'full screen and the mini timer keep out of each other’s way',
      () async {
        final window = FakeFillWindow()..place = normal;
        final memory = WindowMemory(prefs(), window);
        expect(await memory.enterFullScreen(), isTrue);
        expect(await memory.enter(width: 380, height: 150), isFalse);
        expect(window.calls, ['fill']);
        await memory.leaveFullScreen();
        expect(await memory.enter(width: 380, height: 150), isTrue);
        expect(await memory.enterFullScreen(), isFalse);
        expect(window.filled, isFalse);
        await memory.leave();
        expect(shown(window.place), shown(normal));
      },
    );
  });

  group('the app', () {
    setUpAll(loadAppFonts);

    /// A Sunday service in its second segment with 12:38 left.
    Future<(AppController, FakePort)> running(
      WidgetTester t, {
      bool desktop = true,
      Size size = const Size(1366, 768),
      bool start = true,
      bool noEnd = false,
      bool tip = false,
    }) async {
      desktopWording = desktop;
      addTearDown(() => desktopWording = false);
      setScreen(t, size);
      final port = desktop ? DesktopPort() : FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((draft, _) => draft.themeId = 'graphite');
      // The gestures tip has its own tests; elsewhere it has been seen.
      if (!tip) {
        await c.commit((d, _) => d.dismissedHints.add(gesturesTipHint));
      }
      if (start) {
        await c.act('load', value: sunday(noEnd: noEnd));
        await c.act('start');
        port.at = after(340);
        await c.tick();
        await c.act('advance');
        port.at = after(340 + 1642);
        await c.tick();
      }
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      return (c, port);
    }

    HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));

    /// The end screen scrolls, so it never settles: step through time.
    Future<void> step(WidgetTester t) async {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Finder key(String name) => find.byKey(ValueKey(name));
    final stage = find.byKey(const ValueKey('host-full-screen'));

    /// The time the stage is showing.
    String time(WidgetTester t) =>
        t.widget<ClockText>(find.byType(ClockText)).text;

    Future<void> press(WidgetTester t, LogicalKeyboardKey k) async {
      await t.sendKeyEvent(k);
      await t.pumpAndSettle();
    }

    Future<void> control(WidgetTester t, LogicalKeyboardKey k) async {
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(k);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
    }

    /// Lets the Exit control, shown at first, go away again.
    Future<void> settleControl(WidgetTester t) async {
      await t.pump(HostFullScreenView.controlTime);
      await t.pumpAndSettle();
    }

    /// A single tap or click on the stage: it waits to be sure it is not
    /// the first of two.
    Future<void> tapStage(WidgetTester t, Offset at) async {
      await t.tapAt(at);
      await t.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
      await t.pumpAndSettle();
    }

    Future<void> done(WidgetTester t) async {
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    }

    testWidgets('the button on Live opens it, and not while locked', (t) async {
      final (_, port) = await running(t);
      expect(
        find.byTooltip('Full screen: show the stage on this screen (F11)'),
        findsOneWidget,
      );
      // Beside the mini timer's place, before Lock controls.
      expect(
        t.getCenter(key('full-screen-button')).dx,
        lessThan(t.getCenter(key('control-lock')).dx),
      );
      home(t).lockControls();
      await t.pumpAndSettle();
      expect(t.widget<IconButton>(key('full-screen-button')).onPressed, isNull);
      home(t).refreshHome(() => home(t).controlsLocked = false);
      await t.pumpAndSettle();

      await t.tap(key('full-screen-button'));
      await t.pumpAndSettle();
      expect(stage, findsOneWidget);
      expect(home(t).hostFullScreen.showing, isTrue);
      expect((port as DesktopPort).window.calls, ['enter']);
      // The stage and nothing else: no header, no tabs, no Live controls.
      expect(key('live-menu'), findsNothing);
      expect(key('control-lock'), findsNothing);
      expect(find.byType(StageSurface), findsOneWidget);
      expect(time(t), '12:38');
      // On black, filling the window.
      expect(t.widget<Scaffold>(stage).backgroundColor, Colors.black);
      expect(t.getSize(key('full-screen-stage')), const Size(1366, 768));
      await done(t);
    });

    testWidgets('the Live menu opens it', (t) async {
      final (c, _) = await running(t);
      await t.tap(key('live-menu'));
      await t.pumpAndSettle();
      // The key is shown beside it.
      expect(find.text('F11'), findsOneWidget);
      await t.tap(find.text('Full screen'));
      await t.pumpAndSettle();
      expect(stage, findsOneWidget);
      expect(c.state.session.paused, isFalse);
      await done(t);
    });

    testWidgets('Commands opens it', (t) async {
      await running(t);
      await control(t, LogicalKeyboardKey.keyK);
      await t.enterText(key('command-search'), 'full screen');
      await t.pumpAndSettle();
      expect(key('command-fullscreen'), findsOneWidget);
      expect(
        find.descendant(
          of: key('command-fullscreen'),
          matching: find.text('F11'),
        ),
        findsOneWidget,
      );
      await t.tap(key('command-fullscreen'));
      await t.pumpAndSettle();
      expect(key('command-palette'), findsNothing);
      expect(stage, findsOneWidget);
      // In full screen, Commands still opens, without offering it again.
      await control(t, LogicalKeyboardKey.keyK);
      expect(key('command-palette'), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      expect(key('command-palette'), findsNothing);
      // That Esc closed the list, not full screen.
      expect(stage, findsOneWidget);
      await done(t);
    });

    testWidgets('F11 opens it; F11, Esc and the exit control leave', (t) async {
      final (_, port) = await running(t);
      final window = (port as DesktopPort).window;
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsNothing);
      expect(key('live-menu'), findsOneWidget);
      expect(window.calls, ['enter', 'leave']);

      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      expect(stage, findsNothing);
      expect(window.calls, ['enter', 'leave', 'enter', 'leave']);

      // The exit control is there at first, then goes.
      await press(t, LogicalKeyboardKey.f11);
      expect(key('full-screen-exit'), findsOneWidget);
      expect(find.text('Exit full screen'), findsOneWidget);
      await settleControl(t);
      expect(key('full-screen-exit'), findsNothing);
      // Small, in a corner, clear of the countdown.
      await press(t, LogicalKeyboardKey.escape);
      await press(t, LogicalKeyboardKey.f11);
      final control = t.getRect(key('full-screen-exit'));
      expect(control.height, lessThan(60));
      expect(control.right, greaterThan(1366 - 40));
      expect(control.top, lessThan(40));
      await settleControl(t);
      expect(key('full-screen-exit'), findsNothing);
      // A click anywhere brings up the tray, with Exit at its end; that
      // click changes nothing.
      await tapStage(t, const Offset(300, 500));
      expect(stage, findsOneWidget);
      expect(key('full-screen-tray'), findsOneWidget);
      expect(key('full-screen-exit'), findsOneWidget);
      expect(find.byTooltip('Exit full screen (Esc)'), findsOneWidget);
      await t.pump(HostFullScreenView.trayTime);
      await t.pumpAndSettle();
      expect(key('full-screen-exit'), findsNothing);
      await tapStage(t, const Offset(300, 500));
      await t.tap(key('full-screen-exit'));
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect(key('live-menu'), findsOneWidget);
      expect(window.calls.length, 8);
      await done(t);
    });

    testWidgets('F11 is in the list of shortcuts, and keeps to its rules', (
      t,
    ) async {
      final s = shortcut('fullscreen');
      expect(s.hint, 'F11');
      expect(s.action, 'Full screen');
      expect(shortcutFor(LogicalKeyboardKey.f11, control: false), same(s));

      // Not without a service.
      await running(t, start: false);
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsNothing);
      expect(key('full-screen-button'), findsNothing);
      await t.tap(key('live-menu'));
      await t.pumpAndSettle();
      expect(find.text('Full screen'), findsNothing);
      await press(t, LogicalKeyboardKey.escape);
      await done(t);

      // Not under a question, and not while the controls are locked.
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.space);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsNothing);
      await press(t, LogicalKeyboardKey.escape);
      expect(c.state.session.paused, isFalse);
      home(t).lockControls();
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsNothing);
      await done(t);
    });

    testWidgets('it shows the countdown and follows it', (t) async {
      final (c, port) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      expect(time(t), '12:38');
      // Every digit as wide as the next, so the numbers hold still.
      final style = t.widget<ClockText>(find.byType(ClockText)).style;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      final width = t.getSize(key('stage-time-width')).width;
      port.at = after(340 + 1642 + 27);
      await c.tick();
      await t.pump();
      expect(time(t), '12:11');
      expect(t.getSize(key('stage-time-width')).width, width);
      // The same picture the second screen is given.
      expect(home(t).hostStageSnapshot()['displayText'], '12:11');
      expect(
        home(t).hostStageSnapshot()..remove('stageLayout'),
        c.stageWindowSnapshot()..remove('stageLayout'),
      );
      await done(t);
    });

    testWidgets('its time holds still as the digits change', (t) async {
      final (c, port) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      final times = {'12:38': 0, '12:11': 27, '10:58': 100, '08:47': 231};
      await expectTimeHoldsStill(t, stage, times.keys.toList(), (time) async {
        port.at = after(340 + 1642 + times[time]!);
        await c.tick();
        await t.pump();
      });
      // In the face the app carries, as stage screens are.
      expectBundledFont(t, stage);
      await done(t);
    });

    testWidgets('it stays on the end screen when the service ends, and '
        'leaves when the next is set up', (t) async {
      final (c, port) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      await c.act('end');
      await step(t);
      expect(stage, findsOneWidget);
      expect(home(t).hostFullScreen.showing, isTrue);
      expect(c.state.session.outputMode(c.now), 'End screen');
      expect((port as DesktopPort).window.calls, ['enter']);
      // Setting up the next service brings Live back.
      await c.act('load', value: sunday());
      await step(t);
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect(port.window.calls, ['enter', 'leave']);
      expect(key('live-menu'), findsOneWidget);
      await done(t);
    });

    testWidgets('Space asks to confirm, over the stage, and only then pauses', (
      t,
    ) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await press(t, LogicalKeyboardKey.space);
      // The compact card, in the same words as on Live.
      expect(key('mini-dialog'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      expect(find.text('Confirm pause'), findsOneWidget);
      expect(c.state.session.paused, isFalse);
      expect(stage, findsOneWidget);
      final card = t.getSize(key('mini-dialog'));
      expect(card.width, lessThanOrEqualTo(440));
      expect(card.height, lessThanOrEqualTo(300));
      // Esc cancels the question and stays in full screen.
      await press(t, LogicalKeyboardKey.escape);
      expect(key('mini-dialog'), findsNothing);
      expect(c.state.session.paused, isFalse);
      expect(stage, findsOneWidget);

      await press(t, LogicalKeyboardKey.keyB);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      expect(c.state.session.paused, isFalse);
      await press(t, LogicalKeyboardKey.space);
      expect(c.state.session.paused, isTrue);
      expect(key('mini-dialog'), findsNothing);
      expect(stage, findsOneWidget);

      await press(t, LogicalKeyboardKey.space);
      expect(find.text('Resume Sermon?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.enter);
      expect(c.state.session.paused, isFalse);
      await done(t);
    });

    testWidgets('Page Down twice goes to the next segment', (t) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await t.pump();
      expect(c.state.session.index, 1);
      expect(find.text('Press again to start Response'), findsOneWidget);
      await press(t, LogicalKeyboardKey.pageDown);
      expect(c.state.session.index, 2);
      expect(stage, findsOneWidget);
      expect(time(t), '10:00');
      // Ctrl+Z asks before it goes back.
      await control(t, LogicalKeyboardKey.keyZ);
      expect(key('mini-dialog'), findsOneWidget);
      expect(find.text('Undo segment change?'), findsOneWidget);
      expect(c.state.session.index, 2);
      await t.tap(find.text('Restore previous segment'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);
      // The right arrow is Next too.
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      expect(c.state.session.index, 1);
      await done(t);
    });

    testWidgets('+ opens Adjust time, and digits send cues', (t) async {
      final (c, _) = await running(t);
      // Full screen is This computer, in Church Auditorium: cues show there once
      // Church Auditorium shows cues (it does not at first, facing the room).
      await c.screens.setCues('room', true);
      await press(t, LogicalKeyboardKey.f11);
      await press(t, LogicalKeyboardKey.equal);
      expect(find.byType(TimeAdjustmentDialog), findsOneWidget);
      final before = c.state.session.toJson().toString();
      await press(t, LogicalKeyboardKey.escape);
      expect(find.byType(TimeAdjustmentDialog), findsNothing);
      expect(c.state.session.toJson().toString(), before);
      expect(stage, findsOneWidget);

      // A cue shows on it as it does on a stage screen: TIME'S UP in
      // place of the countdown, WRAP UP in a banner under it.
      await t.sendKeyEvent(LogicalKeyboardKey.digit2);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(c.state.session.alert?.text, "TIME'S UP");
      expect(find.text("TIME'S UP"), findsOneWidget);
      expect(find.byType(ClockText), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(c.state.session.alert?.text, 'WRAP UP');
      expect(find.text('WRAP UP'), findsOneWidget);
      expect(find.byType(ClockText), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpAndSettle();
      expect(find.text('WRAP UP'), findsNothing);
      expect(time(t), '12:38');
      await done(t);
    });

    testWidgets('a warning shows on it as on a stage screen', (t) async {
      final (c, port) = await running(t);
      await c.screens.setCues('room', true);
      await press(t, LogicalKeyboardKey.f11);
      // Into overtime: what the stage is sent is what is drawn.
      port.at = after(340 + 2400 + 75);
      await c.tick();
      await t.pump();
      final data = home(t).hostStageSnapshot();
      expect(data['overtime'], isTrue);
      expect(find.text(data['displayText'] as String), findsWidgets);
      await done(t);
    });

    testWidgets('locked controls block every key', (t) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await control(t, LogicalKeyboardKey.keyL);
      expect(home(t).controlsLocked, isTrue);
      final before = c.state.session.toJson().toString();
      for (final k in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.equal,
        LogicalKeyboardKey.minus,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.escape,
      ]) {
        await press(t, k);
        expect(stage, findsOneWidget, reason: k.debugName);
        expect(key('mini-dialog'), findsNothing, reason: k.debugName);
        expect(find.byType(TimeAdjustmentDialog), findsNothing);
      }
      await control(t, LogicalKeyboardKey.keyZ);
      await control(t, LogicalKeyboardKey.keyK);
      expect(key('command-palette'), findsNothing);
      expect(c.state.session.toJson().toString(), before);

      // Esc showed why: the control offers Hold to unlock, not Exit.
      expect(key('full-screen-locked'), findsOneWidget);
      expect(find.text('Controls locked'), findsOneWidget);
      expect(key('full-screen-exit'), findsNothing);
      await t.tap(key('full-screen-unlock'));
      await t.pump();
      expect(home(t).controlsLocked, isTrue);
      expect(find.text('Click and hold to unlock controls.'), findsOneWidget);
      await t.longPress(key('full-screen-unlock'));
      await t.pumpAndSettle();
      expect(home(t).controlsLocked, isFalse);
      // Unlocked, the way out is back.
      expect(key('full-screen-exit'), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      expect(stage, findsNothing);
      await done(t);
    });

    testWidgets('a quick timer works', (t) async {
      final (c, _) = await running(t, start: false);
      expect(
        await c.startQuickTimer(const QuickTimerChoice('Offering', 300)),
        isTrue,
      );
      await t.pumpAndSettle();
      expect(c.state.session.quickTimer, isTrue);
      await t.tap(key('full-screen-button'));
      await t.pumpAndSettle();
      expect(stage, findsOneWidget);
      expect(time(t), '05:00');
      await press(t, LogicalKeyboardKey.space);
      expect(find.text('Pause Offering?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.space);
      expect(c.state.session.paused, isTrue);
      await press(t, LogicalKeyboardKey.escape);
      expect(stage, findsNothing);
      await done(t);
    });

    testWidgets('it shows what the choice says', (t) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      expect(find.text('Sermon'), findsNothing);
      expect(find.text('UP NEXT'), findsNothing);
      await c.screens.setShow('room', 'current');
      await t.pumpAndSettle();
      expect(find.text('Sermon'), findsOneWidget);
      await c.screens.setShow('room', 'next');
      await t.pumpAndSettle();
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(time(t), '12:38');
      // Up next only: the next item and no time.
      await c.screens.setShow('room', 'only');
      await t.pumpAndSettle();
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
      expect(find.byType(ClockText), findsNothing);
      await c.screens.setShow('room', 'next');
      await t.pumpAndSettle();
      // Kept on this device with the groups.
      expect(
        AppState.fromJson(
          c.state.toJson(),
        ).screens!.groupOf(thisScreenKey).show,
        'next',
      );
      await done(t);
    });

    testWidgets('a computer shows what its second screen is set to show', (
      t,
    ) async {
      desktopWording = true;
      addTearDown(() => desktopWording = false);
      setScreen(t, const Size(1366, 768));
      final c = AppController(SecondPort());
      await c.initialize(startTicker: false);
      await c.act('load', value: sunday());
      await c.act('start');
      await c.commit((d, _) => d.dismissedHints.add(gesturesTipHint));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
      await c.screens.setShow('room', 'next');
      await t.pumpAndSettle();
      expect(find.text('UP NEXT'), findsOneWidget);
      expect(find.text('Sermon'), findsOneWidget);
      expect(find.text('40 min'), findsOneWidget);
      expect(home(t).hostStageSnapshot(), c.stageWindowSnapshot());
      // No window to change here: the stage fills the one there is.
      expect(t.getSize(key('full-screen-stage')), const Size(1366, 768));
      await press(t, LogicalKeyboardKey.escape);
      expect(stage, findsNothing);
      await done(t);
    });

    testWidgets('a window that will not go full screen still shows it', (
      t,
    ) async {
      final (_, port) = await running(t);
      (port as DesktopPort).window.works = false;
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      expect(t.getSize(key('full-screen-stage')), const Size(1366, 768));
      await press(t, LogicalKeyboardKey.escape);
      expect(stage, findsNothing);
      await done(t);
    });

    testWidgets('a phone gets it: a button, the menu and its own choice', (
      t,
    ) async {
      final modes = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (c, _) = await running(
        t,
        desktop: false,
        size: const Size(430, 900),
      );
      // No key is promised where there is no keyboard.
      expect(
        find.byTooltip('Full screen: show the stage on this screen'),
        findsOneWidget,
      );
      // Under the stage preview: the header is too narrow for one more.
      expect(
        find.descendant(
          of: find.byType(SliverAppBar),
          matching: key('full-screen-button'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: key('full-screen-button'),
          matching: find.text('Full screen'),
        ),
        findsOneWidget,
      );
      await t.ensureVisible(key('full-screen-button'));
      await t.pumpAndSettle();
      await t.tap(key('full-screen-button'));
      await t.pumpAndSettle();
      expect(stage, findsOneWidget);
      expect(time(t), '12:38');
      // The system bars are hidden while it shows.
      expect(modes, ['SystemUiMode.immersiveSticky']);
      await settleControl(t);
      await tapStage(t, const Offset(200, 600));
      expect(find.byTooltip('Exit full screen'), findsOneWidget);
      await t.tap(key('full-screen-exit'));
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(modes, [
        'SystemUiMode.immersiveSticky',
        'SystemUiMode.edgeToEdge',
      ]);

      await openLiveMenu(t, 'Full screen');
      expect(stage, findsOneWidget);
      // Back leaves full screen, not the app.
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(find.text('Leave the app?'), findsNothing);
      // F11 is a computer's key.
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsNothing);
      expect(modes.length, 4);

      // Its own choice of what to show, in Screens & devices.
      await c.act('end');
      await t.pumpAndSettle();
      unawaited(
        home(
          t,
        ).openSettingsDetail('Screens & devices', home(t).pairedDeviceSettings),
      );
      await t.pumpAndSettle();
      final note = key('screen-group-note-this');
      await t.ensureVisible(note);
      await t.pumpAndSettle();
      expect(find.text('Full screen on this phone'), findsOneWidget);
      // What it shows is its group's, set in Screens.
      expect(key('full-screen-layout-next'), findsNothing);
      expect(key('open-screens-this'), findsOneWidget);
      await done(t);
    });

    /// Records Android's "follow the sensor" request, in the same list as
    /// what was asked of Flutter's own orientation call.
    bool? recordSensorLandscape(WidgetTester t, List<String> asked) {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('church.timer/device'),
        (call) async {
          if (call.method == 'sensorLandscape') {
            asked.add(
              'sensorLandscape ${call.arguments == true ? 'on' : 'off'}',
            );
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('church.timer/device'),
          null,
        ),
      );
      return true;
    }

    testWidgets('a phone or tablet turns landscape, and back on leaving', (
      t,
    ) async {
      ScreenOrientation.reset();
      addTearDown(ScreenOrientation.reset);
      // What the app asks the system for, latest last.
      final asked = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            final list = (call.arguments as List).cast<String>();
            asked.add(
              list.isEmpty
                  ? 'any'
                  : list.map((o) => o.split('.').last).join(' '),
            );
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const landscape = 'landscapeLeft landscapeRight';
      await running(t, desktop: false, size: const Size(430, 900));
      expect(asked, isEmpty);
      // Android's own request for the sensor, and its order among them.
      final sensor = recordSensorLandscape(t, asked);
      Future<void> open() async {
        await openLiveMenu(t, 'Full screen');
        expect(stage, findsOneWidget);
        expect(asked[asked.length - 2], landscape);
        expect(asked.last, 'sensorLandscape on');
      }

      // Exit.
      await open();
      await settleControl(t);
      await tapStage(t, const Offset(200, 600));
      await t.tap(key('full-screen-exit'));
      await t.pumpAndSettle();
      // Both landscapes, then the sensor on whatever auto-rotate says;
      // leaving drops the sensor first, then asks as before.
      expect(asked, [
        landscape,
        'sensorLandscape on',
        'sensorLandscape off',
        'any',
      ]);
      expect(sensor, isNotNull);
      asked.clear();

      // Back.
      await open();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(asked, [
        landscape,
        'sensorLandscape on',
        'sensorLandscape off',
        'any',
      ]);
      asked.clear();

      // Closed with the app, from full screen.
      await open();
      await done(t);
      expect(asked, [
        landscape,
        'sensorLandscape on',
        'sensorLandscape off',
        'any',
      ]);
      expect(ScreenOrientation.fullScreen, isFalse);
    });

    testWidgets('leaving brings back what the app asked for before', (t) async {
      ScreenOrientation.reset();
      addTearDown(ScreenOrientation.reset);
      final asked = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            final list = (call.arguments as List).cast<String>();
            asked.add(
              list.isEmpty
                  ? 'any'
                  : list.map((o) => o.split('.').last).join(' '),
            );
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const landscape = 'landscapeLeft landscapeRight';
      final (c, _) = await running(
        t,
        desktop: false,
        size: const Size(430, 900),
      );
      Future<void> open() async {
        await openLiveMenu(t, 'Full screen');
        expect(stage, findsOneWidget);
        expect(asked.last, landscape);
      }

      // Whatever the app asked for before comes back, not "any".
      await ScreenOrientation.setApp(const [DeviceOrientation.portraitUp]);
      asked.clear();
      await open();
      // Asked for while full screen: kept for later, still landscape.
      await ScreenOrientation.setApp(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
      ]);
      expect(asked, [landscape]);
      // The service ends: on a phone full screen closes, and the screen
      // goes back to what the app asked for last.
      await c.act('end');
      await step(t);
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect(asked, [landscape, 'portraitUp landscapeLeft']);
      expect(ScreenOrientation.fullScreen, isFalse);
      await ScreenOrientation.setApp(const []);
      await done(t);
    });

    testWidgets('joining another service as a stage screen stays landscape', (
      t,
    ) async {
      ScreenOrientation.reset();
      addTearDown(ScreenOrientation.reset);
      final asked = <List<Object?>>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            asked.add(call.arguments as List);
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final (c, _) = await running(
        t,
        desktop: false,
        size: const Size(430, 900),
      );
      await openLiveMenu(t, 'Full screen');
      expect(stage, findsOneWidget);
      c.pairing
        ..mode = 'stage'
        ..status = 'Connected to Grace Chapel sound desk'
        ..snapshot = c.pairedSnapshot(false)
        ..lastSnapshot = DateTime.now().millisecondsSinceEpoch
        ..changed();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(PairedScreen), findsOneWidget);
      expect(stage, findsNothing);
      // The stage screen's own landscape, whichever came last.
      expect(asked.last, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      expect(ScreenOrientation.app, ScreenOrientation.landscape);
      expect(ScreenOrientation.fullScreen, isFalse);
      await done(t);
    });

    testWidgets('a computer leaves its orientation alone', (t) async {
      ScreenOrientation.reset();
      addTearDown(ScreenOrientation.reset);
      var asked = 0;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations' ||
              call.method == 'SystemChrome.setEnabledSystemUIMode') {
            asked++;
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await running(t);
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      expect(stage, findsNothing);
      expect(asked, 0);
      await done(t);
    });

    testWidgets('a joined stage screen does not get it', (t) async {
      final (c, port) = await running(t);
      expect(key('full-screen-button'), findsOneWidget);
      // This device now follows another's service as a stage screen.
      c.pairing
        ..mode = 'stage'
        ..status = 'Connected to Grace Chapel sound desk'
        ..snapshot = c.pairedSnapshot(false)
        ..lastSnapshot = DateTime.now().millisecondsSinceEpoch
        ..changed();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(PairedScreen), findsOneWidget);
      expect(home(t).hostFullScreenAvailable, isFalse);
      expect(key('full-screen-button'), findsNothing);
      expect(await home(t).setHostFullScreen(true), isFalse);
      await t.sendKeyEvent(LogicalKeyboardKey.f11);
      await t.pump();
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect((port as DesktopPort).window.calls, isEmpty);
      await done(t);
    });

    testWidgets('nothing overflows, from a small phone to a large monitor', (
      t,
    ) async {
      for (final (size, desktop, scale) in const [
        (Size(320, 568), false, 1.6),
        (Size(568, 320), false, 1.6),
        (Size(1200, 600), true, 1.0),
        (Size(1920, 1080), true, 1.3),
        (Size(2560, 1440), true, 1.0),
      ]) {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final (c, _) = await running(t, desktop: desktop, size: size);
        await c.screens.setShow('room', 'next');
        await t.pumpAndSettle();
        // The header with its new button.
        expect(key('full-screen-button'), findsOneWidget, reason: '$size');
        expect(t.takeException(), isNull, reason: 'Live at $size');
        await t.ensureVisible(key('full-screen-button'));
        await t.pumpAndSettle();
        await t.tap(key('full-screen-button'));
        await t.pumpAndSettle();
        expect(stage, findsOneWidget, reason: '$size');
        expect(t.getSize(stage), size);
        expect(key('full-screen-exit'), findsOneWidget);
        final window = Offset.zero & size;
        final exit = t.getRect(key('full-screen-exit'));
        expect(window.intersect(exit), exit, reason: '$size');
        expect(t.takeException(), isNull, reason: 'stage at $size');
        // A question over it.
        final asked = home(t).confirmPause();
        await t.pumpAndSettle();
        final card = t.getRect(key('mini-dialog'));
        expect(window.intersect(card), card, reason: '$size');
        for (final button in ['mini-confirm-cancel', 'mini-confirm-action']) {
          final rect = t.getRect(key(button));
          expect(card.intersect(rect), rect, reason: '$size');
        }
        expect(t.takeException(), isNull, reason: 'question at $size');
        await t.tap(key('mini-confirm-cancel'));
        await t.pumpAndSettle();
        await asked;
        // Locked, the control still fits.
        home(t).lockControls();
        await t.pumpAndSettle();
        await tapStage(t, size.center(Offset.zero));
        final locked = t.getRect(key('full-screen-locked'));
        expect(window.intersect(locked), locked, reason: '$size');
        expect(t.takeException(), isNull, reason: 'locked at $size');
        await done(t);
      }
    });

    /// Two quick taps, or two clicks with [kind] mouse, at [at].
    Future<void> doubleTap(
      WidgetTester t,
      Offset at, {
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      await t.tapAt(at, kind: kind);
      await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(at, kind: kind);
      await t.pumpAndSettle();
    }

    /// The left, middle and right thirds of a 1366 × 768 window.
    const left = Offset(200, 400),
        middle = Offset(683, 400),
        right = Offset(1160, 400);

    /// A swipe up from the bottom edge of a window [size].
    Future<void> swipeUp(
      WidgetTester t, {
      Size size = const Size(1366, 768),
    }) async {
      await t.dragFrom(
        Offset(size.width / 2, size.height - 20),
        const Offset(0, -150),
      );
      await t.pumpAndSettle();
    }

    final tray = find.byKey(const ValueKey('full-screen-tray'));

    testWidgets('a double click on the right asks for the next segment', (
      t,
    ) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      expect(stageThird(1000, 1366), StageThird.right);
      await doubleTap(t, right, kind: PointerDeviceKind.mouse);
      // The same question as Next segment on Live, in the card over the
      // stage; nothing has changed yet.
      expect(key('mini-dialog'), findsOneWidget);
      expect(find.text('Start Response?'), findsOneWidget);
      expect(c.state.session.index, 1);
      // Two clicks are not a click: no tray.
      expect(tray, findsNothing);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);
      // A double tap too; confirming goes on.
      await doubleTap(t, right);
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 2);
      expect(time(t), '10:00');
      expect(stage, findsOneWidget);
      // On the last segment there is nowhere to go: a hint, no question.
      await doubleTap(t, right);
      expect(key('mini-dialog'), findsNothing);
      expect(find.text('This is the last segment'), findsOneWidget);
      await t.pump(HostFullScreenView.hintTime);
      await t.pumpAndSettle();
      expect(key('full-screen-hint'), findsNothing);
      await done(t);
    });

    testWidgets('a double tap in the middle asks to pause, then to resume', (
      t,
    ) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await doubleTap(t, middle);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      expect(find.text('Confirm pause'), findsOneWidget);
      expect(c.state.session.paused, isFalse);
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, isTrue);
      await doubleTap(t, middle);
      expect(find.text('Resume Sermon?'), findsOneWidget);
      // Cancel leaves it paused.
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, isTrue);
      await doubleTap(t, middle);
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, isFalse);
      await done(t);
    });

    testWidgets('a double tap on the left asks to undo, if there is any', (
      t,
    ) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      // Going from Welcome to Sermon can be undone.
      expect(c.state.session.undo, isNotNull);
      await doubleTap(t, left);
      expect(find.text('Undo segment change?'), findsOneWidget);
      expect(c.state.session.index, 1);
      await t.tap(find.text('Restore previous segment'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 0);
      // Nothing left to undo: a small hint that fades, and no question.
      expect(c.state.session.undo, isNull);
      await doubleTap(t, left);
      expect(key('mini-dialog'), findsNothing);
      expect(key('full-screen-hint'), findsOneWidget);
      expect(find.text('Nothing to undo'), findsOneWidget);
      expect(c.state.session.index, 0);
      await t.pump(HostFullScreenView.hintTime);
      await t.pumpAndSettle();
      expect(find.text('Nothing to undo'), findsNothing);
      await done(t);
    });

    testWidgets('locked controls block the gestures and the tray', (t) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      home(t).lockControls();
      await t.pumpAndSettle();
      final before = c.state.session.toJson().toString();
      for (final at in [left, middle, right]) {
        await doubleTap(t, at);
        expect(key('mini-dialog'), findsNothing, reason: '$at');
        expect(key('full-screen-hint'), findsNothing, reason: '$at');
      }
      await swipeUp(t);
      expect(tray, findsNothing);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(683, 300));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(const Offset(683, 767));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      await tapStage(t, middle);
      expect(tray, findsNothing);
      expect(c.state.session.toJson().toString(), before);
      // Only the way to unlock is offered.
      expect(key('full-screen-locked'), findsOneWidget);
      await t.longPress(key('full-screen-unlock'));
      await t.pumpAndSettle();
      expect(home(t).controlsLocked, isFalse);
      await swipeUp(t);
      expect(tray, findsOneWidget);
      // Locking again puts the tray away.
      await control(t, LogicalKeyboardKey.keyL);
      expect(tray, findsNothing);
      await done(t);
    });

    testWidgets('a swipe up brings the tray; each action asks first', (
      t,
    ) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      // A swipe up the middle of the stage is not from the bottom.
      await t.dragFrom(middle, const Offset(0, -220));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      await swipeUp(t);
      expect(tray, findsOneWidget);
      for (final name in [
        'pause',
        'next',
        'minus',
        'plus',
        'undo',
        'cues',
        'clock',
        'blank',
        'gestures',
        'end',
      ]) {
        expect(key('full-screen-tray-$name'), findsOneWidget, reason: name);
      }
      expect(key('full-screen-exit'), findsOneWidget);
      // Along the bottom, small, inside the window.
      final rect = t.getRect(tray);
      expect(rect.bottom, closeTo(768, 1));
      expect(rect.height, lessThan(110));
      expect((Offset.zero & const Size(1366, 768)).intersect(rect), rect);
      // The stage picture is what it was: the tray is not part of it.
      expect(home(t).hostStageSnapshot(), isNot(contains('tray')));

      await t.tap(key('full-screen-tray-pause'));
      await t.pumpAndSettle();
      expect(find.text('Pause Sermon?'), findsOneWidget);
      expect(c.state.session.paused, isFalse);
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.paused, isTrue);
      // Still there, now offering Resume.
      expect(find.text('Resume'), findsOneWidget);

      await t.tap(key('full-screen-tray-next'));
      await t.pumpAndSettle();
      expect(find.text('Start Response?'), findsOneWidget);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.index, 1);

      await t.tap(key('full-screen-tray-plus'));
      await t.pumpAndSettle();
      expect(find.byType(TimeAdjustmentDialog), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      expect(find.byType(TimeAdjustmentDialog), findsNothing);

      await t.tap(key('full-screen-tray-undo'));
      await t.pumpAndSettle();
      expect(find.text('Undo segment change?'), findsOneWidget);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();

      await t.tap(key('full-screen-tray-blank'));
      await t.pumpAndSettle();
      expect(find.text('Blank the screen?'), findsOneWidget);
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.outputBlank, isTrue);
      expect(find.text('Unblank'), findsOneWidget);
      await t.tap(key('full-screen-tray-blank'));
      await t.pumpAndSettle();
      await t.tap(key('mini-confirm-action'));
      await t.pumpAndSettle();
      expect(c.state.session.outputBlank, isFalse);

      // End service asks first, as on Live; Cancel keeps the service.
      await t.tap(key('full-screen-tray-end'));
      await t.pumpAndSettle();
      expect(find.textContaining('End Sunday'), findsOneWidget);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      expect(c.state.session.active, isTrue);

      // The clock, and back, as on Live: no question.
      await t.tap(key('full-screen-tray-clock'));
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Clock');
      expect(find.byTooltip('Show timer'), findsOneWidget);
      await t.tap(key('full-screen-tray-clock'));
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), isNot('Clock'));

      // A cue from the list, and the same cue again goes back.
      await t.tap(key('full-screen-tray-cues'));
      await t.pumpAndSettle();
      await t.tap(key('full-screen-tray-cue-0'));
      // WRAP UP pulses on the stage, so it never settles.
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      expect(c.state.session.alert?.text, 'WRAP UP');
      await t.tap(key('full-screen-tray-cues'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(key('full-screen-tray-cue-0'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(c.state.session.hasManualCue(c.now), isFalse);

      // A swipe down puts it away; Esc does too, before it leaves.
      await t.dragFrom(t.getCenter(tray), const Offset(0, 200));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      await swipeUp(t);
      await press(t, LogicalKeyboardKey.escape);
      expect(tray, findsNothing);
      expect(stage, findsOneWidget);
      await swipeUp(t);
      await t.tap(key('full-screen-exit'));
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      await done(t);
    });

    Future<void> endFromTray(
      WidgetTester t, {
      Size size = const Size(1366, 768),
    }) async {
      await swipeUp(t, size: size);
      await t.tap(key('full-screen-tray-end'));
      await t.pumpAndSettle();
      await t.tap(key('mini-confirm-action'));
      await step(t);
    }

    testWidgets('End service in the tray ends it and stays on the end screen, '
        'with only the stage controls left', (t) async {
      final (c, _) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await endFromTray(t);
      expect(c.state.session.phase, 'ended');
      expect(home(t).hostFullScreen.showing, isTrue);
      expect(stage, findsOneWidget);
      expect(c.state.session.outputMode(c.now), 'End screen');
      expect(
        home(t).hostStageSnapshot().toString(),
        contains(sunday().display.end!.text),
      );
      // The timer controls are greyed out; cues, the clock, blank and exit
      // still work.
      await t.dragFrom(const Offset(683, 748), const Offset(0, -150));
      await step(t);
      bool on(String k) => t.widget<TextButton>(key(k)).onPressed != null;
      for (final name in ['pause', 'next', 'minus', 'plus', 'undo', 'end']) {
        expect(on('full-screen-tray-$name'), isFalse, reason: name);
      }
      for (final name in ['cues', 'clock', 'blank']) {
        expect(on('full-screen-tray-$name'), isTrue, reason: name);
      }
      expect(on('full-screen-exit'), isTrue);
      await t.tap(key('full-screen-tray-clock'));
      await step(t);
      expect(c.state.session.outputMode(c.now), 'Clock');
      await t.tap(key('full-screen-exit'));
      await step(t);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('with no end screen, End service says the clock will show, '
        'and full screen shows it', (t) async {
      final (c, _) = await running(t, noEnd: true);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await swipeUp(t);
      await t.tap(key('full-screen-tray-end'));
      await t.pumpAndSettle();
      expect(find.textContaining('show the clock'), findsOneWidget);
      expect(find.textContaining('Hallelujah'), findsNothing);
      await t.tap(key('mini-confirm-action'));
      await step(t);
      expect(c.state.session.phase, 'ended');
      expect(home(t).hostFullScreen.showing, isTrue);
      expect(c.state.session.outputMode(c.now), 'Clock');
      final snapshot = home(t).hostStageSnapshot();
      expect(snapshot['outputMode'], 'Clock');
      expect(
        snapshot['displayText'],
        stageClockText(c.now.wall, c.state.session.clockFormat),
      );
      expect(snapshot.toString(), isNot(contains('Hallelujah')));
      // The clock fills the screen as a flip clock.
      expect(find.byType(FlipClock), findsOneWidget);
      // The clock is already showing: the tray's Clock has nothing to do.
      await t.dragFrom(const Offset(683, 748), const Offset(0, -150));
      await step(t);
      bool on(String k) => t.widget<TextButton>(key(k)).onPressed != null;
      expect(on('full-screen-tray-clock'), isFalse);
      expect(on('full-screen-tray-blank'), isTrue);
      await t.tap(key('full-screen-exit'));
      await step(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('the tray goes after six seconds untouched', (t) async {
      await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      expect(HostFullScreenView.trayTime, const Duration(seconds: 6));
      await swipeUp(t);
      expect(tray, findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      expect(tray, findsOneWidget);
      // A touch in it starts the six seconds again.
      await t.tapAt(t.getTopLeft(tray) + const Offset(20, 4));
      await t.pump(const Duration(seconds: 5));
      expect(tray, findsOneWidget);
      await t.pump(const Duration(milliseconds: 1100));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      // So does a question opened from it, until it is answered.
      await swipeUp(t);
      await t.tap(key('full-screen-tray-pause'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 10));
      expect(tray, findsOneWidget);
      await t.tap(key('mini-confirm-cancel'));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 5));
      expect(tray, findsOneWidget);
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      await done(t);
    });

    testWidgets('on a computer the mouse at the bottom brings the tray', (
      t,
    ) async {
      await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(683, 300));
      addTearDown(mouse.removePointer);
      // Moving about the stage does nothing.
      await mouse.moveTo(const Offset(900, 600));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      await mouse.moveTo(const Offset(683, 767));
      await t.pumpAndSettle();
      expect(tray, findsOneWidget);
      // It stays while the mouse is on it.
      await mouse.moveTo(t.getCenter(key('full-screen-tray-pause')));
      await t.pump(const Duration(seconds: 10));
      expect(tray, findsOneWidget);
      // Then goes six seconds after the mouse leaves it.
      await mouse.moveTo(const Offset(683, 300));
      await t.pump(const Duration(seconds: 5));
      expect(tray, findsOneWidget);
      await t.pump(const Duration(milliseconds: 1100));
      await t.pumpAndSettle();
      expect(tray, findsNothing);
      // A single click brings it too, once it is sure it was not two.
      await mouse.down(const Offset(683, 300));
      await mouse.up();
      await t.pump();
      expect(tray, findsNothing);
      await t.pump(kDoubleTapTimeout);
      await t.pumpAndSettle();
      expect(tray, findsOneWidget);
      // The keys still work with it showing.
      await press(t, LogicalKeyboardKey.space);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      await press(t, LogicalKeyboardKey.escape);
      await done(t);
    });

    testWidgets('with Reduced motion the tray appears at once', (t) async {
      final (c, _) = await running(t);
      await c.commit(
        (draft, _) =>
            draft.appearance = const AppearancePreferences(reducedMotion: true),
      );
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await t.dragFrom(const Offset(683, 748), const Offset(0, -220));
      await t.pump();
      expect(tray, findsOneWidget);
      expect(t.getRect(tray).bottom, closeTo(768, 1));
      await done(t);
    });

    testWidgets('the tray fits from a small phone to a large monitor', (
      t,
    ) async {
      for (final (size, desktop, scale) in const [
        (Size(568, 320), false, 1.6),
        (Size(844, 390), false, 1.0),
        (Size(1920, 1080), true, 1.3),
      ]) {
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await running(t, desktop: desktop, size: size);
        unawaited(home(t).setHostFullScreen(true));
        await t.pumpAndSettle();
        await settleControl(t);
        await swipeUp(t, size: size);
        expect(tray, findsOneWidget, reason: '$size');
        final rect = t.getRect(tray);
        expect((Offset.zero & size).intersect(rect), rect, reason: '$size');
        expect(t.takeException(), isNull, reason: '$size');
        await done(t);
      }
    });

    testWidgets('on a phone the service ending closes full screen and the '
        'orientation goes back, whoever ends it', (t) async {
      ScreenOrientation.reset();
      addTearDown(ScreenOrientation.reset);
      final asked = <String>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            final list = (call.arguments as List).cast<String>();
            asked.add(
              list.isEmpty
                  ? 'any'
                  : list.map((o) => o.split('.').last).join(' '),
            );
          }
          return null;
        },
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      const landscape = 'landscapeLeft landscapeRight';
      const size = Size(844, 390);
      Future<AppController> open() async {
        final (c, _) = await running(t, desktop: false, size: size);
        await ScreenOrientation.setApp(const [DeviceOrientation.portraitUp]);
        asked.clear();
        unawaited(home(t).setHostFullScreen(true));
        await t.pumpAndSettle();
        await settleControl(t);
        expect(stage, findsOneWidget);
        expect(asked, [landscape]);
        return c;
      }

      // End service in the tray.
      var c = await open();
      await endFromTray(t, size: size);
      expect(c.state.session.phase, 'ended');
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect(asked, [landscape, 'portraitUp']);
      expect(ScreenOrientation.fullScreen, isFalse);
      expect(t.takeException(), isNull);
      await done(t);

      // End service from the Live controls, with full screen open: the
      // same way out.
      ScreenOrientation.reset();
      c = await open();
      unawaited(home(t).confirmEndService());
      await t.pumpAndSettle();
      await t.tap(key('mini-confirm-action'));
      await step(t);
      expect(c.state.session.phase, 'ended');
      expect(stage, findsNothing);
      expect(asked, [landscape, 'portraitUp']);
      await done(t);

      // Ended from a paired device.
      ScreenOrientation.reset();
      c = await open();
      await c.act('end');
      await step(t);
      expect(stage, findsNothing);
      expect(asked, [landscape, 'portraitUp']);
      expect(ScreenOrientation.fullScreen, isFalse);
      // Live shows the ended service, not the stage.
      expect(key('live-menu'), findsOneWidget);
      await done(t);
    });

    testWidgets('on a computer the service ending leaves full screen open', (
      t,
    ) async {
      final (c, port) = await running(t, size: const Size(1366, 768));
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await endFromTray(t);
      expect(c.state.session.phase, 'ended');
      expect(stage, findsOneWidget);
      expect((port as DesktopPort).window.calls, ['enter']);
      await t.tap(key('full-screen-exit'));
      await step(t);
      expect(port.window.calls, ['enter', 'leave']);
    });

    testWidgets('a computer sends Android no orientation request', (t) async {
      final asked = <String>[];
      recordSensorLandscape(t, asked);
      await running(t);
      await press(t, LogicalKeyboardKey.f11);
      await press(t, LogicalKeyboardKey.escape);
      expect(asked, isEmpty);
      await done(t);
    });

    group('the gestures tip', () {
      const phone = Size(844, 390);
      final tip = find.byKey(const ValueKey('full-screen-tip'));
      bool seen(AppController c) =>
          c.state.dismissedHints.contains(gesturesTipHint);

      Future<AppController> open(
        WidgetTester t, {
        bool desktop = false,
        Size size = phone,
      }) async {
        final (c, _) = await running(
          t,
          desktop: desktop,
          size: size,
          tip: true,
        );
        unawaited(home(t).setHostFullScreen(true));
        await t.pumpAndSettle();
        return c;
      }

      testWidgets('shows the first time, in plain words, and is kept on the '
          'device only', (t) async {
        final c = await open(t);
        expect(stage, findsOneWidget);
        expect(tip, findsOneWidget);
        for (final words in [
          'Undo',
          'Pause or resume',
          'Next segment',
          'Swipe up from the bottom, or tap once, for the controls',
        ]) {
          expect(find.text(words), findsOneWidget, reason: words);
        }
        expect(find.text('Double-tap here'), findsNWidgets(3));
        expect(find.textContaining('tap anywhere'), findsNothing);
        expect(find.textContaining('Tap anywhere'), findsOneWidget);
        expect(seen(c), isTrue);
        // Drawn on this screen only: the stage picture is untouched.
        final snapshot = home(t).hostStageSnapshot();
        expect(snapshot.toString().toLowerCase(), isNot(contains('gesture')));
        expect(snapshot.toString(), isNot(contains('Pause or resume')));
        expect(snapshot, {...c.stageWindowSnapshot(), 'stageLayout': 'timer'});
        // Not in a backup.
        final backup = exportBackup(c.state, c.now);
        expect(backup, isNot(contains(gesturesTipHint)));
        expect(backup, isNot(contains('dismissedHints')));
        // On the device it is kept.
        expect(
          AppState.fromJson(c.state.toJson()).dismissedHints,
          contains(gesturesTipHint),
        );
        await t.tap(key('full-screen-tip-tap'));
        await t.pumpAndSettle();
        await done(t);
      });

      testWidgets('says click, not tap, on a computer', (t) async {
        await open(t, desktop: true, size: const Size(1920, 1080));
        expect(tip, findsOneWidget);
        expect(find.text('Double-click here'), findsNWidgets(3));
        expect(
          find.text(
            'Click once, or move the mouse to the bottom edge, for the controls',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Click anywhere'), findsOneWidget);
        expect(find.textContaining('tap'), findsNothing);
        await t.tap(key('full-screen-tip-tap'));
        await t.pumpAndSettle();
        await done(t);
      });

      testWidgets('a tap dismisses it, and neither it nor a quick second '
          'tap does anything else', (t) async {
        final c = await open(t);
        final before = c.state.session.toJson().toString();
        // Two quick taps on the left third, as a double tap would be.
        await t.tapAt(const Offset(150, 200));
        await t.pump(const Duration(milliseconds: 60));
        expect(tip, findsNothing);
        await t.tapAt(const Offset(150, 200));
        await t.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
        await t.pumpAndSettle();
        expect(key('mini-dialog'), findsNothing);
        expect(key('full-screen-hint'), findsNothing);
        expect(tray, findsNothing);
        expect(stage, findsOneWidget);
        expect(c.state.session.toJson().toString(), before);
        // Afterwards the stage answers as usual.
        await t.pump(HostFullScreenView.tipGuard);
        await doubleTap(t, const Offset(422, 200));
        expect(find.text('Pause Sermon?'), findsOneWidget);
        await t.tap(key('mini-confirm-cancel'));
        await t.pumpAndSettle();
        await done(t);
      });

      testWidgets('a key, the time, or Back dismisses it; Esc and Back stay '
          'in full screen', (t) async {
        await open(t);
        expect(HostFullScreenView.tipTime, const Duration(seconds: 8));
        await t.pump(const Duration(seconds: 7));
        expect(tip, findsOneWidget);
        await t.pump(const Duration(seconds: 1, milliseconds: 100));
        await t.pumpAndSettle();
        expect(tip, findsNothing);
        expect(stage, findsOneWidget);

        home(t).hostFullScreen.showTip!();
        await t.pumpAndSettle();
        expect(tip, findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.keyQ);
        await t.pumpAndSettle();
        expect(tip, findsNothing);

        home(t).hostFullScreen.showTip!();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pumpAndSettle();
        expect(tip, findsNothing);
        expect(stage, findsOneWidget);

        home(t).hostFullScreen.showTip!();
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(tip, findsNothing);
        expect(stage, findsOneWidget);
        await done(t);
      });

      testWidgets('never shows again by itself, but Show gestures brings it '
          'back', (t) async {
        final c = await open(t);
        await t.tap(key('full-screen-tip-tap'));
        await t.pumpAndSettle();
        await t.pump(HostFullScreenView.tipGuard);
        expect(tip, findsNothing);
        // Leave, open again: nothing.
        await home(t).setHostFullScreen(false);
        await t.pumpAndSettle();
        unawaited(home(t).setHostFullScreen(true));
        await t.pumpAndSettle();
        expect(stage, findsOneWidget);
        expect(tip, findsNothing);
        expect(seen(c), isTrue);
        // From the tray, on demand.
        await swipeUp(t, size: phone);
        expect(tray, findsOneWidget);
        expect(find.text('Show gestures'), findsOneWidget);
        await t.tap(key('full-screen-tray-gestures'));
        await t.pumpAndSettle();
        expect(tip, findsOneWidget);
        expect(tray, findsNothing);
        await t.pump(HostFullScreenView.tipTime);
        await t.pumpAndSettle();
        expect(tip, findsNothing);
        await done(t);
      });

      testWidgets('with the controls locked it does not show, or get in the '
          'way of Hold to unlock', (t) async {
        final (c, _) = await running(t, desktop: false, size: phone, tip: true);
        home(t).lockControls();
        await t.pumpAndSettle();
        unawaited(home(t).setHostFullScreen(true));
        await t.pumpAndSettle();
        expect(stage, findsOneWidget);
        expect(tip, findsNothing);
        expect(key('full-screen-tip-tap'), findsNothing);
        // Not used up: it shows when unlocked.
        expect(seen(c), isFalse);
        expect(key('full-screen-locked'), findsOneWidget);
        await t.longPress(key('full-screen-unlock'));
        await t.pumpAndSettle();
        expect(home(t).controlsLocked, isFalse);
        expect(tip, findsNothing);

        // Locking while it shows takes it away.
        home(t).hostFullScreen.showTip!();
        await t.pumpAndSettle();
        expect(tip, findsOneWidget);
        home(t).lockControls();
        await t.pumpAndSettle();
        expect(tip, findsNothing);
        expect(key('full-screen-tip-tap'), findsNothing);
        // Show gestures does nothing locked.
        home(t).hostFullScreen.showTip!();
        await t.pumpAndSettle();
        expect(tip, findsNothing);
        await t.longPress(key('full-screen-unlock'));
        await t.pumpAndSettle();
        expect(home(t).controlsLocked, isFalse);
        await done(t);
      });

      testWidgets('with Reduced motion it comes and goes at once', (t) async {
        final (c, _) = await running(t, desktop: false, size: phone, tip: true);
        await c.commit(
          (d, _) =>
              d.appearance = const AppearancePreferences(reducedMotion: true),
        );
        unawaited(home(t).setHostFullScreen(true));
        await t.pump();
        await t.pump();
        expect(tip, findsOneWidget);
        await t.tap(key('full-screen-tip-tap'));
        await t.pump();
        expect(tip, findsNothing);
        await done(t);
      });

      testWidgets('fits from a small phone to a large monitor', (t) async {
        for (final (size, desktop, scale) in const [
          (Size(568, 320), false, 1.6),
          (Size(844, 390), false, 1.0),
          (Size(1920, 1080), true, 1.0),
        ]) {
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          await open(t, desktop: desktop, size: size);
          expect(tip, findsOneWidget, reason: '$size');
          expect(t.getSize(tip), size, reason: '$size');
          expect(t.takeException(), isNull, reason: '$size');
          await done(t);
        }
      });

      for (final (name, size, desktop) in const [
        ('phone', Size(844, 390), false),
        ('1920', Size(1920, 1080), true),
      ]) {
        testWidgets('looks right on $name', (t) async {
          await open(t, desktop: desktop, size: size);
          expect(t.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../goldens/host-full-screen-tip-$name.png'),
          );
          await t.tap(key('full-screen-tip-tap'));
          await t.pumpAndSettle();
          await done(t);
        });
      }
    });

    testWidgets('looks right with the tray on a phone', (t) async {
      await running(t, desktop: false, size: const Size(844, 390));
      unawaited(home(t).setHostFullScreen(true));
      await t.pumpAndSettle();
      await settleControl(t);
      await swipeUp(t, size: const Size(844, 390));
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/host-full-screen-tray-phone.png'),
      );
      await done(t);
    });

    testWidgets('looks right with the tray in a full HD window', (t) async {
      await running(t, size: const Size(1920, 1080));
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await swipeUp(t, size: const Size(1920, 1080));
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-host-full-screen-tray.png'),
      );
      await done(t);
    });

    testWidgets('looks right in a full HD window', (t) async {
      await running(t, size: const Size(1920, 1080));
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-host-full-screen.png'),
      );
      await done(t);
    });

    testWidgets('looks right with a confirmation showing', (t) async {
      final (c, _) = await running(t, size: const Size(1920, 1080));
      await c.screens.setShow('room', 'next');
      await press(t, LogicalKeyboardKey.f11);
      await settleControl(t);
      await press(t, LogicalKeyboardKey.space);
      expect(find.text('Pause Sermon?'), findsOneWidget);
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-host-full-screen-confirm.png'),
      );
      await press(t, LogicalKeyboardKey.escape);
      await done(t);
    });
  });
}

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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/live_helpers.dart';
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

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5),
  Segment('Sermon', 40),
  Segment('Response', 10),
], DisplaySettings());

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
    }) async {
      desktopWording = desktop;
      addTearDown(() => desktopWording = false);
      setScreen(t, size);
      final port = desktop ? DesktopPort() : FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((draft, _) => draft.themeId = 'graphite');
      if (start) {
        await c.act('load', value: sunday());
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
      // A click anywhere brings it back; that click changes nothing.
      await t.tapAt(const Offset(300, 500));
      await t.pumpAndSettle();
      expect(stage, findsOneWidget);
      expect(key('full-screen-exit'), findsOneWidget);
      expect(find.byTooltip('Exit full screen (Esc)'), findsOneWidget);
      // Small, in a corner, clear of the countdown.
      final control = t.getRect(key('full-screen-exit'));
      expect(control.height, lessThan(60));
      expect(control.right, greaterThan(1366 - 40));
      expect(control.top, lessThan(40));
      await settleControl(t);
      expect(key('full-screen-exit'), findsNothing);
      await t.tapAt(const Offset(300, 500));
      await t.pumpAndSettle();
      await t.tap(key('full-screen-exit'));
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect(key('live-menu'), findsOneWidget);
      expect(window.calls.length, 6);
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

    testWidgets('it leaves by itself when the service ends', (t) async {
      final (c, port) = await running(t);
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      await c.act('end');
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(home(t).hostFullScreen.showing, isFalse);
      expect((port as DesktopPort).window.calls, ['enter', 'leave']);
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
      expect(find.text('Next: Response'), findsNothing);
      await c.commit((draft, _) => draft.fullScreenLayout = 'current');
      await t.pumpAndSettle();
      expect(find.text('Sermon'), findsOneWidget);
      await c.commit((draft, _) => draft.fullScreenLayout = 'next');
      await t.pumpAndSettle();
      expect(find.text('Next: Response · 10 min'), findsOneWidget);
      expect(time(t), '12:38');
      // Kept on this device: in its saved state, never in a backup.
      expect(c.state.toJson()['fullScreenLayout'], 'next');
      expect(AppState.fromJson(c.state.toJson()).fullScreenLayout, 'next');
      expect(exportBackup(c.state, c.now), isNot(contains('fullScreenLayout')));
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
      // The phone's choice is not the one a computer uses.
      await c.commit((draft, _) => draft.fullScreenLayout = 'current');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await press(t, LogicalKeyboardKey.f11);
      expect(stage, findsOneWidget);
      expect(find.text('Welcome'), findsNothing);
      await c.secondScreen!.setLayout('next');
      await t.pumpAndSettle();
      expect(find.text('Next: Sermon · 40 min'), findsOneWidget);
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
      await t.tapAt(const Offset(200, 600));
      await t.pumpAndSettle();
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
      await t.ensureVisible(key('full-screen-layout-next'));
      await t.pumpAndSettle();
      expect(find.text('Full screen on this phone'), findsOneWidget);
      expect(
        find.text(
          'Only this phone. Paired stage screens keep their own choice.',
        ),
        findsOneWidget,
      );
      await t.tap(key('full-screen-layout-next'));
      await t.pumpAndSettle();
      expect(c.state.fullScreenLayout, 'next');
      expect(
        t.widget<ChoiceChip>(key('full-screen-layout-next')).selected,
        isTrue,
      );
      await done(t);
    });

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
      Future<void> open() async {
        await openLiveMenu(t, 'Full screen');
        expect(stage, findsOneWidget);
        expect(asked.last, landscape);
      }

      // Exit.
      await open();
      await settleControl(t);
      await t.tapAt(const Offset(200, 600));
      await t.pumpAndSettle();
      await t.tap(key('full-screen-exit'));
      await t.pumpAndSettle();
      expect(asked, [landscape, 'any']);

      // Back.
      await open();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(asked, [landscape, 'any', landscape, 'any']);

      // Closed with the app, from full screen.
      await open();
      await done(t);
      expect(asked, [landscape, 'any', landscape, 'any', landscape, 'any']);
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
      // The service ends: it leaves by itself.
      await c.act('end');
      await t.pumpAndSettle();
      expect(stage, findsNothing);
      expect(asked, [landscape, 'portraitUp landscapeLeft']);
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
        await c.commit((draft, _) => draft.fullScreenLayout = 'next');
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
        await t.tapAt(size.center(Offset.zero));
        await t.pumpAndSettle();
        final locked = t.getRect(key('full-screen-locked'));
        expect(window.intersect(locked), locked, reason: '$size');
        expect(t.takeException(), isNull, reason: 'locked at $size');
        await done(t);
      }
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
      await c.commit((draft, _) => draft.fullScreenLayout = 'next');
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

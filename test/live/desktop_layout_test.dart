import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class DesktopFakePort extends FakePort {
  @override
  bool get isDesktop => true;
  bool warningSound = false;
  @override
  Future<void> setWarningSound(bool on) async => warningSound = on;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': warningSound,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

/// A Sunday service part-way through its third segment, running late.
Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5, speaker: 'Deacon Ruth'),
  Segment('Praise & Worship', 20, speaker: 'Worship team'),
  Segment(
    'Sermon',
    40,
    speaker: 'Pastor Samuel',
    notes: 'Altar call follows. Band back on stage at 5:00 left.',
  ),
  Segment('Response', 10, speaker: 'Worship team'),
  Segment('Closing', 5),
], DisplaySettings());

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<(AppController, DesktopFakePort)> running(
    WidgetTester t, {
    Size size = const Size(1366, 768),
    String layout = 'three_panes',
    String theme = 'midnight_lime',
    DesktopFakePort? on,
    List<int> advanceAfter = const [340, 1330],
    int then = 1642,
  }) async {
    setScreen(t, size);
    final port = on ?? DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
      draft.themeId = theme;
    });
    await c.act('load', value: sunday());
    await c.act('start');
    var at = 0;
    for (final seconds in advanceAfter) {
      at += seconds;
      port.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    port.at = after(at + then);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  Future<void> openLayoutSettings(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Appearance'));
    await t.pumpAndSettle();
    await t.tap(find.text('Layout & accessibility'));
    await t.pumpAndSettle();
  }

  Future<void> press(WidgetTester t, Finder target) async {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  testWidgets('three panes at laptop size', (t) async {
    await running(t);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    // Everything an operator needs is in view without scrolling.
    for (final key in ['pause-resume', 'next-segment', 'end-service']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-three-panes.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('three panes at full HD in Paper & Ink', (t) async {
    await running(t, size: const Size(1920, 1080), theme: 'paper_ink');
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-three-panes-1080-paper.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control at laptop size', (t) async {
    await running(t, layout: 'mission_control');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    // The side rail stays; nothing an operator needs is off screen.
    expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
    for (final key in ['pause-resume', 'next-segment', 'end-service', 'undo']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('timeline-4')).hitTestable(),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-mission-control.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control at full HD', (t) async {
    await running(t, layout: 'mission_control', size: const Size(1920, 1080));
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-mission-control-1080.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The dial at laptop size', (t) async {
    await running(t, layout: 'dial', theme: 'royal_navy');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('service-dial')), findsOneWidget);
    // Three panes around it, with the header tabs.
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsOneWidget);
    for (final key in ['pause-resume', 'next-segment', 'end-service', 'undo']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    // End service is wholly in view, not cut off by the window.
    expect(
      t.getRect(find.byKey(const ValueKey('end-service'))).bottom,
      lessThanOrEqualTo(768),
    );
    expect(find.text('12:38'), findsOneWidget);
    expect(find.text('of 40:00 allocated'), findsOneWidget);
    // The private note keeps one line in a short window.
    expect(
      find.text(
        'Private note: Altar call follows. Band back on stage at 5:00 left.',
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-dial.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The dial at full HD', (t) async {
    await running(
      t,
      layout: 'dial',
      theme: 'royal_navy',
      size: const Size(1920, 1080),
    );
    expect(t.takeException(), isNull);
    expect(
      find.text('Altar call follows. Band back on stage at 5:00 left.'),
      findsOneWidget,
    );
    expect(
      t.getRect(find.byKey(const ValueKey('end-service'))).bottom,
      lessThanOrEqualTo(1080),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-dial-1080.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The dial follows the service: ready, warning, overtime', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: 'dial'),
    );
    await c.act('load', value: sunday());
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // Ready keeps the start controls; the dial waits for the service.
    expect(find.text('Start first segment'), findsOneWidget);
    expect(find.byKey(const ValueKey('service-dial')), findsNothing);
    await c.act('start');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-dial')), findsOneWidget);
    expect(find.byKey(const ValueKey('dial-ends')), findsOneWidget);
    expect(find.text('REMAINING'), findsOneWidget);
    // Six minutes into a five-minute Welcome.
    port.at = after(360);
    await c.tick();
    await t.pumpAndSettle();
    expect(find.text('OVERTIME'), findsOneWidget);
    expect(find.text('+01:00'), findsOneWidget);
    expect(find.text('Allocated time exceeded'), findsOneWidget);
    // Keys and confirmations are as everywhere else.
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('choosing The dial brings Royal Navy with it', (t) async {
    final (c, _) = await running(t);
    await openLayoutSettings(t);
    await press(t, find.byKey(const ValueKey('desktop-layout-dial')));
    expect(c.appearanceSelection.value.desktopLayout, 'dial');
    expect(c.themeSelection.value, 'royal_navy');
    await t.tap(find.text('Save appearance'));
    await t.pumpAndSettle();
    expect(c.state.appearance.desktopLayout, 'dial');
    expect(c.state.themeId, 'royal_navy');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Keys at laptop size', (t) async {
    await running(t, layout: 'keys', theme: 'graphite');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('keys-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsOneWidget);
    for (final key in ['pause-resume', 'next-segment', 'end-service', 'undo']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    expect(
      t.getRect(find.byKey(const ValueKey('key-legend'))).bottom,
      lessThanOrEqualTo(768),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-keys.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Keys at full HD', (t) async {
    await running(
      t,
      layout: 'keys',
      theme: 'graphite',
      size: const Size(1920, 1080),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-keys-1080.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the Keys rundown table has every figure in its column', (
    t,
  ) async {
    final (c, _) = await running(t, layout: 'keys');
    final table = find.byKey(const ValueKey('rundown-table'));
    List<String?> row(int i) => t
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey('rundown-$i')),
            matching: find.byType(Text),
          ),
        )
        .map((w) => w.data)
        .toList();
    expect(row(0), [
      '1',
      'Welcome',
      'Deacon Ruth',
      '05:00',
      isNotNull,
      '05:40',
      '+0:40',
      'Done',
    ]);
    expect(row(2).sublist(0, 4), ['3', 'Sermon', 'Pastor Samuel', '40:00']);
    expect(row(2)[5], '27:22 so far');
    expect(row(2).last, 'Running');
    expect(row(3).last, 'Next');
    expect(row(3)[4], startsWith('~'));
    expect(row(4).last, 'Upcoming');
    expect(
      find.descendant(of: table, matching: find.text('Private note · Sermon')),
      findsOneWidget,
    );
    final strip = find.byKey(const ValueKey('now-strip'));
    expect(
      find.descendant(of: strip, matching: find.text('12:38')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: strip, matching: find.text('2 min 50 s behind')),
      findsOneWidget,
    );
    await c.act('pause');
    await t.pumpAndSettle();
    expect(row(2).last, 'Paused');
    await t.tap(find.byKey(const ValueKey('rundown-0')));
    await t.pumpAndSettle();
    expect(find.text('Segment details'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Keys uses the panes before the start and is Compact', (t) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: 'keys'),
    );
    await c.act('load', value: sunday());
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('keys-live')), findsNothing);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(find.text('Start first segment'), findsOneWidget);
    expect(
      appLayout(
        t.element(find.byKey(const ValueKey('three-pane-live'))),
      ).density,
      'compact',
    );
    await c.act('start');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('keys-live')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('number keys send cues on a computer, in any layout', (t) async {
    for (final layout in ['keys', 'three_panes', 'classic']) {
      final (c, _) = await running(t, layout: layout);
      final cues = c.state.stageCues;
      // Each cue button shows its number.
      expect(find.text('1'), findsWidgets, reason: layout);
      await t.sendKeyEvent(LogicalKeyboardKey.digit2);
      await t.pumpAndSettle();
      expect(c.state.session.alert?.text, cues[1].text, reason: layout);
      expect(c.state.session.outputMode(c.now), 'Cue', reason: layout);
      // Another number replaces it; the same number goes back to the timer.
      await t.sendKeyEvent(LogicalKeyboardKey.numpad1);
      await t.pumpAndSettle();
      expect(c.state.session.alert?.text, cues[0].text, reason: layout);
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown', reason: layout);
      // A number with no cue behind it does nothing.
      await t.sendKeyEvent(LogicalKeyboardKey.digit9);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown', reason: layout);
      // Nor does any number while the controls are locked.
      await t.tap(find.byKey(const ValueKey('control-lock')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown', reason: layout);
      expect(t.takeException(), isNull, reason: layout);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('number keys are left alone on a tablet and while typing', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    desktopWording = false;
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pumpAndSettle();
    expect(c.state.session.outputMode(c.now), 'Countdown');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tall Mission control window adds screens and activity', (
    t,
  ) async {
    await running(t, layout: 'mission_control', size: const Size(1920, 1080));
    final screens = find.byKey(const ValueKey('screens-section'));
    expect(
      find.descendant(of: screens, matching: find.text('Showing on Simulator')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: screens,
        matching: find.text('No stage screens have joined.'),
      ),
      findsOneWidget,
    );
    final activity = find.byKey(const ValueKey('activity-section'));
    // Newest first.
    final started = t
        .widgetList<Text>(
          find.descendant(
            of: activity,
            matching: find.textContaining(' started'),
          ),
        )
        .map((w) => w.data)
        .toList();
    expect(started, [
      'Sermon started',
      'Praise & Worship started',
      'Welcome started',
    ]);
    await t.tap(find.descendant(of: screens, matching: find.text('Manage')));
    await t.pumpAndSettle();
    expect(find.text('Screens & devices'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a laptop Mission control window keeps to what fits', (t) async {
    await running(t, layout: 'mission_control');
    expect(find.byKey(const ValueKey('screens-section')), findsNothing);
    expect(find.byKey(const ValueKey('activity-section')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control shows the service against plan', (t) async {
    final (c, port) = await running(t, layout: 'mission_control');
    final status = find.byKey(const ValueKey('mission-status'));
    Finder inStatus(String text) =>
        find.descendant(of: status, matching: find.text(text));
    expect(inStatus('2 min 50 s behind'), findsOneWidget);
    expect(inStatus('55 min 12 s'), findsOneWidget);
    expect(inStatus('Now ending'), findsOneWidget);
    // Finished segments show what they took and how far over they ran.
    final welcome = find.byKey(const ValueKey('timeline-0'));
    expect(
      find.descendant(of: welcome, matching: find.text('05:40 · +0:40')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-2')),
        matching: find.text('12:38 left of 40:00'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('timeline-now')), findsOneWidget);
    await t.tap(welcome);
    await t.pumpAndSettle();
    expect(find.text('Segment details'), findsOneWidget);
    expect(find.text('Recorded duration: 5 min 40 s'), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await c.act('pause');
    port.at = after(port.at.mono ~/ 1000 + 60);
    await c.tick();
    await t.pumpAndSettle();
    expect(inStatus('Ending, if resumed now'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control keeps confirmations, the lock and the keys', (
    t,
  ) async {
    final (c, _) = await running(t, layout: 'mission_control');
    expect(find.byKey(const ValueKey('key-legend')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.active, isTrue);
    // Page Down is Next segment, pressed twice; it never scrolls a pane.
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(c.state.session.index, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.session.index, 3);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('controls-locked-banner')),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.tap(find.byKey(const ValueKey('end-service')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.text('End Sunday Service?'), findsNothing);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'off'),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-legend')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control before the start and in overtime', (t) async {
    setScreen(t, const Size(1366, 768));
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'mission_control',
      ),
    );
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // Standing by keeps its centred column.
    expect(find.byKey(const ValueKey('mission-control-live')), findsNothing);
    await c.act('load', value: sunday());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.text('Start first segment'), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-status')), findsNothing);
    expect(find.text('5 segments · 1 h 20 min planned'), findsOneWidget);
    await c.act('start');
    // Six minutes into a five-minute Welcome.
    port.at = after(360);
    await c.tick();
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-0')),
        matching: find.text('+01:00 over of 05:00'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the rundown shows how the service is running against plan', (
    t,
  ) async {
    await running(t);
    final pane = find.byKey(const ValueKey('rundown-pane'));
    Finder inPane(String text) =>
        find.descendant(of: pane, matching: find.text(text));
    // Welcome ran 40 s over and Praise & Worship 2 min 10 s over.
    expect(inPane('2 min 50 s behind'), findsOneWidget);
    expect(inPane('05:40'), findsOneWidget);
    expect(inPane('+0:40'), findsOneWidget);
    expect(inPane('+2:10'), findsOneWidget);
    expect(inPane('12:38 left'), findsOneWidget);
    expect(inPane('of 40:00'), findsOneWidget);
    expect(inPane('10 min'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('rundown-0')));
    await t.pumpAndSettle();
    expect(find.text('Segment details'), findsOneWidget);
    expect(find.text('Recorded duration: 5 min 40 s'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a paused service says so beside its finish time', (t) async {
    final (c, _) = await running(t, size: const Size(1200, 700));
    await c.act('pause');
    await t.pumpAndSettle();
    expect(find.textContaining('if resumed now'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the private note is in view, not folded away', (t) async {
    await running(t);
    expect(
      find.text('Altar call follows. Band back on stage at 5:00 left.'),
      findsOneWidget,
    );
    expect(find.text('View operator notes'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('End service still asks first', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    expect(c.state.session.active, isTrue);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Lock controls blocks the panes until Hold to unlock', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('controls-locked-banner')),
      findsOneWidget,
    );
    await t.tap(
      find.byKey(const ValueKey('pause-resume')),
      warnIfMissed: false,
    );
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.text('Confirm pause'), findsNothing);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('unlock-controls')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('controls-locked-banner')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the header tabs move between pages', (t) async {
    await running(t);
    final home = t.state<HomeState>(find.byType(Home));
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    expect(home.page, 1);
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    await t.tap(find.byKey(const ValueKey('desktop-tab-0')));
    await t.pumpAndSettle();
    expect(home.page, 0);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('standing by offers a program, then Ready shows the panes', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('desktop-tabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    expect(find.byKey(const ValueKey('standing-by-desktop')), findsOneWidget);
    expect(find.text('Start service'), findsOneWidget);
    await c.act('load', value: sunday());
    await t.pumpAndSettle();
    // Ready: the panes appear, with the start controls in the middle.
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(find.text('Start first segment'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a narrow or short window uses the phone and tablet layout', (
    t,
  ) async {
    for (final size in const [Size(1100, 800), Size(1366, 560)]) {
      await running(t, size: size);
      expect(
        find.byKey(const ValueKey('three-pane-live')),
        findsNothing,
        reason: '$size',
      );
      expect(find.byKey(const ValueKey('desktop-tabs')), findsNothing);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the focused operator view leaves the panes', (t) async {
    await running(t);
    t.state<HomeState>(find.byType(Home)).setFocused(true);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    expect(find.text('Exit focused view'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('key labels show on a computer and can be turned off', (t) async {
    final (c, _) = await running(t);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('PgDn'), findsOneWidget);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'off'),
    );
    await t.pumpAndSettle();
    expect(find.text('Space'), findsNothing);
    expect(find.text('PgDn'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tablet shows no key labels unless they are turned on', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    desktopWording = false;
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(find.text('Space'), findsNothing);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'on'),
    );
    await t.pumpAndSettle();
    expect(find.text('Space'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('choosing a layout previews it and Save keeps it', (t) async {
    final (c, _) = await running(t, theme: 'graphite');
    await openLayoutSettings(t);
    expect(
      find.byKey(const ValueKey('desktop-layout-section')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-layout-settings.png'),
    );
    // Classic keeps the theme in use.
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    expect(c.appearanceSelection.value.desktopLayout, 'classic');
    expect(c.themeSelection.value, 'graphite');
    expect(c.state.appearance.desktopLayout, 'three_panes');
    // Three panes arrives with Midnight Lime.
    await press(t, find.byKey(const ValueKey('desktop-layout-three_panes')));
    expect(c.themeSelection.value, 'midnight_lime');
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    await t.tap(find.text('Save appearance'));
    await t.pumpAndSettle();
    expect(c.state.appearance.desktopLayout, 'classic');
    expect(c.state.themeId, 'midnight_lime');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Desktop layout has its own row in Settings and in search', (
    t,
  ) async {
    final (c, _) = await running(
      t,
      layout: 'mission_control',
      size: const Size(1920, 1080),
    );
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    // The row names the layout in use and opens straight on its tab.
    expect(find.text('Mission control · for a wide window'), findsOneWidget);
    await press(t, find.text('Desktop layout'));
    expect(
      find.byKey(const ValueKey('desktop-layout-section')),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    // Appearance still opens on Theme, with a pointer to the other tab.
    await press(t, find.text('Appearance'));
    expect(find.byKey(const ValueKey('desktop-layout-section')), findsNothing);
    await press(t, find.byKey(const ValueKey('to-desktop-layout')));
    expect(
      find.byKey(const ValueKey('desktop-layout-section')),
      findsOneWidget,
    );
    expect(c.state.appearance.desktopLayout, 'mission_control');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Cancel leaves the layout and theme as they were', (t) async {
    final (c, _) = await running(t, theme: 'graphite');
    await openLayoutSettings(t);
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    await press(t, find.byKey(const ValueKey('desktop-layout-three_panes')));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.appearance.desktopLayout, 'three_panes');
    expect(c.state.themeId, 'graphite');
    expect(c.themeSelection.value, 'graphite');
    expect(c.appearanceSelection.value.desktopLayout, 'three_panes');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a look can be saved, used again, replaced and deleted', (
    t,
  ) async {
    final (c, _) = await running(t, theme: 'royal_navy');
    await openLayoutSettings(t);
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    await press(t, find.byKey(const ValueKey('save-look')));
    // A name is needed.
    await t.tap(find.byKey(const ValueKey('look-name-save')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('look-name')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('look-name')), 'Midweek');
    await t.tap(find.byKey(const ValueKey('look-name-save')));
    await t.pumpAndSettle();
    // Kept at once, whatever happens to the rest of the page.
    expect(c.state.savedLooks.single.name, 'Midweek');
    expect(c.state.savedLooks.single.layout, 'classic');
    expect(c.state.savedLooks.single.themeId, 'royal_navy');
    expect(c.state.appearance.desktopLayout, 'three_panes');

    // Back to the default, then the saved look brings both back.
    await press(t, find.byKey(const ValueKey('reset-look')));
    expect(c.appearanceSelection.value.desktopLayout, 'three_panes');
    expect(c.themeSelection.value, 'midnight_lime');
    await press(t, find.byKey(const ValueKey('saved-look-Midweek')));
    expect(c.appearanceSelection.value.desktopLayout, 'classic');
    expect(c.themeSelection.value, 'royal_navy');

    // Saving under the same name replaces it.
    await press(t, find.byKey(const ValueKey('reset-look')));
    await press(t, find.byKey(const ValueKey('save-look')));
    await t.enterText(find.byKey(const ValueKey('look-name')), 'midweek');
    await t.pump();
    expect(
      find.text('This replaces the saved look with the same name.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('look-name-save')));
    await t.pumpAndSettle();
    expect(c.state.savedLooks.single.name, 'midweek');
    expect(c.state.savedLooks.single.layout, 'three_panes');

    await press(t, find.byTooltip('Delete midweek'));
    await t.tap(find.text('Delete look'));
    await t.pumpAndSettle();
    expect(c.state.savedLooks, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Reset returns to Three panes with Midnight Lime', (t) async {
    final (c, _) = await running(t, layout: 'classic', theme: 'paper_ink');
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        density: 'compact',
        highContrast: true,
        keyHints: 'off',
        dividers: 'strong',
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('Appearance'));
    await t.pumpAndSettle();
    await t.tap(find.text('Layout & accessibility'));
    await t.pumpAndSettle();
    await press(t, find.byKey(const ValueKey('reset-look')));
    await t.tap(find.text('Save appearance'));
    await t.pumpAndSettle();
    expect(c.state.themeId, 'midnight_lime');
    expect(c.state.appearance.desktopLayout, 'three_panes');
    expect(c.state.appearance.density, 'automatic');
    expect(c.state.appearance.highContrast, isFalse);
    expect(c.state.appearance.keyHints, 'automatic');
    // What a look does not cover is left alone.
    expect(c.state.appearance.dividers, 'strong');
    await t.pumpWidget(const SizedBox());
  });
}

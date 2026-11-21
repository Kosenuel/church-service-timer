import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/clock_text.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The choice of no end screen, which shows the clock when the service ends.
void main() {
  setUpAll(loadAppFonts);

  Finder key(String name) => find.byKey(ValueKey(name));

  Timeline sunday({bool noEnd = false}) => Timeline('Sunday Service', const [
    Segment('Welcome', 5),
    Segment('Sermon', 40),
  ], noEnd ? DisplaySettings(end: null) : DisplaySettings());

  Future<void> golden(WidgetTester t, String name) async {
    expect(t.takeException(), isNull, reason: name);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/$name.png'),
    );
  }

  Future<AppController> app(
    WidgetTester t, {
    Size size = const Size(430, 1000),
    bool desktop = false,
  }) async {
    desktopWording = desktop;
    addTearDown(() => desktopWording = false);
    setScreen(t, size);
    final c = AppController(desktop ? DesktopFakePort() : FakePort());
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      if (desktop) {
        draft.appearance = draft.appearance.copyWith(
          desktopLayout: 'three_panes',
        );
      }
      draft.templates.clear();
      draft.saveTemplate(sunday());
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> openEditor(WidgetTester t, {required bool desktop}) async {
    if (desktop) {
      await t.tap(key('desktop-tab-1'));
    } else {
      await t.tap(find.text('Programs').last);
    }
    await t.pumpAndSettle();
    await t.tap(key('template-row:Sunday Service'));
    await t.pumpAndSettle();
    await t.tap(key('edit-program'));
    await t.pumpAndSettle();
  }

  Future<void> choose(WidgetTester t, String label) async {
    final choice = find.descendant(
      of: key('end-screen-choice'),
      matching: find.text(label),
    );
    await t.ensureVisible(choice);
    await t.pumpAndSettle();
    await t.tap(choice);
    await t.pumpAndSettle();
  }

  Future<void> save(WidgetTester t) async {
    await t.tap(find.text('Save changes').last);
    await t.pumpAndSettle();
  }

  for (final desktop in [false, true]) {
    final name = desktop
        ? 'desktop-no-end-screen-editor-1366'
        : 'no-end-screen-editor-phone';
    testWidgets('the program editor offers no end screen, '
        '${desktop ? 'in a 1366 × 768 window' : 'on a phone'}', (t) async {
      final c = await app(
        t,
        desktop: desktop,
        size: desktop ? const Size(1366, 768) : const Size(430, 1000),
      );
      await openEditor(t, desktop: desktop);
      expect(key('end-screen-choice'), findsOneWidget);
      expect(find.text('When the service ends'), findsOneWidget);
      expect(find.text('End screen · Hallelujah'), findsOneWidget);
      expect(key('no-end-screen'), findsNothing);

      await choose(t, 'Clock');
      expect(find.text('End screen · Hallelujah'), findsNothing);
      expect(key('no-end-screen'), findsOneWidget);
      expect(
        find.textContaining('the sign and stage screens show the clock'),
        findsOneWidget,
      );
      // Not the default, which has an end screen.
      expect(find.text('Use current default'), findsOneWidget);
      await t.ensureVisible(key('end-screen-choice'));
      await t.pumpAndSettle();
      await golden(t, name);
      await save(t);
      expect(c.state.templates.single.display.end, isNull);
      expect(find.text('No end screen'), findsWidgets);
      expect(find.text('Shows the clock when the service ends'), findsWidgets);

      // Choosing End screen again brings the text back.
      await t.tap(key('edit-program'));
      await t.pumpAndSettle();
      expect(key('no-end-screen'), findsOneWidget);
      await choose(t, 'End screen');
      expect(find.text('End screen · Hallelujah'), findsOneWidget);
      expect(find.text('Use current default'), findsNothing);
      await save(t);
      expect(c.state.templates.single.display.end!.text, 'Hallelujah');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Settings can make new programs have no end screen', (t) async {
    final c = await app(t);
    await c.commit((draft, _) => draft.defaults = draft.defaults.withEnd(null));
    await t.pumpAndSettle();
    expect(c.state.defaults.end, isNull);
    // A new program starts with no end screen.
    await t.tap(find.text('Programs').last);
    await t.pumpAndSettle();
    await t.tap(key('new-template'));
    await t.pumpAndSettle();
    expect(key('no-end-screen'), findsOneWidget);
    expect(find.text('Use current default'), findsNothing);
    await choose(t, 'End screen');
    expect(find.text('End screen · Hallelujah'), findsOneWidget);
    expect(find.text('Use current default'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('ending a service with no end screen shows the clock on the '
      'stage simulator, and End service says so', (t) async {
    setScreen(t, const Size(430, 1000));
    late AppController c;
    await t.runAsync(() async {
      c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.setSimulatorKind('stage');
      await c.act('load', value: sunday(noEnd: true));
      await c.act('start');
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    final end = key('end-service');
    await t.ensureVisible(end);
    await t.pumpAndSettle();
    await t.tap(end);
    await t.pumpAndSettle();
    expect(
      find.text(
        'Finish this service, save its report, clear the active cue and '
        'show the clock. This service has no end screen.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Hallelujah'), findsNothing);
    await t.tap(find.text('End service').last);
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ended');
    expect(c.state.session.outputMode(c.now), 'Clock');
    // Live shows the simulator below what it offers after the service.
    setScreen(t, const Size(430, 3000));
    await t.pumpAndSettle();
    final home = t.state<HomeState>(find.byType(Home));
    expect(home.liveShowingText(), 'Showing the clock');
    final snapshot = c.stageSimulatorSnapshot();
    expect(snapshot['outputMode'], 'Clock');
    expect(snapshot['displayText'], stageClockText(c.now.wall, '24h'));
    // Stage & display is closed after End service; it says what shows.
    expect(find.textContaining('Simulator · clock ·'), findsOneWidget);
    await t.tap(find.text('Stage & display'));
    await t.pumpAndSettle();
    final preview = key('stage-simulator-preview');
    expect(preview, findsOneWidget);
    expect(
      find.descendant(of: preview, matching: find.byType(ClockText)),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}

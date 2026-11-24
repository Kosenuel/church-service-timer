import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'desktop_layout_test.dart' show DesktopFakePort, sunday;

/// Pages other than a running service, in a large window: they use the
/// room instead of sitting in a narrow column.
void main() {
  setUpAll(loadAppFonts);
  // Paper & Ink and the Finish tiles draw the finish photographs.
  setUpAll(FinishTextures.instance.loadAll);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<(AppController, DesktopFakePort)> standingBy(
    WidgetTester t, {
    Size size = const Size(1920, 1080),
    String layout = 'three_panes',
    String theme = 'midnight_lime',
  }) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
      draft.themeId = theme;
      draft.templates.clear();
      draft.saveTemplate(sunday());
      draft.saveTemplate(
        Timeline('Midweek Prayer', const [
          Segment('Welcome', 5),
          Segment('Prayer', 30),
          Segment('Word', 20),
          Segment('Closing', 5),
        ], DisplaySettings()),
      );
      draft.saveTemplate(
        Timeline('Youth Night', const [
          Segment('Games', 15),
          Segment('Worship', 20),
          Segment('Talk', 25),
          Segment('Small groups', 30),
        ], DisplaySettings()),
      );
    });
    // One finished service, so Last service has something to show.
    await c.act(
      'load',
      value: c.state.templates.firstWhere((p) => p.name == 'Sunday Service'),
    );
    await c.act('start');
    var at = 0;
    for (final seconds in const [340, 1330, 2300, 560]) {
      at += seconds;
      port.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    port.at = after(at + 280);
    await c.tick();
    await c.act('end');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  testWidgets('standing by fills a full-HD window', (t) async {
    final (c, _) = await standingBy(t);
    expect(find.byKey(const ValueKey('standing-by-desktop')), findsOneWidget);
    expect(find.byKey(const ValueKey('standing-by-clock')), findsOneWidget);
    // Stage and cues are open on the right, not folded away.
    expect(
      find.byKey(const ValueKey('standing-by-stage-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stage-and-display-false-true')),
      findsNothing,
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-standing-by-1080.png'),
    );
    // A click on a program shows its order of service; the one filled
    // button loads it into Ready.
    expect(find.text('Small groups'), findsNothing);
    await t.tap(find.byKey(const ValueKey('standing-by-program:Youth Night')));
    await t.pumpAndSettle();
    expect(find.text('Small groups'), findsOneWidget);
    expect(c.liveSession.phase, isNot('ready'));
    await t.tap(find.byKey(const ValueKey('standing-by-load')));
    await t.pumpAndSettle();
    expect(c.liveSession.phase, 'ready');
    expect(c.liveSession.timeline!.name, 'Youth Night');
    expect(t.takeException(), isNull);
  });

  testWidgets('Print on the order of service prints the chosen program', (
    t,
  ) async {
    await standingBy(t);
    await t.tap(find.byKey(const ValueKey('standing-by-program:Youth Night')));
    await t.pumpAndSettle();
    final print = find.byKey(const ValueKey('standing-by-print'));
    expect(t.widget<IconButton>(print).tooltip, 'Print order of service');
    await t.tap(print);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('print-sheet')), findsOneWidget);
    expect(find.text('Print order of service'), findsOneWidget);
    // The sheet is for the program shown, and nothing was loaded for it.
    expect(find.textContaining('Youth Night'), findsWidgets);
    // Locked controls leave nothing to press.
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    t.state<HomeState>(find.byType(Home)).lockControls();
    await t.pumpAndSettle();
    expect(t.widget<IconButton>(print).onPressed, isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('standing by at 1440p and at the smallest desktop size', (
    t,
  ) async {
    await standingBy(
      t,
      size: const Size(2560, 1440),
      layout: 'mission_control',
      theme: 'graphite',
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-standing-by-1440.png'),
    );
    await standingBy(t, size: const Size(1200, 600));
    expect(find.byKey(const ValueKey('standing-by-desktop')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Appearance keeps its preview beside the settings', (t) async {
    await standingBy(t);
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Appearance'));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('appearance-preview-pane')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-appearance-theme.png'),
    );
    await t.tap(find.text('Layout & accessibility'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-appearance-layout.png'),
    );
    // Save is an ordinary button, not one the width of the window.
    expect(
      t.getSize(find.widgetWithText(FilledButton, 'Save appearance')).width,
      lessThan(400),
    );
  });

  testWidgets('Settings uses three columns in a full HD window', (t) async {
    await standingBy(t);
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-three-columns')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(TimerApp),
      matchesGoldenFile('../goldens/desktop-settings.png'),
    );
  });
}

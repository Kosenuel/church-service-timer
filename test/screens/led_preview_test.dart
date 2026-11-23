import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lyrics/lyrics_page_test.dart' show DesktopPort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The LED sign's own preview: a strip on Live above the stage picture
/// when a sign is the display, and a card in the Screens panel.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  /// A sign set up as the display, in the state given. Nothing is sent to
  /// a real sign: the test sets the connection the sign would report.
  Future<AppController> withSign(
    WidgetTester t,
    Size size, {
    bool desktop = true,
    String layout = 'three_panes',
    bool connected = true,
    bool sign = true,
  }) async {
    setScreen(t, size);
    desktopWording = desktop;
    late AppController c;
    await t.runAsync(() async {
      c = AppController(desktop ? DesktopPort() : FakePort());
      await c.initialize(startTicker: false);
      await c.commit((draft, _) {
        draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
        if (sign) draft.outputDestination = 'led';
      });
      await c.act(
        'load',
        value: Timeline('Sunday', const [
          Segment('Welcome', 5),
          Segment('Sermon', 30),
        ], DisplaySettings()),
      );
      await c.act('start');
    });
    if (sign) {
      c.hardware
        ..enabled = true
        ..connected = connected
        ..held = false
        ..rememberedName = 'Hall sign';
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  for (final layout in builtDesktopLayouts) {
    testWidgets('Live, $layout at 1366 × 768: the sign beside the stage', (
      t,
    ) async {
      await withSign(t, const Size(1366, 768), layout: layout);
      expect(t.takeException(), isNull, reason: layout);
      expect(find.byKey(const ValueKey('led-sign-strip')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stage-simulator-preview')),
        findsOneWidget,
      );
      // The controls are still in view.
      for (final key in ['pause-resume']) {
        final f = find.byKey(ValueKey(key));
        if (f.evaluate().isEmpty) continue;
        expect(
          t.getRect(f).bottom,
          lessThanOrEqualTo(768),
          reason: '$key in $layout',
        );
      }
      if (layout == 'three_panes') {
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/screens-live-led-1366.png'),
        );
      }
    });
  }

  testWidgets('Live on a phone: a thin strip above the stage preview', (
    t,
  ) async {
    await withSign(t, const Size(360, 2600), desktop: false);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('led-sign-strip')), findsOneWidget);
    final strip = t.getRect(find.byKey(const ValueKey('led-sign-strip')));
    final stage = t.getRect(
      find.byKey(const ValueKey('stage-simulator-preview')),
    );
    expect(strip.bottom, lessThan(stage.top));
    expect(strip.height, lessThan(80));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/screens-live-led-phone.png'),
    );
  });

  testWidgets('no sign, no LED strip: churches without one lose no space', (
    t,
  ) async {
    final c = await withSign(t, const Size(1366, 768), sign: false);
    expect(find.byKey(const ValueKey('led-sign-strip')), findsNothing);
    await t.runAsync(() => c.setSimulatorKind('stage'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('led-sign-strip')), findsNothing);
  });

  testWidgets('the strip draws what the app sent the sign', (t) async {
    final c = await withSign(t, const Size(1366, 768));
    final matrix = t.widget<LedMatrix>(
      find.descendant(
        of: find.byKey(const ValueKey('led-sign-strip')),
        matching: find.byType(LedMatrix),
      ),
    );
    expect(matrix.pixels, c.hardware.preview(c.now));
    expect(matrix.hardware, isTrue);
  });

  testWidgets('a lost sign says so and is dimmed', (t) async {
    await withSign(t, const Size(1366, 768), connected: false);
    expect(find.textContaining('Not found'), findsWidgets);
    final matrix = t.widget<LedMatrix>(
      find.descendant(
        of: find.byKey(const ValueKey('led-sign-strip')),
        matching: find.byType(LedMatrix),
      ),
    );
    expect(matrix.stale, isTrue);
  });

  Future<void> panel(WidgetTester t, AppController c) async {
    final home = t.state<HomeState>(find.byType(Home));
    await openScreensPanelFor(home, c);
    await t.pumpAndSettle();
  }

  for (final connected in [true, false]) {
    testWidgets(
      'the Screens panel has a card for the sign, ${connected ? 'connected' : 'not found'}',
      (t) async {
        final c = await withSign(
          t,
          const Size(1920, 1300),
          connected: connected,
        );
        await panel(t, c);
        final card = find.byKey(const ValueKey('led-sign-card'));
        expect(card, findsOneWidget);
        expect(
          find.text('Shows the countdown and cues. Never slides.'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(connected ? 'Connected' : 'Not found'),
          ),
          findsOneWidget,
        );
        // It has no tiles and cannot be put in a group.
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('Timer only'),
          ),
          findsNothing,
        );
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(ScreensPage),
          matchesGoldenFile(
            '../goldens/screens-led-card-${connected ? 'connected' : 'lost'}.png',
          ),
        );
      },
    );
  }

  testWidgets('no sign and the stage simulator: no card', (t) async {
    late AppController c;
    setScreen(t, const Size(1366, 900));
    await t.runAsync(() async {
      c = AppController(DesktopPort());
      await c.initialize(startTicker: false);
      await c.setSimulatorKind('stage');
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await panel(t, c);
    expect(find.byKey(const ValueKey('led-sign-card')), findsNothing);
  });
}

Future<void> openScreensPanelFor(HomeState home, AppController c) async {
  // Not awaited: the panel stays open until popped.
  openScreensPanel(home.context, c);
}

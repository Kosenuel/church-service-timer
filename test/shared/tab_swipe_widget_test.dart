import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<AppController> open(
    WidgetTester t, {
    Size size = const Size(420, 900),
  }) async {
    setScreen(t, size);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  HomeState home(WidgetTester t) => t.state<HomeState>(find.byType(Home));

  Future<void> swipe(WidgetTester t, double dx, {double fromX = 210}) async {
    await t.flingFrom(Offset(fromX, 400), Offset(dx, 0), 1500);
    await t.pumpAndSettle();
  }

  Future<void> left(WidgetTester t) => swipe(t, -300);
  Future<void> right(WidgetTester t) => swipe(t, 300, fromX: 110);

  testWidgets(
    'Swiping moves between Live, Programs, Slides and Reports in order',
    (t) async {
      await open(t);
      expect(home(t).page, 0);
      await right(t);
      expect(home(t).page, 0, reason: 'nothing before Live');
      await left(t);
      expect(home(t).page, 1);
      expect(find.byKey(const ValueKey('new-template')), findsOneWidget);
      // Slides comes after Programs, as the bar shows it, then Reports.
      await left(t);
      expect(home(t).page, lyricsPage);
      await left(t);
      expect(home(t).page, 2);
      await right(t);
      expect(home(t).page, lyricsPage);
      await right(t);
      expect(home(t).page, 1);
      await right(t);
      expect(home(t).page, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A swipe from the screen edge is left to Android Back', (
    t,
  ) async {
    await open(t);
    await swipe(t, -300, fromX: 410);
    expect(home(t).page, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A loaded service keeps Live in place until it is over', (
    t,
  ) async {
    final c = await open(t);
    await c.act('load', value: c.state.templates.first);
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    await left(t);
    expect(home(t).page, 0, reason: 'no swiping away from a loaded service');
    // The bar still leaves Live, and a swipe comes back to it.
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    expect(home(t).page, 1);
    await right(t);
    expect(home(t).page, 0);
    await c.act('start');
    await t.pumpAndSettle();
    await left(t);
    expect(home(t).page, 0, reason: 'no swiping away from a running service');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Selection mode stops swiping', (t) async {
    await open(t);
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    home(t).refreshHome(() => home(t).programsPage.selecting = true);
    await t.pumpAndSettle();
    await left(t);
    expect(home(t).page, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Each tab keeps its own scroll position', (t) async {
    // Short enough for Programs to scroll.
    await open(t, size: const Size(420, 560));
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    final scroll = home(t).homeScroll;
    scroll.jumpTo(240);
    await t.pumpAndSettle();
    await left(t);
    expect(home(t).page, lyricsPage);
    expect(scroll.offset, 0, reason: 'Slides opens at its own position');
    await right(t);
    expect(home(t).page, 1);
    expect(scroll.offset, 240);
    await t.pumpWidget(const SizedBox());
  });
}

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/command_palette.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/screens/screens_entry.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'screens_panel_test.dart' show PcPort, PhonePort, service;

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => desktopWording = false);

  Future<AppController> start(
    WidgetTester t,
    FakePort port,
    Size size, {
    String? layout,
    double text = 1,
    String? theme,
  }) async {
    setScreen(t, size);
    t.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    desktopWording = port.isDesktop;
    late AppController c;
    await t.runAsync(() async => c = await service(port, layout: layout));
    if (theme != null) {
      await t.runAsync(() => c.commit((d, at) => d.themeId = theme));
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    t.takeException();
    return c;
  }

  HomeState home(WidgetTester t) =>
      t.state<HomeState>(find.byType(Home, skipOffstage: false));

  Finder railLabel(String name) => find.descendant(
    of: find.byKey(const ValueKey('navigation-rail')),
    matching: find.text(name),
  );

  group('the board fills the width', () {
    for (final size in const [
      Size(1280, 800),
      Size(1366, 768),
      Size(1920, 1080),
    ]) {
      testWidgets('at $size', (t) async {
        await start(t, PcPort(), size);
        await t.tap(railLabel('Screens'));
        await t.pumpAndSettle();
        final board = t.getRect(find.byKey(const ValueKey('screens-board')));
        // Every card of the board (the groups, the LED sign when there is
        // one, New group), grouped into rows by their top edge.
        final keys = [
          for (final g in home(t).c.screens.setup.groups) 'group-${g.id}',
          'led-sign-card',
          'new-group',
        ];
        final rows = <double, List<Rect>>{};
        for (final k in keys) {
          final f = find.byKey(ValueKey(k));
          if (f.evaluate().isEmpty) continue;
          final r = t.getRect(f);
          rows.putIfAbsent(r.top.roundToDouble(), () => []).add(r);
        }
        expect(rows.length, greaterThan(0));
        for (final row in rows.values) {
          row.sort((a, b) => a.left.compareTo(b.left));
          final unique = row;
          expect(unique.first.left, closeTo(board.left, 1));
          expect(
            unique.last.right,
            closeTo(board.right, 1),
            reason: 'a row leaves nothing unused on the right',
          );
          for (final r in unique) {
            expect(r.width, closeTo(unique.first.width, 1));
            expect(r.width, greaterThanOrEqualTo(300));
          }
        }
        // The board itself reaches the page's edge, within its padding.
        final page = t.getRect(find.byKey(const ValueKey('screens-page')));
        expect(page.right - board.right, lessThan(24 + 32 + 2));
        expect(
          t.getRect(find.byKey(const ValueKey('screens-list'))).width,
          closeTo(board.width, 1),
        );
        expect(
          t.getRect(find.byKey(const ValueKey('screens-scenes'))).width,
          closeTo(board.width, 1),
        );
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a wide window has more columns than a narrow one', (t) async {
      await start(t, PcPort(), const Size(1366, 768));
      await t.tap(railLabel('Screens'));
      await t.pumpAndSettle();
      double column(String key) => t.getRect(find.byKey(ValueKey(key))).width;
      final narrow = column('group-stage');
      setScreen(t, const Size(1920, 1080));
      await t.pumpAndSettle();
      // At 1920 the same groups sit in columns no wider than 600.
      expect(column('group-stage'), lessThan(600));
      expect(narrow, lessThan(600));
    });

    testWidgets('a phone keeps one column', (t) async {
      await start(t, PhonePort(), const Size(360, 780));
      final button = find.byKey(const ValueKey('live-screens-button'));
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pumpAndSettle();
      final stage = t.getRect(find.byKey(const ValueKey('group-stage')));
      final room = t.getRect(find.byKey(const ValueKey('group-room')));
      expect(stage.left, room.left);
      expect(stage.width, room.width);
      expect(stage.top == room.top, isFalse);
    });
  });

  group('Screens is a destination', () {
    testWidgets('on the rail, after Slides and before Programs, selected on its page', (t) async {
      await start(t, PcPort(), const Size(1366, 768));
      expect(
        [for (final p in homePageOrder) p.name],
        ['Live', 'Slides', 'Screens', 'Programs', 'Reports', 'Settings'],
      );
      final rail = t.widget<NavigationRail>(
        find.byKey(const ValueKey('navigation-rail')),
      );
      expect(rail.destinations.length, 6);
      await t.tap(railLabel('Screens'));
      await t.pumpAndSettle();
      expect(home(t).page, screensPage);
      expect(find.byType(ScreensPage), findsOneWidget);
      expect(
        t
            .widget<NavigationRail>(
              find.byKey(const ValueKey('navigation-rail')),
            )
            .selectedIndex,
        2,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('on the top tabs of a desktop layout', (t) async {
      await start(t, PcPort(), const Size(1920, 1080), layout: 'three_panes');
      final tab = find.byKey(ValueKey('desktop-tab-$screensPage'));
      expect(tab, findsOneWidget);
      await t.tap(tab);
      await t.pumpAndSettle();
      expect(home(t).page, screensPage);
      expect(find.byType(ScreensPage), findsOneWidget);
      expect(find.byKey(const ValueKey('navigation-rail')), findsNothing);
    });

    testWidgets('not on a phone bar, which keeps five', (t) async {
      await start(t, PhonePort(), const Size(360, 780));
      final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 5);
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Screens'),
        ),
        findsNothing,
      );
      // Live's own button is still there.
      expect(find.byKey(const ValueKey('live-screens-button')), findsOneWidget);
    });

    testWidgets('a locked screen opens nothing and Return to Live works', (
      t,
    ) async {
      final c = await start(t, PcPort(), const Size(1366, 768));
      await t.tap(railLabel('Screens'));
      await t.pumpAndSettle();
      // Esc and Back leave for Live.
      home(t).handleBack();
      await t.pumpAndSettle();
      expect(home(t).page, 0);
      await t.tap(railLabel('Screens'));
      await t.pumpAndSettle();
      c.uiLocked = true;
      home(t).refreshHome(() => home(t).controlsLocked = true);
      await t.pumpAndSettle();
      await t.tap(railLabel('Live'), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(home(t).page, screensPage, reason: 'locked: the rail is inert');
      c.uiLocked = false;
      home(t).refreshHome(() => home(t).controlsLocked = false);
      home(t).returnToLive();
      await t.pumpAndSettle();
      expect(home(t).page, 0);
    });

    testWidgets('a phone swipe skips Screens', (t) async {
      await start(t, PhonePort(), const Size(360, 780));
      expect([
        for (final p in home(t).navigationPages) p.page,
      ], isNot(contains(screensPage)));
    });
  });

  group('every way in selects the destination', () {
    testWidgets('the Live button and Commands', (t) async {
      await start(t, PcPort(), const Size(1366, 768));
      final button = find.byKey(const ValueKey('live-screens-button'));
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pumpAndSettle();
      expect(home(t).page, screensPage);
      expect(find.byType(ScreensPage), findsOneWidget, reason: 'one copy');
      expect(
        Navigator.of(
          t.element(find.byType(Home, skipOffstage: false)),
        ).canPop(),
        isFalse,
      );
      home(t).handleBack();
      await t.pumpAndSettle();
      expect(home(t).page, 0);
      await t.runAsync(() async {
        await home(
          t,
        ).paletteCommands().firstWhere((p) => p.id == 'screens-panel').run();
      });
      await t.pumpAndSettle();
      expect(home(t).page, screensPage);
      expect(find.byType(ScreensPage), findsOneWidget);
      // No second "Go to Screens" beside the Screens command.
      expect(
        home(t).paletteCommands().where((p) => p.label == 'Go to Screens'),
        isEmpty,
      );
    });

    testWidgets('the Slides page and a page pushed over the home screen', (
      t,
    ) async {
      final c = await start(t, PcPort(), const Size(1366, 768));
      await home(t).goToPage(lyricsPage);
      await t.pump(const Duration(seconds: 1));
      final header = find.byKey(const ValueKey('lyrics-screens-row-header'));
      await t.ensureVisible(header);
      await t.tap(header);
      await t.pump(const Duration(seconds: 1));
      final open = find.byKey(const ValueKey('lyrics-open-screens'));
      await t.ensureVisible(open);
      await t.tap(open);
      await t.pumpAndSettle();
      expect(home(t).page, screensPage);
      expect(find.byType(ScreensPage), findsOneWidget);
      // From a page pushed over the home screen (Settings › Screens &
      // devices opens Screens this way) the pushed page goes and the
      // destination is shown.
      home(t).handleBack();
      await t.pumpAndSettle();
      Navigator.of(
        t.element(find.byType(Home)),
      ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
      await t.pumpAndSettle();
      await t.runAsync(
        () => openScreensPanel(t.element(find.byType(Scaffold).last), c),
      );
      await t.pumpAndSettle();
      expect(home(t).page, screensPage);
      expect(
        Navigator.of(
          t.element(find.byType(Home, skipOffstage: false)),
        ).canPop(),
        isFalse,
      );
    });

    testWidgets('a phone still pushes the panel', (t) async {
      await start(t, PhonePort(), const Size(360, 780));
      final button = find.byKey(const ValueKey('live-screens-button'));
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pumpAndSettle();
      expect(home(t).page, 0);
      expect(find.byType(ScreensPage), findsOneWidget);
      expect(
        Navigator.of(t.element(find.byType(ScreensPage))).canPop(),
        isTrue,
      );
    });
  });

  group('the rail with six destinations', () {
    for (final text in [1.0, 1.6]) {
      testWidgets('fits at 1366 × 768, text $text', (t) async {
        await start(t, PcPort(), const Size(1366, 768), text: text);
        await t.tap(railLabel('Screens'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        for (final name in [
          'Live',
          'Programs',
          'Slides',
          'Screens',
          'Reports',
          'Settings',
        ]) {
          expect(railLabel(name), findsOneWidget);
        }
      });
    }
    testWidgets('a sideways phone scrolls the rail instead of overflowing', (
      t,
    ) async {
      await start(t, PcPort(), const Size(844, 390));
      expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(railLabel('Settings'));
      await t.pumpAndSettle();
      await t.tap(railLabel('Screens'), warnIfMissed: false);
      expect(t.takeException(), isNull);
    });

    testWidgets('golden: Screens selected on the rail', (t) async {
      await start(t, PcPort(), const Size(1366, 768));
      await t.tap(railLabel('Screens'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(Home),
        matchesGoldenFile('../goldens/screens-rail-selected-1366.png'),
      );
    });
    testWidgets('golden: the rail at text 1.6', (t) async {
      await start(t, PcPort(), const Size(1366, 768), text: 1.6);
      await t.tap(railLabel('Screens'));
      await t.pumpAndSettle();
      await expectLater(
        find.byType(Home),
        matchesGoldenFile('../goldens/screens-rail-text16-1366.png'),
      );
    });
  });

  group('other pages use the window too', () {
    for (final (size, key, least) in [
      (const Size(1366, 768), 'settings-two-columns', 1150.0),
      (const Size(1920, 1080), 'settings-three-columns', 1700.0),
    ]) {
      testWidgets('Settings fills $size', (t) async {
        await start(t, PcPort(), size);
        await t.tap(railLabel('Settings'));
        await t.pumpAndSettle();
        expect(find.byKey(ValueKey(key)), findsOneWidget);
        // The groups run to the window's width, not a capped 1200.
        expect(t.getSize(find.byKey(ValueKey(key))).width, greaterThan(least));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('the embedded page has the theme background', () {
    for (final layout in [
      'classic',
      'three_panes',
      'mission_control',
      'dial',
      'keys',
    ]) {
      for (final theme in ['midnight_lime', 'morning_sky']) {
        testWidgets('$layout, $theme', (t) async {
          await start(
            t,
            PcPort(),
            const Size(1920, 1080),
            layout: layout,
            theme: theme,
          );
          await home(t).goToPage(screensPage);
          await t.pumpAndSettle();
          expect(find.byType(ScreensPage), findsOneWidget);
          final want = appColors(
            t.element(find.byType(ScreensPage)),
          ).background;
          // A spot of bare page: the right margin, beside the cards.
          final page = t.getRect(find.byKey(const ValueKey('screens-page')));
          final at = Offset(page.right - 8, page.top + 300);
          late ui.Image image;
          await t.runAsync(() async {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            image = await boundary.toImage();
          });
          late ByteData data;
          await t.runAsync(() async {
            data = (await image.toByteData())!;
          });
          final i = ((at.dy.round() * image.width) + at.dx.round()) * 4;
          final got = Color.fromARGB(
            data.getUint8(i + 3),
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          );
          expect(got.toARGB32(), want.toARGB32(), reason: 'at $at');
        });
      }
    }
  });
}

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../live/screen_sizes_test.dart' show DesktopPort;

/// Small cards in a finish are material cards: the panel's own material a
/// step darker and calmer, with the finish's own edge, their dividers
/// grooves and a hovered row pressed in. Flat keeps its cards as they were.
void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);

  Future<AppController> settings(
    WidgetTester t,
    String finish,
    Size size,
  ) async {
    setScreen(t, size);
    final wide = size.width >= 1200;
    desktopWording = wide;
    addTearDown(() => desktopWording = false);
    final c = AppController(wide ? DesktopPort() : FakePort());
    await c.initialize(startTicker: false);
    await c.commit((d, _) {
      d.themeId = 'royal_navy';
      d.appearance = d.appearance.copyWith(
        finish: finish,
        finishStrength: 'full',
        desktopLayout: 'mission_control',
      );
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(
      wide
          ? find
                .descendant(
                  of: find.byKey(const ValueKey('navigation-rail')),
                  matching: find.text('Settings'),
                )
                .first
          : find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text('Settings'),
            ),
    );
    await t.pumpAndSettle();
    return c;
  }

  Finder card(String row) => find
      .ancestor(of: find.text(row), matching: find.byType(FinishCard))
      .first;

  testWidgets('a card on a panel is the material, set in, with its edge', (
    t,
  ) async {
    await settings(t, 'walnut', const Size(1366, 768));
    final surface = find.descendant(
      of: card('Church profile'),
      matching: find.byType(FinishSurface),
    );
    expect(surface, findsOneWidget);
    expect(t.widget<FinishSurface>(surface).card, isTrue);
    final paints = t
        .renderObjectList<RenderFinishPaint>(
          find.descendant(of: surface, matching: find.byType(FinishPaint)),
        )
        .toList();
    expect(
      [for (final p in paints) p.part],
      [FinishPart.panel, FinishPart.seam],
    );
    final look = paints.first.look;
    expect(look.isCard, isTrue);
    final panel = finishLook(t.element(surface));
    // A step darker than the panel and calmer.
    expect(
      look.panel.computeLuminance(),
      lessThan(panel.panel.computeLuminance()),
    );
    expect(look.panelLight, lessThan(panel.panelLight));
    // No rounded clip of its own.
    expect(
      find.descendant(
        of: card('Church profile'),
        matching: find.byType(ClipRRect),
      ),
      findsNothing,
    );
  });

  testWidgets('dividers in a card are grooves', (t) async {
    await settings(t, 'marble', const Size(1366, 768));
    expect(
      find.descendant(
        of: card('Church profile'),
        matching: find.byType(FinishGroove),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: card('Church profile'),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
  });

  testWidgets('a hovered row is pressed in', (t) async {
    await settings(t, 'plastic', const Size(1366, 768));
    expect(find.byKey(const ValueKey('finish-pressed')), findsNothing);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('Appearance').first));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('finish-pressed')), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('finish-pressed')), findsNothing);
  });

  testWidgets('Flat keeps its cards and dividers as they were', (t) async {
    await settings(t, 'flat', const Size(1366, 768));
    expect(find.byType(FinishPaint), findsNothing);
    expect(find.byType(FinishGroove), findsNothing);
    expect(find.byType(Divider), findsWidgets);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(t.getCenter(find.text('Appearance').first));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('finish-pressed')), findsNothing);
  });

  group('goldens', () {
    Future<void> shot(WidgetTester t, String name, Rect crop) async {
      expect(t.takeException(), isNull);
      final view = t.binding.renderViews.first;
      final image = await t.runAsync(
        () => (view.debugLayer! as OffsetLayer).toImage(crop),
      );
      await expectLater(
        image,
        matchesGoldenFile('../goldens/finish/$name.png'),
      );
    }

    for (final finish in ['marble', 'walnut', 'plastic', 'console', 'denim']) {
      testWidgets('Settings on a computer, $finish', (t) async {
        await settings(t, finish, const Size(1366, 768));
        // One row under the pointer, pressed in.
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(t.getCenter(find.text('Appearance').first));
        await t.pumpAndSettle();
        await shot(
          t,
          'cards-settings-$finish-1366',
          const Rect.fromLTWH(100, 112, 640, 448),
        );
      });

      testWidgets('Settings on a phone, $finish', (t) async {
        await settings(t, finish, const Size(360, 780));
        await shot(
          t,
          'cards-settings-$finish-phone',
          const Rect.fromLTWH(0, 150, 360, 450),
        );
      });
    }
  });
}

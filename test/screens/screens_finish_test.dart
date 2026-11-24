import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/screens/screens_panel.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_popups.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'screens_panel_test.dart' show PcPort, PhonePort, service;

/// The Screens page in a finish: on a panel of it with its cards set in,
/// its bar a plate of the material, its menus and dialogs made of it, and
/// all of it drawn once, as images, like every other page (see
/// finish_performance_test.dart and finish_legibility_test.dart).
void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);
  tearDown(() => desktopWording = false);

  Future<(AppController, FakePort)> open(
    WidgetTester t,
    FakePort port,
    Size size,
    String finish,
  ) async {
    setScreen(t, size);
    desktopWording = port.isDesktop;
    late AppController c;
    // Saved with the finish, so the app starts in it.
    port.data = jsonEncode(
      (AppState.fresh(start)
            ..themeId = 'royal_navy'
            ..appearance = AppearancePreferences(
              finish: finish,
              finishStrength: 'full',
            ))
          .toJson(),
    );
    await t.runAsync(() async => c = await service(port));
    expect(c.appearanceSelection.value.finish, finish);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    t.takeException();
    final button = find.byKey(const ValueKey('live-screens-button'));
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byType(ScreensPage), findsOneWidget);
    return (c, port);
  }

  bool onMaterial(Element e) {
    var ok = false;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is FinishSurface ||
          w is FinishPopupFrame ||
          w is AppBar ||
          (w is Material &&
              w.type != MaterialType.transparency &&
              (w.color?.a ?? 0) == 1)) {
        ok = true;
        return false;
      }
      return true;
    });
    return ok;
  }

  for (final (name, port, size) in [
    ('a computer', () => PcPort(), const Size(1366, 768)),
    ('a phone', () => PhonePort(), const Size(360, 780)),
  ]) {
    testWidgets('no words on the bare wall on $name', (t) async {
      await open(t, port(), size, 'denim');
      final bare = [
        for (final e
            in find
                .descendant(
                  of: find.byType(ScreensPage),
                  matching: find.byType(Text),
                )
                .hitTestable()
                .evaluate())
          if (!onMaterial(e)) (e.widget as Text).data ?? '?',
      ];
      expect(bare, isEmpty);
      // The bar is a plate of the material.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byType(FinishSurface),
        ),
        findsWidgets,
      );
    });
  }

  for (final finish in ['denim', 'console', 'glass']) {
    testWidgets('$finish: drawn once, as images, and its menus take it', (
      t,
    ) async {
      final (c, port) = await open(t, PcPort(), const Size(1366, 768), finish);
      final boxes = t
          .renderObjectList<RenderFinishPaint>(find.byType(FinishPaint))
          .toList();
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        final canvas = TestRecordingCanvas();
        box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
        final calls = canvas.invocations
            .map((i) => i.invocation.memberName)
            .toList();
        expect(calls, isNot(contains(#saveLayer)));
        expect(calls, isNot(contains(#drawPath)));
        expect(calls, isNot(contains(#drawShadow)));
      }
      final before = FinishPaintCount.total;
      for (var i = 1; i <= 6; i++) {
        port.at = after(i);
        await c.tick();
        await t.pump(const Duration(seconds: 1));
      }
      expect(FinishPaintCount.total, before, reason: 'a surface drew again');
      // A group's menu is made of the finish.
      await t.tap(
        find
            .descendant(
              of: find.byType(ScreensPage),
              matching: find.byType(PopupMenuButton<String>),
            )
            .first,
      );
      await t.pumpAndSettle();
      expect(
        t.allRenderObjects.whereType<RenderFinishPopupFrame>().where(
          (f) => f.sheet != null,
        ),
        isNotEmpty,
      );
    });
  }

  testWidgets('golden: Denim on a computer', (t) async {
    await open(t, PcPort(), const Size(1366, 768), 'denim');
    expect(t.takeException(), isNull);
    final view = t.binding.renderViews.first;
    final image = await t.runAsync(
      () => (view.debugLayer! as OffsetLayer).toImage(
        const Rect.fromLTWH(0, 0, 1366, 380),
      ),
    );
    await expectLater(
      image,
      matchesGoldenFile('../goldens/finish/screens-denim-full-dark-1366.png'),
    );
  });
}

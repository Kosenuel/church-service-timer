import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../live/screen_sizes_test.dart' show DesktopPort, sunday;
import '../lyrics/lyrics_page_test.dart' show openLyrics, settle;

/// Nothing a page shows is drawn across a panel's edge or past it: every
/// word, picture, row and card that shows on a panel is inside the panel's
/// inner boundary (see finishEdgeInset), where the edge detail, drawn over
/// the content, begins. In 0.39.0-beta.2 only Denim and Leather kept their
/// content in; on the others a list's rows and a slide's picture ran over
/// the wood lip, the chamfer or the rim, and out past the corners.
void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);

  /// The part of [box] that shows, in the window: its bounds cut by every
  /// clip above it; null when none shows.
  ///
  /// Without [edges], a panel's own cut at its edge is left out, to find
  /// what is laid out under the edge rather than scrolled there.
  Rect? showing(RenderObject box, {bool edges = true}) {
    var rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      box.paintBounds,
    );
    RenderObject child = box;
    for (var parent = box.parent; parent != null; parent = parent.parent) {
      if (parent is RenderOffstage && parent.offstage) return null;
      if (parent is RenderIndexedStack) {
        var i = 0, at = -1;
        parent.visitChildren((c) {
          if (c == child) at = i;
          i++;
        });
        if (at != (parent.index ?? 0)) return null;
      }
      if (parent is RenderOpacity && parent.opacity == 0) return null;
      if (parent is RenderAnimatedOpacity && parent.opacity.value == 0) {
        return null;
      }
      final cut =
          parent is RenderClipRect && parent.clipper is FinishEdgeClipper;
      final clip = cut && !edges
          ? null
          : parent.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
        if (rect.width <= .5 || rect.height <= .5) return null;
      }
      child = parent;
    }
    return rect;
  }

  /// The ways [box] scrolls: in a list it goes on past the panel's edge.
  Set<Axis> scrolls(RenderObject box) {
    final creator = box.debugCreator;
    if (creator is! DebugCreator) return const {};
    final axes = <Axis>{};
    creator.element.visitAncestorElements((e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final p = (e.state as ScrollableState).position;
        // One that scrolls by less than a row is a layout a little too
        // big for its panel, not a list.
        if (p.hasContentDimensions && p.maxScrollExtent > 16) {
          axes.add(p.axis);
        }
      }
      return true;
    });
    return axes;
  }

  /// What shows across an edge: each drawn thing that overlaps a panel but
  /// is not inside the panel's inner boundary.
  List<String> across(WidgetTester t, {bool edges = true}) {
    final panels = [
      for (final p in t.allRenderObjects.whereType<RenderFinishPaint>())
        if (p.part == FinishPart.seam && p.attached && p.hasSize)
          if (showing(p) case final shown?)
            (
              outer: MatrixUtils.transformRect(
                p.getTransformTo(null),
                Offset.zero & p.size,
              ),
              inner: MatrixUtils.transformRect(
                p.getTransformTo(null),
                (Offset.zero & p.size).deflate(finishEdgeInset(p.look.id)),
              ).inflate(.5),
              shown: shown,
              stack: _stackOf(p),
            ),
    ];
    final found = <String>[];
    for (final r in t.allRenderObjects) {
      if (r is! RenderParagraph &&
          r is! RenderImage &&
          r is! RenderPhysicalShape &&
          r is! RenderPhysicalModel &&
          r is! RenderDecoratedBox &&
          r is! RenderEditable) {
        continue;
      }
      if (r is RenderBox && (!r.hasSize || r.size.isEmpty)) continue;
      // A button's ink, clear until it is pressed, and a clear sheet.
      if (r is RenderPhysicalShape && r.color.a == 0) continue;
      if (r is RenderPhysicalModel && r.color.a == 0) continue;
      final shown = showing(r, edges: edges);
      if (shown == null) continue;
      // In a list that scrolls, rows go on past the foot of the panel (or
      // its far side), under its edge; at rest the top is still clear.
      final axes = edges ? const <Axis>{} : scrolls(r);
      for (final p in panels) {
        // Only the panel it is on: a bar or a popup over a panel is a
        // surface of its own.
        var on = false;
        for (var a = r.parent; a != null && !on; a = a.parent) {
          on = a == p.stack;
        }
        if (!on) continue;
        final over = shown.intersect(p.outer);
        if (over.width <= .5 || over.height <= .5) continue;
        // A background the whole panel stands on.
        if (shown.contains(p.outer.topLeft) &&
            shown.contains(p.outer.bottomRight - const Offset(1, 1))) {
          continue;
        }
        // A rule across the panel runs on under its edge and fades there,
        // like a row of a list.
        final rule = shown.height <= 2 || shown.width <= 2;
        // At rest, clear of the fade under the edge as well.
        final inside = rule
            ? p.outer
            : edges
            ? p.inner
            : p.inner.deflate(finishFade / 2);
        final across = axes.contains(Axis.horizontal);
        if ((over.left < inside.left && !across) ||
            over.top < inside.top ||
            (over.right > inside.right && !across) ||
            (over.bottom > inside.bottom && !axes.contains(Axis.vertical))) {
          found.add('${r.runtimeType} ${_describe(r)} at $over, panel $inside');
        }
      }
    }
    return found;
  }

  Future<AppController> app(WidgetTester t, String finish, Size size) async {
    setScreen(t, size);
    final wide = size.width >= 1200;
    desktopWording = wide;
    addTearDown(() => desktopWording = false);
    final port = wide ? DesktopPort() : FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((d, _) {
      d.themeId = 'royal_navy';
      d.appearance = d.appearance.copyWith(
        finish: finish,
        finishStrength: 'full',
        desktopLayout: 'mission_control',
      );
    });
    for (var r = 0; r < 14; r++) {
      await c.act('load', value: sunday());
      await c.act('start');
      port.at = after(600 + r);
      await c.tick();
      await c.act('end');
    }
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> tab(WidgetTester t, String name, Size size) async {
    await t.tap(
      size.width >= 840
          ? find
                .descendant(
                  of: find.byKey(const ValueKey('navigation-rail')),
                  matching: find.text(name),
                )
                .first
          : find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(name),
            ),
    );
    await t.pumpAndSettle();
  }

  /// Every list on the page part way down, so its rows meet the edges.
  Future<void> scrollAll(WidgetTester t) async {
    for (final s in find.byType(Scrollable).hitTestable().evaluate().toList()) {
      final state = (s as StatefulElement).state as ScrollableState;
      final p = state.position;
      if (p.maxScrollExtent > 0 && p.axis == Axis.vertical) {
        p.jumpTo((p.maxScrollExtent / 2).clamp(0, 37));
      }
    }
    await t.pump();
  }

  const sizes = {
    '1366': Size(1366, 768),
    '1920': Size(1920, 1080),
    'phone': Size(360, 780),
  };
  for (final finish in ['walnut', 'plastic', 'console', 'cashmere', 'denim']) {
    for (final MapEntry(key: name, value: size) in sizes.entries) {
      testWidgets('$finish $name: the pages', (t) async {
        await app(t, finish, size);
        final pages = [
          'Live',
          'Programs',
          if (size.width >= 840) 'Slides',
          'Reports',
          'Settings',
        ];
        for (final page in pages) {
          await tab(t, page, size);
          expect(across(t, edges: false), isEmpty, reason: page);
          await scrollAll(t);
          expect(across(t), isEmpty, reason: '$page scrolled');
        }
      });

      testWidgets('$finish $name: Settings pages', (t) async {
        await app(t, finish, size);
        for (final page in [
          'Church profile',
          'Appearance',
          'Desktop layout',
          'Warnings & alerts',
          'Screens & devices',
          'Backup & restore',
          'About',
        ]) {
          await tab(t, 'Settings', size);
          final entry = find.text(page);
          if (entry.evaluate().isEmpty) continue;
          await t.ensureVisible(entry.first);
          await t.pumpAndSettle();
          await t.tap(entry.first);
          await t.pumpAndSettle();
          expect(across(t, edges: false), isEmpty, reason: page);
          await scrollAll(t);
          expect(across(t), isEmpty, reason: '$page scrolled');
          final back = find.byType(BackButton);
          if (back.evaluate().isNotEmpty) {
            await t.tap(back.first);
          } else {
            await t.tapAt(const Offset(4, 4));
          }
          await t.pumpAndSettle();
        }
      });

      testWidgets('$finish $name: a program open', (t) async {
        await app(t, finish, size);
        await tab(t, 'Programs', size);
        await t.tap(find.textContaining('Sunday Service').first);
        await t.pumpAndSettle();
        expect(across(t, edges: false), isEmpty);
        await scrollAll(t);
        expect(across(t), isEmpty, reason: 'scrolled');
      });
    }
  }

  group('the two places the owner saw', () {
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

    for (final finish in ['walnut', 'plastic', 'marble']) {
      testWidgets('the slide picture under the top edge on Slides, $finish', (
        t,
      ) async {
        final c = await openLyrics(t, finish: finish, running: false);
        c.lyrics.show('amazing', 0);
        await settle(t);
        // Scrolled a little, so the picture passes under the edge.
        final list = find
            .descendant(
              of: find.byKey(const ValueKey('lyrics-column-screens')),
              matching: find.byType(Scrollable),
            )
            .first;
        (t.state<ScrollableState>(list)).position.jumpTo(46);
        await t.pump();
        final panel = t.getRect(
          find.byKey(const ValueKey('lyrics-column-screens')),
        );
        await shot(
          t,
          'edge-slides-preview-$finish',
          Rect.fromLTWH(panel.left - 12, panel.top - 12, 260, 140),
        );
      });

      testWidgets('the Reports list at the foot of its panel, $finish', (
        t,
      ) async {
        setScreen(t, const Size(1920, 1080));
        desktopWording = true;
        addTearDown(() => desktopWording = false);
        await app(t, finish, const Size(1920, 1080));
        await tab(t, 'Reports', const Size(1920, 1080));
        final list = find.byType(Scrollable).hitTestable().first;
        (t.state<ScrollableState>(list)).position.jumpTo(30);
        await t.pump();
        final box = t.getRect(list);
        await shot(
          t,
          'edge-reports-list-$finish',
          Rect.fromLTWH(box.left - 20, 1080 - 180, 360, 180),
        );
      });
    }
  });
}

String _describe(RenderObject r) => switch (r) {
  RenderParagraph p => '"${p.text.toPlainText()}"',
  _ => r.debugCreator?.toString().split('\n').first ?? '',
};

/// The stack a panel's material and content are laid in.
RenderObject _stackOf(RenderObject panel) {
  var r = panel.parent!;
  while (r is! RenderStack) {
    r = r.parent!;
  }
  return r;
}

import 'dart:ui' as ui;
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/finish_popups.dart';
import 'package:church_service_timer/shared/device_words.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../live/screen_sizes_test.dart' show DesktopPort, sunday;

/// Words stay legible in every finish: for every finish, both strengths and
/// every built-in theme (and some custom ones), body text, muted text and the
/// accent keep their contrast against every colour a panel or the bare
/// background can have, and against the pixels actually drawn.
///
/// The bars are what the plain theme (Flat) gives: 4.5:1 for body text, and
/// for muted text and the accent on a panel as much as Flat has up to 4.5:1.
/// On the bare background (a title or button outside any panel) muted text
/// and the accent need 3:1, the bar for large text, and body text 4.5:1.
void main() {
  // The photographs, decoded before the pixel tests draw with them.
  setUpAll(FinishTextures.instance.loadAll);
  final looks = [
    ...appPalettes.map((p) => p.id),
    'custom:2f6f4f:101820:1b2833',
    'custom:ffcc00:f2efe6:ffffff',
    'custom:e91e63:fff7f0:fffdfb',
    'custom:00bcd4:001018:0b2230',
  ];
  final finishesOn = [...finishIds.where((f) => f != 'flat'), paperyFinish];
  // Papery belongs to the Paper & Ink themes only.
  bool applies(String finish, String id) =>
      finish != paperyFinish || paperyThemeIds.contains(id);

  double bar(double flat, double max) => flat < max ? flat : max;

  group('colours', () {
    for (final id in looks) {
      final p = paletteFor(id);
      for (final finish in finishesOn) {
        if (!applies(finish, id)) continue;
        for (final strength in finishStrengths) {
          test(
            '$finish at $strength keeps text readable in ${p.name} ($id)',
            () {
              final look = FinishLook.resolve(
                p,
                finish,
                strength == 'full' ? 1 : .5,
              );
              expect(look.active, isTrue);
              final text = bar(contrast(p.text, p.surface), 4.5);
              final muted = bar(contrast(p.muted, p.surface), 4.5);
              final accent = bar(contrast(p.accent, p.surface), 4.5);
              for (final c in look.panelSamples) {
                expect(
                  contrast(p.text, c),
                  greaterThanOrEqualTo(text),
                  reason: 'text on $c',
                );
                expect(
                  contrast(p.muted, c),
                  greaterThanOrEqualTo(muted),
                  reason: 'muted on $c',
                );
                expect(
                  contrast(p.accent, c),
                  greaterThanOrEqualTo(accent),
                  reason: 'accent on $c',
                );
              }
              final wallText = bar(contrast(p.text, p.background), 4.5);
              final wallMuted = bar(contrast(p.muted, p.background), 3);
              final wallAccent = bar(contrast(p.accent, p.background), 3);
              for (final c in look.wallSamples) {
                expect(
                  contrast(p.text, c),
                  greaterThanOrEqualTo(wallText),
                  reason: 'text on wall $c',
                );
                expect(
                  contrast(p.muted, c),
                  greaterThanOrEqualTo(wallMuted),
                  reason: 'muted on wall $c',
                );
                expect(
                  contrast(p.accent, c),
                  greaterThanOrEqualTo(wallAccent),
                  reason: 'accent on wall $c',
                );
              }
              // The key face of a filled button keeps its label readable.
              final label = readable(p.accent);
              final face = bar(contrast(label, p.accent), 4.5);
              for (final c in [
                Color.lerp(p.accent, Colors.white, .12)!,
                Color.lerp(p.accent, Colors.black, .15)!,
              ]) {
                expect(
                  contrast(label, c),
                  greaterThanOrEqualTo(face - .6),
                  reason: 'label on key face $c',
                );
              }
            },
          );
        }
      }
    }

    test('the bars are what Flat gives or better', () {
      for (final p in appPalettes) {
        expect(
          contrast(p.text, p.surface),
          greaterThanOrEqualTo(4.5),
          reason: p.id,
        );
        expect(
          contrast(p.text, p.background),
          greaterThanOrEqualTo(4.5),
          reason: p.id,
        );
      }
    });

    test(
      'a finish stays visible in every theme, and Subtle is never stronger than Full',
      () {
        for (final id in looks) {
          final p = paletteFor(id);
          for (final finish in finishesOn) {
            if (!applies(finish, id)) continue;
            final full = FinishLook.resolve(p, finish, 1);
            final subtle = FinishLook.resolve(p, finish, .5);
            // Some of the material survives the legibility limit.
            expect(
              full.wallScale + full.panelScale,
              greaterThan(.4),
              reason: '$finish in $id',
            );
            expect(
              subtle.wallScale,
              lessThanOrEqualTo(full.wallScale),
              reason: '$finish in $id',
            );
            expect(
              subtle.panelScale,
              lessThanOrEqualTo(full.panelScale),
              reason: '$finish in $id',
            );
          }
        }
      },
    );

    test('Flat and High contrast draw nothing of their own', () {
      final p = appPalettes.first;
      expect(FinishLook.resolve(p, 'flat', 1).active, isFalse);
      final hc = appTheme(
        p.id,
        appearance: const AppearancePreferences(
          finish: 'brick',
          finishStrength: 'full',
          highContrast: true,
        ),
      ).extension<FinishLook>()!;
      expect(hc.active, isFalse);
      final on = appTheme(
        p.id,
        appearance: const AppearancePreferences(finish: 'brick'),
      );
      expect(on.extension<FinishLook>()!.active, isTrue);
      expect(on.scaffoldBackgroundColor, Colors.transparent);
      final flat = appTheme(p.id);
      expect(flat.scaffoldBackgroundColor, p.background);
    });
  });

  group('pixels', () {
    // The painters' own pixels, not only the budgets: the worst contrast of
    // any pixel in the middle of a panel and of the wall, against the words.
    final themes = [
      for (final id in looks)
        if (id.startsWith('custom:')
            ? id.endsWith('1b2833') || id.endsWith('fffdfb')
            : true)
          id,
    ];
    Future<List<int>> pixels(WidgetTester t, Widget child, Size size) async {
      final key = GlobalKey();
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await t.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return [
          for (var i = 0; i < data!.lengthInBytes; i += 4)
            0xff000000 |
                (data.getUint8(i) << 16) |
                (data.getUint8(i + 1) << 8) |
                data.getUint8(i + 2),
        ];
      }))!;
    }

    /// The least contrast of [color] against any pixel, ignoring a margin.
    double worst(List<int> px, Size size, double margin, Color color) {
      final seen = <int, double>{};
      var least = 99.0;
      final w = size.width.toInt(), h = size.height.toInt(), m = margin.toInt();
      for (var y = m; y < h - m; y++) {
        for (var x = m; x < w - m; x++) {
          final v = px[y * w + x];
          final c = seen[v] ??= contrast(color, Color(v));
          if (c < least) least = c;
        }
      }
      return least;
    }

    for (final id in themes) {
      for (final finish in finishesOn) {
        if (!applies(finish, id)) continue;
        for (final strength in finishStrengths) {
          testWidgets('$finish at $strength draws legible pixels in $id', (
            t,
          ) async {
            final p = paletteFor(id);
            final theme = appTheme(
              id,
              appearance: AppearancePreferences(
                finish: finish,
                finishStrength: strength,
              ),
            );
            Widget themed(Widget child) => Theme(data: theme, child: child);
            const panel = Size(320, 200), wall = Size(400, 300);
            final panelPx = await pixels(
              t,
              themed(
                Container(
                  color: p.background,
                  padding: const EdgeInsets.all(30),
                  child: const FinishSurface(child: SizedBox.expand()),
                ),
              ),
              panel,
            );
            // Inside the panel, clear of its edge trim and screws.
            final text = bar(contrast(p.text, p.surface), 4.5);
            final muted = bar(contrast(p.muted, p.surface), 4.5);
            final accent = bar(contrast(p.accent, p.surface), 4.5);
            expect(
              worst(panelPx, panel, 44, p.text),
              greaterThanOrEqualTo(text - .01),
              reason: 'text on the panel',
            );
            expect(
              worst(panelPx, panel, 44, p.muted),
              greaterThanOrEqualTo(muted - .01),
              reason: 'muted on the panel',
            );
            expect(
              worst(panelPx, panel, 44, p.accent),
              greaterThanOrEqualTo(accent - .01),
              reason: 'accent on the panel',
            );
            final wallPx = await pixels(
              t,
              themed(const FinishWall(child: SizedBox.expand())),
              wall,
            );
            expect(
              worst(wallPx, wall, 0, p.text),
              greaterThanOrEqualTo(
                bar(contrast(p.text, p.background), 4.5) - .01,
              ),
              reason: 'text on the wall',
            );
            expect(
              worst(wallPx, wall, 0, p.muted),
              greaterThanOrEqualTo(
                bar(contrast(p.muted, p.background), 3) - .01,
              ),
              reason: 'muted on the wall',
            );
            expect(
              worst(wallPx, wall, 0, p.accent),
              greaterThanOrEqualTo(
                bar(contrast(p.accent, p.background), 3) - .01,
              ),
              reason: 'accent on the wall',
            );
          });
        }
      }
    }
  });

  group('popups', () {
    // The sheet of a dialog and of a menu is the panel material, laid on by
    // FinishPopupFrame, Glass showing the wall of the page behind it: the
    // words in it keep the contrast they have on a panel.
    final themes = ['royal_navy', 'warm_ivory', 'custom:00bcd4:001018:0b2230'];
    Future<List<int>> window(WidgetTester t, Rect area) async {
      final view = t.binding.renderViews.first;
      return (await t.runAsync(() async {
        final image = await (view.debugLayer! as OffsetLayer).toImage(area);
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return [
          for (var i = 0; i < data!.lengthInBytes; i += 4)
            0xff000000 |
                (data.getUint8(i) << 16) |
                (data.getUint8(i + 1) << 8) |
                data.getUint8(i + 2),
        ];
      }))!;
    }

    double least(List<int> px, Color color) {
      final seen = <int, double>{};
      var low = 99.0;
      for (final v in px) {
        final c = seen[v] ??= contrast(color, Color(v));
        if (c < low) low = c;
      }
      return low;
    }

    for (final id in themes) {
      for (final finish in finishesOn.where((f) => f != paperyFinish)) {
        for (final strength in finishStrengths) {
          for (final kind in ['dialog', 'menu']) {
            testWidgets('$finish at $strength: a $kind is legible in $id', (
              t,
            ) async {
              t.view.physicalSize = const Size(800, 600);
              t.view.devicePixelRatio = 1;
              addTearDown(t.view.resetPhysicalSize);
              addTearDown(t.view.resetDevicePixelRatio);
              final p = paletteFor(id);
              await t.pumpWidget(
                MaterialApp(
                  theme: appTheme(
                    id,
                    appearance: AppearancePreferences(
                      finish: finish,
                      finishStrength: strength,
                    ),
                  ),
                  home: Scaffold(
                    body: Builder(
                      builder: (context) => Center(
                        child: TextButton(
                          onPressed: () => kind == 'dialog'
                              ? showDialog<void>(
                                  context: context,
                                  builder: (_) => const Dialog(
                                    key: ValueKey('sheet'),
                                    child: SizedBox(width: 360, height: 200),
                                  ),
                                )
                              : showMenu<void>(
                                  context: context,
                                  position: const RelativeRect.fromLTRB(
                                    200,
                                    100,
                                    200,
                                    100,
                                  ),
                                  items: const [
                                    PopupMenuItem(
                                      enabled: false,
                                      height: 160,
                                      child: SizedBox(
                                        key: ValueKey('sheet'),
                                        width: 220,
                                      ),
                                    ),
                                  ],
                                ),
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await t.tap(find.text('Open'));
              await t.pumpAndSettle();
              final frame = t.allRenderObjects
                  .whereType<RenderFinishPopupFrame>()
                  .firstWhere((f) => f.sheet != null);
              final sheet = frame.sheet!;
              final area = (sheet.localToGlobal(Offset.zero) & sheet.size)
                  .deflate(
                    // Clear of the edge, its stitches and screws.
                    kind == 'menu' ? 18 : 30,
                  );
              final px = await window(t, area);
              final text = bar(contrast(p.text, p.surface), 4.5);
              final muted = bar(contrast(p.muted, p.surface), 4.5);
              final accent = bar(contrast(p.accent, p.surface), 4.5);
              expect(least(px, p.text), greaterThanOrEqualTo(text - .01));
              expect(least(px, p.muted), greaterThanOrEqualTo(muted - .01));
              expect(least(px, p.accent), greaterThanOrEqualTo(accent - .01));
            });
          }
        }
      }
    }
  });

  group('no words on the bare wall', () {
    // Real letters, so the pages lay out as they do in the app.
    setUpAll(loadAppFonts);
    // Every word on these pages is on a panel of the finish (a column, a
    // card, a bar), not straight on its wall: the wall's budgets are only
    // for large text, and the owner asked for nothing to float on it.
    bool onMaterial(Element e) {
      var ok = false;
      e.visitAncestorElements((a) {
        final w = a.widget;
        if (w is FinishSurface ||
            w is FinishPopupFrame ||
            w is AppBar ||
            w is NavigationBar ||
            w is FloatingActionButton) {
          ok = true;
          return false;
        }
        // A plain Material of the theme's surface is a card of its own.
        if (w is Material &&
            w.type != MaterialType.transparency &&
            (w.color?.a ?? 0) == 1) {
          ok = true;
          return false;
        }
        return true;
      });
      return ok;
    }

    Future<void> open(
      WidgetTester t,
      Size size,
      Future<void> Function(AppController, FakePort) setup,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.view.display.size = size;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.display.resetSize);
      final port = size.width >= 1200 ? DesktopPort() : FakePort();
      // Words for a computer on one, as the app has there.
      desktopWording = size.width >= 1200;
      addTearDown(() => desktopWording = false);
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.commit((d, _) {
        d.appearance = d.appearance.copyWith(
          finish: 'denim',
          desktopLayout: 'mission_control',
        );
      });
      await setup(c, port);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
    }

    List<String> bare(WidgetTester t) => [
      for (final e in find.byType(Text).hitTestable().evaluate())
        if (!onMaterial(e))
          (e.widget as Text).data ??
              (e.widget as Text).textSpan?.toPlainText() ??
              '?',
    ];

    Future<void> live(AppController c, FakePort p) async {
      await c.act('load', value: sunday());
      await c.act('start');
      p.at = after(60);
      await c.tick();
    }

    Future<void> reported(AppController c, FakePort p) async {
      await live(c, p);
      p.at = after(400);
      await c.tick();
      await c.act('end');
      p.at = after(4000);
      await c.tick();
    }

    Future<void> nothing(AppController c, FakePort p) async {}

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

    const desktop = Size(1366, 768), phone = Size(360, 780);
    for (final (name, size) in [('a computer', desktop), ('a phone', phone)]) {
      testWidgets('Live standing by on $name', (t) async {
        await open(t, size, nothing);
        expect(bare(t), isEmpty);
      });
      testWidgets('Live during a service on $name', (t) async {
        await open(t, size, live);
        expect(bare(t), isEmpty);
      });
      testWidgets('Programs on $name', (t) async {
        await open(t, size, live);
        await tab(t, 'Programs', size);
        expect(bare(t), isEmpty);
      });
      testWidgets('Reports on $name', (t) async {
        await open(t, size, reported);
        await tab(t, 'Reports', size);
        expect(bare(t), isEmpty);
      });
      testWidgets('Settings on $name', (t) async {
        await open(t, size, nothing);
        await tab(t, 'Settings', size);
        expect(bare(t), isEmpty);
      });
    }
    for (final page in [
      'Church profile',
      'Warnings & alerts',
      'Stage cues',
      'Screens & devices',
      'LED device management',
      'Backup & restore',
      'Feedback centre',
      'About',
    ]) {
      testWidgets('Settings › $page on a computer', (t) async {
        await open(t, desktop, nothing);
        await tab(t, 'Settings', desktop);
        final entry = find.text(page).first;
        await t.ensureVisible(entry);
        await t.pumpAndSettle();
        await t.tap(entry);
        await t.pumpAndSettle();
        expect(find.text(page), findsWidgets);
        expect(find.byType(AppBar), findsOneWidget, reason: 'opened');
        expect(bare(t), isEmpty);
      });
    }
  });
}

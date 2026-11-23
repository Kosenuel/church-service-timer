import 'dart:ui' as ui;
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final looks = [
    ...appPalettes.map((p) => p.id),
    'custom:2f6f4f:101820:1b2833',
    'custom:ffcc00:f2efe6:ffffff',
    'custom:e91e63:fff7f0:fffdfb',
    'custom:00bcd4:001018:0b2230',
  ];
  final finishesOn = finishIds.where((f) => f != 'flat');

  double bar(double flat, double max) => flat < max ? flat : max;

  group('colours', () {
    for (final id in looks) {
      final p = paletteFor(id);
      for (final finish in finishesOn) {
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
}

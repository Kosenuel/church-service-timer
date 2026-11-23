import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../live/screen_sizes_test.dart' show DesktopPort, sunday;

/// A finish must not make the app slower. In 0.37.0 the materials were
/// drawn as thousands of paths (wood grain, paper fibres, marble veins),
/// blurred shadows and layers, recorded once but replayed by the GPU on
/// every frame (every tick of the clock, every scroll): Impeller keeps no
/// raster cache. Now each surface is a few pre-made images, drawn into its
/// own layer once. These tests hold that: no surface draws again on a tick
/// or a scroll, and what a surface draws has no layers, blurs or paths.
void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);

  Future<(AppController, FakePort)> live(
    WidgetTester t,
    String finish, {
    String theme = 'royal_navy',
    Size size = const Size(1366, 768),
  }) async {
    setScreen(t, size);
    final port = size.width >= 1200 ? DesktopPort() : FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((d, _) {
      d.themeId = theme;
      d.appearance = d.appearance.copyWith(
        finish: finish,
        finishStrength: 'full',
        desktopLayout: 'mission_control',
      );
    });
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  group('drawn once', () {
    for (final finish in [...finishIds.where((f) => f != 'flat'), 'papery']) {
      testWidgets('$finish: nothing draws again while the clock ticks', (
        t,
      ) async {
        final (c, port) = await live(
          t,
          finish == 'papery' ? 'flat' : finish,
          theme: finish == 'papery' ? 'paper_ink' : 'royal_navy',
        );
        expect(find.byType(FinishPaint), findsWidgets);
        final before = FinishPaintCount.total;
        for (var i = 1; i <= 12; i++) {
          port.at = after(i);
          await c.tick();
          await t.pump(const Duration(seconds: 1));
        }
        expect(FinishPaintCount.total, before, reason: 'a surface drew again');
      });
    }

    for (final finish in ['walnut', 'denim', 'glass']) {
      testWidgets('$finish: nothing draws again while a list scrolls', (
        t,
      ) async {
        setScreen(t, const Size(360, 780));
        final c = AppController(FakePort());
        await c.initialize(startTicker: false);
        await c.commit((d, _) {
          d.appearance = d.appearance.copyWith(finish: finish);
        });
        await t.pumpWidget(TimerApp(controller: c));
        await t.pumpAndSettle();
        await t.tap(find.byType(NavigationDestination).at(4));
        await t.pumpAndSettle();
        final before = FinishPaintCount.total;
        // Within what the list has already built, down and back.
        for (final dy in const <double>[-40, -40, -40, 40, 40, 40]) {
          await t.drag(find.byType(Scrollable).first, Offset(0, dy));
          await t.pump(const Duration(milliseconds: 16));
        }
        await t.pumpAndSettle();
        expect(FinishPaintCount.total, before);
      });
    }

    testWidgets('Flat draws no material at all', (t) async {
      final before = FinishPaintCount.total;
      await live(t, 'flat');
      expect(find.byType(FinishPaint), findsNothing);
      expect(FinishPaintCount.total, before);
    });
  });

  group('cheap to draw', () {
    // What each surface sends to the GPU, recorded call by call.
    for (final finish in [...finishIds.where((f) => f != 'flat'), 'papery']) {
      testWidgets(
        '$finish: images only, with no layers, blurs or paths in a frame',
        (t) async {
          await live(
            t,
            finish == 'papery' ? 'flat' : finish,
            theme: finish == 'papery' ? 'paper_ink' : 'royal_navy',
          );
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
            expect(calls, isNot(contains(#saveLayer)), reason: finish);
            expect(calls, isNot(contains(#drawPath)), reason: finish);
            expect(calls, isNot(contains(#drawShadow)), reason: finish);
            final draws = calls.where(
              (m) => !const {#save, #restore, #translate, #scale}.contains(m),
            );
            expect(
              draws.length,
              lessThanOrEqualTo(10),
              reason: '$finish: $calls',
            );
            for (final i in canvas.invocations) {
              for (final a in i.invocation.positionalArguments) {
                if (a is Paint) {
                  expect(a.maskFilter, isNull, reason: '$finish: a blur');
                  expect(a.imageFilter, isNull, reason: '$finish: a filter');
                }
              }
            }
          }
        },
      );
    }

    testWidgets('the header has no backdrop blur in a finish', (t) async {
      await live(t, 'console');
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('the seam', () {
    const size = Size(300, 220);
    Future<List<int>> shot(WidgetTester t, Widget child) async {
      final key = GlobalKey();
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: appTheme(
              'royal_navy',
              appearance: const AppearancePreferences(
                finish: 'denim',
                finishStrength: 'full',
              ),
            ),
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox.fromSize(
                  size: size,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: child,
                  ),
                ),
              ),
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
            (data.getUint8(i) << 16) |
                (data.getUint8(i + 1) << 8) |
                data.getUint8(i + 2),
        ];
      }))!;
    }

    bool red(int v) =>
        (v >> 16) > 200 && ((v >> 8) & 255) < 60 && (v & 255) < 60;

    /// The red pixels within [inset] of the panel's edge (the panel is the
    /// shot less 20 on every side).
    int redNearEdge(List<int> px, double inset) {
      var n = 0;
      final w = size.width.toInt(), h = size.height.toInt();
      for (var y = 20; y < h - 20; y++) {
        for (var x = 20; x < w - 20; x++) {
          final edge = [
            x - 20,
            y - 20,
            w - 21 - x,
            h - 21 - y,
          ].reduce((a, b) => a < b ? a : b);
          if (edge < inset && red(px[y * w + x])) n++;
        }
      }
      return n;
    }

    testWidgets('content never paints over the stitches', (t) async {
      // A box that would fill the panel to its very edge.
      final px = await shot(
        t,
        const FinishSurface(child: ColoredBox(color: Color(0xffff0000))),
      );
      expect(
        redNearEdge(px, finishSeamInset),
        0,
        reason: 'nothing reaches the thread',
      );
      // It still fills the inside of the panel.
      final w = size.width.toInt();
      expect(red(px[(size.height ~/ 2) * w + w ~/ 2]), isTrue);
      expect(red(px[(size.height ~/ 2) * w + 20 + 14]), isTrue);
    });

    testWidgets('a scrolled list is cut off inside the seam, under the hem', (
      t,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      Widget list() => FinishSurface(
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(12),
          children: [
            for (var i = 0; i < 30; i++)
              Container(
                height: 22,
                margin: const EdgeInsets.only(bottom: 4),
                color: const Color(0xffff0000),
              ),
          ],
        ),
      );
      await shot(t, list());
      controller.jumpTo(37);
      final px = await shot(t, list());
      expect(redNearEdge(px, finishSeamInset), 0);
      // The clip is inside the seam, and the seam is drawn over it.
      final clip = t.renderObject<RenderClipRRect>(
        find.byKey(const ValueKey('finish-seam-clip')),
      );
      expect(clip.clipper, isNotNull);
      final seam = find.byWidgetPredicate(
        (w) => w is FinishPaint && w.part == FinishPart.seam,
      );
      expect(seam, findsOneWidget);
      final stack = t.widget<Stack>(
        find.ancestor(of: seam, matching: find.byType(Stack)).first,
      );
      expect(
        (stack.children.last as Positioned).child,
        isA<IgnorePointer>(),
        reason: 'the stitches are the top layer',
      );
    });

    testWidgets('Leather keeps its content inside the seam too', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(
            'royal_navy',
            appearance: const AppearancePreferences(finish: 'leather'),
          ),
          home: const Scaffold(
            body: FinishSurface(child: SizedBox(width: 200, height: 100)),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('finish-seam-clip')), findsOneWidget);
    });
  });

  group('the textures', () {
    test('every texture is bundled, small, and credited as CC0', () {
      final credits =
          (jsonDecode(File('assets/finish/credits.json').readAsStringSync())
                  as List)
              .cast<Map>();
      final ids = {for (final c in credits) c['id']};
      expect(ids, finishTextureNames, reason: 'one credit for each texture');
      var total = 0;
      for (final name in finishTextureNames) {
        final file = File('assets/finish/$name.jpg');
        expect(file.existsSync(), isTrue, reason: name);
        total += file.lengthSync();
        expect(file.lengthSync(), lessThan(700 * 1024), reason: name);
      }
      expect(total, lessThan(4 * 1024 * 1024), reason: 'the set is small');
      final files = Directory(
        'assets/finish',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.jpg'));
      expect(files.length, finishTextureNames.length, reason: 'no extras');
      for (final c in credits) {
        expect(c['license'], 'CC0', reason: '${c['id']}');
        expect('${c['author']}', isNotEmpty);
        expect('${c['title']}', isNotEmpty);
        final source = '${c['source']}';
        expect(
          source.startsWith('https://polyhaven.com/a/') ||
              source.startsWith('Made for this app'),
          isTrue,
          reason: source,
        );
      }
      final doc = File('docs/FINISH-TEXTURES.md').readAsStringSync();
      for (final c in credits) {
        expect(doc, contains('${c['title']}'), reason: '${c['id']}');
      }
    });

    testWidgets('every texture decodes', (t) async {
      for (final name in finishTextureNames) {
        expect(FinishTextures.instance.image(name), isNotNull, reason: name);
      }
    });

    testWidgets('Texture credits lists every texture', (t) async {
      setScreen(t, const Size(430, 900));
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byType(NavigationDestination).at(4));
      await t.pumpAndSettle();
      await t.tap(find.text('Appearance'));
      await t.pumpAndSettle();
      final list = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('finish-credits')),
        300,
        scrollable: list,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('finish-credits')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pumpAndSettle();
      expect(find.text('Texture credits'), findsWidgets);
      expect(find.text('Red Brick 03'), findsOneWidget);
      expect(find.textContaining('Rob Tuytel'), findsWidgets);
    });
  });
}

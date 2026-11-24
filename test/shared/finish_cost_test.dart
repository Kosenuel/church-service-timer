import 'dart:io';
import 'dart:ui' as ui;

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../live/screen_sizes_test.dart' show DesktopPort, sunday;

/// What a finish costs the GPU on every frame while the app is used (a
/// scroll, a page sliding in), which finish_performance_test does not see:
/// that test holds that nothing is recorded again, but what was recorded is
/// still drawn on every frame (Impeller keeps no raster cache). In
/// 0.39.0-beta.2 every panel drew its shadow, its material and its edge
/// each over its whole area (Plastic two more, for its gloss), so a page
/// cost several full passes over the window per frame on top of Flat; on a
/// weak integrated GPU that was the lag. Now a panel covers its area once,
/// and its shadow and edge are thin bands.
///
/// Run with FINISH_COST=1 to print what each page costs to open, to scroll
/// and to draw (a frame rasterised in this test runner, on the CPU).
void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);
  final report = Platform.environment['FINISH_COST'] == '1';
  const desktop = Size(1366, 768);
  const everyFinish = [
    'cashmere',
    'denim',
    'leather',
    'glass',
    'walnut',
    'oak',
    'plastic',
    'console',
    'carbon',
    'marble',
    'brick',
    'papery',
  ];

  Future<(AppController, DesktopPort)> app(
    WidgetTester t,
    String finish, {
    int programs = 0,
    int reports = 0,
  }) async {
    setScreen(t, desktop);
    final port = DesktopPort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((d, _) {
      d.themeId = finish == 'papery' ? 'paper_ink' : 'royal_navy';
      d.appearance = d.appearance.copyWith(
        finish: finish == 'papery' ? 'flat' : finish,
        finishStrength: 'full',
        desktopLayout: 'mission_control',
      );
      for (var p = 0; p < programs; p++) {
        d.saveTemplate(
          Timeline('Program ${p + 1}', [
            for (var s = 0; s < 8; s++)
              Segment('Segment ${s + 1}', 1 + s % 9, speaker: 'Speaker'),
          ], DisplaySettings()),
        );
      }
    });
    for (var r = 0; r < reports; r++) {
      await c.act('load', value: sunday());
      await c.act('start');
      port.at = after(60 + r);
      await c.act('end');
    }
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  Future<void> open(WidgetTester t, String page) async {
    await t.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('navigation-rail')),
            matching: find.text(page),
          )
          .first,
    );
    await t.pumpAndSettle();
  }

  /// The area each call of [box]'s drawing covers, as a share of the box:
  /// a band (a shadow, an edge, a fade) is drawn as triangles and counted
  /// as none here; the test below checks that they leave the middle clear.
  List<(Symbol, double)> coverage(RenderFinishPaint box) {
    final canvas = TestRecordingCanvas();
    box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
    final whole = box.size.width * box.size.height;
    double area(Rect r) => r.width * r.height;
    return [
      for (final i in canvas.invocations)
        if (!const {
          #save,
          #restore,
          #translate,
          #scale,
        }.contains(i.invocation.memberName))
          (
            i.invocation.memberName,
            switch (i.invocation.memberName) {
                  #drawRect => area(i.invocation.positionalArguments[0]),
                  #drawRRect => area(
                    (i.invocation.positionalArguments[0] as RRect).outerRect,
                  ),
                  #drawDRRect =>
                    area(
                          (i.invocation.positionalArguments[0] as RRect)
                              .outerRect,
                        ) -
                        area(
                          (i.invocation.positionalArguments[1] as RRect)
                              .outerRect,
                        ),
                  #drawImageRect => area(i.invocation.positionalArguments[2]),
                  #drawImageNine => area(i.invocation.positionalArguments[2]),
                  #drawPaint || #drawColor => whole,
                  _ => 0.0,
                } /
                whole,
          ),
    ];
  }

  group('each panel covers its area once per frame', () {
    for (final finish in everyFinish) {
      testWidgets(finish, (t) async {
        await app(t, finish);
        for (final page in ['Live', 'Programs', 'Settings']) {
          await open(t, page);
          final boxes = t
              .renderObjectList<RenderFinishPaint>(find.byType(FinishPaint))
              .where((b) => b.hasSize && b.size.width * b.size.height > 4000);
          expect(boxes, isNotEmpty);
          for (final box in boxes) {
            if (box.part == FinishPart.wall) continue;
            final calls = coverage(box);
            final names = [for (final (m, _) in calls) m];
            expect(names, isNot(contains(#drawImageNine)), reason: finish);
            final whole = calls.where((c) => c.$2 > .5).length;
            // The material; on brushed steel its sheen and on Glass its
            // frost, which lie over the whole panel.
            final allowed = switch (box.part) {
              FinishPart.panel =>
                finish == 'console' || finish == 'glass' ? 2 : 1,
              _ => 0,
            };
            expect(
              whole,
              lessThanOrEqualTo(allowed),
              reason: '$finish $page ${box.part}: $calls',
            );
          }
        }
      });
    }
  });

  group('the edge, the fade and the shadow leave the middle undrawn', () {
    Future<List<int>> pixels(WidgetTester t, String finish, Widget w) async {
      final key = GlobalKey();
      await t.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: appTheme(
              'royal_navy',
              appearance: AppearancePreferences(
                finish: finish,
                finishStrength: 'full',
              ),
            ),
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: const Color(0xffff0000),
                  child: SizedBox(width: 300, height: 200, child: w),
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

    for (final finish in ['plastic', 'walnut', 'console', 'denim', 'glass']) {
      testWidgets(finish, (t) async {
        for (final part in [FinishPart.seam, FinishPart.edge]) {
          final px = await pixels(
            t,
            finish,
            Builder(
              builder: (context) => FinishPaint(
                look: finishLook(context),
                part: part,
                corners: BorderRadius.circular(finishRadius(finish)),
              ),
            ),
          );
          // The middle is the red under it; the edge is drawn.
          expect(px[100 * 300 + 150], 0xff0000, reason: '$finish $part');
          expect(px[100 * 300], isNot(0xff0000), reason: '$finish $part');
        }
      });
    }
  });

  testWidgets('opening a page seen before and scrolling a long list make '
      'no new images', (t) async {
    await app(t, 'plastic', programs: 40, reports: 30);
    for (final page in ['Programs', 'Slides', 'Reports', 'Settings', 'Live']) {
      await open(t, page);
    }
    final images = FinishPaintCount.images;
    for (final page in ['Programs', 'Slides', 'Reports', 'Settings', 'Live']) {
      await open(t, page);
      expect(FinishPaintCount.images, images, reason: page);
    }
    for (final page in ['Programs', 'Reports']) {
      await open(t, page);
      final paints = FinishPaintCount.total;
      for (final dy in const <double>[-300, -300, -300, 300, 300, 300]) {
        await t.drag(
          find.byType(Scrollable).hitTestable().first,
          Offset(0, dy),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 16));
      }
      await t.pumpAndSettle();
      expect(FinishPaintCount.images, images, reason: '$page scrolled');
      expect(FinishPaintCount.total, paints, reason: '$page scrolled');
    }
  });

  testWidgets('a finish keeps its images small on a dense screen', (t) async {
    // A phone or a 4K monitor at 200%: the tiles are never made larger than
    // the photographs they come from.
    for (final finish in everyFinish) {
      t.view.devicePixelRatio = 3;
      t.view.physicalSize = const Size(1080, 2340);
      addTearDown(t.view.reset);
      final before = FinishPaintCount.imageBytes;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(
            finish == 'papery' ? 'paper_ink' : 'royal_navy',
            appearance: AppearancePreferences(
              finish: finish == 'papery' ? 'flat' : finish,
              finishStrength: 'full',
            ),
          ),
          home: const FinishWall(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: FinishSurface(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await t.pump();
      final mb = (FinishPaintCount.imageBytes - before) / (1024 * 1024);
      expect(mb, lessThan(14), reason: '$finish: ${mb.toStringAsFixed(1)} MB');
    }
  });

  // The numbers, for a person to read.
  Future<double> raster(WidgetTester t) async {
    final view = t.binding.renderViews.first;
    final times = <int>[];
    for (var i = 0; i < 7; i++) {
      final w = Stopwatch()..start();
      await t.runAsync(() async {
        final image = await (view.debugLayer! as OffsetLayer).toImage(
          Offset.zero & desktop,
        );
        await image.toByteData();
        image.dispose();
      });
      times.add(w.elapsedMicroseconds);
    }
    times.sort();
    return times[times.length ~/ 2] / 1000;
  }

  for (final finish in ['flat', ...everyFinish]) {
    testWidgets('cost: $finish', skip: !report, (t) async {
      await app(t, finish, programs: 40, reports: 30);
      final lines = <String>[];
      for (final page in [
        'Programs',
        'Slides',
        'Reports',
        'Settings',
        'Live',
      ]) {
        final p0 = FinishPaintCount.total, i0 = FinishPaintCount.images;
        final b0 = FinishPaintCount.imageBytes;
        final w = Stopwatch()..start();
        await open(t, page);
        final cpu = w.elapsedMilliseconds;
        final ms = await raster(t);
        lines.add(
          '$finish $page: raster ${ms.toStringAsFixed(1)} ms | open: cpu '
          '$cpu ms, ${FinishPaintCount.total - p0} paints, '
          '${FinishPaintCount.images - i0} images '
          '(${(FinishPaintCount.imageBytes - b0) ~/ 1024} KB)',
        );
      }
      // ignore: avoid_print
      print(lines.join('\n'));
    });
  }
}

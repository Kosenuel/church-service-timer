import 'dart:ui' as ui;
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_pickers.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/finish_popups.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import '../live/screen_sizes_test.dart' show DesktopPort, sunday;

/// Dialogs, sheets, menus, pickers and the Commands palette take the finish
/// (FinishPopupFrame): their sheet is laid on the panel material, edge and
/// shadow, with a stitched finish's stitches, from one place, so every
/// popup opened on a page has it. Flat keeps them as they were.
void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<(AppController, FakePort)> live(
    WidgetTester t,
    String finish, {
    Size size = const Size(1366, 768),
    String theme = 'royal_navy',
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

  /// The popup frames showing now that found a sheet to lay material under.
  List<RenderFinishPopupFrame> framed(WidgetTester t) => [
    for (final r
        in t.allRenderObjects.whereType<RenderFinishPopupFrame>().toSet())
      if (r.sheet != null) r,
  ];

  Future<void> endService(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('end-service')).first);
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
  }

  group('every popup takes the finish', () {
    for (final finish in ['denim', 'console', 'glass', 'walnut']) {
      testWidgets('$finish: the End service question', (t) async {
        await live(t, finish);
        await endService(t);
        final frames = framed(t);
        expect(frames, hasLength(1));
        final frame = frames.single;
        // The material is laid exactly under the dialog's sheet.
        final dialog = t.renderObject<RenderBox>(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        );
        final sheet = frame.sheet!;
        expect(
          sheet.localToGlobal(Offset.zero) & sheet.size,
          dialog.localToGlobal(Offset.zero) & dialog.size,
        );
        expect(frame.panel.size, sheet.size);
        expect(frame.panel.look.id, finish);
        // The sheet itself is clear, with no shadow of its own.
        final material = t.widget<Material>(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.color, finishPopupColor);
        expect(material.elevation, 0);
      });
    }

    testWidgets('the header menu', (t) async {
      await live(t, 'denim');
      await t.tap(find.byIcon(Icons.more_vert).first);
      await t.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(framed(t), hasLength(1));
      expect(framed(t).single.stitches.look.id, 'denim');
    });

    testWidgets('the Commands palette', (t) async {
      await live(t, 'leather');
      await t.tap(find.byIcon(Icons.more_vert).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Commands'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
      expect(framed(t), hasLength(1));
      final palette = t.renderObject<RenderBox>(
        find.byKey(const ValueKey('command-palette')),
      );
      expect(framed(t).single.sheet!.size.width, lessThan(palette.size.width));
    });

    testWidgets('a bottom sheet on a phone', (t) async {
      await live(t, 'oak', size: const Size(360, 780));
      await t.tap(find.text('Welcome').first);
      await t.pumpAndSettle();
      expect(find.text('Jump to segment'), findsOneWidget);
      final frame = framed(t).single;
      final sheet = frame.sheet!;
      // A sheet rounds its top corners only.
      expect(frame.panel.corners.bottomLeft, Radius.zero);
      expect(frame.panel.corners.topLeft.x, greaterThan(0));
      expect(sheet.localToGlobal(Offset.zero).dy, greaterThan(100));
    });

    testWidgets('a date picker', (t) async {
      setScreen(t, const Size(1366, 768));
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(
            'warm_ivory',
            appearance: const AppearancePreferences(finish: 'marble'),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppDatePicker(
                  context,
                  initialDate: DateTime(2026, 11, 22),
                  firstDate: DateTime(2026),
                  lastDate: DateTime(2027),
                ),
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Pick'));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(framed(t), hasLength(1));
    });

    testWidgets('a dialog opened from a dialog', (t) async {
      setScreen(t, const Size(800, 600));
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(
            'royal_navy',
            appearance: const AppearancePreferences(finish: 'brick'),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('First'),
                    actions: [
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              const AlertDialog(title: Text('Second')),
                        ),
                        child: const Text('More'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.tap(find.text('More'));
      await t.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(framed(t), hasLength(2));
    });

    testWidgets('snack bars and tooltips take the panel colour', (t) async {
      final theme = appTheme(
        'royal_navy',
        appearance: const AppearancePreferences(finish: 'denim'),
      );
      final look = theme.extension<FinishLook>()!;
      expect(theme.snackBarTheme.backgroundColor, look.panel);
      expect(
        (theme.tooltipTheme.decoration! as BoxDecoration).color,
        look.panel,
      );
      expect(theme.popupMenuTheme.color, look.panel);
      // Flat keeps Flutter's own.
      final flat = appTheme('royal_navy');
      expect(flat.snackBarTheme.backgroundColor, isNull);
      expect(flat.tooltipTheme.decoration, isNull);
    });
  });

  group('Flat popups are as they were', () {
    testWidgets('no frame, and the theme\'s own colour', (t) async {
      await live(t, 'flat');
      await endService(t);
      expect(find.byType(FinishPopupFrame), findsNothing);
      expect(find.byType(FinishPopups), findsNothing);
      final material = t.widget<Material>(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, isNot(finishPopupColor));
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.more_vert).first);
      await t.pumpAndSettle();
      expect(find.byType(FinishPopupFrame), findsNothing);
    });
  });

  group('the material of a popup is cheap', () {
    for (final finish in ['denim', 'console', 'glass']) {
      testWidgets('$finish: drawn once while the clock ticks under it', (
        t,
      ) async {
        final (c, port) = await live(t, finish);
        await endService(t);
        final before = FinishPaintCount.total;
        for (var i = 1; i <= 8; i++) {
          port.at = after(i);
          await c.tick();
          await t.pump(const Duration(seconds: 1));
        }
        expect(FinishPaintCount.total, before, reason: 'a surface drew again');
        // And what it draws is images only.
        for (final box in [
          for (final f in framed(t)) ...[f.panel, f.stitches],
        ]) {
          if (!box.hasSize) continue;
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
          expect(draws.length, lessThanOrEqualTo(10), reason: '$calls');
        }
      });
    }

    testWidgets('a menu opening does not leave the material behind', (t) async {
      await live(t, 'denim');
      await t.tap(find.byIcon(Icons.more_vert).first);
      // Part way through the menu growing, then when it has settled.
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpAndSettle();
      final frame = framed(t).single;
      expect(frame.panel.size, frame.sheet!.size);
    });
  });

  group('the destructive button stays red on the material', () {
    for (final finish in ['console', 'plastic']) {
      testWidgets('End service in the question, $finish', (t) async {
        await live(t, finish);
        await endService(t);
        final button = find.ancestor(
          of: find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('End service'),
          ),
          matching: find.byType(FilledButton),
        );
        final rect = t.getRect(button);
        // The whole window, dialog and all.
        final view = t.binding.renderViews.first;
        final pixel = await t.runAsync(() async {
          final image = await (view.debugLayer! as OffsetLayer).toImage(
            Offset.zero & view.size,
          );
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final x = (rect.left + 6).round(), y = rect.center.dy.round();
          final i = (y * image.width + x) * 4;
          return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
        });
        final red = destructiveColor.toARGB32();
        final want = [(red >> 16) & 255, (red >> 8) & 255, red & 255];
        for (var k = 0; k < 3; k++) {
          expect(
            (pixel![k] - want[k]).abs(),
            lessThanOrEqualTo(8),
            reason: '$finish: channel $k is ${pixel[k]}, wanted ${want[k]}',
          );
        }
      });
    }
  });
}

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'screen_sizes_test.dart' show DesktopPort, sunday;

/// Every finish on Live and on Settings, in a dark and a light theme, at both
/// strengths, on a computer and a phone. Run with
/// `--dart-define=FINISH_SCRATCH=<dir>` to write the whole matrix there (for
/// looking at); the committed goldens are a smaller set that covers each
/// finish, both strengths and both themes.
const scratch = String.fromEnvironment('FINISH_SCRATCH');
const only = String.fromEnvironment('FINISH_ONLY');

const dark = 'royal_navy', light = 'warm_ivory';
final finishes = [
  for (final id in finishIds)
    if (id != 'flat') id,
];

void main() {
  setUpAll(loadAppFonts);
  // The photographs, decoded before any test draws, so every shot shows
  // them (decoding cannot finish inside a test's fake clock).
  setUpAll(FinishTextures.instance.loadAll);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<AppController> start(
    WidgetTester t, {
    required Size size,
    required String theme,
    required String finish,
    required String strength,
    bool live = true,
    double textScale = 1,
    String layout = 'mission_control',
    Size? crop,
  }) async {
    setScreen(t, size);
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final port = size.width >= 1200 ? DesktopPort() : FakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.themeId = theme;
      draft.appearance = draft.appearance.copyWith(
        desktopLayout: layout,
        finish: finish,
        finishStrength: strength,
      );
    });
    if (live) {
      await c.act('load', value: sunday());
      await c.act('start');
      var at = 0;
      for (var i = 0; i < 2; i++) {
        at += 60;
        port.at = after(at);
        await c.tick();
        await c.act('advance');
      }
      port.at = after(at + 2);
      await c.tick();
    }
    // A corner of the window, for goldens: texture does not compress, so the
    // whole window would make a very large file.
    await t.pumpWidget(
      crop == null
          ? TimerApp(controller: c)
          : Align(
              alignment: Alignment.topLeft,
              child: SizedBox.fromSize(
                size: crop,
                child: RepaintBoundary(
                  key: const ValueKey('crop'),
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: size.width,
                      maxWidth: size.width,
                      minHeight: size.height,
                      maxHeight: size.height,
                      child: TimerApp(controller: c),
                    ),
                  ),
                ),
              ),
            ),
    );
    await t.pumpAndSettle();
    return c;
  }

  Future<void> shot(WidgetTester t, String name, {bool always = false}) async {
    expect(t.takeException(), isNull);
    final path = scratch.isEmpty
        ? '../goldens/finish/$name.png'
        : '$scratch/$name.png';
    final crop = find.byKey(const ValueKey('crop'));
    await expectLater(
      crop.evaluate().isNotEmpty ? crop : find.byType(TimerApp),
      matchesGoldenFile(path),
    );
  }

  bool wanted(String finish) =>
      only.isEmpty || only.split(',').contains(finish);
  const desktop = Size(1366, 768), phone = Size(360, 780);

  for (final finish in finishes) {
    if (!wanted(finish)) continue;
    for (final strength in finishStrengths) {
      for (final (theme, tone) in [(dark, 'dark'), (light, 'light')]) {
        // Committed: a corner of Live on a computer in the dark theme at Full
        // for every finish, and Live on a phone in the light theme at Subtle
        // for three; the rest only to look at.
        final keepDesktop = tone == 'dark' && strength == 'full';
        final keepPhone =
            tone == 'light' &&
            strength == 'subtle' &&
            const ['console', 'denim', 'marble'].contains(finish);
        testWidgets('$finish $strength $tone on a computer', (t) async {
          if (scratch.isEmpty && !keepDesktop) return;
          await start(
            t,
            size: desktop,
            theme: theme,
            finish: finish,
            strength: strength,
            crop: scratch.isEmpty ? const Size(560, 315) : null,
          );
          await shot(t, 'live-$finish-$strength-$tone-1366');
        });
        testWidgets('$finish $strength $tone on a phone', (t) async {
          if (scratch.isEmpty && !keepPhone) return;
          await start(
            t,
            size: phone,
            theme: theme,
            finish: finish,
            strength: strength,
          );
          await shot(t, 'live-$finish-$strength-$tone-phone');
        });
        // Settings and the lists behind the other tabs on a phone, and the
        // Appearance page with the Finish tiles themselves.
        for (final (name, tab) in [
          ('settings', 4),
          ('programs', 1),
          ('reports', 3),
        ]) {
          testWidgets('$finish $strength $tone $name', (t) async {
            if (scratch.isEmpty) return;
            await start(
              t,
              size: phone,
              theme: theme,
              finish: finish,
              strength: strength,
            );
            await t.tap(find.byType(NavigationDestination).at(tab));
            await t.pumpAndSettle();
            await shot(t, '$name-$finish-$strength-$tone-phone');
          });
        }
      }
    }
  }

  // Papery: the finish that comes with the Paper & Ink themes, whatever
  // finish is saved (here Flat, to show the theme alone brings it).
  for (final theme in ['paper_ink', 'paper_ink_blue']) {
    for (final strength in finishStrengths) {
      testWidgets('Papery $theme $strength on a computer', (t) async {
        final keep = theme == 'paper_ink' && strength == 'full';
        if (scratch.isEmpty && !keep) return;
        await start(
          t,
          size: desktop,
          theme: theme,
          finish: 'flat',
          strength: strength,
          crop: scratch.isEmpty ? const Size(560, 315) : null,
        );
        await shot(t, 'live-papery-$theme-$strength-1366');
      });
      for (final (name, tab) in [
        ('live', -1),
        ('settings', 4),
        ('programs', 1),
        ('reports', 3),
      ]) {
        testWidgets('Papery $theme $strength $name on a phone', (t) async {
          final keep = theme == 'paper_ink' && strength == 'full' && tab == -1;
          if (scratch.isEmpty && !keep) return;
          await start(
            t,
            size: phone,
            theme: theme,
            finish: 'flat',
            strength: strength,
          );
          if (tab >= 0) {
            await t.tap(find.byType(NavigationDestination).at(tab));
            await t.pumpAndSettle();
          }
          await shot(t, 'papery-$theme-$strength-$name-phone');
        });
      }
    }
    testWidgets('the Finish section of $theme is a note', (t) async {
      if (scratch.isEmpty && theme != 'paper_ink') return;
      await start(
        t,
        size: phone,
        theme: theme,
        finish: 'brick',
        strength: 'subtle',
        live: false,
      );
      await t.tap(find.byType(NavigationDestination).at(4));
      await t.pumpAndSettle();
      await t.tap(find.text('Appearance'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('finish-title')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('finish-papery-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('finish-brick')), findsNothing);
      expect(find.byKey(const ValueKey('finish-strength')), findsOneWidget);
      if (scratch.isEmpty) return;
      await shot(t, 'papery-appearance-note-$theme');
    });
  }

  // Every desktop layout, in a few window sizes and at larger text, draws in
  // a finish without overflowing, and the cues and Pause stay in view.
  for (final layout in [
    'mission_control',
    'three_panes',
    'dial',
    'keys',
    'classic',
  ]) {
    for (final finish in ['brick', 'console', 'glass', 'oak', 'denim']) {
      for (final size in const [
        Size(1366, 768),
        Size(1280, 720),
        Size(1920, 1080),
      ]) {
        if (!wanted(finish)) continue;
        testWidgets(
          '$layout in $finish at ${size.width.toInt()}x${size.height.toInt()}',
          (t) async {
            final c = await start(
              t,
              size: size,
              theme: dark,
              finish: finish,
              strength: 'full',
              layout: layout,
            );
            expect(t.takeException(), isNull);
            expect(find.byType(FilledButton), findsWidgets);
            final pause = find.text('Pause');
            expect(pause, findsWidgets);
            final r = t.getRect(pause.first);
            expect(
              r.bottom,
              lessThanOrEqualTo(size.height),
              reason: 'Pause is in the window',
            );
            expect(c.state.appearance.finish, finish);
            if (scratch.isNotEmpty && size.width == 1366) {
              await shot(t, 'layout-$layout-$finish');
            }
          },
        );
      }
    }
  }

  // A destructive button keeps its danger colour in every finish: the keycap
  // and gloss of Console and Plastic only shade it.
  for (final finish in [...finishes, 'papery']) {
    testWidgets('End service is red in $finish', (t) async {
      await start(
        t,
        size: desktop,
        theme: finish == 'papery' ? 'paper_ink' : dark,
        finish: finish == 'papery' ? 'flat' : finish,
        strength: 'full',
      );
      final button = find.byKey(const ValueKey('end-service'));
      expect(button, findsOneWidget);
      final rect = t.getRect(button);
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final pixel = await t.runAsync(() async {
        final image = await boundary.toImage();
        final data = (await image.toByteData())!;
        final x = (rect.left + 5).round(), y = rect.center.dy.round();
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

  // The Finish section of Appearance, in the dark and the light theme, on a
  // phone, at larger text, and in a wide window with the preview beside it.
  for (final (theme, tone) in [(dark, 'dark'), (light, 'light')]) {
    for (final (size, scale, name) in [
      (phone, 1.0, 'phone'),
      (phone, 1.6, 'phone-text-1.6'),
      (desktop, 1.0, '1366'),
    ]) {
      testWidgets('the Finish tiles in $tone at $name', (t) async {
        await start(
          t,
          size: size,
          theme: theme,
          finish: 'walnut',
          strength: 'full',
          live: false,
          textScale: scale,
        );
        if (size.width < 840) {
          await t.tap(find.byType(NavigationDestination).at(4));
        } else {
          await t.tap(
            find.descendant(
              of: find.byKey(const ValueKey('navigation-rail')),
              matching: find.text('Settings'),
            ),
          );
        }
        await t.pumpAndSettle();
        await t.tap(find.text('Appearance'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byKey(const ValueKey('finish-title')),
          300,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        // Larger text is checked for fit; its picture only to look at.
        if (scratch.isEmpty && scale != 1) return;
        await shot(t, 'appearance-finish-$tone-$name');
      });
    }
  }
}

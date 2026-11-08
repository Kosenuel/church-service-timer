import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/display/pixels.dart';
import 'package:church_service_timer/display/square_matrix_font.dart';
import '../support/fake_port.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
  });

  test(
    'Sq-Matrix is a separate complete font with compact and integer-doubled tall pixels',
    () {
      final asset = jsonDecode(
        File('assets/pixel_fonts/i-proton_sq_matrix.json').readAsStringSync(),
      );
      expect(asset['glyphs'], squareGlyphs);
      expect(squareGlyphs.keys.toSet(), glyphs.keys.toSet());
      expect(
        textWidth(const TextLayout('WRAP', font: 'i-proton_sq_matrix')),
        20,
      );
      expect(textWidth(const TextLayout('WRAP')), 23);
      final tall = renderPixels(
        const TextLayout(
          'A',
          font: 'i-proton_sq_matrix',
          height: 2,
          align: 'left',
        ),
        0,
      );
      final rows = squareGlyphs['A']!.split('/');
      for (var y = 0; y < 14; y++) {
        for (var x = 0; x < 8; x++) {
          expect(tall[(y + 1) * 32 + x], rows[y ~/ 2][x ~/ 2] == '1');
        }
      }
      for (final char in squareGlyphs.keys.where((c) => c != ' ')) {
        for (final height in [1, 2]) {
          for (final bold in [false, true]) {
            for (final italic in [false, true]) {
              final l = TextLayout(
                char,
                font: 'i-proton_sq_matrix',
                height: height,
                bold: bold,
                italic: italic,
              );
              validateLayout(l);
              expect(renderPixels(l, 0).where((p) => p), isNotEmpty);
            }
          }
        }
      }
    },
  );

  testWidgets(
    'LED shape selection persists and is inherited by Live and dialog previews',
    (t) async {
      t.view.physicalSize = const Size(700, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      final before = [...c.simulator.pixels];
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('Display settings'));
      await t.pumpAndSettle();
      await t.tap(find.text('LED preview shape'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Circular LEDs'));
      await t.tap(find.text('Circular LEDs'));
      await t.pumpAndSettle();
      expect(c.state.pixelShape, 'circular');
      expect(c.simulator.pixels, before);
      expect(
        LedAppearance.of(t.element(find.byType(LedMatrix).first)),
        'circular',
      );
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Live'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Manage cues'));
      await t.pumpAndSettle();
      await t.tap(find.text('Manage cues'));
      await t.pumpAndSettle();
      await t.tap(find.text('New cue'));
      await t.pump(const Duration(milliseconds: 300));
      expect(
        LedAppearance.of(
          t.element(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(LedMatrix),
                )
                .first,
          ),
        ),
        'circular',
      );
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.stageCues.length, 3);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = AppController(port);
      await restored.initialize(startTicker: false);
      expect(restored.state.pixelShape, 'circular');
      restored.dispose();
    },
  );

  testWidgets('Square and circular LED font comparison', (t) async {
    t.view.physicalSize = const Size(760, 1040);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Widget sample(
      String title,
      String font,
      String shape,
      String text, {
      int height = 1,
    }) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: LedAppearance(
                  shape: shape,
                  child: LedMatrix(
                    pixels: renderPixels(
                      TextLayout(text, font: font, height: height),
                      0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                sample(
                  'Original I-Proton Matrix · square LEDs · 7 px',
                  'i-proton_matrix',
                  'square',
                  'Amen',
                ),
                sample(
                  'I-Proton Sq-Matrix · square LEDs · 7 px',
                  'i-proton_sq_matrix',
                  'square',
                  'Amen',
                ),
                sample(
                  'I-Proton Sq-Matrix · circular LEDs · 7 px',
                  'i-proton_sq_matrix',
                  'circular',
                  'Amen',
                ),
                sample(
                  'I-Proton Sq-Matrix · square LEDs · 14 px',
                  'i-proton_sq_matrix',
                  'square',
                  'GO',
                  height: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/display-fonts.png'),
    );
    await t.pumpWidget(const SizedBox());
  });
}

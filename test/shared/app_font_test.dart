import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/pairing/stage_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/widget_setup.dart';

/// Every platform draws the app's text in the Roboto the app ships. Without
/// a font in the theme, Windows used Segoe UI, whose letters are a different
/// width from the Roboto that every layout test and screenshot uses.
void main() {
  setUpAll(loadAppFonts);

  List<TextStyle?> styles(TextTheme t) => [
    t.displayLarge,
    t.displayMedium,
    t.displaySmall,
    t.headlineLarge,
    t.headlineMedium,
    t.headlineSmall,
    t.titleLarge,
    t.titleMedium,
    t.titleSmall,
    t.bodyLarge,
    t.bodyMedium,
    t.bodySmall,
    t.labelLarge,
    t.labelMedium,
    t.labelSmall,
  ];

  test('the app font is the Roboto the stage screens use', () {
    expect(appFontFamily, 'Roboto');
    expect(appFontFamily, stageFontFamily);
  });

  for (final platform in TargetPlatform.values) {
    test('every text style is Roboto when the platform is $platform', () {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final id in ['midnight_lime', 'paper_ink']) {
        final theme = appTheme(id);
        for (final t in [theme.textTheme, theme.primaryTextTheme]) {
          for (final style in styles(t)) {
            expect(style?.fontFamily, 'Roboto', reason: '$platform $id');
          }
        }
      }
    });
  }

  testWidgets('plain text in the app is drawn in Roboto on Windows', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme('midnight_lime'),
          home: const Scaffold(
            body: Column(
              children: [
                Text('Custom'),
                TextField(),
                Tooltip(message: 'Tip', child: Text('Next')),
              ],
            ),
          ),
        ),
      );
      for (final text in ['Custom', 'Next']) {
        final run = tester.widget<RichText>(
          find.descendant(of: find.text(text), matching: find.byType(RichText)),
        );
        final style = DefaultTextStyle.of(tester.element(find.text(text)));
        expect(
          run.text.style?.fontFamily ?? style.style.fontFamily,
          'Roboto',
          reason: text,
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

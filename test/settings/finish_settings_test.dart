import 'dart:convert';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/finish.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the saved choice', () {
    test(
      'a new install, and a look saved before finishes, is Flat and Subtle',
      () {
        expect(const AppearancePreferences().finish, 'flat');
        expect(const AppearancePreferences().finishStrength, 'subtle');
        final old = AppearancePreferences.fromJson({
          'density': 'spacious',
          'dividers': 'strong',
          'desktopLayout': 'classic',
        });
        expect(old.finish, 'flat');
        expect(old.finishStrength, 'subtle');
        expect(old.density, 'spacious');
      },
    );

    test('every finish and strength survives saving and loading', () {
      for (final id in finishIds) {
        for (final strength in finishStrengths) {
          final a = AppState.fresh(start)
            ..appearance = AppearancePreferences(
              finish: id,
              finishStrength: strength,
            );
          final copy = AppState.fromJson(jsonDecode(jsonEncode(a.toJson())));
          expect(copy.appearance.finish, id);
          expect(copy.appearance.finishStrength, strength);
          expect(copy.appearance, a.appearance);
        }
      }
    });

    test('state written before finishes existed loads as Flat', () {
      final old = AppState.fresh(start).toJson();
      final appearance = Map<String, dynamic>.from(old['appearance'] as Map)
        ..remove('finish')
        ..remove('finishStrength');
      old['appearance'] = appearance;
      final state = AppState.fromJson(old);
      expect(state.appearance.finish, 'flat');
      expect(state.appearance.finishStrength, 'subtle');
    });

    test(
      'a finish this version does not know draws as Flat instead of failing the load',
      () {
        final later = AppearancePreferences.fromJson({
          'finish': 'holographic',
          'finishStrength': 'extreme',
        });
        expect(later.finish, 'flat');
        expect(later.finishStrength, 'subtle');
        expect(finishValue(7), 'flat');
      },
    );

    test('every finish has a name and a one-line description', () {
      expect(finishIds.first, 'flat');
      expect(finishIds.toSet().length, finishIds.length);
      for (final id in finishIds) {
        expect(finishName(id), isNotEmpty);
        expect(finishDescription(id), isNotEmpty);
        expect(finishDescription(id), isNot(contains('\n')));
      }
      expect(finishName('console'), 'Bridge console');
    });

    test(
      'a saved look keeps its finish, and one saved before finishes is Flat',
      () {
        const look = SavedLook(
          name: 'Stone',
          layout: 'classic',
          themeId: 'royal_navy',
          finish: 'marble',
          finishStrength: 'full',
        );
        final back = SavedLook.fromJson(
          Map<String, dynamic>.from(jsonDecode(jsonEncode(look.toJson()))),
        );
        expect(back.finish, 'marble');
        expect(back.finishStrength, 'full');
        final applied = look.applyTo(const AppearancePreferences());
        expect(applied.finish, 'marble');
        expect(applied.finishStrength, 'full');
        expect(SavedLook.of('Now', applied, 'royal_navy').finish, 'marble');
        final old = SavedLook.fromJson({
          'name': 'Old',
          'layout': 'classic',
          'themeId': 'royal_navy',
          'density': 'automatic',
          'keyHints': 'automatic',
          'highContrast': false,
        });
        expect(old.finish, 'flat');
        expect(old.finishStrength, 'subtle');
        // A plain look is written as before, so its backup opens in an
      // earlier version.
      expect(old.toJson().containsKey('finish'), isFalse);
      expect(old.toJson().containsKey('finishStrength'), isFalse);
      // Reset to the default look puts the plain panels back.
        expect(defaultLook.applyTo(applied).finish, 'flat');
      },
    );
  });

  group('the theme', () {
    test('Flat is the theme as it was', () {
      final theme = appTheme('midnight_lime');
      final look = theme.extension<FinishLook>()!;
      expect(look.active, isFalse);
      expect(theme.scaffoldBackgroundColor, appPalettes.first.background);
      expect(theme.appBarTheme.backgroundColor, appPalettes.first.background);
    });

    test('High contrast draws every finish as Flat', () {
      for (final id in finishIds) {
        final theme = appTheme(
          'royal_navy',
          appearance: AppearancePreferences(
            finish: id,
            finishStrength: 'full',
            highContrast: true,
          ),
        );
        expect(theme.extension<FinishLook>()!.active, isFalse, reason: id);
        expect(
          theme.scaffoldBackgroundColor,
          isNot(Colors.transparent),
          reason: id,
        );
      }
    });

    testWidgets(
      'a panel is plain in Flat and in High contrast, and in the finish otherwise',
      (t) async {
        Widget panel(AppearancePreferences a) => MaterialApp(
          theme: appTheme('royal_navy', appearance: a),
          home: const Scaffold(body: AppPanel(child: Text('Words'))),
        );
        bool painted() => find
            .byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is FinishPanelPainter,
            )
            .evaluate()
            .isNotEmpty;
        await t.pumpWidget(panel(const AppearancePreferences()));
        await t.pumpAndSettle();
        expect(painted(), isFalse);
        await t.pumpWidget(
          panel(const AppearancePreferences(finish: 'leather')),
        );
        await t.pumpAndSettle();
        expect(painted(), isTrue);
        await t.pumpWidget(
          panel(
            const AppearancePreferences(finish: 'leather', highContrast: true),
          ),
        );
        await t.pumpAndSettle();
        expect(painted(), isFalse);
      },
    );
  });

  group('the Finish section', () {
    final sizes = [
      (const Size(360, 780), 1.0),
      (const Size(360, 780), 1.6),
      (const Size(430, 900), 1.6),
      (const Size(800, 900), 1.0),
      (const Size(1366, 768), 1.0),
      (const Size(1366, 768), 1.6),
    ];

    Future<AppController> open(WidgetTester t, Size size, double scale) async {
      setScreen(t, size);
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final port = FakePort();
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      // Settings › Appearance, as a person gets there.
      if (size.width < 840) {
        await t.tap(find.byType(NavigationDestination).at(3));
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
      // The section is below the themes: scroll the Theme tab to it.
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
      return c;
    }

    for (final (size, scale) in sizes) {
      testWidgets(
        'the tiles wrap and fit at ${size.width.toInt()} wide, text ×$scale',
        (t) async {
          await open(t, size, scale);
          expect(find.text('Finish'), findsOneWidget);
          expect(
            find.text(
              'The material of the app’s panels and background. Your theme’s colours stay as they are.',
            ),
            findsOneWidget,
          );
          final tiles = <Rect>[];
          for (final id in finishIds) {
            final tile = find.byKey(ValueKey('finish-$id'));
            await t.ensureVisible(tile);
            await t.pumpAndSettle();
            expect(tile, findsOneWidget, reason: id);
            final r = t.getRect(tile);
            expect(r.left, greaterThanOrEqualTo(0), reason: id);
            expect(r.right, lessThanOrEqualTo(size.width + .5), reason: id);
            tiles.add(r);
            // Name and description are whole, not cut.
            expect(
              find.descendant(of: tile, matching: find.text(finishName(id))),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: tile,
                matching: find.text(finishDescription(id)),
              ),
              findsOneWidget,
            );
          }
          // Tiles in one row are the same height and the same width.
          expect(t.takeException(), isNull);
          final first = t.getRect(find.byKey(const ValueKey('finish-flat')));
          final second = t.getRect(find.byKey(const ValueKey('finish-glass')));
          expect(second.top, first.top);
          expect(second.height, first.height);
          expect(second.width, first.width);
          // Never fewer than two to a row, and wide enough to read.
          expect(first.width, greaterThan(100));
          expect(first.width * 2 + 10, lessThanOrEqualTo(size.width));
        },
      );
    }

    testWidgets(
      'choosing a finish previews at once, and Save appearance keeps it',
      (t) async {
        final c = await open(t, const Size(430, 900), 1.0);
        await t.ensureVisible(find.byKey(const ValueKey('finish-brick')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('finish-brick')));
        await t.pumpAndSettle();
        expect(c.appearanceSelection.value.finish, 'brick');
        expect(c.appearanceSelection.value.finishStrength, 'subtle');
        expect(c.state.appearance.finish, 'flat');
        // The app behind the editor takes the finish's theme straight away.
        final theme = Theme.of(t.element(find.byType(AppearancePage)));
        expect(theme.extension<FinishLook>()!.id, 'brick');
        await t.ensureVisible(find.byKey(const ValueKey('finish-strength')));
        await t.pumpAndSettle();
        await t.tap(
          find.descendant(
            of: find.byKey(const ValueKey('finish-strength')),
            matching: find.text('Full'),
          ),
        );
        await t.pumpAndSettle();
        expect(c.appearanceSelection.value.finishStrength, 'full');
        await t.tap(find.text('Save appearance'));
        await t.pumpAndSettle();
        expect(c.state.appearance.finish, 'brick');
        expect(c.state.appearance.finishStrength, 'full');
      },
    );

    testWidgets('Cancel puts the saved finish back', (t) async {
      final c = await open(t, const Size(430, 900), 1.0);
      await t.ensureVisible(find.byKey(const ValueKey('finish-denim')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('finish-denim')));
      await t.pumpAndSettle();
      expect(c.appearanceSelection.value.finish, 'denim');
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.appearanceSelection.value.finish, 'flat');
    });

    testWidgets(
      'Strength is for a finish, and High contrast says it keeps panels plain',
      (t) async {
        final c = await open(t, const Size(430, 900), 1.0);
        SegmentedButton<String> strength() =>
            t.widget(find.byKey(const ValueKey('finish-strength')));
        expect(
          strength().onSelectionChanged,
          isNull,
          reason: 'Flat has no strength',
        );
        expect(find.byKey(const ValueKey('finish-plain-note')), findsNothing);
        await t.ensureVisible(find.byKey(const ValueKey('finish-oak')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('finish-oak')));
        await t.pumpAndSettle();
        expect(strength().onSelectionChanged, isNotNull);
        expect(strength().selected, {'subtle'});
        // High contrast on (set on the other tab) keeps panels plain.
        c.previewAppearance(
          c.appearanceSelection.value.copyWith(highContrast: true),
        );
        await t.pumpAndSettle();
        expect(find.byType(AppearancePage), findsOneWidget);
      },
    );
  });
}

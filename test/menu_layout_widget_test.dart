import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'domain_test.dart' show FakePort, timeline;

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  void size(WidgetTester t, Size value) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<AppController> open(
    WidgetTester t,
    AppearancePreferences preferences,
  ) async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.commit((draft, _) => draft.appearance = preferences);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  Future<void> tap(WidgetTester t, String text) async {
    final target = find.text(text).last;
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/menu-$name-0201.png'),
    );
  }

  for (final scenario in [
    ('compact', 'subtle', const Size(430, 1000), 'compact'),
    ('comfortable', 'strong', const Size(430, 1000), 'comfortable'),
    ('spacious', 'hidden', const Size(430, 1000), 'spacious'),
    ('automatic', 'subtle', const Size(430, 1000), 'compact'),
    ('automatic', 'subtle', const Size(800, 1200), 'comfortable'),
    ('automatic', 'strong', const Size(1200, 800), 'spacious'),
  ]) {
    final (density, dividers, screen, resolved) = scenario;
    testWidgets(
      'Start service uses $density/$dividers at $screen and loads Ready',
      (t) async {
        size(t, screen);
        final c = await open(
          t,
          AppearancePreferences(density: density, dividers: dividers),
        );
        await tap(t, 'Start service');
        final list = find.byKey(const ValueKey('start-service-programs'));
        final context = t.element(list);
        final layout = appLayout(context);
        expect(layout.density, resolved);
        final rows = find.descendant(of: list, matching: find.byType(ListTile));
        for (final row in rows.evaluate()) {
          expect(
            t.getSize(find.byWidget(row.widget)).height,
            greaterThanOrEqualTo(layout.controlHeight),
          );
        }
        final lines = find.descendant(of: list, matching: find.byType(Divider));
        expect(
          lines,
          dividers == 'hidden'
              ? findsNothing
              : findsNWidgets(c.state.templates.length - 1),
        );
        if (dividers == 'strong') {
          expect(t.widget<Divider>(lines.first).thickness, 1.5);
        }
        expect(c.state.session.phase, 'idle');
        await shot(t, 'start-$density-$resolved');
        await tap(t, 'Quick rehearsal');
        expect(c.state.session.phase, 'ready');
        expect(c.state.session.timeline!.name, 'Quick rehearsal');
        expect(c.simulator.delivered, isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Start menu scrolls long programs and large text without overflow',
    (t) async {
      size(t, const Size(320, 850));
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await open(
        t,
        const AppearancePreferences(density: 'spacious', dividers: 'strong'),
      );
      await c.commit((draft, _) {
        draft.templates.clear();
        for (var i = 1; i <= 20; i++) {
          draft.saveTemplate(
            timeline().renamed('Youth Sunday extended program $i'),
          );
        }
      });
      await t.pumpAndSettle();
      await tap(t, 'Start service');
      await shot(t, 'start-large-text');
      await tap(t, 'Youth Sunday extended program 20');
      expect(
        c.state.session.timeline!.name,
        'Youth Sunday extended program 20',
      );
      expect(c.state.session.phase, 'ready');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final menu in [
    'Cue actions',
    'Warning actions',
    'Program list options',
  ]) {
    testWidgets('$menu follows spacing, dividers and keeps its action', (
      t,
    ) async {
      size(t, const Size(430, 1000));
      final c = await open(
        t,
        AppearancePreferences(
          density: 'spacious',
          dividers: menu == 'Cue actions' ? 'hidden' : 'strong',
        ),
      );
      if (menu == 'Program list options') {
        await tap(t, 'Programs');
      } else {
        await tap(t, 'Settings');
        await tap(
          t,
          menu == 'Cue actions' ? 'Stage cues' : 'Warnings & alerts',
        );
      }
      final trigger = find.byTooltip(menu).first;
      await t.ensureVisible(trigger);
      await t.pumpAndSettle();
      await t.tap(trigger);
      await t.pumpAndSettle();
      final popup = menu == 'Program list options'
          ? find.byType(CheckedPopupMenuItem<bool>).first
          : find.byType(PopupMenuItem<String>).first;
      expect(t.getSize(popup).height, greaterThanOrEqualTo(60));
      final popupMaterial = find
          .ancestor(of: popup, matching: find.byType(Material))
          .first;
      final lines = find.descendant(
        of: popupMaterial,
        matching: find.byType(Divider),
      );
      expect(lines, findsNWidgets(menu == 'Warning actions' ? 2 : 1));
      await shot(t, menu.toLowerCase().replaceAll(' ', '-'));
      if (menu == 'Program list options') {
        await t.tap(popup);
        await t.pumpAndSettle();
        expect(c.state.groupTemplates, false);
      } else if (menu == 'Warning actions') {
        await tap(t, 'Disable warning');
        expect(c.state.defaults.warnings.first.enabled, false);
      } else {
        final cue = c.state.stageCues.first.text;
        await tap(t, 'Move down');
        expect(c.state.stageCues[1].text, cue);
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}

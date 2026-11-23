import 'dart:convert';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/finish_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'screen_sizes_test.dart' show DesktopPort, sunday;

/// The finish on the pages and popups that had none of their own: the
/// Programs and Reports panes on a computer, the End service question, the
/// header menu, the Commands palette, the update notice on Live and a sheet
/// on a phone. Each is a part of the window (texture does not compress, so
/// whole windows would make the golden folder very large).
class _UpdatedPort extends DesktopPort {
  @override
  Future<String> installedVersion() async => '0.39.0-beta.1 (44)';
}

void main() {
  setUpAll(loadAppFonts);
  setUpAll(FinishTextures.instance.loadAll);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  const desktop = Size(1366, 768), phone = Size(360, 780);

  /// The app in [finish] at Full, with [setup] run on its controller first;
  /// [crop] is the part of the window the golden keeps.
  Future<AppController> app(
    WidgetTester t, {
    required String finish,
    String theme = 'royal_navy',
    Size size = desktop,
    FakePort? port,
    Future<void> Function(AppController, FakePort)? setup,
  }) async {
    setScreen(t, size);
    final p = port ?? (size.width >= 1200 ? DesktopPort() : FakePort());
    final c = AppController(p);
    await c.initialize(startTicker: false);
    await c.commit((d, _) {
      d.themeId = theme;
      d.appearance = d.appearance.copyWith(
        finish: finish,
        finishStrength: 'full',
        desktopLayout: 'mission_control',
      );
    });
    await setup?.call(c, p);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  /// [crop] of the window, as the golden [name].
  Future<void> shot(WidgetTester t, String name, Rect crop) async {
    expect(t.takeException(), isNull);
    final view = t.binding.renderViews.first;
    final image = await t.runAsync(
      () => (view.debugLayer! as OffsetLayer).toImage(crop),
    );
    await expectLater(image, matchesGoldenFile('../goldens/finish/$name.png'));
  }

  Future<void> running(AppController c, FakePort p) async {
    await c.act('load', value: sunday());
    await c.act('start');
    p.at = after(120);
    await c.tick();
  }

  /// A finished service, for Reports.
  Future<void> reported(AppController c, FakePort p) async {
    await c.act('load', value: sunday());
    await c.act('start');
    var at = 0;
    for (final seconds in [300, 1330, 2250, 720]) {
      at += seconds;
      p.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    p.at = after(at += 270);
    await c.tick();
    await c.act('end');
    p.at = after(at + 3600);
    await c.tick();
  }

  Future<void> tab(WidgetTester t, String name) async {
    await t.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('navigation-rail')),
            matching: find.text(name),
          )
          .first,
    );
    await t.pumpAndSettle();
  }

  testWidgets('Programs on a computer, Denim, dark', (t) async {
    await app(t, finish: 'denim', setup: running);
    await tab(t, 'Programs');
    await t.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('programs-list-pane')),
            matching: find.text('Sunday Service'),
          )
          .first,
    );
    await t.pumpAndSettle();
    await shot(
      t,
      'programs-denim-full-dark-1366',
      const Rect.fromLTWH(100, 0, 1266, 300),
    );
  });

  testWidgets('Programs on a computer, Oak, light', (t) async {
    await app(t, finish: 'oak', theme: 'warm_ivory');
    await tab(t, 'Programs');
    await t.tap(
      find
          .descendant(
            of: find.byKey(const ValueKey('programs-list-pane')),
            matching: find.text('Sunday Service'),
          )
          .first,
    );
    await t.pumpAndSettle();
    await shot(
      t,
      'programs-oak-full-light-1366',
      const Rect.fromLTWH(100, 0, 1266, 300),
    );
  });

  testWidgets('Reports on a computer, Denim', (t) async {
    await app(t, finish: 'denim', setup: reported);
    await tab(t, 'Reports');
    await shot(
      t,
      'reports-denim-full-dark-1366',
      const Rect.fromLTWH(100, 0, 1266, 330),
    );
  });

  for (final finish in ['denim', 'console', 'glass']) {
    testWidgets('the End service question, $finish', (t) async {
      await app(t, finish: finish, setup: running);
      await t.tap(find.byKey(const ValueKey('end-service')).first);
      await t.pumpAndSettle();
      await shot(
        t,
        'dialog-end-service-$finish',
        const Rect.fromLTWH(370, 262, 626, 244),
      );
    });
  }

  testWidgets('the header menu, Denim', (t) async {
    await app(t, finish: 'denim', setup: running);
    await t.tap(find.byIcon(Icons.more_vert).first);
    await t.pumpAndSettle();
    await shot(t, 'menu-header-denim', const Rect.fromLTWH(966, 0, 400, 340));
  });

  testWidgets('the Commands palette, Leather', (t) async {
    await app(t, finish: 'leather', setup: running);
    await t.tap(find.byIcon(Icons.more_vert).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Commands'));
    await t.pumpAndSettle();
    await shot(t, 'palette-leather', const Rect.fromLTWH(343, 56, 680, 340));
  });

  testWidgets('the update notice on Live, Denim', (t) async {
    final port = _UpdatedPort();
    final saved = AppState.fresh(start)
      ..appearance = const AppearancePreferences(
        finish: 'denim',
        finishStrength: 'full',
      );
    port.data = jsonEncode(saved.toJson()..['seenVersion'] = '0.38.0');
    await app(t, finish: 'denim', port: port);
    expect(find.byKey(const ValueKey('whats-new-notice')), findsOneWidget);
    await shot(t, 'live-notice-denim', const Rect.fromLTWH(430, 60, 560, 290));
  });

  testWidgets('a sheet on a phone, Oak', (t) async {
    await app(t, finish: 'oak', size: phone, setup: running);
    await t.tap(find.text('Welcome').first);
    await t.pumpAndSettle();
    expect(find.text('Jump to segment'), findsOneWidget);
    await shot(
      t,
      'sheet-jump-oak-phone',
      const Rect.fromLTWH(0, 150, 360, 400),
    );
  });
}

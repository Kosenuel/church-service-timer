// PROTOTYPE: renders the large-window options for the desktop Live layouts
// into prototype-shots/ at the repository root, for the owner to choose
// from. Run with:
//
//   flutter test --update-goldens test/prototype/large_screen_shots_test.dart
//
// Without --update-goldens the renders are skipped; the layout checks at
// the end always run.
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/live/large_screen_variants.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort, sunday;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() {
    desktopWording = false;
    LargeScreenLive.reset();
  });

  /// The Sunday service of the desktop layout tests, part-way through its
  /// third segment.
  Future<AppController> running(
    WidgetTester t, {
    required Size size,
    required String layout,
    String theme = 'midnight_lime',
    double textScale = 1,
  }) async {
    setScreen(t, size);
    t.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
      draft.themeId = theme;
    });
    await c.act('load', value: sunday());
    await c.act('start');
    var at = 0;
    for (final seconds in const [340, 1330]) {
      at += seconds;
      port.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    port.at = after(at + 1642);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  const sizes = {
    '2560': Size(2560, 1440),
    '1920': Size(1920, 1080),
    '1366x900': Size(1366, 900),
  };

  /// name → (layout, theme, sizes, switch).
  final shots = <(String, String, String, List<String>, void Function())>[
    for (final (name, layout, theme) in const [
      ('three-panes', 'three_panes', 'midnight_lime'),
      ('dial', 'dial', 'royal_navy'),
    ]) ...[
      ('$name-before', layout, theme, ['2560', '1920', '1366x900'], () {}),
      (
        '$name-A',
        layout,
        theme,
        ['2560', '1920', '1366x900'],
        () => LargeScreenLive.panes = 'grow',
      ),
      (
        '$name-B',
        layout,
        theme,
        ['2560', '1920', '1366x900'],
        () => LargeScreenLive.panes = 'beside',
      ),
    ],
    (
      'mission-control-before',
      'mission_control',
      'midnight_lime',
      ['2560'],
      () {},
    ),
    (
      'mission-control-A',
      'mission_control',
      'midnight_lime',
      ['2560'],
      () => LargeScreenLive.mission = 'fill',
    ),
    (
      'mission-control-B',
      'mission_control',
      'midnight_lime',
      ['2560'],
      () => LargeScreenLive.mission = 'rundown',
    ),
    (
      'mission-control-AB',
      'mission_control',
      'midnight_lime',
      ['2560'],
      () => LargeScreenLive.mission = 'both',
    ),
    ('classic-before', 'classic', 'midnight_lime', ['2560'], () {}),
    (
      'classic-A',
      'classic',
      'midnight_lime',
      ['2560'],
      () => LargeScreenLive.classic = 'wide',
    ),
    (
      'classic-B',
      'classic',
      'midnight_lime',
      ['2560'],
      () => LargeScreenLive.classic = 'three',
    ),
    ('keys-before', 'keys', 'graphite', ['2560'], () {}),
  ];

  for (final (name, layout, theme, at, enable) in shots) {
    for (final size in at) {
      testWidgets('$name at $size', skip: !autoUpdateGoldenFiles, (t) async {
        enable();
        // The smaller windows show a variant only when it is allowed to
        // start below its default height.
        if (size != '2560') LargeScreenLive.panesFromHeight = 800;
        await running(t, size: sizes[size]!, layout: layout, theme: theme);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../../prototype-shots/$name-$size.png'),
        );
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  // Nothing overflows, and the timer controls stay in reach, with every
  // variant at every window size the brief names.
  final variants = <(String, String, void Function())>[
    ('three_panes', 'grow', () => LargeScreenLive.panes = 'grow'),
    ('three_panes', 'beside', () => LargeScreenLive.panes = 'beside'),
    ('dial', 'grow', () => LargeScreenLive.panes = 'grow'),
    ('dial', 'beside', () => LargeScreenLive.panes = 'beside'),
    ('mission_control', 'fill', () => LargeScreenLive.mission = 'fill'),
    ('mission_control', 'rundown', () => LargeScreenLive.mission = 'rundown'),
    ('mission_control', 'both', () => LargeScreenLive.mission = 'both'),
    ('classic', 'wide', () => LargeScreenLive.classic = 'wide'),
    ('classic', 'three', () => LargeScreenLive.classic = 'three'),
  ];
  const windows = [
    (Size(1200, 600), 1.0),
    (Size(1366, 768), 1.0),
    (Size(1366, 900), 1.0),
    (Size(1920, 1080), 1.0),
    (Size(2560, 1440), 1.0),
    (Size(2560, 1440), 1.3),
    (Size(3840, 2160), 1.0),
  ];
  for (final (layout, variant, enable) in variants) {
    testWidgets('$layout $variant fits every window', (t) async {
      for (final (size, scale) in windows) {
        enable();
        await running(t, size: size, layout: layout, textScale: scale);
        expect(
          t.takeException(),
          isNull,
          reason: '$layout $variant at $size ×$scale',
        );
        for (final key in ['pause-resume', 'next-segment', 'end-service']) {
          final button = find.byKey(ValueKey(key));
          expect(button, findsOneWidget, reason: '$key at $size ×$scale');
          if (layout != 'classic') {
            // The desktop layouts fill the window: no scrolling to reach
            // a timer control at the default text size.
            if (scale == 1 && size.height >= 768) {
              expect(
                button.hitTestable(),
                findsOneWidget,
                reason: '$key in view at $size',
              );
            }
          }
        }
        await t.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('timer actions still confirm with a variant on', (t) async {
    LargeScreenLive.panes = 'beside';
    final c = await running(
      t,
      size: const Size(2560, 1440),
      layout: 'three_panes',
    );
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });
}

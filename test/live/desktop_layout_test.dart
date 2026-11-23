import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/mission_control_live.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

class DesktopFakePort extends FakePort {
  @override
  bool get isDesktop => true;
  bool warningSound = false;
  @override
  Future<void> setWarningSound(bool on) async => warningSound = on;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': warningSound,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

/// A Sunday service part-way through its third segment, running late.
Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5, speaker: 'Deacon Ruth'),
  Segment('Praise & Worship', 20, speaker: 'Worship team'),
  Segment(
    'Sermon',
    40,
    speaker: 'Pastor Samuel',
    notes: 'Altar call follows. Band back on stage at 5:00 left.',
  ),
  Segment('Response', 10, speaker: 'Worship team'),
  Segment('Closing', 5),
], DisplaySettings());

/// A service of many short segments, part-way through one with a long
/// title.
Timeline manyShort() => Timeline('Youth Sunday', [
  const Segment(
    'Call to worship and opening prayer',
    2,
    speaker: 'Elder Bartholomew Achterberg',
  ),
  const Segment('Welcome', 1, speaker: 'Deacon Ruth'),
  const Segment('Praise & Worship', 20, speaker: 'Worship team'),
  for (var i = 1; i <= 8; i++) Segment('Testimony $i', 1, speaker: 'Member $i'),
  const Segment(
    'A very long segment title for the combined thanksgiving sermon and '
    'communion',
    30,
    speaker: 'Pastor Samuel',
  ),
  const Segment('Offering', 2),
  const Segment('Notices', 1, speaker: 'Secretary'),
  const Segment('Closing', 2),
], DisplaySettings());

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  Future<(AppController, DesktopFakePort)> running(
    WidgetTester t, {
    Size size = const Size(1366, 768),
    String layout = 'three_panes',
    String theme = 'midnight_lime',
    DesktopFakePort? on,
    List<int> advanceAfter = const [340, 1330],
    int then = 1642,
    double textScale = 1,
    Timeline Function() timeline = sunday,
  }) async {
    setScreen(t, size);
    if (textScale != 1) {
      t.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final port = on ?? DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
      draft.themeId = theme;
    });
    await c.act('load', value: timeline());
    await c.act('start');
    var at = 0;
    for (final seconds in advanceAfter) {
      at += seconds;
      port.at = after(at);
      await c.tick();
      await c.act('advance');
    }
    port.at = after(at + then);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return (c, port);
  }

  Future<void> openLayoutSettings(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('desktop-tab-3')));
    await t.pumpAndSettle();
    await t.tap(find.text('Appearance'));
    await t.pumpAndSettle();
    await t.tap(find.text('Layout & accessibility'));
    await t.pumpAndSettle();
  }

  /// The width the ring of the running segment is drawn at.
  double ringWidth(WidgetTester t) => t
      .getSize(
        find
            .descendant(
              of: find.byType(SegmentGauge),
              matching: find.byType(CustomPaint),
            )
            .first,
      )
      .width;

  Future<void> press(WidgetTester t, Finder target) async {
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    await t.tap(target);
    await t.pumpAndSettle();
  }

  testWidgets('three panes at laptop size', (t) async {
    await running(t);
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    // Everything an operator needs is in view without scrolling.
    for (final key in ['pause-resume', 'next-segment', 'end-service']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-three-panes.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('three panes at full HD in Paper & Ink', (t) async {
    await running(t, size: const Size(1920, 1080), theme: 'paper_ink');
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-three-panes-1080-paper.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control at laptop size', (t) async {
    await running(t, layout: 'mission_control');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    // The side rail stays; nothing an operator needs is off screen.
    expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
    for (final key in ['pause-resume', 'next-segment', 'end-service', 'undo']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('timeline-4')).hitTestable(),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-mission-control.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control at full HD', (t) async {
    await running(t, layout: 'mission_control', size: const Size(1920, 1080));
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-mission-control-1080.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The dial at laptop size', (t) async {
    await running(t, layout: 'dial', theme: 'royal_navy');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('service-dial')), findsOneWidget);
    // Three panes around it, with the header tabs.
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsOneWidget);
    for (final key in ['pause-resume', 'next-segment', 'end-service', 'undo']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    // End service is wholly in view, not cut off by the window.
    expect(
      t.getRect(find.byKey(const ValueKey('end-service'))).bottom,
      lessThanOrEqualTo(768),
    );
    expect(find.text('12:38'), findsOneWidget);
    expect(find.text('of 40:00 allocated'), findsOneWidget);
    // The private note keeps one line in a short window.
    expect(
      find.text(
        'Private note: Altar call follows. Band back on stage at 5:00 left.',
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-dial.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The dial at full HD', (t) async {
    await running(
      t,
      layout: 'dial',
      theme: 'royal_navy',
      size: const Size(1920, 1080),
    );
    expect(t.takeException(), isNull);
    expect(
      find.text('Altar call follows. Band back on stage at 5:00 left.'),
      findsOneWidget,
    );
    expect(
      t.getRect(find.byKey(const ValueKey('end-service'))).bottom,
      lessThanOrEqualTo(1080),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-dial-1080.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  // A large window: the ring grows, Mission control fills its height and
  // Classic has a column for the rundown.
  for (final (name, layout, theme) in const [
    ('three-panes', 'three_panes', 'midnight_lime'),
    ('dial', 'dial', 'royal_navy'),
    ('mission-control', 'mission_control', 'midnight_lime'),
    ('classic', 'classic', 'midnight_lime'),
  ]) {
    testWidgets('$name in a 2560 × 1440 window', (t) async {
      await running(
        t,
        layout: layout,
        theme: theme,
        size: const Size(2560, 1440),
      );
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-$name-1440.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  /// Whether every main control is on screen without scrolling in a
  /// [size] window: all but the desktop layouts with panes in a window
  /// 600 tall, which is too short for them.
  bool inReach(String layout, Size size) =>
      size.height >= 720 ||
      size.width < 1200 ||
      const {'classic', 'keys'}.contains(layout);

  // With the sizes Windows display scaling gives the app: 1920 × 1080 at
  // 150% and 125%, and 1920 × 1200 at 150%.
  const windows = [
    // 1366 × 768 at 125%: too narrow for the desktop layouts, so Classic.
    (Size(1093, 614), 1.0),
    (Size(1200, 600), 1.0),
    (Size(1280, 720), 1.0),
    (Size(1270, 790), 1.0),
    (Size(1366, 768), 1.0),
    (Size(1536, 864), 1.0),
    (Size(1440, 900), 1.0),
    (Size(1366, 900), 1.0),
    (Size(1920, 1080), 1.0),
    (Size(2560, 1440), 1.0),
    (Size(2560, 1440), 1.3),
    (Size(3840, 2160), 1.0),
  ];
  for (final layout in const [
    'three_panes',
    'dial',
    'mission_control',
    'classic',
    'keys',
  ]) {
    testWidgets('$layout fits every window with its controls in reach', (
      t,
    ) async {
      for (final (size, scale) in windows) {
        await running(t, size: size, layout: layout, textScale: scale);
        final where = '$layout at $size ×$scale';
        expect(t.takeException(), isNull, reason: where);
        for (final key in ['pause-resume', 'next-segment', 'end-service']) {
          final button = find.byKey(ValueKey(key));
          expect(button, findsOneWidget, reason: '$key, $where');
          // No scrolling to reach a timer control at the usual text size.
          // A window 600 tall is too short for the panes; a window under
          // 1200 wide has Classic, whatever the choice.
          if (scale == 1 && inReach(layout, size)) {
            expect(
              button.hitTestable(),
              findsOneWidget,
              reason: '$key, $where',
            );
            expect(
              t.getRect(button).bottom,
              lessThanOrEqualTo(size.height),
              reason: '$key, $where',
            );
          }
        }
        await t.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('Keys fits every window just after a service starts', (t) async {
    // The first seconds of a service, with nothing done yet: at 1200 × 600
    // the buttons under the rundown overflowed beside End service.
    for (final (size, scale) in const [
      (Size(1200, 600), 1.0),
      (Size(1366, 768), 1.0),
      (Size(1920, 1080), 1.0),
      (Size(2560, 1440), 1.0),
      (Size(2560, 1440), 1.3),
    ]) {
      await running(
        t,
        size: size,
        layout: 'keys',
        textScale: scale,
        advanceAfter: const [],
        then: 2,
      );
      final where = 'Keys at $size ×$scale';
      expect(t.takeException(), isNull, reason: where);
      for (final key in [
        'pause-resume',
        'next-segment',
        'end-service',
        'print-rundown',
      ]) {
        final button = find.byKey(ValueKey(key));
        expect(button.hitTestable(), findsOneWidget, reason: '$key, $where');
        expect(
          t.getRect(button).right,
          lessThanOrEqualTo(size.width),
          reason: '$key, $where',
        );
      }
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Mission control fits a laptop window with large system text', (
    t,
  ) async {
    // At 1366 × 768 with text at 1.6 the rundown's blocks were 0.4 short
    // of their two lines, which overflowed. The text size comes from a
    // MediaQuery above the app here, as well as from the system below.
    Timeline three() => Timeline('Sunday Service', const [
      Segment('Welcome', 5),
      Segment('Praise & Worship', 20),
      Segment('Sermon', 40),
    ], DisplaySettings());
    for (final (size, scale) in const [
      (Size(1366, 768), 1.15),
      (Size(1366, 768), 1.3),
      (Size(1366, 768), 1.6),
      (Size(1366, 768), 2.0),
      (Size(1280, 720), 1.6),
      (Size(1920, 1080), 1.6),
      (Size(1920, 1080), 2.0),
    ]) {
      final where = 'Mission control at $size ×$scale';
      setScreen(t, size);
      final c = AppController(DesktopFakePort());
      await c.initialize(startTicker: false);
      await c.commit((draft, _) {
        draft.appearance = draft.appearance.copyWith(
          desktopLayout: 'mission_control',
        );
      });
      await c.act('load', value: three());
      await c.act('start');
      await t.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            t.view,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: TimerApp(controller: c),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull, reason: where);
      // Each block still has a line of figures under its name.
      final blocks = find.byType(TimelineBlock);
      expect(blocks, findsNWidgets(3), reason: where);
      for (final name in ['Welcome', 'Praise & Worship', 'Sermon']) {
        final block = find.ancestor(
          of: find.text(name),
          matching: find.byType(TimelineBlock),
        );
        expect(
          find.descendant(of: block, matching: find.byType(Text)),
          findsAtLeast(2),
          reason: '$name, $where',
        );
      }
      await t.pumpWidget(const SizedBox());
    }

    // The same through the system's own text size, part-way through.
    for (final scale in const [1.6, 2.0]) {
      await running(t, layout: 'mission_control', textScale: scale);
      expect(t.takeException(), isNull, reason: 'system text ×$scale');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a rundown block keeps only the lines its height has room for', (
    t,
  ) async {
    Future<void> block(
      double height, {
      double scale = 1,
      List<String>? more,
    }) async {
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 600,
                  height: height,
                  child: TimelineBlock(
                    name: 'Sermon',
                    detail: '40 min',
                    border: Colors.grey,
                    strong: true,
                    more: more,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        t.takeException(),
        isNull,
        reason: '$height high ×$scale, more $more',
      );
    }

    const more = ['Pastor Samuel', 'Planned 40:00', 'Starts about 10:25'];

    // The height the block asks for holds both lines at any text size.
    for (final scale in const [1.0, 1.3, 1.6, 2.0, 3.0]) {
      late double needed, rich;
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  needed = TimelineBlock.heightFor(context);
                  rich = TimelineBlock.heightFor(context, rich: true);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await block(needed, scale: scale);
      expect(find.text('40 min'), findsOneWidget, reason: '×$scale');
      // A little shorter, as the rundown's blocks were at 1.6: the name
      // alone.
      await block(needed - 6, scale: scale);
      expect(find.text('Sermon'), findsOneWidget, reason: '×$scale');
      expect(find.text('40 min'), findsNothing, reason: '×$scale');
      await block(rich, scale: scale, more: more);
      for (final text in more) {
        expect(find.text(text), findsOneWidget, reason: '$text ×$scale');
      }
    }

    // The taller block steps down: every line, the name and the short
    // detail, the name alone, and still nothing overflows with no height.
    await block(118, more: more);
    expect(find.text('Pastor Samuel'), findsOneWidget);
    expect(find.text('40 min'), findsNothing);
    await block(70, more: more);
    expect(find.text('Pastor Samuel'), findsNothing);
    expect(find.text('40 min'), findsOneWidget);
    await block(40, more: more);
    expect(find.text('Sermon'), findsOneWidget);
    expect(find.text('40 min'), findsNothing);
    for (final height in const [20.0, 8.0, 2.0]) {
      await block(height);
      await block(height, scale: 2, more: more);
      expect(find.text('Sermon'), findsOneWidget);
    }
  });

  testWidgets('the ring grows with the height of the pane at every size', (
    t,
  ) async {
    // From the shortest pane to the tallest: a laptop, a laptop with
    // display scaling, then larger screens.
    const sizes = [
      Size(1366, 768),
      Size(1270, 790),
      Size(1600, 900),
      Size(1920, 1080),
    ];
    for (final layout in ['three_panes', 'dial', 'mission_control']) {
      final rings = <double>[];
      for (final size in sizes) {
        // The Welcome, which has no private note under the controls.
        await running(
          t,
          layout: layout,
          size: size,
          advanceAfter: const [],
          then: 2,
        );
        final where = '$layout at $size';
        expect(t.takeException(), isNull, reason: where);
        rings.add(
          layout == 'dial'
              ? t.getSize(find.byKey(const ValueKey('service-dial'))).width
              : ringWidth(t),
        );
        // The ring never takes the room of the controls: nothing to
        // scroll to.
        for (final key in ['pause-resume', 'next-segment', 'end-service']) {
          final button = find.byKey(ValueKey(key));
          expect(button.hitTestable(), findsOneWidget, reason: '$key, $where');
          expect(
            t.getRect(button).bottom,
            lessThanOrEqualTo(size.height),
            reason: '$key, $where',
          );
        }
        await t.pumpWidget(const SizedBox());
      }
      for (var i = 1; i < rings.length; i++) {
        expect(
          rings[i],
          layout == 'mission_control'
              ? greaterThanOrEqualTo(rings[i - 1])
              : greaterThan(rings[i - 1]),
          reason: '$layout: $rings',
        );
      }
      expect(rings.last, greaterThan(rings.first + 60), reason: layout);
    }
    // A laptop window with display scaling has a ring that fills the
    // middle pane, not one at its smallest.
    await running(t, size: const Size(1270, 790), advanceAfter: const []);
    expect(ringWidth(t), greaterThan(340));
    expect(find.byKey(const ValueKey('key-legend')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    // Wide enough: the controls sit at the ring's right.
    await running(t, size: const Size(2560, 1440));
    expect(
      t.getRect(find.byKey(const ValueKey('pause-resume'))).left,
      greaterThan(t.getRect(find.byType(SegmentGauge)).right - 1),
    );
    await t.pumpWidget(const SizedBox());
  });

  /// A service loaded and not yet started.
  Future<AppController> readyFor(
    WidgetTester t, {
    required String layout,
    required Size size,
    String theme = 'midnight_lime',
  }) async {
    setScreen(t, size);
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
      draft.themeId = theme;
    });
    await c.act('load', value: sunday());
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  /// The layout's own timer: the ring, the dial or the Keys countdown.
  Finder ownTimer(String layout) => switch (layout) {
    'dial' => find.byKey(const ValueKey('service-dial')),
    'keys' => find.byKey(const ValueKey('operator-clock')),
    _ =>
      find
          .descendant(
            of: find.byType(SegmentGauge),
            matching: find.byType(CustomPaint),
          )
          .first,
  };

  const readyWindows = [
    Size(1093, 614),
    Size(1200, 600),
    Size(1280, 720),
    Size(1270, 790),
    Size(1366, 768),
    Size(1536, 864),
    Size(1440, 900),
    Size(1920, 1080),
    Size(2560, 1440),
  ];
  for (final layout in const [
    'three_panes',
    'dial',
    'mission_control',
    'keys',
    'classic',
  ]) {
    testWidgets('$layout shows its own timer in Ready, with the Ready form', (
      t,
    ) async {
      for (final size in readyWindows) {
        final c = await readyFor(t, layout: layout, size: size);
        final where = '$layout at $size';
        // A window under 1200 wide has Classic, whatever the choice.
        final shown = size.width < 1200 ? 'classic' : layout;
        expect(t.takeException(), isNull, reason: where);
        expect(c.state.session.phase, 'ready');
        expect(ownTimer(shown), findsOneWidget, reason: where);
        if (shown == 'keys') {
          expect(find.byKey(const ValueKey('keys-live')), findsOneWidget);
          expect(
            t.widget<Text>(find.byKey(const ValueKey('operator-clock'))).data,
            '05:00',
            reason: where,
          );
        }
        // Not counting: Pause and Next segment wait for the service.
        expect(find.byKey(const ValueKey('pause-resume')), findsNothing);
        final form = <Finder>[
          find.byKey(const ValueKey('ready-program')),
          find.byKey(const ValueKey('change-program')),
          find.byKey(const ValueKey('ready-inline')),
          find.byKey(const ValueKey('pre-service-row')),
          find.byKey(ValueKey('speed-${c.state.session.id}')),
          find.byKey(const ValueKey('ready-not-started')),
          find.text('Start first segment'),
          find.text('Cancel setup'),
          find.byKey(const ValueKey('check-service')),
        ];
        for (final item in form) {
          expect(item, findsOneWidget, reason: '$item, $where');
          if (!inReach(shown, size)) continue;
          expect(item.hitTestable(), findsOneWidget, reason: '$item, $where');
          final rect = t.getRect(item);
          expect(
            rect.bottom,
            lessThanOrEqualTo(size.height),
            reason: '$item, $where',
          );
          expect(
            rect.right,
            lessThanOrEqualTo(size.width),
            reason: '$item, $where',
          );
        }
        // Starting keeps the timer where it was, at the same size. Classic
        // adds the service's status line above it.
        final before = t.getRect(ownTimer(shown));
        await c.act('start');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: where);
        expect(ownTimer(shown), findsOneWidget, reason: where);
        final after = t.getRect(ownTimer(shown));
        // To a hundredth: Classic's card moves down for the timing bar,
        // and the move can round the last decimal place.
        expect(after.width, closeTo(before.width, .01), reason: where);
        expect(after.height, closeTo(before.height, .01), reason: where);
        if (shown != 'classic') {
          expect(after.topLeft, before.topLeft, reason: where);
        }
        await t.pumpWidget(const SizedBox());
      }
    });
  }

  // Ready in each layout, to compare with the running goldens: the same
  // timer, with the Ready form where the controls go.
  for (final (name, layout) in const [
    ('three-panes', 'three_panes'),
    ('dial', 'dial'),
    ('mission-control', 'mission_control'),
    ('keys', 'keys'),
    ('classic', 'classic'),
  ]) {
    testWidgets('$name in Ready at full HD', (t) async {
      await readyFor(t, layout: layout, size: const Size(1920, 1080));
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-$name-ready-1080.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  // Laptop windows, running just after the start and in Ready: 1920 × 1200
  // at 150% (about 1270 × 790), 1366 × 768, and 1920 × 1080 at 125%.
  for (final (name, layout) in const [
    ('three-panes', 'three_panes'),
    ('mission-control', 'mission_control'),
  ]) {
    for (final size in const [
      Size(1270, 790),
      Size(1366, 768),
      Size(1536, 864),
    ]) {
      final width = size.width.round();
      testWidgets('$name in a $size window, running and Ready', (t) async {
        await running(
          t,
          layout: layout,
          size: size,
          advanceAfter: const [],
          then: 2,
        );
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/desktop-$name-$width.png'),
        );
        await t.pumpWidget(const SizedBox());
        await readyFor(t, layout: layout, size: size);
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('../goldens/desktop-$name-ready-$width.png'),
        );
        await t.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'a large window keeps warning, overtime and a long title in view',
    (t) async {
      for (final layout in ['three_panes', 'dial', 'mission_control']) {
        for (final size in const [Size(1920, 1080), Size(2560, 1440)]) {
          // 45 seconds left of the Sermon, then three minutes over.
          await running(t, layout: layout, size: size, then: 2355);
          expect(t.takeException(), isNull);
          expect(
            find.textContaining('00:45 left'),
            findsWidgets,
            reason: '$layout $size',
          );
          await t.pumpWidget(const SizedBox());
          await running(t, layout: layout, size: size, then: 2585);
          expect(t.takeException(), isNull);
          expect(
            find.text('Allocated time exceeded'),
            findsOneWidget,
            reason: '$layout $size',
          );
          expect(find.text('+03:05'), findsOneWidget);
          await t.pumpWidget(const SizedBox());
          // A title that wraps, in a service of many short segments.
          await running(
            t,
            layout: layout,
            size: size,
            timeline: manyShort,
            advanceAfter: const [130, 70, 1250, 60, 60, 60, 60, 60, 60, 60, 60],
            then: 400,
          );
          expect(t.takeException(), isNull);
          for (final key in ['pause-resume', 'next-segment', 'end-service']) {
            expect(
              t.getRect(find.byKey(ValueKey(key))).bottom,
              lessThanOrEqualTo(size.height),
              reason: '$key, $layout $size',
            );
          }
          await t.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets('the last segment, a quick timer and a pause in a large window', (
    t,
  ) async {
    for (final layout in ['three_panes', 'dial', 'mission_control']) {
      for (final size in const [Size(1920, 1080), Size(2560, 1440)]) {
        // Closing: the last segment, with no private note.
        final (c, _) = await running(
          t,
          layout: layout,
          size: size,
          advanceAfter: const [340, 1330, 2500, 600],
          then: 100,
        );
        expect(t.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('desktop-private-note')),
          findsNothing,
        );
        expect(find.textContaining('Final segment'), findsWidgets);
        expect(
          t.getRect(find.byKey(const ValueKey('end-service'))).bottom,
          lessThanOrEqualTo(size.height),
          reason: '$layout $size',
        );
        await c.act('pause');
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Resume'), findsOneWidget);
        await t.pumpWidget(const SizedBox());

        setScreen(t, size);
        final quick = AppController(DesktopFakePort());
        await quick.initialize(startTicker: false);
        await quick.commit(
          (draft, _) => draft.appearance = draft.appearance.copyWith(
            desktopLayout: layout,
          ),
        );
        await quick.startQuickTimer(
          const QuickTimerChoice('Prayer meeting', 900),
        );
        await t.pumpWidget(TimerApp(controller: quick));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('End timer').hitTestable(), findsOneWidget);
        // Pause is alone, and is not stretched across the pane.
        expect(
          t.getSize(find.byKey(const ValueKey('pause-resume'))).width,
          lessThanOrEqualTo(600),
          reason: '$layout $size',
        );
        await t.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('Mission control in a large window: buttons keep a sensible '
      'width and short segments keep readable blocks', (t) async {
    await running(
      t,
      layout: 'mission_control',
      size: const Size(2560, 1440),
      timeline: manyShort,
      advanceAfter: const [130, 70, 1250, 60, 60, 60, 60, 60, 60, 60, 60],
      then: 400,
    );
    expect(t.takeException(), isNull);
    for (final key in ['pause-resume', 'next-segment']) {
      expect(
        t.getSize(find.byKey(ValueKey(key))).width,
        lessThanOrEqualTo(360),
      );
    }
    // A wide block has the speaker and planned against actual time.
    final worship = find.byKey(const ValueKey('timeline-2'));
    expect(
      find.descendant(of: worship, matching: find.text('Worship team')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: worship, matching: find.text('Planned 20:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: worship, matching: find.text('Took 20:50 · +0:50')),
      findsOneWidget,
    );
    // A one-minute block is too narrow for them: it keeps its name only,
    // and still opens the segment's details.
    final testimony = find.byKey(const ValueKey('timeline-5'));
    expect(t.getSize(testimony).width, lessThan(64));
    expect(
      find.descendant(of: testimony, matching: find.textContaining('Planned')),
      findsNothing,
    );
    expect(
      find.descendant(of: testimony, matching: find.text('Member 3')),
      findsNothing,
    );
    // A laptop window keeps the short timeline.
    await t.pumpWidget(const SizedBox());
    await running(t, layout: 'mission_control');
    expect(find.text('Planned 20:00'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('timer actions still ask first in a large window, and Lock '
      'controls blocks them', (t) async {
    for (final layout in [
      'three_panes',
      'dial',
      'mission_control',
      'classic',
    ]) {
      final (c, _) = await running(
        t,
        layout: layout,
        size: const Size(2560, 1440),
      );
      await press(t, find.byKey(const ValueKey('pause-resume')));
      expect(c.state.session.paused, isFalse, reason: layout);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await press(t, find.byKey(const ValueKey('end-service')));
      expect(find.text('End Sunday Service?'), findsOneWidget, reason: layout);
      expect(c.state.session.active, isTrue);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('control-lock')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('controls-locked-banner')),
        findsOneWidget,
        reason: layout,
      );
      for (final key in ['pause-resume', 'next-segment', 'end-service']) {
        await t.tap(find.byKey(ValueKey(key)), warnIfMissed: false);
        await t.pumpAndSettle();
      }
      expect(find.byType(AlertDialog), findsNothing, reason: layout);
      expect(c.state.session.paused, isFalse);
      expect(c.state.session.index, 2);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Classic has a rundown column only in a very wide window', (
    t,
  ) async {
    Future<void> at(Size size) => running(t, layout: 'classic', size: size);
    await at(const Size(2560, 1440));
    expect(t.takeException(), isNull);
    // Timer, then display and cues, then the rundown, side by side.
    expect(
      t.getRect(find.text('SERVICE RUNDOWN')).left,
      greaterThan(t.getRect(find.text('DISPLAY PREVIEW')).right),
    );
    expect(
      t.getRect(find.text('SERVICE RUNDOWN')).top,
      lessThan(t.getRect(find.text('STAGE CUES')).top),
    );
    // The ring keeps its usual size.
    expect(ringWidth(t), lessThanOrEqualTo(306));
    await t.pumpWidget(const SizedBox());
    // A narrower window keeps two columns at the usual width, with the
    // rundown under the cues.
    await at(const Size(1800, 1000));
    expect(
      t.getRect(find.text('SERVICE RUNDOWN')).top,
      greaterThan(t.getRect(find.text('STAGE CUES')).top),
    );
    expect(
      t.getRect(find.text('DISPLAY PREVIEW')).right -
          t.getRect(find.text('SEGMENT 3 OF 5')).left,
      lessThan(1200),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Classic before a service keeps its usual width when wide', (
    t,
  ) async {
    setScreen(t, const Size(2560, 1440));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'classic',
      ),
    );
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // Standing by: one centred column.
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(
      t.getSize(find.text('Start service').hitTestable()).width,
      lessThan(760),
    );
    // Ready: the rundown has its column, and Start is in view.
    await c.act('load', value: sunday());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Start first segment').hitTestable(), findsOneWidget);
    expect(
      t.getRect(find.text('SERVICE RUNDOWN')).left,
      greaterThan(t.getRect(find.text('DISPLAY PREVIEW')).right),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('The dial follows the service: ready, warning, overtime', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: 'dial'),
    );
    await c.act('load', value: sunday());
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // Ready shows the dial the service will have, at the same size and
    // place, with the start controls where Pause and Next segment go.
    expect(find.text('Start first segment'), findsOneWidget);
    expect(find.byKey(const ValueKey('service-dial')), findsOneWidget);
    expect(find.byKey(const ValueKey('dial-ends')), findsNothing);
    final readyDial = t.getRect(find.byKey(const ValueKey('service-dial')));
    await c.act('start');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('service-dial')), findsOneWidget);
    expect(t.getRect(find.byKey(const ValueKey('service-dial'))), readyDial);
    expect(find.byKey(const ValueKey('dial-ends')), findsOneWidget);
    expect(find.text('REMAINING'), findsOneWidget);
    // Six minutes into a five-minute Welcome.
    port.at = after(360);
    await c.tick();
    await t.pumpAndSettle();
    expect(find.text('OVERTIME'), findsOneWidget);
    expect(find.text('+01:00'), findsOneWidget);
    expect(find.text('Allocated time exceeded'), findsOneWidget);
    // Keys and confirmations are as everywhere else.
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.session.index, 1);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('choosing The dial brings Royal Navy with it', (t) async {
    final (c, _) = await running(t);
    await openLayoutSettings(t);
    await press(t, find.byKey(const ValueKey('desktop-layout-dial')));
    expect(c.appearanceSelection.value.desktopLayout, 'dial');
    expect(c.themeSelection.value, 'royal_navy');
    await t.tap(find.text('Save appearance'));
    await t.pumpAndSettle();
    expect(c.state.appearance.desktopLayout, 'dial');
    expect(c.state.themeId, 'royal_navy');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Keys at laptop size', (t) async {
    await running(t, layout: 'keys', theme: 'graphite');
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('keys-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsOneWidget);
    for (final key in ['pause-resume', 'next-segment', 'end-service', 'undo']) {
      expect(find.byKey(ValueKey(key)).hitTestable(), findsOneWidget);
    }
    expect(find.text('Blank screen').hitTestable(), findsOneWidget);
    expect(
      t.getRect(find.byKey(const ValueKey('key-legend'))).bottom,
      lessThanOrEqualTo(768),
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-keys.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Keys at full HD', (t) async {
    await running(
      t,
      layout: 'keys',
      theme: 'graphite',
      size: const Size(1920, 1080),
    );
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-keys-1080.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the Keys rundown table has every figure in its column', (
    t,
  ) async {
    final (c, _) = await running(t, layout: 'keys');
    final table = find.byKey(const ValueKey('rundown-table'));
    List<String?> row(int i) => t
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey('rundown-$i')),
            matching: find.byType(Text),
          ),
        )
        .map((w) => w.data)
        .toList();
    expect(row(0), [
      '1',
      'Welcome',
      'Deacon Ruth',
      '05:00',
      isNotNull,
      '05:40',
      '+0:40',
      'Done',
    ]);
    expect(row(2).sublist(0, 4), ['3', 'Sermon', 'Pastor Samuel', '40:00']);
    expect(row(2)[5], '27:22 so far');
    expect(row(2).last, 'Running');
    expect(row(3).last, 'Next');
    expect(row(3)[4], startsWith('~'));
    expect(row(4).last, 'Upcoming');
    expect(
      find.descendant(of: table, matching: find.text('Private note · Sermon')),
      findsOneWidget,
    );
    final strip = find.byKey(const ValueKey('now-strip'));
    expect(
      find.descendant(of: strip, matching: find.text('12:38')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: strip, matching: find.text('2 min 50 s behind')),
      findsOneWidget,
    );
    await c.act('pause');
    await t.pumpAndSettle();
    expect(row(2).last, 'Paused');
    await t.tap(find.byKey(const ValueKey('rundown-0')));
    await t.pumpAndSettle();
    expect(find.text('Segment details'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Keys has its own strip before the start and is Compact', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(desktopLayout: 'keys'),
    );
    await c.act('load', value: sunday());
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // Ready shows the countdown it will have, with Start where Pause goes.
    expect(find.byKey(const ValueKey('keys-live')), findsOneWidget);
    expect(find.byKey(const ValueKey('operator-clock')), findsOneWidget);
    expect(find.text('Start first segment'), findsOneWidget);
    expect(
      appLayout(t.element(find.byKey(const ValueKey('keys-live')))).density,
      'compact',
    );
    await c.act('start');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('keys-live')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('number keys send cues on a computer, in any layout', (t) async {
    for (final layout in ['keys', 'three_panes', 'classic']) {
      final (c, _) = await running(t, layout: layout);
      final cues = c.state.stageCues;
      // Each cue button shows its number.
      expect(find.text('1'), findsWidgets, reason: layout);
      await t.sendKeyEvent(LogicalKeyboardKey.digit2);
      await t.pumpAndSettle();
      expect(c.state.session.alert?.text, cues[1].text, reason: layout);
      expect(c.state.session.outputMode(c.now), 'Cue', reason: layout);
      // Another number replaces it; the same number goes back to the timer.
      await t.sendKeyEvent(LogicalKeyboardKey.numpad1);
      await t.pumpAndSettle();
      expect(c.state.session.alert?.text, cues[0].text, reason: layout);
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown', reason: layout);
      // A number with no cue behind it does nothing.
      await t.sendKeyEvent(LogicalKeyboardKey.digit9);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown', reason: layout);
      // Nor does any number while the controls are locked.
      await t.tap(find.byKey(const ValueKey('control-lock')));
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.digit1);
      await t.pumpAndSettle();
      expect(c.state.session.outputMode(c.now), 'Countdown', reason: layout);
      expect(t.takeException(), isNull, reason: layout);
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('number keys are left alone on a tablet and while typing', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    desktopWording = false;
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.digit1);
    await t.pumpAndSettle();
    expect(c.state.session.outputMode(c.now), 'Countdown');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tall Mission control window adds screens and activity', (
    t,
  ) async {
    await running(t, layout: 'mission_control', size: const Size(1920, 1080));
    final screens = find.byKey(const ValueKey('screens-section'));
    expect(
      find.descendant(of: screens, matching: find.text('Showing on Simulator')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: screens,
        matching: find.text('No stage screens have joined.'),
      ),
      findsOneWidget,
    );
    final activity = find.byKey(const ValueKey('activity-section'));
    // Newest first.
    final started = t
        .widgetList<Text>(
          find.descendant(
            of: activity,
            matching: find.textContaining(' started'),
          ),
        )
        .map((w) => w.data)
        .toList();
    expect(started, [
      'Sermon started',
      'Praise & Worship started',
      'Welcome started',
    ]);
    await t.tap(find.descendant(of: screens, matching: find.text('Manage')));
    await t.pumpAndSettle();
    expect(find.text('Screens & devices'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a laptop Mission control window keeps to what fits', (t) async {
    await running(t, layout: 'mission_control');
    expect(find.byKey(const ValueKey('screens-section')), findsNothing);
    expect(find.byKey(const ValueKey('activity-section')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control shows the service against plan', (t) async {
    final (c, port) = await running(t, layout: 'mission_control');
    final status = find.byKey(const ValueKey('mission-status'));
    Finder inStatus(String text) =>
        find.descendant(of: status, matching: find.text(text));
    expect(inStatus('2 min 50 s behind'), findsOneWidget);
    expect(inStatus('55 min 12 s'), findsOneWidget);
    expect(inStatus('Now ending'), findsOneWidget);
    // Finished segments show what they took and how far over they ran.
    final welcome = find.byKey(const ValueKey('timeline-0'));
    expect(
      find.descendant(of: welcome, matching: find.text('05:40 · +0:40')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-2')),
        matching: find.text('12:38 left of 40:00'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('timeline-now')), findsOneWidget);
    await t.tap(welcome);
    await t.pumpAndSettle();
    expect(find.text('Segment details'), findsOneWidget);
    expect(find.text('Recorded duration: 5 min 40 s'), findsOneWidget);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await c.act('pause');
    port.at = after(port.at.mono ~/ 1000 + 60);
    await c.tick();
    await t.pumpAndSettle();
    expect(inStatus('Ending, if resumed now'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control keeps confirmations, the lock and the keys', (
    t,
  ) async {
    final (c, _) = await running(t, layout: 'mission_control');
    expect(find.byKey(const ValueKey('key-legend')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.active, isTrue);
    // Page Down is Next segment, pressed twice; it never scrolls a pane.
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(c.state.session.index, 2);
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.session.index, 3);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('controls-locked-banner')),
      findsOneWidget,
    );
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.tap(find.byKey(const ValueKey('end-service')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.text('End Sunday Service?'), findsNothing);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'off'),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('key-legend')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Mission control before the start and in overtime', (t) async {
    setScreen(t, const Size(1366, 768));
    final port = DesktopFakePort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        desktopLayout: 'mission_control',
      ),
    );
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // Standing by keeps its centred column.
    expect(find.byKey(const ValueKey('mission-control-live')), findsNothing);
    await c.act('load', value: sunday());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.text('Start first segment'), findsOneWidget);
    expect(find.byKey(const ValueKey('mission-status')), findsNothing);
    expect(find.text('5 segments · 1 h 20 min planned'), findsOneWidget);
    await c.act('start');
    // Six minutes into a five-minute Welcome.
    port.at = after(360);
    await c.tick();
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('timeline-0')),
        matching: find.text('+01:00 over of 05:00'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the rundown shows how the service is running against plan', (
    t,
  ) async {
    await running(t);
    final pane = find.byKey(const ValueKey('rundown-pane'));
    Finder inPane(String text) =>
        find.descendant(of: pane, matching: find.text(text));
    // Welcome ran 40 s over and Praise & Worship 2 min 10 s over.
    expect(inPane('2 min 50 s behind'), findsOneWidget);
    expect(inPane('05:40'), findsOneWidget);
    expect(inPane('+0:40'), findsOneWidget);
    expect(inPane('+2:10'), findsOneWidget);
    expect(inPane('12:38 left'), findsOneWidget);
    expect(inPane('of 40:00'), findsOneWidget);
    expect(inPane('10 min'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('rundown-0')));
    await t.pumpAndSettle();
    expect(find.text('Segment details'), findsOneWidget);
    expect(find.text('Recorded duration: 5 min 40 s'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a paused service says so beside its finish time', (t) async {
    final (c, _) = await running(t, size: const Size(1200, 700));
    await c.act('pause');
    await t.pumpAndSettle();
    expect(find.textContaining('if resumed now'), findsWidgets);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the private note is in view, not folded away', (t) async {
    // A laptop window gives it a line under the title, so the ring keeps
    // its room with the keys line along the foot of the pane.
    await running(t);
    expect(
      find.text(
        'Private note: Altar call follows. Band back on stage at 5:00 left.',
      ),
      findsOneWidget,
    );
    await t.pumpWidget(const SizedBox());
    // A taller one, a block of its own under the controls.
    await running(t, size: const Size(1440, 900));
    expect(
      find.text('Altar call follows. Band back on stage at 5:00 left.'),
      findsOneWidget,
    );
    expect(find.text('View operator notes'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('End service still asks first', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('end-service')));
    await t.pumpAndSettle();
    expect(find.text('End Sunday Service?'), findsOneWidget);
    expect(c.state.session.active, isTrue);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Lock controls blocks the panes until Hold to unlock', (t) async {
    final (c, _) = await running(t);
    await t.tap(find.byKey(const ValueKey('control-lock')));
    await t.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('controls-locked-banner')),
      findsOneWidget,
    );
    await t.tap(
      find.byKey(const ValueKey('pause-resume')),
      warnIfMissed: false,
    );
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    expect(c.state.session.paused, isFalse);
    expect(find.text('Confirm pause'), findsNothing);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('unlock-controls')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('controls-locked-banner')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the header tabs move between pages', (t) async {
    await running(t);
    final home = t.state<HomeState>(find.byType(Home));
    await t.tap(find.byKey(const ValueKey('desktop-tab-1')));
    await t.pumpAndSettle();
    expect(home.page, 1);
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    await t.tap(find.byKey(const ValueKey('desktop-tab-0')));
    await t.pumpAndSettle();
    expect(home.page, 0);
    expect(find.byKey(const ValueKey('three-pane-live')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('standing by offers a program, then Ready shows the panes', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    // A new install is in Mission control: a rail, not tabs in the header.
    expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-tabs')), findsNothing);
    expect(find.byKey(const ValueKey('mission-control-live')), findsNothing);
    expect(find.byKey(const ValueKey('standing-by-desktop')), findsOneWidget);
    expect(find.text('Start service'), findsOneWidget);
    await c.act('load', value: sunday());
    await t.pumpAndSettle();
    // Ready: the layout appears, with the start controls in it.
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.text('Start first segment'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a narrow or short window uses the phone and tablet layout', (
    t,
  ) async {
    for (final size in const [Size(1100, 800), Size(1366, 560)]) {
      await running(t, size: size);
      expect(
        find.byKey(const ValueKey('three-pane-live')),
        findsNothing,
        reason: '$size',
      );
      expect(find.byKey(const ValueKey('desktop-tabs')), findsNothing);
      expect(t.takeException(), isNull, reason: '$size');
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the focused operator view leaves the panes', (t) async {
    await running(t);
    t.state<HomeState>(find.byType(Home)).setFocused(true);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('three-pane-live')), findsNothing);
    expect(find.text('Exit focused view'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('key labels show on a computer and can be turned off', (t) async {
    final (c, _) = await running(t);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('PgDn'), findsOneWidget);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'off'),
    );
    await t.pumpAndSettle();
    expect(find.text('Space'), findsNothing);
    expect(find.text('PgDn'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a tablet shows no key labels unless they are turned on', (
    t,
  ) async {
    setScreen(t, const Size(1366, 768));
    desktopWording = false;
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: sunday());
    await c.act('start');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('mission-control-live')), findsOneWidget);
    expect(find.text('Space'), findsNothing);
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'on'),
    );
    await t.pumpAndSettle();
    expect(find.text('Space'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the running service name in the header returns to Live', (
    t,
  ) async {
    for (final layout in const ['mission_control', 'three_panes']) {
      await running(t, layout: layout);
      final name = find.byKey(const ValueKey('header-return-to-live'));
      // On Live it is only the title.
      expect(t.widget<InkWell>(name).onTap, isNull, reason: layout);
      await t.tap(find.text('Reports'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('rundown-pane')), findsNothing);
      expect(find.byTooltip('Return to Live'), findsWidgets, reason: layout);
      await t.tap(find.byKey(const ValueKey('header-title')));
      await t.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey(
            layout == 'mission_control'
                ? 'mission-control-live'
                : 'three-pane-live',
          ),
        ),
        findsOneWidget,
        reason: layout,
      );
      await t.pumpWidget(const SizedBox());
    }
    // With no service loaded the title is the app's name, and it still
    // returns to Live, standing by.
    setScreen(t, const Size(1366, 768));
    final c = AppController(DesktopFakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('header-title')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('standing-by-desktop')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('choosing a layout previews it and Save keeps it', (t) async {
    final (c, _) = await running(t, theme: 'graphite');
    await openLayoutSettings(t);
    expect(
      find.byKey(const ValueKey('desktop-layout-section')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-layout-settings.png'),
    );
    // Classic keeps the theme in use.
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    expect(c.appearanceSelection.value.desktopLayout, 'classic');
    expect(c.themeSelection.value, 'graphite');
    expect(c.state.appearance.desktopLayout, 'three_panes');
    // Three panes arrives with Midnight Lime.
    await press(t, find.byKey(const ValueKey('desktop-layout-three_panes')));
    expect(c.themeSelection.value, 'midnight_lime');
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    await t.tap(find.text('Save appearance'));
    await t.pumpAndSettle();
    expect(c.state.appearance.desktopLayout, 'classic');
    expect(c.state.themeId, 'midnight_lime');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Desktop layout has its own row in Settings and in search', (
    t,
  ) async {
    final (c, _) = await running(
      t,
      layout: 'mission_control',
      size: const Size(1920, 1080),
    );
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    // The row names the layout in use and opens straight on its tab.
    expect(find.text('Mission control · for a wide window'), findsOneWidget);
    await press(t, find.text('Desktop layout'));
    expect(
      find.byKey(const ValueKey('desktop-layout-section')),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    // Appearance still opens on Theme, with a pointer to the other tab.
    await press(t, find.text('Appearance'));
    expect(find.byKey(const ValueKey('desktop-layout-section')), findsNothing);
    await press(t, find.byKey(const ValueKey('to-desktop-layout')));
    expect(
      find.byKey(const ValueKey('desktop-layout-section')),
      findsOneWidget,
    );
    expect(c.state.appearance.desktopLayout, 'mission_control');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Cancel leaves the layout and theme as they were', (t) async {
    final (c, _) = await running(t, theme: 'graphite');
    await openLayoutSettings(t);
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    await press(t, find.byKey(const ValueKey('desktop-layout-three_panes')));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(c.state.appearance.desktopLayout, 'three_panes');
    expect(c.state.themeId, 'graphite');
    expect(c.themeSelection.value, 'graphite');
    expect(c.appearanceSelection.value.desktopLayout, 'three_panes');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a look can be saved, used again, replaced and deleted', (
    t,
  ) async {
    final (c, _) = await running(t, theme: 'royal_navy');
    await openLayoutSettings(t);
    await press(t, find.byKey(const ValueKey('desktop-layout-classic')));
    await press(t, find.byKey(const ValueKey('save-look')));
    // A name is needed.
    await t.tap(find.byKey(const ValueKey('look-name-save')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('look-name')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('look-name')), 'Midweek');
    await t.tap(find.byKey(const ValueKey('look-name-save')));
    await t.pumpAndSettle();
    // Kept at once, whatever happens to the rest of the page.
    expect(c.state.savedLooks.single.name, 'Midweek');
    expect(c.state.savedLooks.single.layout, 'classic');
    expect(c.state.savedLooks.single.themeId, 'royal_navy');
    expect(c.state.appearance.desktopLayout, 'three_panes');

    // Back to the default, then the saved look brings both back.
    await press(t, find.byKey(const ValueKey('reset-look')));
    expect(c.appearanceSelection.value.desktopLayout, 'mission_control');
    expect(c.themeSelection.value, 'midnight_lime');
    await press(t, find.byKey(const ValueKey('saved-look-Midweek')));
    expect(c.appearanceSelection.value.desktopLayout, 'classic');
    expect(c.themeSelection.value, 'royal_navy');

    // Saving under the same name replaces it.
    await press(t, find.byKey(const ValueKey('reset-look')));
    await press(t, find.byKey(const ValueKey('save-look')));
    await t.enterText(find.byKey(const ValueKey('look-name')), 'midweek');
    await t.pump();
    expect(
      find.text('This replaces the saved look with the same name.'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('look-name-save')));
    await t.pumpAndSettle();
    expect(c.state.savedLooks.single.name, 'midweek');
    expect(c.state.savedLooks.single.layout, 'mission_control');

    await press(t, find.byTooltip('Delete midweek'));
    await t.tap(find.text('Delete look'));
    await t.pumpAndSettle();
    expect(c.state.savedLooks, isEmpty);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Reset returns to Mission control with Midnight Lime', (t) async {
    final (c, _) = await running(t, layout: 'classic', theme: 'paper_ink');
    await c.commit(
      (draft, _) => draft.appearance = draft.appearance.copyWith(
        density: 'compact',
        highContrast: true,
        keyHints: 'off',
        dividers: 'strong',
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('Appearance'));
    await t.pumpAndSettle();
    await t.tap(find.text('Layout & accessibility'));
    await t.pumpAndSettle();
    await press(t, find.byKey(const ValueKey('reset-look')));
    await t.tap(find.text('Save appearance'));
    await t.pumpAndSettle();
    expect(c.state.themeId, 'midnight_lime');
    expect(c.state.appearance.desktopLayout, 'mission_control');
    expect(c.state.appearance.density, 'automatic');
    expect(c.state.appearance.highContrast, isFalse);
    expect(c.state.appearance.keyHints, 'automatic');
    // What a look does not cover is left alone.
    expect(c.state.appearance.dividers, 'strong');
    await t.pumpWidget(const SizedBox());
  });
}

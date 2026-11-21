import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

/// The screens Live is checked on: the window sizes the app gets on the
/// laptops and monitors most churches have, at the display scaling Windows
/// gives them, and tablets held in landscape and portrait.
class DesktopPort extends FakePort {
  @override
  bool get isDesktop => true;
  @override
  Future<Json> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': false,
  };
  @override
  Future<bool> setActiveService(bool enabled) async => enabled;
}

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

/// Window sizes with the desktop layouts, each of which has room for the
/// keys line: laptops at 100%, 125% and 150% display scaling, monitors,
/// ultrawides and 4K.
const stripWindows = [
  Size(1270, 790), // 1920 × 1200 at 150%
  Size(1280, 720), // 1920 × 1080 at 150%
  Size(1280, 800),
  Size(1366, 768),
  Size(1440, 900),
  Size(1536, 864), // 1920 × 1080 at 125%
  Size(1600, 900),
  Size(1680, 1050),
  Size(1920, 1080),
  Size(1920, 1200),
  Size(2560, 1080),
  Size(2560, 1440),
  Size(3440, 1440),
  Size(3840, 2160),
];

/// Windows under 1200 wide, which have Classic whatever the choice:
/// 1366 × 768 at 125%, 1920 × 1080 and 1920 × 1200 at about 166% and
/// 150%, a 1024 × 768 screen and tablets in landscape and portrait.
const classicWindows = [
  Size(1000, 600),
  Size(1024, 768),
  Size(1093, 614),
  Size(1152, 864),
  Size(1154, 957),
  Size(1180, 820),
  Size(1154, 1050),
  Size(1100, 1100),
  Size(1024, 1366),
];

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  /// Live in a [size] window in [layout], two seconds into the Welcome,
  /// or in Ready when [ready]. [segment] moves on to a later segment
  /// first; the Sermon has a private note.
  Future<AppController> live(
    WidgetTester t, {
    required Size size,
    String layout = 'three_panes',
    bool ready = false,
    int segment = 0,
    FakePort? port,
  }) async {
    setScreen(t, size);
    final p = port ?? DesktopPort();
    final c = AppController(p);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: layout);
    });
    await c.act('load', value: sunday());
    if (!ready) {
      await c.act('start');
      var at = 0;
      for (var i = 0; i < segment; i++) {
        at += 60;
        p.at = after(at);
        await c.tick();
        await c.act('advance');
      }
      p.at = after(at + 2);
      await c.tick();
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  /// [target] is on screen, can be pressed, and ends above [bottom].
  void inReach(
    WidgetTester t,
    Finder target,
    Size size,
    String where, {
    double? bottom,
  }) {
    expect(target, findsOneWidget, reason: where);
    expect(target.hitTestable(), findsOneWidget, reason: where);
    final rect = t.getRect(target);
    expect(
      rect.bottom,
      lessThanOrEqualTo(bottom ?? size.height),
      reason: where,
    );
    expect(rect.right, lessThanOrEqualTo(size.width), reason: where);
    expect(rect.left, greaterThanOrEqualTo(0), reason: where);
  }

  final legend = find.byKey(const ValueKey('key-legend'));

  for (final layout in const [
    'three_panes',
    'dial',
    'mission_control',
    'keys',
  ]) {
    testWidgets('$layout has the keys line on every common screen', (t) async {
      for (final size in stripWindows) {
        for (final segment in const [0, 2]) {
          await live(t, size: size, layout: layout, segment: segment);
          final where = '$layout at $size, segment $segment';
          expect(t.takeException(), isNull, reason: where);
          inReach(t, legend, size, where);
          // The keys line sits along the foot of the window or the pane,
          // under every timer control.
          final top = t.getRect(legend).top;
          for (final key in ['pause-resume', 'next-segment', 'end-service']) {
            inReach(
              t,
              find.byKey(ValueKey(key)),
              size,
              '$key, $where',
              bottom: layout == 'mission_control' || layout == 'keys'
                  ? size.height
                  : top,
            );
          }
          await t.pumpWidget(const SizedBox());
        }
        // Ready keeps the room for the line, with the form in reach.
        await live(t, size: size, layout: layout, ready: true);
        final where = '$layout in Ready at $size';
        expect(t.takeException(), isNull, reason: where);
        for (final item in [
          find.text('Start first segment'),
          find.text('Cancel setup'),
          find.byKey(const ValueKey('check-service')),
        ]) {
          inReach(t, item, size, '$item, $where');
        }
        await t.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('the keys line goes only where the ring has no room for it', (
    t,
  ) async {
    // 1200 × 600 is too short for the panes even without it.
    for (final layout in ['three_panes', 'dial']) {
      await live(t, size: const Size(1200, 600), layout: layout);
      expect(t.takeException(), isNull, reason: layout);
      expect(legend, findsNothing, reason: layout);
      expect(find.byKey(const ValueKey('pause-resume')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
    // Key labels off: no keys line, and the ring has the height.
    final c = await live(t, size: const Size(1366, 768));
    final ring = t.getSize(find.byType(SegmentGauge)).height;
    await c.commit(
      (draft, _) =>
          draft.appearance = draft.appearance.copyWith(keyHints: 'off'),
    );
    await t.pumpAndSettle();
    expect(legend, findsNothing);
    expect(t.getSize(find.byType(SegmentGauge)).height, greaterThan(ring));
    await t.pumpWidget(const SizedBox());
  });

  /// Every line of text in [scope] is drawn in full: nothing cut short
  /// with "…", and none that should keep to one line wraps. Cues may take
  /// two lines, but only between words.
  void readsInFull(WidgetTester t, Finder scope, String where) {
    for (final element
        in find
            .descendant(of: scope, matching: find.byType(RichText))
            .evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      if (!paragraph.attached || paragraph.size.isEmpty) continue;
      final text = paragraph.text.toPlainText();
      expect(paragraph.didExceedMaxLines, isFalse, reason: '"$text", $where');
      final cue =
          element.findAncestorWidgetOfExactType<Tooltip>() != null &&
          text == text.toUpperCase() &&
          text.trim().length > 2;
      final width = paragraph.size.width + .5;
      if (cue) {
        // Each word fits on a line of its own.
        for (final word in text.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: paragraph.text.style),
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
          )..layout();
          expect(
            painter.width,
            lessThanOrEqualTo(width),
            reason: 'the word "$word" of the cue, $where',
          );
          painter.dispose();
        }
      } else {
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(width),
          reason: '"$text" wraps, $where',
        );
      }
    }
  }

  Finder inButtons(Finder scope) => find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );

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

  for (final (name, port) in [
    ('a computer', () => DesktopPort()),
    ('a tablet', () => FakePort()),
  ]) {
    testWidgets('Classic reads in full and fills the window on $name', (
      t,
    ) async {
      if (name == 'a tablet') desktopWording = false;
      for (final size in classicWindows) {
        for (final ready in [false, true]) {
          final c = await live(
            t,
            size: size,
            layout: 'classic',
            ready: ready,
            port: port(),
          );
          final where = 'Classic at $size${ready ? ' in Ready' : ''}';
          expect(t.takeException(), isNull, reason: where);
          expect(find.byKey(const ValueKey('navigation-rail')), findsOneWidget);
          final card = find.byKey(const ValueKey('timer-card-content'));
          // The controls, or the Ready form, without scrolling.
          for (final item
              in ready
                  ? [
                      find.text('Start first segment'),
                      find.text('Cancel setup'),
                    ]
                  : [
                      find.byKey(const ValueKey('pause-resume')),
                      find.byKey(const ValueKey('next-segment')),
                      find.byKey(const ValueKey('end-service')),
                      find.byKey(const ValueKey('undo')),
                    ]) {
            expect(item, findsOneWidget, reason: '$item, $where');
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
          // Every button label in the timer card on one line, in full,
          // and the headings and cues beside it.
          readsInFull(t, inButtons(card), where);
          readsInFull(
            t,
            find.byKey(const ValueKey('display-preview-header')),
            where,
          );
          for (final cue in c.state.stageCues) {
            readsInFull(
              t,
              find
                  .ancestor(
                    of: find.text(cue.text),
                    matching: find.byWidgetPredicate(
                      (w) => w is ButtonStyleButton,
                    ),
                  )
                  .first,
              '${cue.text}, $where',
            );
          }
          if (!ready) {
            // A ring that uses the window, and no band of empty page
            // under the card while there is height for it. The smallest
            // window gives the ring up first, so the controls keep to one
            // line beside it.
            final ring = ringWidth(t);
            expect(
              ring,
              greaterThanOrEqualTo(
                size.width <= 1000
                    ? 160
                    : size.height < 700
                    ? 200
                    : 250,
              ),
              reason: where,
            );
            if (size.height >= 700 && size.height <= 1100) {
              expect(
                t.getRect(card).bottom,
                greaterThan(size.height - 150),
                reason: where,
              );
            }
            // A later segment with a private note keeps it all in reach.
            await t.pumpWidget(const SizedBox());
            await live(
              t,
              size: size,
              layout: 'classic',
              segment: 2,
              port: port(),
            );
            expect(t.takeException(), isNull, reason: '$where, Sermon');
            for (final key in ['pause-resume', 'next-segment', 'end-service']) {
              expect(
                t.getRect(find.byKey(ValueKey(key))).bottom,
                lessThanOrEqualTo(size.height),
                reason: '$key, $where, Sermon',
              );
            }
            readsInFull(t, inButtons(card), '$where, Sermon');
          } else {
            // Starting keeps the ring at its size.
            final before = ringWidth(t);
            await c.act('start');
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: where);
            expect(ringWidth(t), before, reason: where);
          }
          await t.pumpWidget(const SizedBox());
        }
      }
      desktopWording = true;
    });
  }

  testWidgets('Classic in a narrow laptop window puts the ring first', (
    t,
  ) async {
    // 1731 × 1435 at 150%, the window reported: the ring centred under the
    // title and filling the height, with the controls across the card
    // under it.
    await live(t, size: const Size(1154, 957), layout: 'classic');
    expect(find.byKey(const ValueKey('classic-stacked')), findsOneWidget);
    expect(ringWidth(t), greaterThan(360));
    await t.pumpWidget(const SizedBox());
    // Taller still, as large as it goes.
    await live(t, size: const Size(1154, 1050), layout: 'classic');
    expect(find.byKey(const ValueKey('classic-stacked')), findsOneWidget);
    expect(ringWidth(t), greaterThan(420));
    await t.pumpWidget(const SizedBox());
    // A shorter one has the title beside the ring.
    await live(t, size: const Size(1024, 768), layout: 'classic');
    expect(find.byKey(const ValueKey('classic-title-beside')), findsOneWidget);
    expect(ringWidth(t), greaterThan(250));
    await t.pumpWidget(const SizedBox());
    // A laptop keeps the controls beside the ring.
    await live(t, size: const Size(1366, 768), layout: 'classic');
    expect(find.byKey(const ValueKey('classic-beside')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Custom keeps to one line in a narrow Classic window', (t) async {
    // So narrow that "Custom" has no room for its key: the key goes, the
    // word stays whole.
    await live(t, size: const Size(1093, 614), layout: 'classic');
    expect(find.text('Custom'), findsOneWidget);
    readsInFull(
      t,
      inButtons(find.byKey(const ValueKey('timer-card-content'))),
      '1093 × 614',
    );
    await t.pumpWidget(const SizedBox());
  });

  // Classic in the windows under 1200 wide it was reported in. Three
  // panes at 1270 × 790, with the keys line, is desktop-three-panes-1270.
  for (final size in const [Size(1154, 957), Size(1024, 768)]) {
    final width = size.width.round();
    testWidgets('Classic in a $size window, running and Ready', (t) async {
      await live(t, size: size, layout: 'classic');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-classic-$width.png'),
      );
      await t.pumpWidget(const SizedBox());
      await live(t, size: size, layout: 'classic', ready: true);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/desktop-classic-ready-$width.png'),
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}

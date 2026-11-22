import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';
import 'screen_sizes_test.dart' show DesktopPort, sunday;

/// Classic's Live page at every window width from 600 to 2000, at heights
/// from 600 to 1100: nothing overflows, no button label or heading is cut
/// or wrapped, the controls stay in reach, and the two columns of cards
/// end about together, with no large empty band.
/// The sweeps take about 20 seconds each, longer on a busy machine.
const sweepTimeout = Timeout(Duration(minutes: 5));

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  // Every 20 from 600 to 2000, and the widths reported or common.
  final widths = <double>{
    for (var w = 600.0; w <= 2000; w += 20) w,
    964,
    1000,
    1024,
    1154,
    1199,
    1200,
    1270,
    1280,
    1366,
    1440,
    1536,
    1600,
    1920,
  }.toList()..sort();
  final keyWidths = {
    964.0,
    1000.0,
    1024.0,
    1154.0,
    1199.0,
    1200.0,
    1270.0,
    1366.0,
    1920.0,
  };
  const heights = [600.0, 700.0, 800.0, 900.0, 1000.0, 1100.0];

  /// The heights tried at [width]: all of them at the widths reported, and
  /// three of them, moving along with the width, at the rest.
  List<double> heightsAt(double width) {
    if (keyWidths.contains(width)) return heights;
    final i = (width ~/ 20) % heights.length;
    return [heights[i], heights[(i + 3) % 6]];
  }

  /// What is wrong, found by the checks, one line each.
  final problems = <String>[];

  void resize(WidgetTester t, Size size) {
    t.view.physicalSize = size;
    t.view.display.size = size;
  }

  Future<AppController> start(
    WidgetTester t,
    Size size, {
    required String state,
    required FakePort port,
  }) async {
    setScreen(t, size);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(desktopLayout: 'classic');
    });
    if (state != 'standing-by') {
      await c.act('load', value: sunday());
      if (state != 'ready') {
        await c.act('start');
        var at = 0;
        if (state == 'sermon') {
          for (var i = 0; i < 2; i++) {
            at += 60;
            port.at = after(at);
            await c.tick();
            await c.act('advance');
          }
        }
        port.at = after(at + 2);
        await c.tick();
      }
    }
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  /// Every line of text on the page is drawn in full: none cut short with
  /// "…", and the ones that should keep to one line, in buttons and
  /// panel headings, do not wrap.
  void readsInFull(String where) {
    for (final element in find.byType(RichText).evaluate()) {
      final paragraph = element.renderObject! as RenderParagraph;
      if (!paragraph.attached || paragraph.size.isEmpty) continue;
      final text = paragraph.text.toPlainText();
      if (paragraph.didExceedMaxLines)
        problems.add('"$text" cut short, $where');
      var inButton = false;
      element.visitAncestorElements((e) {
        if (e.widget is ButtonStyleButton) inButton = true;
        return !inButton;
      });
      if (!inButton &&
          !const [
            'DISPLAY PREVIEW',
            'STAGE CUES',
            'SERVICE RUNDOWN',
          ].contains(text)) {
        continue;
      }
      // A cue may take two lines, but only between words.
      final cue =
          element.findAncestorWidgetOfExactType<Tooltip>() != null &&
          text == text.toUpperCase() &&
          text.trim().length > 2;
      final width = paragraph.size.width + .5;
      if (cue) {
        for (final word in text.split(' ')) {
          final painter = TextPainter(
            text: TextSpan(text: word, style: paragraph.text.style),
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
          )..layout();
          if (painter.width > width) {
            problems.add('the word "$word" of the cue breaks, $where');
          }
          painter.dispose();
        }
      } else if (paragraph.getMaxIntrinsicWidth(double.infinity) > width) {
        problems.add('"$text" wraps, $where');
      }
    }
  }

  /// The two columns of cards end about together. Where the cards sit in
  /// two columns, the empty band under the shorter column, as far as the
  /// window shows it, is under a quarter of the window height; or the
  /// longer column's last card is too tall for moving it to bring the
  /// columns any closer, as a long rundown is.
  void balanced(WidgetTester t, Size size, String where) {
    final cards = {
      for (final e in find.byWidgetPredicate((w) {
        final k = w.key;
        return k is ValueKey<String> && k.value.startsWith('classic-card:');
      }).evaluate())
        (e.widget.key! as ValueKey<String>).value: t.getRect(
          find.byWidget(e.widget),
        ),
    };
    if (cards.isEmpty) return;
    final timer = cards['classic-card:timer'];
    // A very wide window has the rundown in a column of its own.
    if (timer == null) return;
    final left = cards.values.where((r) => r.left < timer.left + 1).toList();
    final right = cards.values.where((r) => r.left >= timer.left + 1).toList();
    if (right.isEmpty) return;
    double bottom(List<Rect> rects) =>
        rects.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
    final bl = bottom(left), br = bottom(right);
    final gap = (bl - br).abs();
    final taller = bl > br ? left : right;
    final lastCard = taller.reduce((a, b) => b.bottom > a.bottom ? b : a);
    // The empty band under the shorter column, as far as the window shows.
    final shown = (bl > br ? br : bl);
    final visible = ((bl > br ? bl : br).clamp(0, size.height) - shown)
        .clamp(0, size.height)
        .toDouble();
    if (visible > size.height * .25 && lastCard.height < 2 * gap) {
      problems.add(
        'columns end at ${bl.round()} and ${br.round()}, '
        'a band ${visible.round()} high in view, $where',
      );
    }
  }

  void checks(WidgetTester t, Size size, String state, bool computer) {
    {
      final where = '$state at $size${computer ? '' : ' (tablet)'}';
      final thrown = t.takeException();
      if (thrown != null) problems.add('exception $thrown, $where');
      final list = <Finder>[
        if (state == 'standing-by')
          find.text('Start service')
        else if (state == 'ready') ...[
          find.text('Start first segment'),
          find.text('Cancel setup'),
        ] else ...[
          find.byKey(const ValueKey('pause-resume')),
          find.byKey(const ValueKey('next-segment')),
          find.byKey(const ValueKey('end-service')),
        ],
      ];
      for (final item in list) {
        if (item.evaluate().length != 1) {
          problems.add(
            '${item.describeMatch(Plurality.one)} not found once, $where',
          );
          continue;
        }
        if (size.height >= 700) {
          final rect = t.getRect(item);
          if (rect.bottom > size.height || rect.right > size.width) {
            problems.add(
              '${item.describeMatch(Plurality.one)} out of the window at '
              '${rect.bottom.round()}, $where',
            );
          }
        }
      }
      readsInFull(where);
      if (state != 'standing-by') balanced(t, size, where);
    }
  }

  /// A computer in Classic, one state at a time, resized through the
  /// widths. The controls are in reach wherever the window is 700 or more
  /// high; 600 high keeps them within the page, reached by scrolling.
  Future<void> sweep(
    WidgetTester t, {
    required String state,
    required bool computer,
    required List<Size> sizes,
  }) async {
    desktopWording = computer;
    final port = computer ? DesktopPort() : FakePort();
    final c = await start(t, sizes.first, state: state, port: port);
    // Every failure is collected, so one run lists them all.
    problems.clear();
    for (final size in sizes) {
      resize(t, size);
      await t.pump();
      await t.pumpAndSettle();
      checks(t, size, state, computer);
    }
    expect(problems, isEmpty, reason: '\n${problems.join('\n')}');
    expect(c.state.stageCues, isNotEmpty);
    await t.pumpWidget(const SizedBox());
  }

  for (final state in const ['standing-by', 'ready', 'running', 'sermon']) {
    testWidgets(
      'Classic at every width on a computer: $state',
      timeout: sweepTimeout,
      (t) async {
        await sweep(
          t,
          state: state == 'running' ? 'run' : state,
          computer: true,
          sizes: [
            for (final w in widths)
              for (final h in heightsAt(w)) Size(w, h),
          ],
        );
      },
    );
  }

  // Tablets, held both ways, and phones in portrait, which keep one
  // column.
  const tablets = [
    Size(600, 960),
    Size(768, 1024),
    Size(800, 1280),
    Size(820, 1180),
    Size(834, 1194),
    Size(912, 1368),
    Size(1024, 1366),
    Size(960, 600),
    Size(1024, 768),
    Size(1180, 820),
    Size(1194, 834),
    Size(1280, 800),
    Size(1366, 1024),
  ];
  for (final state in const ['ready', 'run', 'sermon']) {
    testWidgets('Classic on tablets: $state', timeout: sweepTimeout, (t) async {
      await sweep(t, state: state, computer: false, sizes: tablets);
    });
  }

  testWidgets('Classic at 964 × 1100 puts the rundown under the timer', (
    t,
  ) async {
    // The reported window: the rundown under the timer card, in the room
    // beside the display and cues, not far down the second column.
    for (final ready in [false, true]) {
      await start(
        t,
        const Size(964, 1100),
        state: ready ? 'ready' : 'run',
        port: DesktopPort(),
      );
      final timer = t.getRect(find.byKey(const ValueKey('classic-card:timer')));
      final rundown = t.getRect(
        find.byKey(const ValueKey('classic-card:rundown')),
      );
      final cues = t.getRect(find.byKey(const ValueKey('classic-card:cues')));
      expect(rundown.left, timer.left, reason: 'ready $ready');
      expect(rundown.top, greaterThan(timer.bottom));
      expect(rundown.top, lessThan(timer.bottom + 40));
      expect(cues.left, greaterThan(timer.right));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          '../goldens/desktop-classic-${ready ? 'ready-' : ''}964x1100.png',
        ),
      );
      await t.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Classic at 1366 × 768 and on a tablet in portrait', (t) async {
    await start(t, const Size(1366, 768), state: 'run', port: DesktopPort());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-classic-1366x768.png'),
    );
    await t.pumpWidget(const SizedBox());
    desktopWording = false;
    await start(t, const Size(834, 1194), state: 'run', port: FakePort());
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/tablet-classic-834x1194.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Classic on a phone keeps one column', (t) async {
    desktopWording = false;
    for (final size in const [Size(360, 800), Size(390, 844), Size(430, 932)]) {
      await start(t, size, state: 'run', port: FakePort());
      expect(t.takeException(), isNull, reason: '$size');
      expect(find.byKey(const ValueKey('classic-card:timer')), findsNothing);
      await t.pumpWidget(const SizedBox());
    }
  });
}

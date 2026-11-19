import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../live/desktop_layout_test.dart' show DesktopFakePort;
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

Timeline sunday() => Timeline('Sunday Service', const [
  Segment('Welcome', 5, speaker: 'Deacon Ruth'),
  Segment('Praise & Worship', 20, speaker: 'Worship team'),
  Segment('Sermon', 40, speaker: 'Pastor Samuel', notes: 'Altar call follows.'),
  Segment('Response', 10, speaker: 'Worship team'),
  Segment('Closing', 5),
], DisplaySettings());

class RecordingPort extends DesktopFakePort {
  final exports = <String, String>{};
  @override
  Future<void> exportFile(String filename, String content) async =>
      exports[filename] = content;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => desktopWording = true);
  tearDown(() => desktopWording = false);

  /// Seconds into the fake clock, carried from one service to the next.
  var clock = 0;
  setUp(() => clock = 0);

  /// Runs [program] to the end, each segment taking [seconds]; a null
  /// entry is skipped by jumping past it.
  Future<void> serve(
    AppController c,
    DesktopFakePort port,
    Timeline program,
    List<int?> seconds, {
    int? rate,
  }) async {
    expect(await c.act('load', value: program), isTrue, reason: c.error);
    if (rate != null) expect(await c.act('rate', value: rate), isTrue);
    expect(await c.act('start'), isTrue, reason: c.error);
    for (var i = 0; i < seconds.length; i++) {
      if (seconds[i] == null) continue;
      clock += seconds[i]!;
      port.at = after(clock);
      await c.tick();
      if (i == seconds.length - 1) break;
      var next = i + 1;
      while (seconds[next] == null) {
        next++;
      }
      expect(
        await (next == i + 1 ? c.act('advance') : c.act('jump', value: next)),
        isTrue,
        reason: c.error,
      );
    }
    expect(await c.act('end'), isTrue, reason: c.error);
    // A gap before the next service.
    clock += 3600;
    port.at = after(clock);
    await c.tick();
  }

  /// A service where some segments ran over and some under.
  Future<void> mixed(AppController c, DesktopFakePort port) =>
      serve(c, port, sunday(), [340, 1330, 2250, 720, 270]);

  Future<(AppController, RecordingPort)> app(
    WidgetTester t, {
    Size size = const Size(1366, 768),
    String layout = 'three_panes',
    String theme = 'midnight_lime',
    String? density,
    Future<void> Function(AppController, DesktopFakePort)? services,
  }) async {
    setScreen(t, size);
    final port = RecordingPort();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.commit((draft, _) {
      draft.appearance = draft.appearance.copyWith(
        desktopLayout: layout,
        density: density,
      );
      draft.themeId = theme;
    });
    await (services ?? mixed)(c, port);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports').first);
    await t.pumpAndSettle();
    return (c, port);
  }

  Finder inRow(int i, String text) => find.descendant(
    of: find.byKey(ValueKey('report-row-$i')),
    matching: find.text(text),
  );

  const page = ValueKey('reports-desktop');
  const ring = ValueKey('report-ring');
  const timeline = ValueKey('report-timeline');

  testWidgets('the timeline report at laptop size', (t) async {
    await app(t);
    expect(t.takeException(), isNull);
    expect(find.byKey(page), findsOneWidget);
    expect(find.byKey(timeline), findsOneWidget);
    expect(find.byKey(ring), findsNothing);
    expect(find.byKey(const ValueKey('master-detail')), findsNothing);
    // The list keeps its search, filters and tabs.
    expect(find.byKey(const ValueKey('report-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-date-filter')), findsOneWidget);
    expect(find.text('Live only'), findsOneWidget);
    expect(find.text('Graph'), findsOneWidget);
    expect(
      t.getSize(find.byKey(const ValueKey('reports-list-pane'))).width,
      300,
    );
    // The report fills the rest of the window.
    expect(
      t.getRect(find.byKey(const ValueKey('report-detail-pane'))).right,
      1366,
    );
    expect(find.byKey(const ValueKey('report-name')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('report-when'))).data,
      contains(' to '),
    );
    expect(
      find.byKey(const ValueKey('print-report')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('report-actions')).hitTestable(),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-reports-timeline.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the ring report in The dial with Royal Navy', (t) async {
    await app(t, layout: 'dial', theme: 'royal_navy');
    expect(t.takeException(), isNull);
    expect(find.byKey(page), findsOneWidget);
    expect(find.byKey(ring), findsOneWidget);
    expect(find.byKey(timeline), findsNothing);
    expect(find.text('1 h 21 min 50 s'), findsWidgets);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('report-ring-variance'))).data,
      '1 min 50 s over',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('report-ring-planned'))).data,
      'planned 1 h 20 min',
    );
    // Segments a minute or more over are in the warning colour, and the
    // rest in a colour that is neither the warning nor the gold accent.
    final painter =
        t
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byKey(ring),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as ReportRingPainter;
    expect(painter.over, {1, 3});
    final colors = Theme.of(
      t.element(find.byKey(ring)),
    ).extension<AppPalette>()!;
    expect(painter.warning, colors.warning);
    expect(painter.ran, isNot(colors.warning));
    expect(painter.ran, isNot(colors.accent));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/desktop-reports-ring.png'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the table gives planned, actual and variance per segment', (
    t,
  ) async {
    await app(t);
    for (final (i, cells) in [
      ['Welcome', '5 min', '5 min 40 s', '40 s over'],
      ['Praise & Worship', '20 min', '22 min 10 s', '2 min 10 s over'],
      ['Sermon', '40 min', '37 min 30 s', '2 min 30 s under'],
      ['Response', '10 min', '12 min', '2 min over'],
      ['Closing', '5 min', '4 min 30 s', '30 s under'],
    ].indexed) {
      for (final cell in cells) {
        expect(inRow(i, cell), findsOneWidget, reason: 'row $i: $cell');
      }
      expect(
        find.descendant(
          of: find.byKey(ValueKey('report-row-$i')),
          matching: find.byType(VarianceBar),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report-row-total')),
        matching: find.text('1 min 50 s over'),
      ),
      findsOneWidget,
    );
    // What the folded rows used to hold is in view.
    expect(
      inRow(2, 'Pastor Samuel · Private note: Altar call follows.'),
      findsOneWidget,
    );
    // Planned and actual blocks for every segment.
    for (var i = 0; i < 5; i++) {
      expect(find.byKey(ValueKey('report-planned-$i')), findsOneWidget);
      expect(find.byKey(ValueKey('report-actual-$i')), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
  });

  for (final (layout, size) in [
    ('three_panes', const Size(1920, 1080)),
    ('dial', const Size(1920, 1080)),
    ('mission_control', const Size(1366, 768)),
    ('mission_control', const Size(1920, 1080)),
    ('keys', const Size(1366, 768)),
    ('keys', const Size(1920, 1080)),
  ]) {
    testWidgets('$layout at ${size.width.round()} wide', (t) async {
      await app(
        t,
        layout: layout,
        size: size,
        density: layout == 'keys' ? 'compact' : null,
      );
      expect(t.takeException(), isNull);
      expect(find.byKey(page), findsOneWidget);
      expect(
        find.byKey(ring),
        layout == 'dial' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(timeline),
        layout == 'dial' ? findsNothing : findsOneWidget,
      );
      expect(
        t.getRect(find.byKey(const ValueKey('report-detail-pane'))).right,
        size.width,
      );
      expect(
        find.byKey(const ValueKey('print-report')).hitTestable(),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a narrow window keeps the list and detail page', (t) async {
    await app(t, size: const Size(1100, 768));
    expect(t.takeException(), isNull);
    expect(find.byKey(page), findsNothing);
    expect(find.byKey(const ValueKey('master-detail')), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a phone keeps the list, and a tap opens the old report page', (
    t,
  ) async {
    final (c, _) = await app(t, size: const Size(430, 1000));
    expect(find.byKey(page), findsNothing);
    await t.tap(find.byKey(ValueKey('open-report-${c.state.reports.last.id}')));
    await t.pumpAndSettle();
    expect(find.text('Service report'), findsOneWidget);
    expect(find.text('Segment breakdown'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-table')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Classic keeps the list and detail page', (t) async {
    await app(t, layout: 'classic');
    expect(t.takeException(), isNull);
    expect(find.byKey(page), findsNothing);
    expect(find.byKey(const ValueKey('master-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-table')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  for (final layout in ['three_panes', 'dial']) {
    testWidgets('a skipped segment takes no room ($layout)', (t) async {
      await app(
        t,
        layout: layout,
        services: (c, port) =>
            serve(c, port, sunday(), [300, 1200, 2400, null, 310]),
      );
      expect(t.takeException(), isNull);
      expect(inRow(3, 'Skipped'), findsOneWidget);
      expect(inRow(3, '—'), findsOneWidget);
      if (layout == 'three_panes') {
        expect(find.byKey(const ValueKey('report-planned-3')), findsOneWidget);
        expect(find.byKey(const ValueKey('report-actual-3')), findsNothing);
        expect(find.byKey(const ValueKey('report-actual-4')), findsOneWidget);
      }
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a one-segment service and a quick timer ($layout)', (t) async {
      final (c, _) = await app(
        t,
        layout: layout,
        services: (c, port) async {
          await serve(
            c,
            port,
            Timeline('Prayer', const [
              Segment('Prayer', 15),
            ], DisplaySettings()),
            [960],
          );
          expect(
            await c.startQuickTimer(
              const QuickTimerChoice('Offering', 180),
              saveReport: true,
            ),
            isTrue,
          );
          clock += 150;
          port.at = after(clock);
          await c.tick();
          expect(await c.act('end'), isTrue, reason: c.error);
        },
      );
      expect(t.takeException(), isNull);
      // The newest report, the quick timer, shows first.
      expect(c.state.reports, hasLength(2));
      expect(inRow(0, 'Offering'), findsOneWidget);
      expect(inRow(0, '3 min'), findsOneWidget);
      expect(inRow(0, '2 min 30 s'), findsOneWidget);
      expect(find.text('QUICK TIMER'), findsOneWidget);
      final prayer = c.state.reports.firstWhere((r) => r.name == 'Prayer');
      await t.tap(find.byKey(ValueKey('open-report-${prayer.id}')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(inRow(0, '15 min'), findsOneWidget);
      expect(inRow(0, '16 min'), findsOneWidget);
      expect(inRow(0, '1 min over'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-row-1')), findsNothing);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a rehearsal and a report with partial timing ($layout)', (
      t,
    ) async {
      final (c, _) = await app(
        t,
        layout: layout,
        services: (c, port) async {
          // Ten times speed: 30 s of clock is 5 min of service.
          await serve(c, port, sunday(), [30, 130, 240, 55, 30], rate: 10);
          final r = c.state.reports.single;
          // An older record with no start, total or second segment time.
          await c.commit((draft, _) {
            draft.reports.add(
              ServiceReport(
                'partial',
                'Evening Prayer',
                null,
                r.endedWall - 86400000,
                null,
                1,
                true,
                const [
                  ReportRow('Opening', 300000, 320000, 0, 0),
                  ReportRow('Psalm', 600000, null, 0, 0),
                  ReportRow('Empty', 0, 0, 0, 0),
                ],
              ),
            );
          });
        },
      );
      expect(t.takeException(), isNull);
      expect(find.textContaining('Rehearsal durations'), findsOneWidget);
      expect(inRow(0, '5 min'), findsNWidgets(2));
      expect(inRow(1, '21 min 40 s'), findsOneWidget);
      expect(c.state.reports, hasLength(2));
      await t.tap(find.byKey(const ValueKey('open-report-partial')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        find.textContaining('Partial or uncertain timing'),
        findsOneWidget,
      );
      expect(inRow(1, 'Not recorded'), findsOneWidget);
      expect(inRow(1, 'No recorded duration'), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('report-when'))).data,
        contains('start not recorded'),
      );
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('choosing a report in the list shows it beside the list', (
    t,
  ) async {
    final (c, _) = await app(
      t,
      services: (c, port) async {
        await mixed(c, port);
        await serve(
          c,
          port,
          Timeline('Midweek', const [
            Segment('Hymn', 5),
            Segment('Study', 30),
          ], DisplaySettings()),
          [300, 1700],
        );
      },
    );
    Text name() => t.widget<Text>(find.byKey(const ValueKey('report-name')));
    // The newest shows until another is chosen.
    expect(name().data, 'Midweek');
    final first = c.state.reports.firstWhere((r) => r.name == 'Sunday Service');
    await t.tap(find.byKey(ValueKey('open-report-${first.id}')));
    await t.pumpAndSettle();
    expect(name().data, 'Sunday Service');
    expect(find.text('Service report'), findsNothing);
    // Search narrows the list and the report follows it.
    await t.enterText(find.byKey(const ValueKey('report-search')), 'study');
    await t.pumpAndSettle();
    expect(name().data, 'Midweek');
    await t.enterText(find.byKey(const ValueKey('report-search')), 'zzz');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-name')), findsNothing);
    expect(find.text('No report matches this search.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Graph, selection, notes and the report menu still work', (
    t,
  ) async {
    final (c, port) = await app(t);
    // Graph puts the charts in the main area and keeps the list.
    await t.tap(find.text('Graph'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('reports-graph-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-list-pane')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('graph-open-report')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-table')), findsOneWidget);
    expect(find.text('Service report'), findsNothing);
    // Selection mode ticks reports in the list.
    await t.tap(find.byKey(const ValueKey('select-reports')));
    await t.pumpAndSettle();
    expect(find.text('0 selected'), findsOneWidget);
    await t.tap(
      find.byKey(ValueKey('open-report-${c.state.reports.single.id}')),
    );
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('done-selecting-reports')));
    await t.pumpAndSettle();
    // A review note.
    await t.ensureVisible(find.byKey(const ValueKey('add-review-note')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('add-review-note')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('review-note-field')),
      'Shorten the response.',
    );
    await t.tap(find.byKey(const ValueKey('save-review-note')));
    await t.pumpAndSettle();
    expect(find.text('Shorten the response.'), findsOneWidget);
    expect(find.byKey(const ValueKey('report-activity')), findsOneWidget);
    // Export from the ⋮ menu.
    await t.ensureVisible(find.byKey(const ValueKey('report-actions')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('report-actions')));
    await t.pumpAndSettle();
    expect(find.text('Export report JSON'), findsOneWidget);
    expect(find.text('Delete report'), findsOneWidget);
    await t.tap(find.text('Export report CSV'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('exclude-review')));
    await t.pumpAndSettle();
    expect(port.exports.keys.single, endsWith('.csv'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}

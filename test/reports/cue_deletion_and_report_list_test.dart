import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import '../domain/service_timing_test.dart' show FakePort;
import '../domain/feature_cases.dart' show epoch, at;
import 'report_export_and_end_screen_cases.dart';

class ExportPort extends FakePort {
  final exports = <Map<String, String>>[];
  @override
  Future<void> exportFile(String filename, String content) async {
    exports.add({'filename': filename, 'content': content});
  }
}

void main() {
  for (final e in revision04Cases.entries) {
    test(e.key, e.value);
  }

  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  void size(WidgetTester t, [Size value = const Size(500, 1100)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  test(
    'Deleting a saved cue is durable and leaves its active stage output intact',
    () async {
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      final cue = c.state.stageCues.first;
      await c.sendAndSaveCue(cue, index: 0);
      port.fail = true;
      expect(await c.deleteStageCue(0, cue), false);
      expect(c.state.stageCues.first.text, cue.text);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.stageCues.any((v) => v.text == cue.text), false);
      expect(c.state.session.alert!.text, cue.text);
      expect(c.simulator.delivered!.text, cue.text);
      c.dispose();
      final restarted = AppController(port);
      await restarted.initialize(startTicker: false);
      expect(restarted.state.stageCues.any((v) => v.text == cue.text), false);
      restarted.dispose();
    },
  );

  test(
    'Stale cue deletion cannot remove the item that replaced its index',
    () async {
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      final first = c.state.stageCues.first;
      final second = c.state.stageCues[1];
      expect(await c.deleteStageCue(0, first), true);
      expect(await c.deleteStageCue(0, first), false);
      expect(c.state.stageCues.first.toJson(), second.toJson());
      c.dispose();
    },
  );

  test(
    'Shared zero saves atomically, updates current output and survives restart',
    () async {
      final port = FakePort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      await c.act(
        'load',
        value: Timeline('Test', const [
          Segment('Talk', 1),
        ], DisplaySettings(warnings: [])),
      );
      await c.act('start');
      port.at = at(61);
      await c.tick();
      final end = c.state.session.timeline!.display.end.toJson();
      port.fail = true;
      expect(await c.setSharedZero(const TextLayout('DONE')), false);
      expect(c.state.defaults.zero, isNull);
      expect(c.simulator.delivered!.text, '00:00');
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.simulator.delivered!.text, 'DONE');
      expect(
        c.state.templates.every((v) => v.display.zero!.text == 'DONE'),
        true,
      );
      expect(c.state.session.timeline!.display.end.toJson(), end);
      c.dispose();
      final restored = AppController(port);
      await restored.initialize(startTicker: false);
      expect(restored.state.session.timeline!.display.zero!.text, 'DONE');
      expect(await restored.setSharedZero(null), true);
      expect(restored.simulator.delivered!.text, '00:00');
      restored.dispose();
    },
  );

  testWidgets(
    'Settings cue list confirms deletion and preserves cancelled item',
    (t) async {
      size(t, const Size(700, 1500));
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      await c.act('load', value: c.state.templates.last);
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Settings'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Stage cues'));
      await t.tap(find.text('Stage cues'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Cue actions').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete cue'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await t.pumpAndSettle();
      expect(c.state.stageCues.first.text, 'WRAP UP');
      await t.tap(find.byTooltip('Cue actions').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete cue'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete cue'));
      await t.pumpAndSettle();
      expect(find.byType(TextComposer), findsNothing);
      expect(c.state.stageCues.any((v) => v.text == 'WRAP UP'), false);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Template end editor saves that template while loaded end stays unchanged',
    (t) async {
      size(t, const Size(700, 1500));
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      await c.act('load', value: c.state.templates.first);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Programs'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('template-row:Sunday Service')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Edit Program'));
      await t.tap(find.widgetWithText(OutlinedButton, 'Edit Program'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('edit-end-screen')));
      await t.tap(find.byKey(const ValueKey('edit-end-screen')));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.widgetWithText(TextField, 'Display text'), 'AMEN');
      await t.tap(find.widgetWithText(FilledButton, 'Use end screen'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Save changes'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Save changes'));
      await t.pumpAndSettle();
      expect(c.state.templates.first.display.end.text, 'AMEN');
      expect(c.state.templates.first.display.end.bold, true);
      expect(c.state.templates.first.display.end.height, 2);
      expect(c.state.templates.last.display.end.text, 'Hallelujah');
      expect(c.state.defaults.end.text, 'Hallelujah');
      expect(c.state.session.timeline!.display.end.text, 'Hallelujah');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Report list opens detailed page and returns after confirmed deletion',
    (t) async {
      size(t, const Size(430, 1100));
      final c = AppController(FakePort()..at = epoch);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      await c.commit((a, _) => a.reports = reportFixtures());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Reports'));
      await t.pumpAndSettle();
      expect(find.text('56m 0s'), findsOneWidget);
      expect(find.text('Export report CSV'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/report-list-phone.png'),
      );
      await t.tap(find.byKey(const ValueKey('open-report-sunday')));
      await t.pumpAndSettle();
      expect(find.byType(ReportDetailPage), findsOneWidget);
      expect(find.text('56m 0s'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/report-detail-phone.png'),
      );
      await t.tap(find.byKey(const ValueKey('report-actions')).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Clear report').last);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Cancel'));
      await t.pumpAndSettle();
      expect(find.byType(ReportDetailPage), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('report-actions')).last);
      await t.pumpAndSettle();
      await t.tap(find.text('Clear report').last);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Clear report'));
      await t.pumpAndSettle();
      expect(find.byType(ReportDetailPage), findsNothing);
      expect(c.state.reports.length, 2);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Report filters affect graphs but export all includes the complete history',
    (t) async {
      size(t, const Size(1000, 1400));
      final port = ExportPort()..at = epoch;
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await c.setSharedWarnings([]);
      await c.commit((a, _) => a.reports = reportFixtures());
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.text('Reports'));
      await t.pumpAndSettle();
      await t.tap(find.text('Graph'));
      await t.pumpAndSettle();
      expect(find.byType(DurationChart), findsOneWidget);
      expect(
        find.textContaining('combines live and simulated'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/report-graph-tablet.png'),
      );
      await t.tap(find.text('Live only'));
      await t.pumpAndSettle();
      expect(find.text('2 records'), findsOneWidget);
      expect(
        t.widget<DurationChart>(find.byType(DurationChart)).entries.length,
        2,
      );
      await t.tap(find.byTooltip('Report list options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Export all records'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(port.exports, isEmpty);
      await t.tap(find.byTooltip('Report list options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Export all records'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, 'JSON'));
      await t.pumpAndSettle();
      expect(jsonDecode(port.exports.single['content']!)['recordCount'], 3);
      await t.tap(find.byTooltip('Report list options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Export all records'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'CSV'));
      await t.pumpAndSettle();
      expect(parseCsv(port.exports.last['content']!).length, 8);
      await t.tap(find.text('Rehearsals'));
      await t.pumpAndSettle();
      expect(find.text('1 record'), findsOneWidget);
      expect(
        t
            .widget<DurationChart>(find.byType(DurationChart))
            .entries
            .single
            .title,
        'Midweek Service',
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('At Zero stays global without a template selector', (t) async {
    size(t, const Size(700, 1500));
    final port = FakePort()..at = epoch;
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.setSharedWarnings([]);
    await c.act(
      'load',
      value: Timeline('Test', const [
        Segment('Talk', 1),
      ], DisplaySettings(warnings: [])),
    );
    await c.act('start');
    port.at = at(61);
    await c.tick();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.tap(find.text('Display settings'));
    await t.pumpAndSettle();
    expect(find.text('Editing'), findsNothing);
    await t.tap(find.text('At Zero'));
    await t.pumpAndSettle();
    await t.tap(find.text('Custom text'));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.widgetWithText(TextField, 'Display text'), 'DONE');
    await t.tap(find.text('Save zero screen'));
    await t.pumpAndSettle();
    expect(c.state.defaults.zero!.text, 'DONE');
    expect(
      c.state.templates.every((v) => v.display.zero!.text == 'DONE'),
      true,
    );
    expect(c.simulator.delivered!.text, 'DONE');
    await t.tap(find.text('Use 00:00'));
    await t.pumpAndSettle();
    expect(c.state.defaults.zero, isNull);
    expect(c.simulator.delivered!.text, '00:00');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Duration chart handles zero, missing durations and narrow display',
    (t) async {
      size(t, const Size(320, 900));
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: DurationChart(
                entries: [
                  DurationEntry(
                    title: 'No duration',
                    subtitle: 'Legacy',
                    planned: 0,
                    actual: null,
                    uncertain: true,
                  ),
                  DurationEntry(
                    title:
                        'A very long service title that wraps to another line',
                    subtitle: 'Zero',
                    planned: 0,
                    actual: 0,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Not recorded'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}

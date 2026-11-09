import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);
  void size(WidgetTester t, [Size value = const Size(430, 1000)]) =>
      setScreen(t, value);

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await t.pumpAndSettle();
    await t.tap(find.text(text).last);
    await t.pumpAndSettle();
  }

  Future<void> shot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/$name.png'),
    );
  }

  testWidgets(
    'Recovery requires a reviewed proposal and keeps protected segments intact',
    (t) async {
      size(t);
      final program = Timeline('Sunday', const [
        Segment('Welcome', 10),
        Segment('Prayer', 5, protected: true),
        Segment('Message', 8),
        Segment('Closing', 2),
      ], DisplaySettings());
      final s = transition(
        transition(
          Session(id: 'recovery', anchor: start),
          'load',
          start,
          value: program,
        ),
        'start',
        start,
      );
      final before = jsonEncode(s.toJson());
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme('royal_navy'),
          home: TimeRecoveryPage(session: s),
        ),
      );
      await tap(t, 'Time to recover');
      await t.tapAt(t.getCenter(find.byType(CupertinoPicker).first));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), '4');
      await tap(t, 'Use value');
      await tap(t, 'Use 04:00');
      expect(find.text('Apply reviewed adjustments'), findsNothing);
      await tap(t, 'Review adjustments');
      expect(find.text('5 min to 5 min'), findsOneWidget);
      expect(find.text('8 min to 4 min'), findsOneWidget);
      expect(jsonEncode(s.toJson()), before);
      await shot(t, 'recover-time-review');
    },
  );
  testWidgets(
    'Stage layouts show the chosen segment and overlays temporarily replace it',
    (t) async {
      size(t, const Size(1000, 600));
      final data = <String, dynamic>{
        'stageSharing': true,
        'blank': false,
        'phase': 'running',
        'displayIsTimer': true,
        'stageLayout': 'next',
        'displayText': '08:30',
        'remaining': '08:30',
        'effect': 'static',
        'segment': 'Message',
        'nextSegment': 'Closing',
        'overtime': false,
      };
      Widget page() => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: appTheme('midnight_lime'),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: StageSurface(data: Map.of(data), stale: false),
        ),
      );
      await t.pumpWidget(page());
      await t.pump();
      expect(find.text('Next: Closing'), findsOneWidget);
      await shot(t, 'stage-next-segment');
      data['quickMessage'] = const QuickMessage(
        headline: 'PLEASE WAIT',
        body: 'The choir is getting ready.',
        requestSeen: true,
      ).toJson();
      await t.pumpWidget(page());
      await t.pump();
      expect(find.text('Next: Closing'), findsNothing);
      expect(find.text('The choir is getting ready.'), findsOneWidget);
      data.remove('quickMessage');
      await t.pumpWidget(page());
      await t.pump();
      expect(find.text('Next: Closing'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Print defaults watermark on; stage copy excludes notes and ink-saving disables decoration',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.first);
      await c.act('start');
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('print-rundown')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('print-rundown')));
      await t.pumpAndSettle();
      expect(find.text('Print order of service'), findsOneWidget);
      CheckboxListTile box(String label) => t.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, label),
      );
      expect(box('Church-name watermark').value, true);
      expect(box('Include church banner').value, true);
      expect(box('Include private operator notes').value, false);
      expect(box('Include private operator notes').onChanged, isNull);
      await tap(t, 'Operator copy');
      expect(box('Include private operator notes').value, true);
      await tap(t, 'Ink-saving');
      expect(box('Church-name watermark').onChanged, isNull);
      expect(box('Include church banner').onChanged, isNull);
      // Ink-saving leaves them out, so they show unticked.
      expect(box('Church-name watermark').value, false);
      expect(box('Include church banner').value, false);
      await shot(t, 'print-ink-saving');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Program draft restores after navigation without changing the saved program',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Programs');
      await tap(t, 'New program');
      await t.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'An unfinished program',
      );
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      expect(
        c.state.templates.any((p) => p.name == 'An unfinished program'),
        false,
      );
      await tap(t, 'New program');
      expect(find.text('Restore program draft?'), findsOneWidget);
      await tap(t, 'Restore draft');
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Program name'))
            .controller!
            .text,
        'An unfinished program',
      );
      expect(
        c.state.templates.any((p) => p.name == 'An unfinished program'),
        false,
      );
      await shot(t, 'restored-program-draft');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Seen is explicit and becomes disabled only after the host confirms it',
    (t) async {
      size(t, const Size(1000, 600));
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      c.pairing.mode = 'stage';
      c.pairing.lastSnapshot = DateTime.now().millisecondsSinceEpoch;
      c.pairing.snapshot = {
        'stageSharing': true,
        'blank': false,
        'messageId': 'test-id',
        'messageSeen': false,
        'quickMessage': const QuickMessage(
          headline: 'ANNOUNCEMENT',
          body: 'Please welcome our visitors.',
          requestSeen: true,
        ).toJson(),
      };
      c.pairing.changed();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Mark Seen'), findsOneWidget);
      await shot(t, 'stage-seen-request');
      c.pairing.snapshot!['messageSeen'] = true;
      c.pairing.changed();
      await t.pump();
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Seen'))
            .onPressed,
        isNull,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Deleting a cue and warning offers Undo and restores their full formatting',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      final cue = c.state.stageCues.first.toJson(),
          warning = c.state.defaults.warnings.first.toJson();
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Settings');
      await tap(t, 'Stage cues');
      await t.tap(find.byTooltip('Cue actions').first);
      await t.pumpAndSettle();
      await tap(t, 'Delete cue');
      await tap(t, 'Delete cue');
      expect(c.state.stageCues.length, 2);
      await tap(t, 'Undo');
      expect(c.state.stageCues.first.toJson(), cue);
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, 'Warnings & alerts');
      await t.tap(find.byTooltip('Warning actions').first);
      await t.pumpAndSettle();
      await tap(t, 'Delete warning');
      await tap(t, 'Delete warning');
      expect(c.state.defaults.warnings.length, 2);
      await tap(t, 'Undo');
      expect(c.state.defaults.warnings.first.toJson(), warning);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}

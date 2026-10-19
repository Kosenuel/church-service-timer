import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/display_connection.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/main.dart';
import 'domain_test.dart' show FakePort;
import 'feature_cases.dart' show epoch, at;
import 'revision_04_test.dart' show ExportPort;
import 'revision_06_cases.dart';

void main() {
  for (final e in revision06Cases.entries) {
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
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) {
    t.view.physicalSize = value;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<AppController> setup(FakePort port) async {
    final c = AppController(port);
    await c.initialize(startTicker: false);
    return c;
  }

  Future<void> templates(WidgetTester t) async {
    await t.tap(find.byType(NavigationDestination).at(1));
    await t.pumpAndSettle();
  }

  for (final width in [430.0, 1024.0]) {
    testWidgets(
      'Gauge remains centered through every timer phase at width $width',
      (t) async {
        size(t, Size(width, 1200));
        final port = FakePort()..at = epoch;
        final c = await setup(port);
        await c.act(
          'load',
          value: Timeline(
            'Alignment',
            const [Segment('Welcome', 3)],
            DisplaySettings(
              warnings: [WarningRule(30, const TextLayout('WRAP UP'))],
            ),
          ),
        );
        await t.pumpWidget(TimerApp(controller: c));
        Future<void> centered() async {
          await t.pumpAndSettle();
          final arc = find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is TimerArcPainter,
          );
          expect(
            t.getCenter(arc).dx,
            closeTo(
              t.getCenter(find.byKey(const ValueKey('timer-card-content'))).dx,
              .01,
            ),
          );
          expect(
            t.getCenter(find.byKey(const ValueKey('operator-clock'))).dx,
            closeTo(t.getCenter(arc).dx, .01),
          );
          expect(t.takeException(), isNull);
        }

        await centered(); // Ready, no notice row.
        await c.act('start');
        port.at = at(61);
        await c.tick();
        await centered();
        await c.act('pause');
        await centered();
        await c.act('pause');
        port.at = at(151);
        await c.tick();
        await centered();
        expect(find.textContaining('Warning ·'), findsOneWidget);
        port.at = at(185);
        await c.tick();
        await centered();
        expect(find.text('OVERTIME'), findsOneWidget);
        await c.act('end');
        await t.pumpAndSettle();
        expect(find.byType(SegmentGauge), findsNothing);
        expect(find.text('Standing by'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Display preview labels stay at opposite edges for all badges and large text',
    (t) async {
      size(t, const Size(800, 900));
      for (final width in [240.0, 350.0, 700.0]) {
        for (final scale in [1.0, 1.8]) {
          for (final connection in DisplayConnection.values) {
            await t.pumpWidget(
              MaterialApp(
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: width,
                        child: DisplayPreviewHeader(connection: connection),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await t.pumpAndSettle();
            final header = t.getRect(
              find.byKey(const ValueKey('display-preview-header')),
            );
            expect(
              t.getRect(find.text('DISPLAY PREVIEW')).left,
              closeTo(header.left, .01),
            );
            expect(
              t.getRect(find.byType(DisplayConnectionBadge)).right,
              closeTo(header.right, .01),
            );
            expect(find.text(connection.label), findsOneWidget);
            expect(t.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets('Compact rows open template details with actions and exports', (
    t,
  ) async {
    size(t);
    final port = ExportPort()..at = epoch;
    final c = await setup(port);
    await c.commit((a, _) {
      a.saveTemplate(
        Timeline('Midweek Service', const [
          Segment('Worship', 15),
          Segment('Message', 30),
        ], DisplaySettings()),
      );
      a.saveTemplate(
        Timeline('Prayer Meeting', const [
          Segment('Welcome', 5),
          Segment('Prayer', 25),
        ], DisplaySettings()),
      );
      a.saveTemplate(
        Timeline('Youth Service', const [
          Segment('Worship', 20),
          Segment('Message', 40),
        ], DisplaySettings()),
      );
    });
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await templates(t);
    expect(find.text('Edit Program'), findsNothing);
    final row = find.byKey(const ValueKey('template-row:Sunday Service'));
    expect(t.getSize(row).height, lessThan(85));
    expect(find.text('4 segments · 55 min'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/templates-phone.png'),
    );
    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.text('Program details'), findsOneWidget);
    expect(find.text('Praise & Worship'), findsOneWidget);
    expect(find.text('Hallelujah'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/template-detail-phone.png'),
    );
    await t.ensureVisible(find.text('Export JSON'));
    await t.tap(find.text('Export JSON'));
    await t.pumpAndSettle();
    expect(
      jsonDecode(port.exports.single['content']!)['name'],
      'Sunday Service',
    );
    await t.pageBack();
    await t.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Duplicate and confirmed delete persist while preserving loaded service',
    (t) async {
      size(t, const Size(500, 1300));
      final port = FakePort()..at = epoch;
      final c = await setup(port);
      await c.act('load', value: c.state.templates.last);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await templates(t);
      await t.tap(find.byKey(const ValueKey('template-row:Quick rehearsal')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Duplicate'));
      await t.tap(find.text('Duplicate'));
      await t.pumpAndSettle();
      expect(find.text('Quick rehearsal (copy)'), findsOneWidget);
      expect(c.state.templates.last.type, 'rehearsal');
      await t.ensureVisible(find.text('Delete program'));
      await t.tap(find.text('Delete program'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.state.templates.length, 3);
      await t.tap(find.text('Delete program'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Delete program'));
      await t.pumpAndSettle();
      expect(c.state.templates.length, 2);
      expect(c.state.session.timeline!.name, 'Quick rehearsal');
      expect(
        find.byKey(const ValueKey('template-row:Quick rehearsal')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = await setup(port);
      expect(restored.state.templates.length, 2);
      restored.dispose();
    },
  );

  testWidgets(
    'Grouping preference survives restart and long names reflow with large text',
    (t) async {
      size(t, const Size(320, 1100));
      final port = FakePort()..at = epoch;
      final c = await setup(port);
      await c.commit(
        (a, _) => a.saveTemplate(
          a.templates.first.renamed(
            'A very long Sunday service template name for testing phone layouts',
          ),
        ),
      );
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Home(controller: c),
          ),
        ),
      );
      await t.pumpAndSettle();
      await templates(t);
      expect(t.takeException(), isNull);
      expect(c.state.groupTemplates, true);
      await t.tap(find.byTooltip('Program list options'));
      await t.pumpAndSettle();
      await t.tap(
        find.widgetWithText(CheckedPopupMenuItem<bool>, 'Single list'),
      );
      await t.pumpAndSettle();
      expect(c.state.groupTemplates, false);
      await t.tap(find.byTooltip('Program list options'));
      await t.pumpAndSettle();
      await t.tap(
        find.widgetWithText(
          CheckedPopupMenuItem<bool>,
          'Services & rehearsals',
        ),
      );
      await t.pumpAndSettle();
      expect(c.state.groupTemplates, true);
      expect(find.text('SERVICES'), findsOneWidget);
      expect(find.text('REHEARSALS'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(
        find.byKey(const ValueKey('template-row:Quick rehearsal')),
      );
      await t.tap(find.byKey(const ValueKey('template-row:Quick rehearsal')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Edit Program'));
      await t.tap(find.text('Edit Program'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'Practice night',
      );
      await t.ensureVisible(find.widgetWithText(ChoiceChip, 'Service'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(ChoiceChip, 'Service'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Save changes'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(TemplateEditor),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.tap(find.text('Save changes'));
      await t.pumpAndSettle();
      expect(c.state.templates[1].type, 'service');
      expect(find.text('Practice night'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      final restored = await setup(port);
      expect(restored.state.groupTemplates, true);
      expect(restored.state.templates[1].type, 'service');
      expect(restored.state.templates[1].name, 'Practice night');
      restored.dispose();
    },
  );

  test(
    'Failed duplicate and deletion publish nothing until the durable retry succeeds',
    () async {
      final port = FakePort()..at = epoch;
      final c = await setup(port);
      final original = c.state.templates.first;
      port.fail = true;
      expect(await c.commit((a, _) => a.duplicateTemplate(original)), false);
      expect(c.state.templates.length, 2);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.templates.length, 3);
      final copy = c.state.templates.last;
      port.fail = true;
      expect(await c.commit((a, _) => a.deleteTemplate(copy)), false);
      expect(c.state.templates.length, 3);
      port.fail = false;
      expect(await c.retry!(), true);
      expect(c.state.templates.length, 2);
      c.dispose();
    },
  );
}

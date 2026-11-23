import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);
  void size(WidgetTester t, [Size value = const Size(430, 1100)]) =>
      setScreen(t, value);

  Future<void> tap(WidgetTester t, String text) async {
    final f = find.text(text).last;
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> golden(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/$name.png'),
    );
  }

  testWidgets(
    'Finishing a scrolled service reveals welcome, including after save retry',
    (t) async {
      size(t);
      final p = FakePort();
      final host = AppController(p);
      await host.initialize(startTicker: false);
      await host.act('load', value: host.state.templates.last);
      await host.act('start');
      await t.pumpWidget(TimerApp(controller: host));
      await t.pumpAndSettle();
      final scroll = t
          .widget<CustomScrollView>(find.byType(CustomScrollView).first)
          .controller!;
      scroll.jumpTo(500);
      await t.pump();
      p.fail = true;
      await host.act('end');
      await t.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      p.fail = false;
      await host.retry!();
      await t.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(find.text('STANDING BY').hitTestable(), findsOneWidget);
      await host.act('load', value: host.state.templates.last);
      await host.act('start');
      await t.pumpAndSettle();
      scroll.jumpTo(500);
      await host.act('end');
      await t.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(
        find.text('View last service report').hitTestable(),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Restarting an ended service renders welcome and output review without losing the report',
    (t) async {
      size(t);
      final p = FakePort();
      final before = AppController(p);
      await before.initialize(startTicker: false);
      await before.act('load', value: before.state.templates.last);
      await before.act('start');
      await before.act('end');
      before.dispose();
      p.at = after(3600);
      final restored = AppController(p);
      await restored.initialize(startTicker: false);
      expect(restored.state.session.held, true);
      await t.pumpWidget(TimerApp(controller: restored));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('STANDING BY'), findsOneWidget);
      expect(find.text('View last service report'), findsOneWidget);
      expect(find.text('Send end screen'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('header-connection')));
      await t.pumpAndSettle();
      expect(find.text('Choose display'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Failed end retains finished card; retry shows clean welcome and printable historical report',
    (t) async {
      size(t);
      final p = FakePort();
      final host = AppController(p);
      await host.initialize(startTicker: false);
      await host.act('load', value: host.state.templates.last);
      await host.act('start');
      await t.pumpWidget(TimerApp(controller: host));
      p.at = after(25);
      p.fail = true;
      await host.act('end');
      await t.pumpAndSettle();
      expect(find.text('Start service'), findsNothing);
      expect(find.text('Retry saving report'), findsOneWidget);
      await golden(t, 'report-save-retry');
      p.fail = false;
      await tap(t, 'Retry saving report');
      expect(find.text('STANDING BY'), findsOneWidget);
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(find.byType(SegmentGauge), findsNothing);
      expect(find.text('SERVICE RUNDOWN · SNAPSHOT'), findsNothing);
      expect(host.state.reports.length, 1);
      expect(host.simulator.delivered!.text, 'Hallelujah');
      await golden(t, 'standing-by-last-report');
      await tap(t, 'View last service report');
      await tap(t, 'Print report');
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Include church banner'),
            )
            .value,
        true,
      );
      expect(
        t
            .widget<CheckboxListTile>(
              find.widgetWithText(
                CheckboxListTile,
                'Include private operator notes',
              ),
            )
            .value,
        false,
      );
      expect(find.text('Service date'), findsOneWidget);
      await golden(t, 'print-historical-report');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Display chooser switches to mobile preview with preserved unsent draft and no LED retry',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      final nav = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(
        nav.destinations.cast<NavigationDestination>().map((d) => d.label),
        ['Live', 'Programs', 'Lyrics', 'Reports', 'Settings'],
      );
      await t.tap(find.byKey(const ValueKey('header-connection')));
      await t.pumpAndSettle();
      await golden(t, 'display-destination-chooser');
      await t.tap(find.byKey(const ValueKey('destination-mobile')));
      await t.pumpAndSettle();
      expect(c.destination, 'mobile');
      expect(c.hardware.retryEnabled, false);
      await golden(t, 'stage-screen-pairing');
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('QUICK MESSAGE'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('open-quick-message')));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Message'),
        'Keep my draft',
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send message'),
            )
            .onPressed,
        isNull,
      );
      await c.act('disconnect');
      await t.pumpAndSettle();
      expect(find.text('Keep my draft'), findsWidgets);
      await golden(t, 'quick-message-composer');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Program editor and details use clear names and place deletion last',
    (t) async {
      size(t);
      final c = AppController(FakePort());
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await tap(t, 'Programs');
      await t.tap(find.byKey(const ValueKey('new-template')));
      await t.pumpAndSettle();
      expect(find.text('Program editor'), findsOneWidget);
      expect(find.text('Youth sunday'), findsOneWidget);
      expect(find.textContaining('Warnings are shared'), findsNothing);
      await golden(t, 'program-editor');
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, 'Quick rehearsal');
      expect(find.text('Program details'), findsOneWidget);
      expect(t.getTopLeft(find.text('Edit program')).dy, lessThan(350));
      await golden(t, 'program-detail');
      await t.tap(find.byTooltip('Program options'));
      await t.pumpAndSettle();
      await tap(t, 'Delete program');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tap(t, 'Cancel');
      expect(c.state.templates.length, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Operator notes change their action label and rich stage text fits extreme supported content',
    (t) async {
      size(t, const Size(960, 540));
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OperatorNotes(notes: 'Private detail')),
        ),
      );
      await tap(t, 'View operator notes');
      expect(find.text('Hide operator notes'), findsOneWidget);
      expect(find.text('Private detail'), findsOneWidget);
      for (final message in [
        defaultQuickMessages.first,
        QuickMessage(
          headline: 'W' * 48,
          body: 'W' * 112,
          bold: true,
          italic: true,
          scale: 1.15,
        ),
        const QuickMessage(
          headline: 'NOTICE',
          body:
              'First line\nSecond line\nThird line\nFourth line\nFifth line\nSixth line',
          scale: 1.15,
        ),
      ]) {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StageSurface(
                data: {'quickMessage': message.toJson(), 'stageSharing': true},
                stale: false,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final rect = t.getRect(find.text(message.body));
        expect(rect.bottom, lessThanOrEqualTo(509));
        expect(rect.top, greaterThanOrEqualTo(31));
        expect(t.takeException(), isNull);
      }
      await golden(t, 'stage-rich-message');
      await t.pumpWidget(const SizedBox());
    },
  );
}

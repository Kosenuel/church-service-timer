import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';

import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<AppController> controller() async {
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    return c;
  }

  group('Quick timer engine', () {
    test(
      'starts at once as one segment and saves nothing by default',
      () async {
        final c = await controller();
        expect(
          await c.startQuickTimer(
            const QuickTimerChoice('Prayer meeting', 330),
          ),
          isTrue,
        );
        final s = c.state.session;
        expect(s.active, isTrue);
        expect(s.quickTimer, isTrue);
        expect(s.noReport, isTrue);
        expect(s.timeline!.name, 'Prayer meeting');
        expect(s.timeline!.segments.single.durationMs, 330000);
        await c.act('end');
        expect(c.state.session.phase, 'ended');
        expect(c.state.reports, isEmpty);
        c.dispose();
      },
    );

    test('with Save as a report, the report is marked Quick timer', () async {
      final c = await controller();
      await c.startQuickTimer(
        const QuickTimerChoice('', 600),
        saveReport: true,
      );
      expect(c.state.session.timeline!.name, 'Quick timer');
      await c.act('end');
      final report = c.state.reports.single;
      expect(report.quickTimer, isTrue);
      final restored = ServiceReport.fromJson(
        jsonDecode(jsonEncode(report.toJson())),
      );
      expect(restored.quickTimer, isTrue);
      c.dispose();
    });

    test('is refused while a service is loaded', () async {
      final c = await controller();
      await c.act('load', value: c.state.templates.first);
      expect(await c.startQuickTimer(const QuickTimerChoice('', 300)), isFalse);
      expect(c.state.session.phase, 'ready');
      expect(c.state.session.quickTimer, isFalse);
      c.dispose();
    });

    test(
      'remembers the last three timers, newest first, stays on this phone',
      () async {
        final c = await controller();
        for (final choice in const [
          QuickTimerChoice('A', 300),
          QuickTimerChoice('B', 600),
          QuickTimerChoice('C', 900),
          QuickTimerChoice('a', 300),
          QuickTimerChoice('D', 1800),
        ]) {
          await c.startQuickTimer(choice);
          await c.act('end');
        }
        expect(c.state.recentQuickTimers.map((r) => r.name), ['D', 'a', 'C']);
        final restored = AppState.fromJson(
          jsonDecode(jsonEncode(c.state.toJson())),
        );
        expect(restored.recentQuickTimers, c.state.recentQuickTimers);
        final backup =
            jsonDecode(exportBackup(c.state, c.now)) as Map<String, dynamic>;
        expect(
          (backup['data'] as Map).containsKey('recentQuickTimers'),
          isFalse,
        );
        c.dispose();
      },
    );
  });

  testWidgets(
    'Live starts a named quick timer from the sheet and ends it with End timer',
    (t) async {
      setScreen(t, const Size(430, 1000));
      final c = await controller();
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('quick-timer-live')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-timer-sheet')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('quick-timer-15')));
      await t.enterText(
        find.byKey(const ValueKey('quick-timer-name')),
        'Prayer meeting',
      );
      await t.pumpAndSettle();
      expect(find.text('Start 15 min timer'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('quick-timer-start')));
      await t.pumpAndSettle();
      expect(c.state.session.active, isTrue);
      expect(c.state.session.timeline!.name, 'Prayer meeting');
      expect(find.text('15:00'), findsWidgets);
      await t.ensureVisible(find.byKey(const ValueKey('end-service')));
      await t.pumpAndSettle();
      expect(find.text('End timer'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('end-service')));
      await t.pumpAndSettle();
      expect(find.text('End the timer?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'End timer').last);
      await t.pumpAndSettle();
      expect(c.state.session.phase, 'ended');
      expect(c.state.reports, isEmpty);

      // The last timer is offered again as a one-tap choice.
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('quick-timer-live')),
        -200,
      );
      await t.tap(find.byKey(const ValueKey('quick-timer-live')));
      await t.pumpAndSettle();
      expect(find.text('Prayer meeting · 15 min'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('A saved quick timer shows in Reports with its own filter', (
    t,
  ) async {
    setScreen(t, const Size(430, 1000));
    final c = await controller();
    await c.startQuickTimer(
      const QuickTimerChoice('Break', 300),
      saveReport: true,
    );
    await c.act('end');
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    await t.tap(find.text('Quick timers'));
    await t.pumpAndSettle();
    expect(find.text('Break'), findsWidgets);
    await t.tap(find.text('Live only'));
    await t.pumpAndSettle();
    expect(find.text('Break'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

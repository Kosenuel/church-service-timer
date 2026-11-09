import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import '../domain/feature_cases.dart' show epoch;
import 'report_export_and_end_screen_cases.dart';
import '../support/fake_port.dart';
import '../support/widget_setup.dart';

void main() {
  void size(WidgetTester t, [Size value = const Size(500, 1100)]) =>
      setScreen(t, value);

  Future<AppController> open(WidgetTester t) async {
    size(t);
    final c = AppController(FakePort()..at = epoch);
    await c.initialize(startTicker: false);
    await c.commit((a, _) => a.reports = reportFixtures());
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('Rows show the outcome chip and the hint stays dismissed', (
    t,
  ) async {
    final c = await open(t);
    expect(find.text('1 min over'), findsOneWidget);
    expect(find.text('4 min under'), findsOneWidget);
    expect(find.text('Partial'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    await t.tap(find.byKey(const ValueKey('dismiss-hint-reports-select')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('hint-reports-select')), findsNothing);
    expect(c.state.dismissedHints, contains('reports-select'));
    // Kept on this phone, and left out of backups.
    expect(
      AppState.fromJson(c.state.toJson()).dismissedHints,
      contains('reports-select'),
    );
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Tapping a graph bar shows that service and opens its report', (
    t,
  ) async {
    await open(t);
    await t.tap(find.text('Graph'));
    await t.pumpAndSettle();
    final card = find.byKey(const ValueKey('graph-report-card'));
    // The newest complete service is shown first.
    expect(
      find.descendant(of: card, matching: find.text('Midweek Service')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('graph-bar-sunday')));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: card, matching: find.text('Sunday Service')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('over plan')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('graph-open-report')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-report-card')), findsNothing);
    expect(find.text('Sunday Service'), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Selecting replaces the bars; Back and ✕ both finish', (t) async {
    await open(t);
    await t.longPress(find.byKey(const ValueKey('open-report-sunday')));
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-bar-reports')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await t.tap(find.byKey(const ValueKey('select-all-reports')));
    await t.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('done-selecting-reports')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-bar-reports')), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

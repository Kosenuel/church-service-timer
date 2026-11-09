import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  Future<AppController> app(WidgetTester t) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    return c;
  }

  testWidgets('No programs at all offers Create program and Import', (t) async {
    final c = await app(t);
    await c.commit((draft, _) => draft.templates = []);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('programs-empty')), findsOneWidget);
    expect(find.text('No programs yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create program'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Import'), findsOneWidget);
    expect(find.byKey(const ValueKey('programs-no-match')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A search with no match offers to show all programs', (t) async {
    final c = await app(t);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Programs'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('program-search')), 'zzzz');
    await t.pumpAndSettle();
    expect(find.text('No programs match “zzzz”.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('clear-program-search')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('programs-no-match')), findsNothing);
    expect(
      find.byKey(ValueKey('template-row:${c.state.templates.first.name}')),
      findsOneWidget,
    );
    final field = t.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('program-search')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}

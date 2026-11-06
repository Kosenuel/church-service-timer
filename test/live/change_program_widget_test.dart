import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

void main() {
  testWidgets('Change in Ready swaps the program, with Undo', (t) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final first = c.state.templates.first, second = c.state.templates[1];
    await c.act('load', value: first);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('ready-program')),
        matching: find.text(first.name),
      ),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('change-program')));
    await t.pumpAndSettle();
    expect(find.text('Change program'), findsOneWidget);
    expect(find.textContaining('Loaded ·'), findsOneWidget);
    await t.tap(find.byKey(ValueKey('start-program:${second.name}')));
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    expect(c.state.session.timeline!.name, second.name);
    expect(find.text('Switched to ${second.name}'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(c.state.session.timeline!.name, first.name);
    expect(c.state.session.phase, 'ready');
    await t.pumpWidget(const SizedBox());
  });
}

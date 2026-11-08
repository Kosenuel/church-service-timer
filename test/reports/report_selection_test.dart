import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fake_port.dart';

void main() {
  testWidgets('Long-press selects a report; Android Back leaves selection', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    await c.act('end');
    final id = c.state.reports.single.id;
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Report actions'), findsNothing);
    await t.longPress(find.byKey(ValueKey('open-report-$id')));
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('export-selected-reports')),
      findsOneWidget,
    );
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

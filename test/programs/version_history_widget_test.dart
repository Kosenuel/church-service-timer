import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

void main() {
  testWidgets('Version history restores an earlier version, with Undo', (
    t,
  ) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    final original = c.state.templates.first;
    await c.commit(
      (d, at) => d.saveTemplate(
        Timeline(original.name, [
          ...original.segments,
          const Segment('Offering', 4),
        ], original.display),
        replacing: 0,
        replacedAt: at.wall,
      ),
    );
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('Programs').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('template-row:${original.name}')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Program options').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Version history (1)'));
    await t.pumpAndSettle();
    expect(find.textContaining('Added “Offering”'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('program-version-0')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('restore-version')));
    await t.pumpAndSettle();
    expect(c.state.templates.first.segments.length, original.segments.length);
    expect(c.state.templates.first.id, original.id);
    expect(find.text('Version restored'), findsOneWidget);
    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(c.state.templates.first.segments.last.name, 'Offering');
    await t.pumpWidget(const SizedBox());
  });
}

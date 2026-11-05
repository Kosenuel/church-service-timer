import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

class ReadyPort extends FakePort {
  @override
  Future<Map<String, dynamic>> notificationStatus() async => {
    'enabled': true,
    'exact': true,
    'sound': true,
  };
}

void main() {
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets(
    'With everything ready, Start first segment starts at once and can be undone',
    (t) async {
      size(t);
      final c = AppController(ReadyPort());
      await c.initialize(startTicker: false);
      await c.act('load', value: c.state.templates.last);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('ready-inline')), findsOneWidget);
      expect(find.textContaining('all set'), findsOneWidget);
      await t.ensureVisible(find.text('Start first segment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Start first segment'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(c.state.session.active, isTrue);
      await t.tap(find.text('Undo start'));
      await t.pumpAndSettle();
      expect(c.state.session.phase, 'ready');
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Pinned programs load straight into Ready from Live', (t) async {
    size(t);
    final c = AppController(ReadyPort());
    await c.initialize(startTicker: false);
    final name = c.state.templates.first.name;
    await c.commit((draft, _) => draft.programLibrary.favourites.add(name));
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('quick-load:$name')));
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    expect(c.state.session.timeline!.name, name);
    await t.pumpWidget(const SizedBox());
  });
}

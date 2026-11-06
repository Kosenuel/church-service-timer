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
    final id = c.state.templates.first.id;
    await c.commit((draft, _) => draft.programLibrary.favourites.add(id));
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('quick-load:$name')));
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    expect(c.state.session.timeline!.name, name);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Undo start times out; a late failure leaves no stuck card', (
    t,
  ) async {
    size(t);
    final c = AppController(ReadyPort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.last);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Start first segment'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start first segment'));
    await t.pumpAndSettle();
    expect(find.text('Undo start'), findsOneWidget);
    await t.pump(const Duration(seconds: 9));
    await t.pumpAndSettle();
    expect(find.text('Undo start'), findsNothing);
    expect(c.state.session.active, isTrue);
    // A refused action shows its error card with a Dismiss button.
    expect(await c.act('advance'), isTrue);
    expect(await c.act('unstart'), isFalse);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('dismiss-error')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('dismiss-error')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('dismiss-error')));
    await t.pumpAndSettle();
    expect(c.error, isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Starting during the pre-service countdown asks first', (
    t,
  ) async {
    size(t);
    final c = AppController(ReadyPort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.last);
    await c.act('schedule', value: c.now.wall + 20 * 60000);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(
      find.textContaining('Tap Start first segment when the service begins'),
      findsOneWidget,
    );
    await t.ensureVisible(find.text('Start first segment'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start first segment'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('early-start')), findsOneWidget);
    expect(find.textContaining('20:00 from now'), findsOneWidget);
    await t.tap(find.text('Keep waiting'));
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    expect(c.state.session.startsAtWall, isNotNull);
    await t.tap(find.text('Start first segment'));
    await t.pumpAndSettle();
    await t.tap(find.text('Start now'));
    await t.pumpAndSettle();
    expect(c.state.session.active, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A held display offers Show on display for the countdown', (
    t,
  ) async {
    size(t);
    final c = AppController(ReadyPort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.last);
    await c.act('schedule', value: c.now.wall + 20 * 60000);
    await c.commit((draft, _) => draft.session.held = true);
    c.simulator.clear();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('show-pre-service')), findsOneWidget);
    expect(find.textContaining('Output is held'), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('show-pre-service')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('show-pre-service')));
    await t.pumpAndSettle();
    expect(c.state.session.held, isFalse);
    expect(c.simulator.delivered?.text, '20:00');
    expect(find.byKey(const ValueKey('show-pre-service')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Android Back in Ready returns to Standing by', (t) async {
    size(t);
    final c = AppController(ReadyPort());
    await c.initialize(startTicker: false);
    await c.act('load', value: c.state.templates.last);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'ready');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(c.state.session.phase, 'idle');
    expect(find.text('STANDING BY'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}

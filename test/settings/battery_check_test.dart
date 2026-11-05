import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/app/controller.dart';
import '../domain/service_timing_test.dart' show FakePort;

class BatteryPort extends FakePort {
  bool? unrestricted;
  int opened = 0;
  BatteryPort(this.unrestricted);
  @override
  Future<bool?> batteryUnrestricted() async => unrestricted;
  @override
  Future<void> openBatterySettings() async => opened++;
}

void main() {
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<AppController> start(WidgetTester t, bool? unrestricted) async {
    size(t);
    final c = AppController(BatteryPort(unrestricted));
    await c.initialize(startTicker: false);
    await c.refreshBatteryStatus();
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('An optimised app is flagged on Live and in Ready for service', (
    t,
  ) async {
    final c = await start(t, false);
    final port = c.port as BatteryPort;
    expect(find.byKey(const ValueKey('battery-hint')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('battery-hint')));
    expect(port.opened, 1);
    await t.tap(find.byKey(const ValueKey('live-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Ready for service').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Android may pause warnings'), findsOneWidget);
    await t.tap(find.textContaining('Android may pause warnings'));
    expect(port.opened, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Unrestricted or unknown status shows no hint', (t) async {
    await start(t, true);
    expect(find.byKey(const ValueKey('battery-hint')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await start(t, null);
    expect(find.byKey(const ValueKey('battery-hint')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  test('Returning to the app refreshes the status', () async {
    final port = BatteryPort(false);
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await c.refreshBatteryStatus();
    expect(c.batteryUnrestricted, isFalse);
    port.unrestricted = true;
    await c.resume();
    await Future<void>.delayed(Duration.zero);
    expect(c.batteryUnrestricted, isTrue);
  });
}

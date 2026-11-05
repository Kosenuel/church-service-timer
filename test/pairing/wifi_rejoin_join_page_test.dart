import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

class ChurchWifiPort extends FakePort {
  @override
  Future<Map<String, dynamic>> displayNetworkInfo({
    bool requestName = false,
  }) async => {'wifiConnected': true, 'ssid': 'Church'};
}

void main() {
  testWidgets('Join page offers to rejoin only the current Wi-Fi', (t) async {
    t.view.physicalSize = const Size(430, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(ChurchWifiPort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(MaterialApp(home: JoinDevicePage(controller: c)));
    await t.pump();
    await t.pump();
    expect(find.textContaining('This phone is on Church'), findsOneWidget);
    expect(find.text('Church Wi-Fi'), findsOneWidget);
    expect(find.text('Save the password on this phone'), findsOneWidget);
    await t.tap(find.text('Rejoin this Wi-Fi automatically'));
    await t.pump();
    expect(find.text('Save the password on this phone'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}

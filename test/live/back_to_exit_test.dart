import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/service_timing_test.dart' show FakePort;

void main() {
  late int exits;
  setUp(() {
    exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<AppController> app(WidgetTester t) async {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final c = AppController(FakePort());
    await c.initialize(startTicker: false);
    await t.pumpWidget(TimerApp(controller: c));
    await t.pumpAndSettle();
    return c;
  }

  testWidgets('Back asks for a second press before leaving the app', (t) async {
    await app(t);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Press Back again to exit'), findsOneWidget);
    expect(exits, 0);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(exits, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('A second press after the hint expires asks again', (t) async {
    await app(t);
    await t.binding.handlePopRoute();
    await t.pump();
    // The hint's timer starts once it has slid in.
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('Press Back again to exit'), findsNothing);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Press Back again to exit'), findsOneWidget);
    expect(exits, 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Back on another tab returns to Live first', (t) async {
    await app(t);
    await t.tap(find.text('Reports'));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Press Back again to exit'), findsNothing);
    expect(exits, 0);
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text('Press Back again to exit'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('During a service Back asks before leaving', (t) async {
    final c = await app(t);
    await c.act('load', value: c.state.templates.last);
    await c.act('start');
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Leave the app?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(exits, 0);
    expect(c.liveSession.active, isTrue);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text('Leave'));
    await t.pumpAndSettle();
    expect(exits, 1);
    await t.pumpWidget(const SizedBox());
  });
}

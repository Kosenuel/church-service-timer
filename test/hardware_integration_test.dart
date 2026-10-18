import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/controller.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/hardware_output.dart';
import 'package:church_service_timer/main.dart';
import 'domain_test.dart' show FakePort, start, after, timeline;

class W2Port extends FakePort {
  final sent = <({Uint8List bytes, int? deadline})>[];
  Completer<Json>? sendGate;
  bool acknowledged = true, reachable = true, hardwarePreference = false;
  int nativeGeneration = 4;
  final profile = <String, dynamic>{
    'id': 'synthetic-w2',
    'name': 'Test sign',
    'firmware': 'HD_W2 V6.02.232',
    'width': 32,
    'height': 16,
    'address': '192.0.2.1',
    'supported': true,
  };
  @override
  Future<Json> displayPreferences() async => {
    'hardware': hardwarePreference,
    'id': 'synthetic-w2',
    'name': 'Test sign',
  };
  @override
  Future<List<Json>> discoverDisplays() async => [profile];
  @override
  Future<Json> connectDisplay(String id, String password) async => {
    ...profile,
    'generation': nativeGeneration,
  };
  @override
  Future<Json> checkDisplay() async => {
    'connected': reachable,
    'generation': nativeGeneration,
  };
  @override
  Future<Json> sendDisplay(
    Uint8List bytes,
    int generation,
    int? deadline,
  ) async {
    sent.add((bytes: bytes, deadline: deadline));
    return sendGate?.future ??
        Future.value({
          'accepted': acknowledged,
          'generation': nativeGeneration,
        });
  }
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<AppController> setup(W2Port port, {bool started = true}) async {
  final c = AppController(port);
  await c.initialize(startTicker: false);
  await c.hardware.discover();
  expect(await c.hardware.connect('synthetic-w2', 'synthetic'), true);
  await c.act('load', value: timeline());
  if (started) {
    await c.act('start');
    await flush();
  }
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Roboto');
    for (final name in ['Regular', 'Light', 'Bold']) {
      font.addFont(
        File(
          'assets/fonts/Roboto-$name.ttf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'Hardware Live shows controller acceptance and recovery separately',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final port = W2Port();
      final c = (await tester.runAsync(() => setup(port)))!;
      await tester.pumpWidget(TimerApp(controller: c));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Display connected · connection details'),
        findsOneWidget,
      );
      expect(
        find.text('Controller accepted · check the sign to confirm appearance'),
        findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/hardware-live-phone.png'),
      );
      await c.hardware.disconnect();
      await tester.pumpAndSettle();
      expect(find.text('Connect display'), findsOneWidget);
      expect(find.text('Restore current output'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Hardware connection layout uses the app theme at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = W2Port();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    await tester.pumpWidget(TimerApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('header-connection')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect a display'));
    await tester.tap(find.text('Connect a display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan for displays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test sign'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/hardware-connection-phone.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Paused controls stay in one even row on a 411px phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 1250);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = (await tester.runAsync(() => setup(W2Port())))!;
    await tester.runAsync(() => c.act('pause'));
    await tester.pumpWidget(TimerApp(controller: c));
    await tester.pumpAndSettle();
    final resume = find.ancestor(
      of: find.text('Resume'),
      matching: find.byWidgetPredicate((w) => w is FilledButton),
    );
    final subtract = find.ancestor(
      of: find.text('−2 min'),
      matching: find.byWidgetPredicate((w) => w is OutlinedButton),
    );
    expect(tester.getRect(resume).top, tester.getRect(subtract).top);
    expect(tester.getSize(resume).height, tester.getSize(subtract).height);
    expect(tester.getSize(find.text('Resume')).height, lessThan(24));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/hardware-paused-phone.png'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Hardware warnings do not claim stage cue delivery', (
    tester,
  ) async {
    final port = W2Port();
    final c = (await tester.runAsync(() => setup(port)))!;
    await tester.runAsync(() async {
      await c.setSharedWarnings(const [
        WarningRule(570, TextLayout('WARN'), destination: 'stage'),
      ]);
      port.at = after(31);
      await c.tick();
      await flush();
    });
    await tester.pumpWidget(TimerApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('WARN · 09:30 remaining'), findsOneWidget);
    expect(find.textContaining('stage cue for 8 seconds'), findsNothing);
    expect(
      find.text(
        'Automatic warnings are not sent to the physical sign in this version.',
      ),
      findsOneWidget,
    );
    expect(port.sent.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'Connect does not replace output; starting sends one native deadline',
    () async {
      final port = W2Port();
      final c = await setup(port, started: false);
      addTearDown(c.dispose);
      expect(port.sent, isEmpty);
      expect(c.hardware.held, true);
      await c.act('start');
      await flush();
      expect(port.sent.length, 1);
      expect(port.sent.single.bytes[142], 0x34);
      expect(port.sent.single.deadline, start.wall + 600000);
      for (var i = 1; i < 15; i++) {
        port.at = after(i);
        await c.tick();
        await flush();
      }
      expect(port.sent.length, 1);
    },
  );
  test(
    'Pause, resume, adjustment and static cue preserve countdown semantics',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      port.at = after(10);
      await c.act('pause');
      await flush();
      expect(port.sent.last.deadline, isNull);
      expect(port.sent.last.bytes.length, 233);
      port.at = after(15);
      await c.act('pause');
      await flush();
      expect(port.sent.last.deadline, start.wall + 605000);
      await c.act('adjust', value: 120);
      await flush();
      final target = port.sent.last.deadline;
      await c.sendAndSaveCue(const TextLayout('AMEN', effect: 'static'));
      await flush();
      expect(c.hardware.acceptedLabel, 'AMEN');
      port.at = after(30);
      await c.act('timer');
      await flush();
      expect(port.sent.last.deadline, target);
    },
  );
  test('A storage failure never sends the unsaved adjustment', () async {
    final port = W2Port();
    final c = await setup(port);
    addTearDown(c.dispose);
    port.fail = true;
    expect(await c.act('adjust', value: 120), false);
    await flush();
    expect(port.sent.length, 1);
  });
  test(
    'Stale cue success reconciles timer even if that timer was previously accepted',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      port.sendGate = Completer<Json>();
      await c.act('cue', value: const TextLayout('AMEN', effect: 'static'));
      expect(c.hardware.sending, true);
      await c.act('timer');
      expect(port.sent.length, 2);
      final gate = port.sendGate!;
      port.sendGate = null;
      gate.complete({'accepted': true, 'generation': 4});
      await flush();
      expect(port.sent.length, 3);
      expect(port.sent.last.deadline, start.wall + 600000);
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
    },
  );
  test(
    'Failed acknowledgement holds output without per-tick retries',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      port.acknowledged = false;
      await c.act('pause');
      await flush();
      expect(c.hardware.connected, false);
      expect(c.hardware.held, true);
      for (var i = 1; i < 5; i++) {
        port.at = after(i);
        await c.tick();
      }
      expect(port.sent.length, 2);
      expect(c.hardware.status, contains('not confirmed'));
    },
  );
  test(
    'Backgrounding during a write never accepts its stale success as current',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      port.sendGate = Completer<Json>();
      await c.act('pause');
      await c.suspend();
      final gate = port.sendGate!;
      port.sendGate = null;
      gate.complete({'accepted': true, 'generation': 4});
      await flush();
      expect(c.hardware.held, true);
      await c.resume();
      await flush();
      expect(port.sent.length, 2);
      expect(c.hardware.accepted!.kind, HardwareOutputKind.countdown);
      expect(await c.restoreHardware(), true);
      await flush();
      expect(port.sent.length, 3);
      expect(c.hardware.accepted!.reason, HardwareOutputReason.paused);
    },
  );
  test('Heartbeat loss and reconnect do not replay a stale cue', () async {
    final port = W2Port();
    final c = await setup(port);
    addTearDown(c.dispose);
    await c.act('cue', value: const TextLayout('AMEN', effect: 'static'));
    await flush();
    port.reachable = false;
    port.at = after(10);
    await c.hardware.check(port.at);
    expect(c.hardware.connected, false);
    port.reachable = true;
    await c.hardware.discover();
    await c.hardware.connect('synthetic-w2', 'synthetic');
    await c.tick();
    await flush();
    expect(port.sent.length, 2);
    expect(await c.restoreHardware(), true);
    await flush();
    expect(port.sent.last.deadline, start.wall + 600000);
    expect(c.state.session.alert, isNull);
  });
  test(
    'Recovered uncertainty requires verified time and stays marked in reports',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      c.state.session.uncertain = true;
      c.hardware.hold('Recovery');
      expect(await c.restoreHardware(), false);
      expect(await c.restoreHardware(verifiedSeconds: 85), true);
      await flush();
      expect(c.state.session.uncertain, true);
      expect(c.hardware.held, false);
      expect(port.sent.last.deadline, start.wall + 85000);
    },
  );
  test(
    'Animation and long countdown controls fail before persistence or sending',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      final before = c.state.session.revision;
      expect(
        await c.sendAndSaveCue(
          const TextLayout('A VERY LONG CUE', effect: 'scroll'),
        ),
        false,
      );
      expect(
        await c.sendAndSaveCue(const TextLayout('AMEN', effect: 'flash')),
        false,
      );
      expect(await c.act('adjust', value: 3600), false);
      expect(c.state.session.revision, before);
      expect(port.sent.length, 1);
    },
  );
  test(
    'Zero does not resend a frame; animated end clears once with an explanation',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      port.at = after(601);
      await c.tick();
      await flush();
      expect(port.sent.length, 1);
      expect(c.hardware.status, contains('00:00'));
      await c.act('end');
      await flush();
      expect(port.sent.length, 2);
      expect(port.sent.last.bytes.sublist(169).every((b) => b == 0), true);
      expect(c.hardware.status, contains('animated end screen'));
    },
  );
  test(
    'Automatic stage warnings do not replace this milestone countdown',
    () async {
      final port = W2Port();
      final c = await setup(port);
      addTearDown(c.dispose);
      await c.setSharedWarnings(const [
        WarningRule(570, TextLayout('WARN'), destination: 'stage'),
      ]);
      port.at = after(31);
      await c.tick();
      await flush();
      expect(c.state.session.automaticCue, isNotNull);
      expect(port.sent.length, 1);
    },
  );
  test('Persisted hardware preference starts disconnected and held', () async {
    final port = W2Port()..hardwarePreference = true;
    final c = AppController(port);
    addTearDown(c.dispose);
    await c.initialize(startTicker: false);
    expect(c.hardware.enabled, true);
    expect(c.hardware.connected, false);
    expect(c.hardware.held, true);
    expect(port.sent, isEmpty);
  });
  testWidgets('Connection page scans, selects and connects without sending', (
    tester,
  ) async {
    final port = W2Port();
    final c = AppController(port);
    await c.initialize(startTicker: false);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(home: HardwareConnectionPage(controller: c)),
    );
    await tester.tap(find.text('Scan for displays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test sign'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'synthetic');
    await tester.ensureVisible(find.text('Connect selected display'));
    await tester.tap(find.text('Connect selected display'));
    await tester.pumpAndSettle();
    expect(c.hardware.connected, true);
    expect(port.sent, isEmpty);
    expect(find.text('synthetic'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import '../domain/service_timing_test.dart' show FakePort;
import 'saved_devices_test.dart' show eventually, pair;

class SavedDevicesPort extends FakePort {
  String? pairingData;
  @override
  Future<String?> loadPairing() async => pairingData;
  @override
  Future<void> savePairing(String value) async {
    pairingData = value;
  }
}

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Light.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  void size(WidgetTester t) {
    t.view.physicalSize = const Size(430, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> settings(WidgetTester t) async {
    await t.tap(find.text('Settings'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Screens & devices'));
    await t.pumpAndSettle();
    await t.tap(find.text('Screens & devices'));
    await t.pumpAndSettle();
  }

  testWidgets(
    'Saved devices remain visible before hosting, and Forget requires confirmation',
    (t) async {
      size(t);
      final port = SavedDevicesPort()
        ..pairingData = jsonEncode({
          'version': 1,
          'hostId': 'saved-host',
          'port': 0,
          'devices': [
            SavedPairDevice(
              'screen',
              'Stage tablet',
              'stage',
              pairRandom(32),
              suspended: true,
              lastSeen: DateTime(2026, 10, 19, 10, 30).millisecondsSinceEpoch,
            ).toJson(),
            SavedPairDevice(
              'operator',
              'Assistant operator',
              'operator',
              pairRandom(32),
              lastSeen: DateTime(2026, 10, 19, 9, 15).millisecondsSinceEpoch,
            ).toJson(),
          ],
        });
      final c = AppController(port);
      await c.initialize(startTicker: false);
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await settings(t);
      expect(c.pairing.hosting, false);
      expect(find.text('SAVED DEVICES'), findsOneWidget);
      expect(find.text('Stage screen · Disconnected'), findsOneWidget);
      expect(find.text('Operator · Unavailable'), findsOneWidget);
      expect(find.text('Reconnect'), findsNWidgets(2));
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../goldens/saved-paired-devices.png'),
      );
      await t.tap(find.byTooltip('Device actions').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Forget device').last);
      await t.pumpAndSettle();
      expect(find.text('Forget device?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(c.pairing.savedDevices.length, 2);
      await t.tap(find.byTooltip('Device actions').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Forget device').last);
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Forget device'),
        ),
      );
      await t.pumpAndSettle();
      expect(c.pairing.savedDevices.single.name, 'Assistant operator');
      expect(port.pairingData, isNot(contains('Stage tablet')));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Host Disconnect and Reconnect move a device between lists without new approval',
    (t) async {
      size(t);
      late AppController c;
      late PairHub client;
      late String id;
      await t.runAsync(() async {
        c = AppController(SavedDevicesPort());
        client = PairHub();
        await c.initialize(startTicker: false);
        await c.pairing.host('127.0.0.1');
        id = await pair(c.pairing, client);
      });
      await t.pumpWidget(TimerApp(controller: c));
      await t.pumpAndSettle();
      await settings(t);
      await t.ensureVisible(find.byTooltip('Device actions'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Device actions'));
      await t.pumpAndSettle();
      expect(find.text('Disconnect'), findsOneWidget);
      await t.tapAt(Offset.zero);
      await t.pumpAndSettle();
      final menu = t.widget<PopupMenuButton<String>>(
        find.byWidgetPredicate(
          (w) => w is PopupMenuButton<String> && w.tooltip == 'Device actions',
        ),
      );
      await t.runAsync(() async {
        menu.onSelected!('disconnect');
        await eventually(() => client.pausedByHost);
        await eventually(() => c.pairing.changingDevices.isEmpty);
      });
      await t.pumpAndSettle();
      expect(find.text('SAVED DEVICES'), findsOneWidget);
      expect(find.text('Stage tablet'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      await t.ensureVisible(find.text('Reconnect'));
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(find.text('Reconnect'));
        await eventually(() => !client.stale);
      });
      await t.pumpAndSettle();
      expect(c.pairing.connectedDevice(id), true);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Reconnect'), findsNothing);
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        await client.stop();
        await c.pairing.stop();
        client.dispose();
      });
      await t.pumpWidget(const SizedBox());
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/pairing/pairing.dart';
import '../support/fake_port.dart';
import '../support/pairing.dart';
import '../support/w2_port.dart';
import '../support/waiting.dart';

void main() {
  group('LED sign reconnection state', () {
    test('Missed replies, then a loss, then recovery', () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      expect(c.hardware.reconnecting, isFalse);
      p.reachable = false;
      await c.hardware.check(after(10));
      expect(c.hardware.connected, isTrue);
      expect(c.hardware.reconnecting, isTrue);
      expect(c.hardware.reconnectAttempt, 0);
      await outage(c, p);
      expect(c.hardware.connected, isFalse);
      expect(c.hardware.reconnecting, isTrue);
      expect(c.hardware.offlineMs, isNotNull);
      p.reachable = true;
      p.at = after(17);
      await c.hardware.check(p.at);
      await Future<void>.delayed(Duration.zero);
      expect(c.hardware.connected, isTrue);
      expect(c.hardware.reconnecting, isFalse);
    });

    test('Stop trying ends the reconnecting state', () async {
      final p = RecoveryPort(), c = await setup(p);
      addTearDown(c.dispose);
      await outage(c, p);
      expect(c.hardware.reconnecting, isTrue);
      await c.hardware.disconnect();
      expect(c.hardware.reconnecting, isFalse);
    });
  });

  testWidgets(
    'Live shows the sign reconnecting without disabling timer controls',
    (t) async {
      t.view.physicalSize = const Size(430, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = RecoveryPort();
      final c = (await t.runAsync(() => setup(p)))!;
      await t.runAsync(() => outage(c, p));
      await t.pumpWidget(TimerApp(controller: c));
      await t.pump();
      expect(find.byKey(const ValueKey('sign-reconnecting')), findsOneWidget);
      expect(find.textContaining('Reconnecting to LED sign'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('header-connection')),
          matching: find.text('Reconnecting…'),
        ),
        findsOneWidget,
      );
      final pause = t.widget<FilledButton>(
        find.byKey(const ValueKey('pause-resume')),
      );
      expect(pause.onPressed, isNotNull);
      final cue = find.ancestor(
        of: find.text(c.state.stageCues.first.text),
        matching: find.byType(OutlinedButton),
      );
      expect(t.widget<OutlinedButton>(cue.first).onPressed, isNotNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  test(
    'A paired phone reports reconnecting after the host goes away',
    () async {
      final host = PairHub(), client = PairHub();
      host.snapshotFor = (_) => {'revision': 1, 'displayText': '05:00'};
      await host.host('127.0.0.1');
      await pair(host, client, role: 'operator');
      expect(client.reconnecting, isFalse);
      expect(client.reconnectingSince, isNull);
      await host.stop();
      await eventually(() => client.reconnecting);
      expect(client.reconnectingSince, isNotNull);
      await eventually(() => client.reconnectAttempt > 0);
      await client.stop();
      expect(client.reconnecting, isFalse);
      expect(client.reconnectingSince, isNull);
      client.dispose();
      host.dispose();
    },
  );
}

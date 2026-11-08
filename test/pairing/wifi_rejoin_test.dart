import 'package:church_service_timer/pairing/pairing.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/pairing.dart';
import '../support/waiting.dart';

void main() {
  Future<(PairHub, PairHub)> joined(
    String Function() ssid,
    List<int> calls,
  ) async {
    final host = PairHub();
    await host.host('127.0.0.1');
    final client = PairHub()
      ..currentSsid = (() async => ssid())
      ..rejoinWifi = (() async {
        calls.add(1);
        return true;
      });
    await pair(host, client);
    client.rejoinSsid = 'Church';
    addTearDown(() async {
      await client.stop();
      client.dispose();
      await host.stop();
      host.dispose();
    });
    return (host, client);
  }

  test(
    'A lost host rejoins only the remembered network when the phone moved off it',
    () async {
      final calls = <int>[];
      final (host, client) = await joined(() => 'Neighbour', calls);
      await host.stop();
      await eventually(() => client.reconnecting);
      await eventually(() => calls.isNotEmpty);
      expect(client.rejoiningWifi, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'No rejoin is attempted while still on the remembered network',
    () async {
      final calls = <int>[];
      final (host, client) = await joined(() => 'Church', calls);
      await host.stop();
      await eventually(() => client.reconnectAttempt >= 3);
      expect(calls, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test('Leaving the host releases the Wi-Fi rejoin', () async {
    final calls = <int>[];
    var cancelled = 0;
    final (_, client) = await joined(() => 'Church', calls);
    client.cancelWifi = () async => cancelled++;
    await client.stop();
    expect(cancelled, 1);
    expect(client.rejoinSsid, isEmpty);
  });
}

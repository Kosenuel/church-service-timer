import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/domain.dart';
import 'package:church_service_timer/pairing.dart';

Future<void> eventually(bool Function() condition) async {
  final end = DateTime.now().add(const Duration(seconds: 12));
  while (!condition() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  expect(condition(), true);
}

class PairMemoryStore {
  String? value;
  bool fail = false;
  PairHub hub() => PairHub()
    ..readMemory = (() async => value)
    ..writeMemory = ((next) async {
      if (fail) throw StateError('Disk full');
      value = next;
    });
}

Future<String> pair(
  PairHub host,
  PairHub client, {
  String role = 'stage',
}) async {
  await client.join(host.code!.encode(), 'Stage tablet', role);
  await eventually(() => host.peers.isNotEmpty);
  final peer = host.peers.last;
  await host.approve(peer);
  await eventually(() => !client.stale);
  return peer.id;
}

void main() {
  test(
    'One host supports three stage screens; disconnecting one preserves the others',
    () async {
      final host = PairHub();
      final clients = List.generate(3, (_) => PairHub());
      addTearDown(() async {
        for (final c in clients) {
          await c.stop();
          c.dispose();
        }
        await host.stop();
        host.dispose();
      });
      var revision = 1;
      host.snapshotFor = (_) => {'revision': revision, 'displayText': '00:42'};
      await host.host('127.0.0.1');
      final ids = <String>[];
      for (var i = 0; i < clients.length; i++) {
        await clients[i].join(host.code!.encode(), 'Screen ${i + 1}', 'stage');
        await host.approve(host.peers.last);
        ids.add(host.peers.last.id);
        await eventually(() => !clients[i].stale);
      }
      await eventually(() => host.syncedStagePeers.length == 3);
      await host.disconnectDevice(ids[1]);
      await eventually(() => clients[1].pausedByHost);
      revision = 2;
      await host.publish();
      await eventually(
        () =>
            clients[0].snapshot?['revision'] == 2 &&
            clients[2].snapshot?['revision'] == 2,
      );
      expect(clients[1].snapshot, null);
      expect(host.savedDevices.length, 3);
      await host.reconnectDevice(ids[1]);
      await eventually(
        () =>
            clients[1].snapshot?['revision'] == 2 &&
            host.syncedStagePeers.length == 3,
      );
    },
  );

  test(
    'Disconnect saves the row, suspends output and commands, reconnect sends current state',
    () async {
      final host = PairMemoryStore().hub(), client = PairMemoryStore().hub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      var remaining = '01:50';
      host.snapshotFor = (private) => {
        'revision': 1,
        'displayText': remaining,
        'rundown': [
          {'name': 'Message', if (private) 'notes': 'PRIVATE'},
        ],
      };
      await host.host('127.0.0.1');
      final id = await pair(host, client, role: 'operator');
      host.grant(host.peerFor(id)!);
      await eventually(() => client.canControl);
      expect(jsonEncode(client.snapshot), contains('PRIVATE'));
      await host.disconnectDevice(id);
      await eventually(() => client.pausedByHost);
      expect(host.savedDevices.single.id, id);
      expect(host.connectedDevice(id), false);
      expect(host.localControl, true);
      expect(client.canControl, false);
      expect(client.reconnecting, false);
      expect(client.snapshot, null);
      remaining = '01:25';
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(client.snapshot, null);
      expect(() => host.grant(host.peerFor(id)!), throwsA(isA<RuleError>()));
      await expectLater(
        client.sendCommand('pause', null),
        throwsA(isA<RuleError>()),
      );
      expect(await host.reconnectDevice(id), true);
      await eventually(() => client.snapshot?['displayText'] == '01:25');
      expect(client.canControl, false);
      expect(jsonEncode(client.snapshot), isNot(contains('PRIVATE')));
      host.grant(host.peerFor(id)!);
      await eventually(() => client.canControl);
    },
  );

  test(
    'Suspended device remains suspended after network loss and resumes only on host action',
    () async {
      final host = PairHub(), client = PairHub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 2, 'displayText': '00:42'};
      await host.host('127.0.0.1');
      final id = await pair(host, client);
      await host.disconnectDevice(id);
      await eventually(() => client.pausedByHost);
      host.peerFor(id)!.wire.close();
      await eventually(() => host.peerFor(id) == null);
      await eventually(() => host.peerFor(id) != null);
      expect(host.stagePeers, isEmpty);
      expect(client.snapshot, null);
      expect(client.pausedByHost, true);
      expect(client.reconnecting, false);
      await host.reconnectDevice(id);
      await eventually(() => !client.stale);
      expect(client.snapshot!['displayText'], '00:42');
    },
  );

  test(
    'Both app restarts retain trust and suspension, without retaining private snapshots or control',
    () async {
      final hostMemory = PairMemoryStore(), clientMemory = PairMemoryStore();
      var host = hostMemory.hub(), client = clientMemory.hub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 1, 'displayText': 'OLD MESSAGE'};
      await host.host('127.0.0.1');
      final id = await pair(host, client);
      final identity = host.hostId;
      await host.disconnectDevice(id);
      await eventually(
        () =>
            client.pausedByHost &&
            clientMemory.value?.contains('"paused":true') == true,
      );
      expect(hostMemory.value, isNot(contains('OLD MESSAGE')));
      expect(clientMemory.value, isNot(contains('OLD MESSAGE')));
      await client.stop(preserveClient: true);
      await host.stop(preserveClient: true);
      client.dispose();
      host.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      host = hostMemory.hub();
      client = clientMemory.hub();
      await host.restoreMemory();
      expect(host.hosting, false);
      expect(host.savedDevices.single.id, id);
      expect(host.savedDevices.single.suspended, true);
      expect(host.hostId, identity);
      host.snapshotFor = (_) => {'revision': 4, 'displayText': '00:19'};
      await host.host('127.0.0.1');
      await client.restoreMemory();
      await client.resumeSavedHost(automatic: true);
      await eventually(() => host.peerFor(id) != null);
      expect(client.snapshot, null);
      await host.reconnectDevice(id);
      await eventually(() => client.snapshot?['displayText'] == '00:19');
      expect(host.savedDevices.length, 1);
    },
  );

  test(
    'Host discovery finds a saved host after its address/port changes, using saved authentication',
    () async {
      final hm = PairMemoryStore(), cm = PairMemoryStore();
      var host = hm.hub();
      final client = cm.hub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 1};
      await host.host('127.0.0.1');
      final id = await pair(host, client);
      await host.stop();
      host.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final memory = jsonDecode(hm.value!) as Json;
      memory['port'] = 0;
      hm.value = jsonEncode(memory);
      host = hm.hub();
      host.snapshotFor = (_) => {'revision': 2};
      await host.host('127.0.0.2');
      client.discoverHosts = () async => [
        {'id': 'different-host', 'address': '127.0.0.1', 'port': 9},
        {
          'id': host.hostId,
          'address': host.code!.address,
          'port': host.code!.port,
        },
      ];
      await eventually(
        () => client.snapshot?['revision'] == 2 && !client.stale,
      );
      expect(host.peers.single.id, id);
    },
  );

  test(
    'Forget revokes saved approval and receiver credentials; joining again needs approval',
    () async {
      final hm = PairMemoryStore(), cm = PairMemoryStore();
      final host = hm.hub(), client = cm.hub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 1};
      await host.host('127.0.0.1');
      final id = await pair(host, client);
      await host.forgetDevice(id);
      await eventually(() => !client.hasSavedHost && host.peers.isEmpty);
      expect(host.savedDevices, isEmpty);
      expect(client.reconnecting, false);
      expect((jsonDecode(hm.value!) as Map)['devices'], isEmpty);
      await client.join(host.code!.encode(), 'Stage tablet', 'stage');
      expect(client.snapshot, null);
      expect(host.peers.single.approved, false);
      expect(host.peers.single.id, isNot(id));
    },
  );

  test(
    'Leaving deliberately keeps a saved host but does not rejoin on restart',
    () async {
      final host = PairHub(), memory = PairMemoryStore();
      var client = memory.hub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 1};
      await host.host('127.0.0.1');
      final id = await pair(host, client);
      await client.stop();
      client.dispose();
      await eventually(
        () => host.peerFor(id) == null && host.savedDevices.single.suspended,
      );
      client = memory.hub();
      await client.restoreMemory();
      await client.resumeSavedHost(automatic: true);
      expect(client.joined, false);
      expect(client.hasSavedHost, true);
      await host.reconnectDevice(id);
      await client.resumeSavedHost();
      await eventually(() => !client.stale);
    },
  );

  test(
    'Failed save cannot claim forgotten approval or permit a resumed session',
    () async {
      final hm = PairMemoryStore(), host = PairHub(), client = PairHub();
      host.writeMemory = (v) async {
        if (hm.fail) throw StateError('Disk full');
        hm.value = v;
      };
      addTearDown(() async {
        hm.fail = false;
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (_) => {'revision': 1};
      await host.host('127.0.0.1');
      final id = await pair(host, client);
      await host.disconnectDevice(id);
      hm.fail = true;
      await expectLater(host.reconnectDevice(id), throwsStateError);
      expect(host.savedDevices.single.suspended, true);
      expect(host.connectedDevice(id), false);
      await expectLater(host.forgetDevice(id), throwsStateError);
      expect(host.savedDevices.single.id, id);
      hm.fail = false;
      await host.forgetDevice(id);
      expect(host.savedDevices, isEmpty);
    },
  );
}

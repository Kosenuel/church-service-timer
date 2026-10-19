import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_service_timer/pairing.dart';
import 'package:church_service_timer/pairing_pin.dart';
import 'package:church_service_timer/domain.dart';

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Pairing state did not arrive');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test('PIN preserves leading zeros and rejects invalid lengths', () {
    expect(validPairPin('001234'), true);
    for (final invalid in ['1234', '12345', '1234567', '12a456', ' 123456']) {
      expect(validPairPin(invalid), false);
    }
    for (var i = 0; i < 30; i++) {
      expect(validPairPin(createPairPin()), true);
    }
  });
  test(
    'SRP authenticates both ends and derives a challenge-bound key',
    () async {
      final invitation = PairPinInvitation('001234');
      final client = PairPinClient(), server = invitation.server();
      final a = client.start(base64Encode(invitation.salt), '001234');
      final b = server.generateServerCredentials()!;
      server.calculateSecret(pairNumber(a));
      final proof = client.prove(b.toRadixString(16));
      expect(
        server.verifyClientEvidenceMessage(pairNumber(proof, proof: true)),
        true,
      );
      final response = server.calculateServerEvidenceMessage()!.toRadixString(
        16,
      );
      final clientKey = await client.finish(response, 'connection one');
      final serverKey = await invitation.sessionKey(server, 'connection one');
      expect(await clientKey.extractBytes(), await serverKey.extractBytes());
      final different = await invitation.sessionKey(server, 'connection two');
      expect(
        await clientKey.extractBytes(),
        isNot(await different.extractBytes()),
      );
      expect(
        () => client.finish('0', 'connection one'),
        throwsA(isA<RuleError>()),
      );
    },
  );
  test('Public values must be bounded and nonzero', () {
    for (final value in [
      '0',
      '-1',
      'g',
      '1' * 769,
      pairPinGroup.N.toRadixString(16),
    ]) {
      expect(() => pairNumber(value), throwsA(isA<RuleError>()));
    }
  });
  test(
    'Six-digit join still requires host approval and control grant',
    () async {
      final host = PairHub(), client = PairHub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      host.snapshotFor = (private) => {
        'revision': 1,
        if (private) 'note': 'PRIVATE',
      };
      await host.host('127.0.0.1');
      await client.joinPin(
        '127.0.0.1',
        host.code!.port,
        host.pin,
        'Operator',
        'operator',
      );
      expect(client.status, 'Waiting for host approval');
      expect(client.snapshot, null);
      expect(client.canControl, false);
      expect(host.peers.length, 1);
      await host.approve(host.peers.single);
      await until(() => client.snapshot != null);
      expect(client.snapshot!.containsKey('note'), false);
      host.grant(host.peers.single);
      await until(() => client.canControl);
      expect(client.snapshot!['note'], 'PRIVATE');
      host.newCode();
      await host.publish();
      expect(
        client.canControl,
        true,
      ); // Code refresh does not disconnect peers.
      host.reclaim();
      await until(() => !client.canControl);
      expect(client.snapshot!.containsKey('note'), false);
    },
  );
  test(
    'Five wrong codes lock PIN entry; QR still works; refresh unlocks',
    () async {
      final host = PairHub(), client = PairHub();
      addTearDown(() async {
        await client.stop();
        await host.stop();
        client.dispose();
        host.dispose();
      });
      await host.host('127.0.0.1');
      final wrong = host.pin == '000000' ? '000001' : '000000';
      for (var i = 0; i < 5; i++) {
        await expectLater(
          client.joinPin('127.0.0.1', host.code!.port, wrong, 'Test', 'viewer'),
          throwsA(anything),
        );
        expect(host.peers, isEmpty);
        expect(client.joined, false);
      }
      expect(host.pinAvailable, false);
      await expectLater(
        client.joinPin(
          '127.0.0.1',
          host.code!.port,
          host.pin,
          'Test',
          'viewer',
        ),
        throwsA(anything),
      );
      await client.join(host.code!.encode(), 'QR viewer', 'viewer');
      expect(host.peers.length, 1);
      await client.stop();
      await until(() => host.peers.isEmpty);
      host.newCode();
      expect(host.pinAvailable, true);
      await client.joinPin(
        '127.0.0.1',
        host.code!.port,
        host.pin,
        'Test',
        'stage',
      );
      expect(client.status, 'Waiting for host approval');
    },
  );
  test('Rotating an invitation rejects an in-flight PIN handshake', () async {
    final host = PairHub();
    await host.host('127.0.0.1');
    final socket = await Socket.connect('127.0.0.1', host.code!.port);
    final input = StreamIterator(pairLines(socket));
    addTearDown(() async {
      socket.destroy();
      await input.cancel();
      await host.stop();
      host.dispose();
    });
    expect(await input.moveNext(), true);
    final challenge = jsonDecode(input.current) as Map;
    final client = PairPinClient();
    final a = client.start(challenge['salt'], host.pin);
    socket.write('${jsonEncode({'type': 'pin', 'a': a})}\n');
    expect(await input.moveNext(), true);
    final proof = client.prove((jsonDecode(input.current) as Map)['b']);
    host.newCode();
    socket.write('${jsonEncode({'proof': proof})}\n');
    expect(await input.moveNext(), true);
    final key = await client.finish(
      (jsonDecode(input.current) as Map)['proof'],
      challenge['challenge'],
    );
    final wire = PairWire(socket, key, challenge['challenge']);
    await wire.send({
      'type': 'hello',
      'name': 'Old invitation',
      'role': 'viewer',
    });
    expect(await input.moveNext().timeout(const Duration(seconds: 3)), false);
    expect(host.peers, isEmpty);
  });
  test('Expired invitations cannot be used by PIN or QR', () async {
    final host = PairHub(), client = PairHub();
    addTearDown(() async {
      await client.stop();
      await host.stop();
      client.dispose();
      host.dispose();
    });
    await host.host('127.0.0.1');
    final old = host.code!;
    host.code = PairCode(old.address, old.port, old.secret, 1);
    expect(host.pinAvailable, false);
    await expectLater(
      client.joinPin(old.address, old.port, host.pin, 'Test', 'viewer'),
      throwsA(anything),
    );
    expect(
      () => client.join(host.code!.encode(), 'Test', 'viewer'),
      throwsA(isA<RuleError>()),
    );
    expect(host.peers, isEmpty);
  });
}

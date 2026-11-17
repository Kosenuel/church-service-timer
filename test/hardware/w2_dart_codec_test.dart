import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:church_service_timer/hardware/w2/hd7_auth.dart';
import 'package:church_service_timer/hardware/w2/w2_administration.dart';
import 'package:church_service_timer/hardware/w2/w2_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_w2_controller.dart';

// The Dart codec must put exactly the same bytes on the wire as the Java
// one the Android app has used with real signs. The fixture was produced
// by running Hd7Auth.java and W2Discovery.java from this repository.

Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

int messageIdOf(Uint8List wire) =>
    ByteData.sublistView(wire).getUint32(18, Endian.little);

void main() {
  final vectors =
      jsonDecode(File('test/fixtures/w2_java_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  tearDown(() => Hd7Auth.nextMessageId = () => 7);

  test('discovery queries match the Java codec byte for byte', () {
    expect(W2Discovery.query(0x89abcdef), unhex(vectors['query']));
    expect(W2Discovery.query(-2), unhex(vectors['queryNegative']));
  });

  test('login packets match the Java codec byte for byte', () {
    for (final (name, password) in [
      ('login', 'Sign1234'),
      ('loginEmpty', ''),
    ]) {
      final java = unhex(vectors[name]);
      final parsed = parseHd7Request(java, fakePasswordKey(password))!;
      final log = utf8.decode(parsed.plain.sublist(4));
      // installId__yyyy/MM/dd HH:mm:ss_application
      final stamp = RegExp(
        r'__(\d{4})/(\d\d)/(\d\d) (\d\d):(\d\d):(\d\d)_',
      ).firstMatch(log)!;
      final at = DateTime(
        int.parse(stamp[1]!),
        int.parse(stamp[2]!),
        int.parse(stamp[3]!),
        int.parse(stamp[4]!),
        int.parse(stamp[5]!),
        int.parse(stamp[6]!),
      );
      Hd7Auth.nextMessageId = () => messageIdOf(java);
      final request = Hd7Auth.login(
        password,
        '00112233445566778899aabbccddeeff',
        'ChurchServiceTimer_Android',
        now: at,
      );
      expect(request.bytes(), java, reason: name);
    }
  });

  test('session commands match the Java codec byte for byte', () {
    // A session only comes from a login reply, so make that reply.
    final loginKey = fakePasswordKey('pw');
    Hd7Auth.nextMessageId = () => 42;
    final login = Hd7Auth.login(
      'pw',
      '00112233445566778899aabbccddeeff',
      'Test',
    );
    final plain = Uint8List.fromList([
      ...unhex(vectors['sessionId']),
      ...unhex(vectors['sessionKey']),
    ]);
    final body = fakeAes(true, loginKey, plain);
    final wire = Uint8List(41 + body.length);
    final b = ByteData.sublistView(wire);
    wire[0] = 0x44;
    wire[1] = 0x48;
    b.setUint16(2, wire.length, Endian.little);
    wire[4] = 24;
    wire[17] = 0xc1;
    b.setUint32(18, 42, Endian.little);
    wire.setAll(24, body);
    wire.setAll(
      wire.length - 17,
      fakeHmac(loginKey, wire.sublist(0, wire.length - 17)),
    );
    wire[wire.length - 1] = 0xaa;
    final session = Hd7Auth.decode(login, wire, 8192).loginSession();

    final payloads = {
      'command2': (2, Uint8List.fromList([5, 0x12, 0x34, 0, 1])),
      'command3': (3, Uint8List.fromList(List.generate(37, (i) => 255 - i))),
      'command20': (20, Uint8List(14)),
    };
    for (final entry in payloads.entries) {
      final java = unhex(vectors[entry.key]);
      Hd7Auth.nextMessageId = () => messageIdOf(java);
      expect(
        session.command(entry.value.$1, entry.value.$2).bytes(),
        java,
        reason: entry.key,
      );
    }
  });

  test('a reply is refused unless it matches and is authentic', () {
    Hd7Auth.nextMessageId = () => 99;
    final request = Hd7Auth.login(
      'pw',
      '00112233445566778899aabbccddeeff',
      'Test',
    );
    Uint8List reply({int messageId = 99, int status = 0, Uint8List? key}) {
      final k = key ?? fakePasswordKey('pw');
      final body = status == 0 ? fakeAes(true, k, Uint8List(24)) : Uint8List(0);
      final wire = Uint8List(41 + body.length);
      final b = ByteData.sublistView(wire);
      wire[0] = 0x44;
      wire[1] = 0x48;
      b.setUint16(2, wire.length, Endian.little);
      wire[4] = 24;
      wire[17] = 0xc1;
      b.setUint32(18, messageId, Endian.little);
      b.setInt8(23, status);
      wire.setAll(24, body);
      wire.setAll(
        wire.length - 17,
        fakeHmac(
          status == 0 ? k : Uint8List(32),
          wire.sublist(0, wire.length - 17),
        ),
      );
      wire[wire.length - 1] = 0xaa;
      return wire;
    }

    expect(Hd7Auth.decode(request, reply(), 8192).status, 0);
    expect(Hd7Auth.decode(request, reply(status: -125), 8192).status, -125);
    expect(
      () => Hd7Auth.decode(request, reply(messageId: 100), 8192),
      throwsA(isA<Hd7SecurityError>()),
    );
    expect(
      () => Hd7Auth.decode(request, reply(key: fakePasswordKey('other')), 8192),
      throwsA(isA<Hd7SecurityError>()),
    );
    final tampered = reply()..[30] ^= 1;
    expect(
      () => Hd7Auth.decode(request, tampered, 8192),
      throwsA(isA<Hd7SecurityError>()),
    );
    expect(
      () => Hd7Auth.decode(request, reply().sublist(0, 40), 8192),
      throwsA(isA<Hd7SecurityError>()),
    );
  });

  test('device settings keep the Android rules', () {
    expect(W2Administration.ssidBody('Hall_1'), [
      8,
      0,
      0,
      4,
      0,
      0,
      0,
      6,
      ...utf8.encode('Hall_1'),
    ]);
    expect(() => W2Administration.ssidBody('no'), throwsA(anything));
    expect(() => W2Administration.ssidBody('has space'), throwsA(anything));
    expect(W2Administration.wifiPasswordBody('Str0ng!pass').sublist(0, 8), [
      8,
      0,
      0,
      5,
      0,
      0,
      0,
      11,
    ]);
    final device = W2Administration.devicePasswordBody('Str0ng!pass');
    expect(device.sublist(0, 4), [4, 2, 0, 16]);
    expect(
      device.sublist(4),
      fakeMd5(utf8.encode('Str0ng!pass64ACFEB8B6FE4EF082DB8F3CD428EB20')),
    );
    for (final weak in [
      'short',
      'aaaaaaaa',
      '12345678',
      'has space1',
      'ünicode12',
    ]) {
      expect(
        () => W2Administration.validateNewPassword(weak),
        throwsA(anything),
        reason: weak,
      );
    }
    final ok = {
      'supported': true,
      'firmware': 'HD_W2 V6.02.232',
      'pwdComplexity': 1,
    };
    expect(W2Administration.supported(ok), isTrue);
    expect(
      W2Administration.supported({...ok, 'firmware': 'HD_W2 V6.02.233'}),
      isFalse,
    );
    expect(W2Administration.supported({...ok, 'pwdComplexity': 0}), isFalse);
    expect(W2Administration.supported({...ok, 'supported': false}), isFalse);
  });
}
